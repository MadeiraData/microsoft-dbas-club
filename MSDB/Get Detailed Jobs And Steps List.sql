WITH JobsAndStepsListCTE AS
(
	SELECT
		j.[name]
		,js.step_name
		,js.[database_name]
		,js.command
		,j.[enabled]	AS isEnabled
		,js.last_run_outcome
		,js.last_run_duration
		,js.retry_attempts
		,js.retry_interval
		,N'SQLAgent - TSQL JobStep (Job 0x'+ CONVERT(CHAR(32),CAST(j.job_id AS BINARY(16)),2) + N' : Step ' + CAST(js.step_id AS NVARCHAR(3)) + N')' AS [ProgramName]
		,js.job_id
		,js.step_id
	FROM
		msdb.dbo.sysjobs AS j 
		INNER JOIN msdb.dbo.sysjobsteps AS js ON j.job_id = js.job_id
)
SELECT
	l.[name]
	,l.step_id
	,l.step_name
	,l.[database_name]
	,l.command
	,l.isEnabled
	,c.[LastRunDuration (d.HH:MM:SS)]
	,l.last_run_outcome
	,l.retry_attempts
	,l.retry_interval
	,l.[ProgramName]
FROM
	JobsAndStepsListCTE AS l
	CROSS APPLY
				(
					SELECT  TOP 1 
						sh.job_id
						,sh.run_date
						,sh.run_time
						,CASE
							WHEN l.last_run_duration > 235959 THEN CAST((CAST(LEFT(CAST(l.last_run_duration AS VARCHAR), LEN(CAST(l.last_run_duration AS VARCHAR)) - 4) AS INT) / 24) AS VARCHAR)
																+ '.' + RIGHT('00' + CAST(CAST(LEFT(CAST(l.last_run_duration AS VARCHAR), LEN(CAST(l.last_run_duration AS VARCHAR)) - 4) AS INT) % 24 AS VARCHAR), 2)
																+ ':' + STUFF(CAST(RIGHT(CAST(l.last_run_duration AS VARCHAR), 4) AS VARCHAR(6)), 3, 0, ':')
							ELSE STUFF(STUFF(RIGHT(REPLICATE('0', 6) + CAST(l.last_run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
							END												AS [LastRunDuration (d.HH:MM:SS)]	
					FROM msdb.dbo.sysjobhistory sh WHERE l.job_id = sh.job_id
					ORDER BY
						4 DESC
				) AS c
ORDER BY 
	l.[name],
	l.step_id ASC