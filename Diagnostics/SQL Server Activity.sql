USE [master]
GO
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*
	Created by: Vitaly Bruk
	Description: This script show all SQL server activity - what is running right now with consumed resources.
*/

;WITH jobs_CTE AS
(
	SELECT
		N'SQLAgent - TSQL JobStep (Job 0x'+ CONVERT(CHAR(32),CAST(j.job_id AS BINARY(16)),2) + N' : Step ' + CAST(js.step_id AS NVARCHAR(3)) + N')' AS [ProgramName]
		,j.[name]
		,js.step_name
	FROM
		msdb.dbo.sysjobs AS j 
		INNER JOIN msdb.dbo.sysjobsteps AS js ON j.job_id = js.job_id
), 
waiting_tasks_CTE AS
(
	SELECT
		[session_id], 
		waiting_task_address, 
		wait_type, 
		wait_duration_ms, 
		resource_description 
	FROM
		sys.dm_os_waiting_tasks AS w 
	GROUP BY
		[session_id], 
		waiting_task_address, 
		wait_type, 
		wait_duration_ms, 
		resource_description
), 
sysprocesses_CTE AS
(
	SELECT
		MAX(sp.ecid) + 1 AS ecid,
		sp.spid
	FROM
		sys.sysprocesses AS sp 
	GROUP BY 
		sp.spid
),
ALL_requests_CTE AS
(
	SELECT TOP (9223372036854775807)
		es.login_time,
		es.[session_id],
		CASE
			WHEN er.blocking_session_id = -1 THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id) + N' (Orphaned lock,​​ commonly​​ a bug)'
			WHEN er.blocking_session_id = -2 THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id) + N' (Orphaned/Pending DTC​​ transaction)'
			WHEN er.blocking_session_id = -3 THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id) + N' (Locked by a​​ deferred transaction)'
			WHEN er.blocking_session_id = -4 THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id) + N' (Internal latch state transition)'
			WHEN er.blocking_session_id = -5 THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id) + N' (Latch, commonly I/O. Waiting on an async action to complete)'
			WHEN er.blocking_session_id IS NOT NULL	AND er.blocking_session_id NOT IN (0,-1,-2,-3,-4,-5)  THEN N'Blk by: ' + CONVERT(NVARCHAR(8), er.blocking_session_id)
			ELSE N'' 
		END																					AS [Blk by],
		es.[status]																			AS [S_Status],
		DATEDIFF(SECOND,
							CASE
								WHEN es.login_time < es.last_request_end_time THEN es.last_request_end_time
								ELSE es.last_request_start_time
							END
							, GETDATE())													AS [RequestTime(ms)],
		er.[status]																			AS [R_Status],
		CONVERT(BIGINT, er.wait_time)														AS wait_time,
		er.wait_type,
		er.request_id,
		er.command,
		er.last_wait_type,
		er.wait_resource,
		er.cpu_time,
		er.logical_reads,
		er.reads,
		er.writes,
		er.database_id,
		es.login_name,
		es.original_login_name,
		es.[host_name],
		er.percent_complete,
		er.estimated_completion_time/(1000*60) AS estimated_completion_time,
		er.[sql_handle],
		er.task_address,
		es.prev_error,
		er.[language],
		CASE
			WHEN ec.client_net_address IS NOT NULL									THEN CONVERT(NVARCHAR(48), ec.client_net_address) + (CASE WHEN ec.client_tcp_port IS NOT NULL THEN N':'+ CONVERT(NVARCHAR(8), ec.client_tcp_port) ELSE N'' END)
			WHEN ec.client_net_address IS NULL AND ec.client_tcp_port IS NOT NULL	THEN CONVERT(NVARCHAR(48), ec.client_tcp_port) + (CASE WHEN ec.local_tcp_port IS NOT NULL THEN N':'+ CONVERT(NVARCHAR(8), ec.local_tcp_port) ELSE N'' END)
			ELSE N'unknow'
		END																					AS [Client Address],
		es.client_interface_name,
		CASE
			WHEN es.[program_name] LIKE N'SQLAgent - TSQL JobStep%'	THEN + 
																			(
																				SELECT
																					N'SQLAgent - Job: ' + name + N', Step: ' + step_name
																				FROM
																					jobs_CTE jb
																				WHERE jb.[ProgramName] = es.[program_name]
																			)
			ELSE REPLACE(REPLACE(es.[program_name], N'Operating System', N'OS'), N'Microsoft SQL Server Management Studio', N'SSMS')
		END																					AS [program_name],
		CASE er.transaction_isolation_level
			WHEN 0 THEN N'Unspecified'
			WHEN 1 THEN N'ReadUncomitted'
			WHEN 2 THEN N'ReadCommitted'
			WHEN 3 THEN N'Repeatable'
			WHEN 4 THEN N'Serializable'
			WHEN 5 THEN N'Snapshot'
		END																					AS [Isolation_level],
		es.open_transaction_count,
		er.plan_handle, 
		er.statement_start_offset, 
		er.statement_end_offset
	FROM
		sys.dm_exec_sessions AS es
		INNER JOIN sys.dm_exec_requests AS er  	ON er.[session_id] = es.[session_id]
		LEFT JOIN sys.dm_exec_connections AS ec		ON ec.[session_id] = er.[session_id]
	WHERE
		es.session_id != @@SPID
		AND			
			(
				es.[status] = N'running'
				OR
					(
						es.[status] != N'running'
						AND
							(
								(
									es.is_user_process = 1
									AND es.open_transaction_count > 0
								)
							OR
								(
									es.is_user_process = 0
									AND 
										(
											(
												er.blocking_session_id IS NOT NULL
												AND er.blocking_session_id != 0
											)
											OR
											es.open_transaction_count > 0
										)
								)
							)
					)
			)
	GROUP BY
		es.[session_id],
		er.blocking_session_id,
		es.login_time,
		es.[status],
		er.[status],
		er.wait_time,
		er.wait_type,
		er.request_id,
		er.command,
		es.last_request_start_time,
		es.last_request_end_time,
		er.last_wait_type,
		er.wait_resource,
		er.cpu_time,
		er.logical_reads,
		er.reads,
		er.writes,
		er.database_id,
		es.login_name,
		es.original_login_name,
		es.[host_name],
		er.percent_complete,
		er.estimated_completion_time,
		er.[sql_handle],
		er.task_address,
		es.client_interface_name,
		es.prev_error,
		er.[language],
		ec.client_net_address,
		ec.client_tcp_port,
		ec.local_tcp_port,
		es.[program_name],
		er.prev_error,
		er.transaction_isolation_level,
		er.plan_handle, 
		er.statement_start_offset, 
		er.statement_end_offset,
		es.open_transaction_count
)
SELECT
	CONVERT(NVARCHAR(8), arc.[session_id])												AS [SPID],					-- SQL Server session ID
	CASE				--	Only for:	ALTER INDEX REORGANIZE, AUTO_SHRINK option with ALTER DATABASE, BACKUP DATABASE, DBCC CHECKDB, DBCC CHECKFILEGROUP, DBCC CHECKTABLE, DBCC INDEXDEFRAG, DBCC SHRINKDATABASE, DBCC SHRINKFILE, RECOVERY, RESTORE DATABASE, ROLLBACK, TDE ENCRYPTION
		WHEN arc.percent_complete != 0 AND arc.estimated_completion_time != 0 THEN N'Completed: '+CONVERT(NVARCHAR(8), arc.percent_complete)+N'%, Estimated End: '+CONVERT(NVARCHAR(8), arc.estimated_completion_time)+N'min'
		WHEN arc.percent_complete != 0 AND arc.estimated_completion_time = 0 THEN N'Completed: '+CONVERT(NVARCHAR(8), arc.percent_complete)+N'%'
		ELSE N''
	END
	+
	CASE
		WHEN  arc.percent_complete != 0 AND arc.[Blk by] != N''	THEN N', '+arc.[Blk by]
		WHEN  arc.percent_complete = 0 AND arc.[Blk by] != N''	THEN arc.[Blk by]
		ELSE N'' 
	END																					AS [Info],					-- Additional information about this session
	arc.[S_Status],
	RIGHT('0' + CAST(arc.[RequestTime(ms)] / (1000 * 60 * 60 * 24) AS VARCHAR), 2) + ' ' +
    RIGHT('0' + CAST((arc.[RequestTime(ms)] % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60) AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST((arc.[RequestTime(ms)] % (1000 * 60 * 60)) / (1000 * 60) AS VARCHAR), 2) + ':' +
    RIGHT('0' + CAST((arc.[RequestTime(ms)] % (1000 * 60)) / 1000 AS VARCHAR), 2) + '.' +
    RIGHT('000' + CAST(arc.[RequestTime(ms)] % 1000 AS VARCHAR), 3)						AS [Duration (dd hh:mm:ss.ms)],
	ISNULL(arc.[R_Status], arc.[S_Status])												AS [R_Status] ,
	CASE
		WHEN wt.wait_type	IS NOT NULL	THEN wt.wait_type
		WHEN wt.wait_type	IS NULL	AND arc.wait_type IS NOT NULL	THEN arc.wait_type
		ELSE N''
	END + 	CASE
		WHEN wt.wait_duration_ms IS NOT NULL AND wt.wait_duration_ms != 0 AND wt.wait_duration_ms >= arc.[RequestTime(ms)] THEN N' (' + CONVERT(NVARCHAR(16), arc.[RequestTime(ms)]) + N'ms) '
		WHEN wt.wait_duration_ms IS NOT NULL AND wt.wait_duration_ms != 0 AND wt.wait_duration_ms < arc.[RequestTime(ms)] THEN N' (' + CONVERT(NVARCHAR(16), wt.wait_duration_ms) + N'ms) '
		WHEN (wt.wait_duration_ms IS NULL OR wt.wait_duration_ms = 0) AND arc.wait_time IS NOT NULL AND arc.wait_time != 0 AND arc.wait_time >= arc.[RequestTime(ms)] AND arc.[RequestTime(ms)] <= 0 THEN N' (0ms) '
		WHEN (wt.wait_duration_ms IS NULL OR wt.wait_duration_ms = 0) AND arc.wait_time IS NOT NULL AND arc.wait_time != 0 AND arc.wait_time >= arc.[RequestTime(ms)] AND arc.[RequestTime(ms)] > 0 THEN N' (' + CONVERT(NVARCHAR(16), arc.[RequestTime(ms)]) + N'ms) '
		WHEN (wt.wait_duration_ms IS NULL OR wt.wait_duration_ms = 0) AND arc.wait_time IS NOT NULL AND arc.wait_time != 0 AND arc.wait_time < arc.[RequestTime(ms)] THEN N' (' + CONVERT(NVARCHAR(16), arc.wait_time) + N'ms) '
		ELSE N''
	END																					AS [CurrentWaitType],
	ISNULL(arc.last_wait_type, N'')														AS [LatWaitType],			-- If this request has previously been blocked, this column returns the type of the last wait. Is not nullable.
	ISNULL(arc.wait_resource, wt.resource_description)									AS [W.Resource],			-- Textual representation of a lock resource.	
	CAST(ISNULL(mg.query_cost, 0) AS DECIMAL(18, 2))									AS [Cost],																										-- Estimated query cost.
	ISNULL(arc.cpu_time, 0)																AS [CPU(ms)],				-- CPU time in milliseconds that is used by the request. Is not nullable.
	ISNULL(arc.logical_reads, 0)														AS [L.Reads],				-- Number of logical reads that have been performed by the request. Is not nullable.
	ISNULL(arc.reads, 0)																AS [P.Reads],				-- Number of reads performed by this request. Is not nullable.
	ISNULL(arc.writes, 0)																AS Writes,					-- Number of writes performed by this request. Is not nullable.
	ISNULL(mg.requested_memory_kb, 0)													AS [R.Mem(KB)],				-- Total requested amount of memory in kb.
	ISNULL(mg.granted_memory_kb, 0)														AS [G.Mem(KB)],				-- Total amount of memory actually granted in kb. Can be NULL if the memory is not granted yet. For a typical situation, this value should be the same as requested_memory_kb. For index creation, the server may allow additional on-demand memory beyond initially granted memory.
	CASE
		WHEN mg.request_time IS NULL		THEN 0
		WHEN mg.request_time IS NOT NULL AND mg.grant_time IS NULL	THEN datediff(MS, mg.request_time, GETDATE())
		ELSE datediff(MS, mg.request_time, mg.grant_time)
	END																					AS [Delay(ms)],				-- Difference between request and grant memory in milliseconds
	ISNULL(mg.used_memory_kb, 0)														AS [UsedMem(KB)],			-- Physical memory used at this moment in kb.
	ISNULL(mg.dop, 0)																	AS [DOP],
	pr.ecid																				AS [P.Threads],
	arc.command																			AS [Command],
	DB_NAME(arc.database_id)															AS [Database],
	ISNULL(OBJECT_SCHEMA_NAME(st.objectid, arc.database_id),N'dbo')						AS [Schema],
	CASE
		WHEN arc.command LIKE 'BACKUP %'	AND OBJECT_NAME(st.objectid, arc.database_id) IS NULL	THEN CONCAT(arc.command, ' ', DB_NAME(arc.database_id))
		ELSE OBJECT_NAME(st.objectid, arc.database_id)
	END																					AS [Object],
	ISNULL(SUBSTRING(st.[text], (arc.statement_start_offset/2)+1,((CASE arc.statement_end_offset WHEN -1 THEN DATALENGTH(st.[text]) WHEN 0 THEN DATALENGTH(st.[text]) ELSE arc.statement_end_offset END - arc.statement_start_offset)/2)+1), ib.[event_info])	AS [Last Executed Statement text],
	TRY_CONVERT(XML, p.query_plan)														AS [Statement_Plan],
	ib.[event_info]																		AS [event_info],
	arc.open_transaction_count															AS open_tran_count,
	arc.[Isolation_level],
	CASE
		WHEN arc.login_name	= N'' THEN arc.original_login_name
		ELSE arc.login_name
	END																					AS [Login],
	arc.[Client Address],
	arc.[host_name]																		AS Host,
	CASE
		WHEN arc.client_interface_name IS NULL OR arc.client_interface_name = LEFT(arc.[program_name], LEN(arc.client_interface_name)) THEN arc.[program_name]
		WHEN arc.client_interface_name IS NOT NULL AND arc.client_interface_name = LEFT(arc.[program_name], LEN(arc.client_interface_name)) THEN arc.[program_name]
		WHEN arc.client_interface_name IS NOT NULL AND arc.client_interface_name != LEFT(arc.[program_name], LEN(arc.client_interface_name)) THEN arc.client_interface_name + N' - ' + arc.[program_name]
		ELSE arc.client_interface_name
	END																					AS [Client & Program],
	arc.prev_error,
	CASE
		WHEN arc.prev_error = 0 THEN N''
		ELSE
			(
				SELECT
					CONVERT(NVARCHAR(8), arc.prev_error) + N': ' + m.[text]
				FROM
					sys.messages AS m
					INNER JOIN sys.syslanguages AS l ON l.msglangid = m.language_id
				WHERE
					l.[name] = arc.[language]
					AND m.message_id = arc.prev_error
			)
	END																					AS [Error]
FROM
	ALL_requests_CTE AS arc
	LEFT JOIN sys.dm_exec_query_memory_grants AS mg	ON mg.[session_id] = arc.[session_id] AND arc.request_id = mg.[request_id]
	OUTER APPLY sys.dm_exec_input_buffer(arc.[session_id], arc.request_id) AS ib
	LEFT JOIN waiting_tasks_CTE AS wt ON arc.[session_id] = wt.[session_id] AND arc.task_address = wt.waiting_task_address
	LEFT JOIN sysprocesses_CTE AS pr ON pr.spid = arc.[session_id]
	OUTER APPLY sys.dm_exec_text_query_plan(arc.plan_handle, arc.statement_start_offset, arc.statement_end_offset) AS p
	OUTER APPLY sys.dm_exec_sql_text(arc.[sql_handle]) AS st
ORDER BY
	arc.[session_id] ASC
OPTION (RECOMPILE, MAXDOP 1); 
