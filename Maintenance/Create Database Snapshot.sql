USE [master]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************************
 Title:		A procedure to create Database Snapshot
 Author:	Reut Almog Talmi and Eitan Blumin @Madeira
********************************************************************************************************************/
CREATE OR ALTER PROCEDURE [dbo].[sp_DBA_CreateDatabaseSnapshot]
	@SourceDBName		SYSNAME,
	@NewSnapshotDBName	SYSNAME = NULL,
	@FileSuffix			NVARCHAR(20) = NULL,
	@DestFilePath		NVARCHAR(200) = NULL, -- Edit when you want the destination snapshot file to reside somewhere(Example: 'Z:\Path\')
	@IgnoreReplicaRole	BIT = 0,			/*By default, the snapshot will be created on the secondary replica only. 
											in case desired to create on primary - set @IgnoreReplicaRole to 1
											For databases not involved in AG -  @IgnoreReplicaRole can be 0 or 1 or NULL*/
	@Debug BIT = 0

AS

SET NOCOUNT ON


DECLARE  	
	@FilePath NVARCHAR(3000),
	@SQLCommand NVARCHAR(4000) = ''
	

IF DB_ID(@SourceDBName) IS NULL OR NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @SourceDBName) 
BEGIN
	RAISERROR('Database %s doesn''t exist',16,1,@SourceDBName)
END

-- Set default suffix with timestamp if it is not defined
IF @FileSuffix IS NULL OR TRIM(@FileSuffix) = ''
BEGIN
	SELECT @FileSuffix = REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(20), GETDATE(), 120), ':', ''), '-','_'), ' ', '_')
END

SET @NewSnapshotDBName = ISNULL(@NewSnapshotDBName, @SourceDBName + '_' + @FileSuffix)


-- Set the file path location of the snapshot data files.

IF TRIM(@DestFilePath ) = ''
BEGIN
	SET @DestFilePath = NULL
END
ELSE
BEGIN
	SET @DestFilePath += @SourceDBName
END


-- build list of files for the database snapshot.
IF ISNULL((SELECT sys.fn_hadr_is_primary_replica (@SourceDBName)), 0) = 0 OR  @IgnoreReplicaRole = 1
BEGIN

	SELECT @FilePath =
	ISNULL(@FilePath + N',
', N'') + N'(NAME = ' + QUOTENAME(mf.name) + N', FILENAME = ''' + ISNULL(@DestFilePath, LEFT(physical_name, LEN(physical_name) - CHARINDEX('\', REVERSE(physical_name)) + 1))
+ '_' + mf.name + '_' + @FileSuffix + '.ss'
+ N''')'
	FROM sys.master_files AS mf
	INNER JOIN sys.databases AS db ON db.database_id = mf.database_id
	WHERE db.state = 0
	AND mf.type = 0 -- Only include data files
	AND db.name = @SourceDBName

	SET @SQLCommand += 
	N'CREATE DATABASE ' + QUOTENAME(@NewSnapshotDBName) + CHAR(10)
+ ISNULL(N'
ON ' + @FilePath, N'') 
+ N' AS SNAPSHOT OF '+ QUOTENAME(@SourceDBName) + ';' + CHAR(30)

END


PRINT @SQLCommand

IF @Debug != 1
BEGIN
	EXEC sp_executesql @SQLCommand
	
	IF DB_ID(@NewSnapshotDBName) IS NOT NULL
		RAISERROR ('Database snapshot [%s] has been created',0,1,@NewSnapshotDBName)
	ELSE
		RAISERROR ('Error trying to create database snapshot [%s]',16,1,@NewSnapshotDBName)
END
GO


IF OBJECT_ID('sp_MS_marksystemobject', 'P') IS NOT NULL AND DB_NAME() = 'master'
BEGIN
	PRINT 'Adding system object flag to allow procedure to be used within all databases'
	EXEC sp_MS_marksystemobject 'sp_DBA_CreateDatabaseSnapshot'
END
PRINT 'Granting EXECUTE permission on stored procedure to all users'
GRANT EXEC ON [sp_DBA_CreateDatabaseSnapshot] TO [public]

GO