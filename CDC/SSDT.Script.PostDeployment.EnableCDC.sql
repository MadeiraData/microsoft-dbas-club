/*
Post-Deployment Script Template							
--------------------------------------------------------------------------------------
 This file contains SQL statements that will be appended to the build script.		
 Use SQLCMD syntax to include a file in the post-deployment script.			
 Example:      :r .\myfile.sql								
 Use SQLCMD syntax to reference a variable in the post-deployment script.		
 Example:      :setvar TableName MyTable							
               SELECT * FROM [$(TableName)]					
--------------------------------------------------------------------------------------
*/
DECLARE @EnableCmd NVARCHAR(4000), @SchemaName NVARCHAR(128), @TableName NVARCHAR(128);

DECLARE c CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
SELECT EnableCmd, SchemaName, TableName
FROM dbo.TMP__CDC_Tables
WHERE OBJECT_ID(QUOTENAME(SchemaName) + '.' + QUOTENAME(TableName)) IS NOT NULL;
;

OPEN c;

WHILE 1=1
BEGIN
	FETCH NEXT FROM c INTO @EnableCmd, @SchemaName, @TableName;
	IF @@FETCH_STATUS <> 0 BREAK;

	RAISERROR('Enabling CDC for %s.%s', 0, 1, @SchemaName, @TableName) WITH NOWAIT;
	EXEC sp_executesql @EnableCmd;
END

CLOSE c;
DEALLOCATE c;

RAISERROR('Dropping TMP__CDC_Tables', 0, 1) WITH NOWAIT;
DROP TABLE dbo.TMP__CDC_Tables;
GO