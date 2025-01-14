USE [YourDatabaseName]; -- change as needed
GO
DECLARE @ProcedureName NVARCHAR(128) = 'YourStoredProcedureName'; -- change as needed


-- Retrieve query plan stats from the plan cache based on object_id
SELECT 
	cp.plan_handle,
	qp.query_plan,
	OBJECT_SCHEMA_NAME(st.objectid) AS SchemaName,
	OBJECT_NAME(st.objectid) AS ObjectName,
	DB_NAME(st.dbid) AS DatabaseName,
	st.text AS [SQLBatchText],
	LTRIM(SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1, 
		(CASE qs.statement_end_offset 
		WHEN -1 THEN DATALENGTH(st.text) 
		ELSE qs.statement_end_offset 
		END - qs.statement_start_offset) / 2 + 1)) AS [Statement],
	qs.*
FROM 
    sys.dm_exec_cached_plans AS cp
CROSS APPLY 
    sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY 
    sys.dm_exec_query_plan(cp.plan_handle) AS qp
CROSS APPLY
	(
		SELECT qs.query_plan_hash, qs.query_hash, qs.statement_start_offset, qs.statement_end_offset
		, TotalDistinctExecPlans = COUNT(*)
		, TotalExecutionCount = SUM(qs.execution_count)
		, TotalWorkerTime = SUM(qs.total_worker_time)
		, TotalElapsedTime = SUM(qs.total_elapsed_time)
		, TotalPhysicalReads = SUM(qs.total_physical_reads)
		, TotalLogicalReads = SUM(qs.total_logical_reads)
		, TotalLogicalWrites = SUM(qs.total_logical_writes)
		, TotalGrantKB = SUM(qs.total_grant_kb)
		, TotalUsedGrantKB = SUM(qs.total_used_grant_kb)
		, CreateTime = MIN(qs.creation_time)
		FROM sys.dm_exec_query_stats AS qs
		WHERE qs.plan_handle = cp.plan_handle
		GROUP BY qs.query_plan_hash, qs.query_hash, qs.statement_start_offset, qs.statement_end_offset
	) as qs
WHERE 
	st.dbid = DB_ID()
AND st.objectid IS NOT NULL
AND st.objectid = OBJECT_ID(@ProcedureName)

