SET NOCOUNT, ARITHABORT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @temp_Orphan AS TABLE
(
[database_name] SYSNAME,
[principal] SYSNAME
);

INSERT INTO @temp_Orphan
EXEC sp_MSforeachdb 
N'
IF ''?'' NOT IN (''DoronTemp'', ''ExtractPool'', ''MergeConversionTables'', ''MergeConversionTablesMVS'', ''Uniform_PizuimInterfaceBeforeMizug'', ''UniformStructure_BillingBeforeMizug'', ''UniformStructure_EmployersBeforeMizug'') 
    AND DATABASEPROPERTYEX(''?'', ''Status'') = ''ONLINE'' 
    AND DATABASEPROPERTYEX(''?'', ''Updateability'') = ''READ_WRITE''
BEGIN
    USE [?];
    SELECT 
        DB_NAME(), 
        name
    FROM sys.database_principals AS dp
    WHERE sid NOT IN (SELECT sid FROM sys.server_principals) 
      AND dp.type IN (''S'',''U'',''G'') 
      AND dp.sid > 0x01
      AND principal_id != 2 
      AND is_fixed_role = 0
      AND authentication_type <> 0
      AND DATALENGTH(sid) <= 28
      AND name NOT IN (''MS_DataCollectorInternalUser'', ''dbo'') 
      AND SUSER_SNAME(sid) IS NULL
END
' 

SELECT 'In server: ' + @@SERVERNAME + ' database: ' + QUOTENAME([database_name]) + ', ' + QUOTENAME([principal]) + ' is Orphan user', 1
FROM @temp_Orphan