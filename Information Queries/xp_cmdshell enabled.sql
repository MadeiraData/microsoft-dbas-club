SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @results AS TABLE
(
dbName SYSNAME NULL,
schemaName SYSNAME NULL,
objectName SYSNAME NULL,
objectDefinition NVARCHAR(MAX)
);

INSERT INTO @results
EXEC sp_MSforeachdb N'IF HAS_DBACCESS(''?'') = 1
SELECT ''?'', object_schema_name(object_id, DB_ID(''?'')), object_name(object_id, DB_ID(''?'')), definition
FROM [?].sys.sql_modules
WHERE definition like ''%xp_cmdshell%''
OPTION (RECOMPILE)'

SELECT * FROM @results

IF HAS_DBACCESS('msdb') = 1
BEGIN
SELECT j.name AS job_name, js.step_name, js.command, j.enabled
, last_run_date_time = (SELECT TOP 1 msdb.dbo.agent_datetime(jh.run_date, jh.run_time) FROM msdb..sysjobhistory AS jh WHERE jh.job_id = j.job_id AND jh.step_id = js.step_id ORDER BY jh.run_date DESC, jh.run_time DESC)
FROM msdb..sysjobs AS j
INNER JOIN msdb..sysjobsteps AS js ON js.job_id = j.job_id
WHERE js.command LIKE '%xp_cmdshell%'
OPTION (RECOMPILE)
END