USE [master]
GO
IF OBJECT_ID(N'tempdb..#VLFs') IS NOT NULL DROP TABLE #VLFs;
CREATE TABLE #VLFs (DBName SYSNAME NOT NULL, VLFsCount INT NOT NULL, TotalFileSize BIGINT NOT NULL, ActiveFileSize BIGINT NOT NULL);

DECLARE @DBName sysname, @spExecute sysname, @CMD NVARCHAR(MAX);

SET @CMD = N'
DECLARE @T TABLE (RecoveryUnitId INT, FileId BIGINT, FileSize BIGINT, StartOffset BIGINT, FSeqNo INT, [Status] INT, Parity INT, CreateLSN NVARCHAR(48));
INSERT INTO @T
EXEC (''DBCC LOGINFO'');

INSERT INTO #VLFs
SELECT DB_NAME(), @@ROWCOUNT, SUM(FileSize), SUM(CASE WHEN [Status] = 2 THEN FileSize ELSE 0 END)
FROM @T;'

DECLARE dbs CURSOR
LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
SELECT [name]
FROM sys.databases
WHERE HAS_DBACCESS([name]) = 1
AND state_desc = 'ONLINE'
AND DATABASEPROPERTYEX([name],'Updateability') = 'READ_WRITE'

OPEN dbs

WHILE 1=1
BEGIN
	FETCH NEXT FROM dbs INTO @DBName;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @spExecute = QUOTENAME(@DBName) + N'..sp_executesql'

	EXEC @spExecute @CMD
END

CLOSE dbs;
DEALLOCATE dbs;

SELECT
	v.*
	, TotalFileSize_MB = v.TotalFileSize / 1024.0 / 1024
	, ActiveFileSize_MB = v.ActiveFileSize / 1024.0 / 1024
	, ActiveFileSize_PCT = CONVERT(smallmoney, v.ActiveFileSize * 1.0 / v.TotalFileSize * 100)
	, d.log_reuse_wait_desc
	, MarkReplicationDoneCmd = CONCAT('USE [', v.DBName, ']; exec sp_repldone null, null, 0,0,1; checkpoint;')
FROM
	#VLFs AS v
	INNER JOIN sys.databases AS d ON v.DBName = d.[name]
WHERE
	d.log_reuse_wait_desc <> 'NOTHING'; -- = 'REPLICATION'