

DECLARE @EndTime datetime = DATEADD(hour, 2, GETDATE())


DECLARE @DBName sysname, @ObjNameFull nvarchar(4000), @ObjNameLean sysname, @SchName sysname
DECLARE @CheckTime datetime, @LastCheckDate datetime, @ObjType sysname

IF OBJECT_ID('tempdb..#Objects') IS NOT NULL DROP TABLE #Objects;
CREATE TABLE #Objects
(
	DBName sysname,
	SchemaName sysname,
	TableName sysname,
	ObjType sysname,
	UsedPages int,
	LastCheck datetime,
	FullTableName AS (QUOTENAME(DBName) + N'.' + QUOTENAME(SchemaName) + '.' + QUOTENAME(TableName))
);

DECLARE @CMD nvarchar(max), @SpExecuteSql nvarchar(4000);

DECLARE DBs CURSOR
LOCAL FAST_FORWARD READ_ONLY
FOR
SELECT [name]
FROM sys.databases
WHERE HAS_DBACCESS([name]) = 1
AND state = 0
AND [name] NOT IN ('tempdb')

OPEN DBs

WHILE 1=1
BEGIN
	FETCH NEXT FROM DBs INTO @DBName;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @SpExecuteSql = QUOTENAME(@DBName) + N'..sp_executesql'

	INSERT INTO #Objects
	(DBName, SchemaName, TableName, ObjType, UsedPages, LastCheck)
	EXEC @SpExecuteSql N'SELECT DB_NAME()
, ss.name
, so.[name]
, CASE WHEN so.[type] = ''V'' THEN ''VIEW'' ELSE ''TABLE'' END
, SUM(sps.used_page_count) AS used_page_count
, ep.[EndTime]
FROM sys.objects so
INNER JOIN sys.dm_db_partition_stats sps ON so.[object_id] = sps.[object_id]
INNER JOIN sys.indexes si ON so.[object_id] = si.[object_id]
INNER JOIN sys.schemas ss ON so.[schema_id] = ss.[schema_id]
OUTER APPLY
(
	SELECT [DatabaseName]
		  ,[SchemaName]
		  ,[ObjectName]
		  ,[ObjectType]
		  ,MAX([EndTime]) AS [EndTime]
	FROM [msdb].[dbo].[CommandLog]
	WHERE CommandType	= ''DBCC_CHECKTABLE''
	AND [DatabaseName]	COLLATE DATABASE_DEFAULT = DB_NAME() COLLATE DATABASE_DEFAULT
	AND [SchemaName]	COLLATE DATABASE_DEFAULT = ss.[name] COLLATE DATABASE_DEFAULT
	AND [ObjectName]	COLLATE DATABASE_DEFAULT = so.[name] COLLATE DATABASE_DEFAULT
	AND [ObjectType]	COLLATE DATABASE_DEFAULT = so.[type] COLLATE DATABASE_DEFAULT
	GROUP BY
		   [DatabaseName]
		  ,[SchemaName]
		  ,[ObjectName]
		  ,[ObjectType]
) AS ep
WHERE so.[type] IN (''U'', ''V'')
GROUP BY so.[object_id], so.[name], ss.name, so.[type], so.type_desc, ep.[EndTime]
ORDER BY ep.[EndTime] ASC, SUM(sps.used_page_count) DESC'

END

CLOSE DBs;
DEALLOCATE DBs;


DECLARE obj CURSOR
LOCAL FAST_FORWARD READ_ONLY
FOR
SELECT DBName
, FullTableName
, SchemaName
, TableName
, ObjType
, LastCheck
FROM #Objects
ORDER BY LastCheck ASC, UsedPages DESC

OPEN obj;

WHILE GETDATE() < @EndTime
BEGIN
	FETCH NEXT FROM obj INTO @DBName, @ObjNameFull, @SchName, @ObjNameLean, @ObjType, @LastCheckDate;
	IF @@FETCH_STATUS <> 0 BREAK;

	EXEC [msdb].[dbo].[DatabaseIntegrityCheck]
		@Databases = @DBName,
		@CheckCommands = 'CHECKTABLE',
		@Objects = @ObjNameFull,
		@Execute = 'Y',
		@LogToTable = 'Y'

END

CLOSE obj
DEALLOCATE obj