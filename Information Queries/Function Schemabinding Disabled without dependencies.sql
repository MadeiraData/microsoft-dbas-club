SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @temp_Schemabinding AS TABLE
(
[database_name] sysname,
[name] nvarchar(1000)
);

INSERT INTO @temp_Schemabinding
exec sp_MSforeachdb 'IF HAS_DBACCESS(''?'') = 1 AND DATABASEPROPERTYEX(''?'', ''Status'') = ''ONLINE'' AND DATABASEPROPERTYEX(''?'', ''Updateability'') = ''READ_WRITE'' 
BEGIN
USE [?];

SELECT DB_NAME(), QUOTENAME(OBJECT_SCHEMA_NAME(OB.id)) + N''.'' + QUOTENAME(OB.name)
FROM sys.sysobjects OB
INNER JOIN sys.sql_modules MO
ON OB.id = MO.object_id
AND OB.type = ''FN''
AND MO.is_schema_bound = 0
WHERE DB_ID() > 4
AND LOWER(DB_NAME()) NOT IN (''reportserver'',''reportservertemp'',''distribution'',''ssisdb'',''DBA_MON'',''OI.CacheDB'')
AND MO.definition IS NOT NULL
AND OB.name <> ''fn_diagramobjects''
AND OB.name not like ''%validate%''
AND OB.name not like ''%removenonascii%''
AND MO.definition NOT LIKE N''%sp_OACreate%sp_OA%''
AND NOT EXISTS
(
select NULL
from sys.sql_dependencies AS d
WHERE d.object_id = OB.id
UNION ALL
select NULL
from sys.sql_expression_dependencies AS d
WHERE d.referencing_id = OB.id
)
END'

IF @@ROWCOUNT <= 10
BEGIN
 SELECT 'In server: ' + @@SERVERNAME + ', database: ' + QUOTENAME([database_name]) + ', function: ' + [name] + ' is without schemabinding', 1
 FROM @temp_Schemabinding
END
ELSE
BEGIN
 SELECT TOP 10 'In server: ' + @@SERVERNAME + ', database: ' + QUOTENAME([database_name]) + ', there are ' + CONVERT(nvarchar(MAX), COUNT(*)) + N' scalar functions without schemabinding', 1
 FROM @temp_Schemabinding
 GROUP BY [database_name]
 ORDER BY COUNT(*) DESC
END