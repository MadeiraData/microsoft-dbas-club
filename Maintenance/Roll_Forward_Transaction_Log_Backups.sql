/*
Author: Eitan Blumin (t: @EitanBlumin | b: eitanblumin.com)
Date: August, 2015
Description:
Use this script to easily roll forward multiple transaction log backups from a given folder.

More info:
https://eitanblumin.com/2018/10/28/t-sql-script-to-roll-forward-transaction-log-backups
*/
DECLARE
	  @TransactionLogBackupFolder	VARCHAR(4000)	= 'C:\SqlDBBackupsMyDB'
	, @FileNameQualifier			VARCHAR(4000)	= 'MyDB_%.trn'
	, @DatabaseName					SYSNAME			= 'MyDB'
	, @PerformRecovery				BIT				= 0
	, @StandByFilePath				VARCHAR(4000)	= NULL --'C:\MSSQL\DATA\MyDB_StandbyFile.undo'

SET NOCOUNT ON;

DECLARE @CMD NVARCHAR(4000), @FilePath NVARCHAR(4000), @CanBeApplied BIT;

-- Add backslash at end of path if doesn't exist already
IF RIGHT(@TransactionLogBackupFolder, 1) <> '\'
	SET @TransactionLogBackupFolder = @TransactionLogBackupFolder + '\'

DECLARE @FileList TABLE
(FileName nvarchar(500)
,depth int
,isFile int)

INSERT INTO @FileList
EXEC xp_dirtree @TransactionLogBackupFolder,1,1

-- Loop through all files that comply with the specified qualifier
DECLARE @CurrPath NVARCHAR(MAX)
DECLARE CM CURSOR
LOCAL FAST_FORWARD
FOR
SELECT FileName
FROM @FileList
WHERE isFile=1
AND FileName LIKE @FileNameQualifier
ORDER BY FileName

OPEN CM

WHILE 1=1
BEGIN
	FETCH NEXT FROM CM INTO @CurrPath
	IF @@FETCH_STATUS <> 0 BREAK;
	
	SET @FilePath = @TransactionLogBackupFolder + @CurrPath;
	SET @CanBeApplied = NULL;

	EXEC sp_can_tlog_be_applied
		@backup_file_name = @FilePath,
		@database_name = @DatabaseName,
		@result = @CanBeApplied OUTPUT;

	IF @CanBeApplied = 1
	BEGIN
		-- Prepare and execute RESTORE LOG command
		SET @CMD = N'RESTORE LOG ' + QUOTENAME(@DatabaseName) + N' FROM  
DISK = N''' + @FilePath + N''' WITH  
FILE = 1,  NORECOVERY,  NOUNLOAD,  STATS = 10'
	
		RAISERROR(@CMD,0,1) WITH NOWAIT;
		EXEC(@CMD);
	END
	ELSE
	BEGIN
		RAISERROR(N'Skipping: %s',0,1,@FilePath) WITH NOWAIT;
	END
END

CLOSE CM
DEALLOCATE CM

-- Perform final recovery if needed
IF @PerformRecovery = 1
BEGIN
	SET @CMD = N'RESTORE LOG ' + QUOTENAME(@DatabaseName) + N' WITH RECOVERY'
	RAISERROR(@CMD,0,1) WITH NOWAIT;
	EXEC(@CMD);
END
-- Attempt to restore with standby if needed
ELSE IF @StandByFilePath IS NOT NULL
BEGIN
	SET @CMD = N'RESTORE LOG ' + QUOTENAME(@DatabaseName) + N' WITH STANDBY=''' + @StandByFilePath + N''''
	RAISERROR(@CMD,0,1) WITH NOWAIT;
	EXEC(@CMD);
END

RAISERROR(N'Done.',0,1) WITH NOWAIT;

GO