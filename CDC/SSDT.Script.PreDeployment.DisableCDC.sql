/*
 Pre-Deployment Script Template							
--------------------------------------------------------------------------------------
 This file contains SQL statements that will be executed before the build script.	
 Use SQLCMD syntax to include a file in the pre-deployment script.			
 Example:      :r .\myfile.sql								
 Use SQLCMD syntax to reference a variable in the pre-deployment script.		
 Example:      :setvar TableName MyTable							
               SELECT * FROM [$(TableName)]					
--------------------------------------------------------------------------------------
*/

IF OBJECT_ID('dbo.TMP__CDC_Tables') IS NULL
BEGIN
    EXEC(N'
    CREATE TABLE dbo.TMP__CDC_Tables
    (
        [SchemaName] NVARCHAR(128) NOT NULL,
        [TableName] NVARCHAR(128) NOT NULL,
        DisableCmd NVARCHAR(4000) NULL,
        EnableCmd NVARCHAR(4000) NULL
    );');
END
GO
MERGE INTO dbo.TMP__CDC_Tables AS target
USING
(
SELECT
  SCHEMA_NAME(schema_id) AS [schema], [name]
, DisableCmd = N'EXEC sys.sp_cdc_disable_table @source_schema = N' + QUOTENAME(SCHEMA_NAME(t.schema_id), '''') + N', @source_name = N' + QUOTENAME(t.[name], '''') + N', @capture_instance = N' + QUOTENAME(ct.capture_instance, '''') + N';' 
, EnableCmd = N'EXEC sys.sp_cdc_enable_table @source_schema = N' + QUOTENAME(SCHEMA_NAME(schema_id), '''') + N', @source_name = N' + QUOTENAME([name], '''') + N', @role_name = NULL, @filegroup_name = NULL, @supports_net_changes = 0;'
FROM sys.tables AS t
INNER JOIN cdc.change_tables AS ct ON t.object_id = ct.source_object_id
WHERE is_ms_shipped = 0 -- non-system
AND t.is_tracked_by_cdc = 1 -- tracked by CDC
) AS source
ON target.SchemaName = source.[schema] AND target.TableName = source.[name]
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SchemaName, TableName, DisableCmd, EnableCmd)
    VALUES (source.[schema], source.[name], source.DisableCmd, source.EnableCmd)
;

RAISERROR('Added %d table(s) with CDC enabled', 0, 1, @@ROWCOUNT) WITH NOWAIT;

GO
DECLARE @DisableCmd NVARCHAR(4000), @SchemaName NVARCHAR(128), @TableName NVARCHAR(128);

DECLARE c CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
SELECT DisableCmd, SchemaName, TableName
FROM dbo.TMP__CDC_Tables
WHERE OBJECT_ID(QUOTENAME(SchemaName) + '.' + QUOTENAME(TableName)) IS NOT NULL;
;

OPEN c;

WHILE 1=1
BEGIN
    FETCH NEXT FROM c INTO @DisableCmd, @SchemaName, @TableName;
	IF @@FETCH_STATUS <> 0 BREAK;

    RAISERROR('Disabling CDC for %s.%s', 0, 1, @SchemaName, @TableName) WITH NOWAIT;
	EXEC sp_executesql @DisableCmd;
END

CLOSE c;
DEALLOCATE c;
GO