DECLARE @Results AS TABLE (DBName sysname, UserName sysname, LoginName sysname)
DECLARE @CurrDB sysname, @spExecSql sysname, @CMD nvarchar(max)

SET @CMD = N'
SELECT DB_NAME()
	, name AS [Principal]
    , SUSER_SNAME(sid) AS [Login]
FROM sys.database_principals
WHERE principal_id != 1
AND IS_SRVROLEMEMBER(''sysadmin'', SUSER_SNAME(sid)) = 1'

DECLARE dbs CURSOR
FAST_FORWARD LOCAL
FOR
SELECT [name]
FROM sys.databases
WHERE HAS_DBACCESS([name]) = 1
AND DATABASEPROPERTYEX([name], 'Updateability') = 'READ_WRITE'
AND state = 0

OPEN dbs;

WHILE 1=1
BEGIN
	FETCH NEXT FROM dbs INTO @CurrDB;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @spExecSql = QUOTENAME(@CurrDB) + N'..sp_executesql'

	INSERT INTO @Results
	EXEC @spExecSql @CMD
END

CLOSE dbs;
DEALLOCATE dbs;

SELECT *
FROM @Results