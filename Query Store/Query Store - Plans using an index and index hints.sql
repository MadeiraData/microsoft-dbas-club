/*
Source: https://littlekendra.com/2017/01/24/how-to-find-queries-using-an-index-and-queries-using-index-hints/
*/
DECLARE @IndexName sysname = 'IX_Sales_Invoice_InvoiceDate'

/* Find queries using the index in Query Store */
SELECT
	qsq.query_id,
    qsq.query_hash,
	QUOTENAME(OBJECT_SCHEMA_NAME(qsq.object_id)) + '.' + QUOTENAME(OBJECT_NAME(qsq.object_id)) AS objectName,
    (SELECT TOP 1 qsqt.query_sql_text FROM sys.query_store_query_text qsqt
        WHERE qsqt.query_text_id = MAX(qsq.query_text_id)) AS sqltext,    
    SUM(qrs.count_executions) AS execution_count,
    SUM(qrs.count_executions) * AVG(qrs.avg_logical_io_reads) as est_logical_reads,
    SUM(qrs.count_executions) * AVG(qrs.avg_logical_io_writes) as est_writes,
    MIN(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as min_execution_time_PST,
    MAX(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as last_execution_time_PST,
    SUM(qsq.count_compiles) AS sum_compiles,
    TRY_CONVERT(XML, (SELECT TOP 1 qsp2.query_plan from sys.query_store_plan qsp2
        WHERE qsp2.query_id=qsq.query_id
        ORDER BY qsp2.plan_id DESC)) AS query_plan
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp on qsq.query_id=qsp.query_id
CROSS APPLY (SELECT TRY_CONVERT(XML, qsp.query_plan) AS query_plan_xml) AS qpx
JOIN sys.query_store_runtime_stats qrs on qsp.plan_id = qrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi on qrs.runtime_stats_interval_id=qsrsi.runtime_stats_interval_id
WHERE    
    qsp.query_plan like N'%' + @IndexName + N'%'
    AND qsp.query_plan not like '%query_store_runtime_stats%' /* Not a query store query */
    AND qsp.query_plan not like '%dm_exec_sql_text%' /* Not a query searching the plan cache */
    AND qsp.query_plan not like '%sys.indexes%' /* Not a query searching the indexes system table */
GROUP BY 
    qsq.query_id, qsq.object_id, qsq.query_hash
ORDER BY est_logical_reads DESC
OPTION (RECOMPILE);

GO

/* Find index hints in Query Store */
SELECT
    qsq.query_id,
    qsq.query_hash,
    (SELECT TOP 1 qsqt.query_sql_text FROM sys.query_store_query_text qsqt
        WHERE qsqt.query_text_id = MAX(qsq.query_text_id)) AS sqltext,    
    SUM(qrs.count_executions) AS execution_count,
    SUM(qrs.count_executions) * AVG(qrs.avg_logical_io_reads) as est_logical_reads,
    SUM(qrs.count_executions) * AVG(qrs.avg_logical_io_writes) as est_writes,
    MIN(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as min_execution_time_PST,
    MAX(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as last_execution_time_PST,
    SUM(qsq.count_compiles) AS sum_compiles,
    TRY_CONVERT(XML, (SELECT TOP 1 qsp2.query_plan from sys.query_store_plan qsp2
        WHERE qsp2.query_id=qsq.query_id
        ORDER BY qsp2.plan_id DESC)) AS query_plan
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp on qsq.query_id=qsp.query_id
CROSS APPLY (SELECT TRY_CONVERT(XML, qsp.query_plan) AS query_plan_xml) AS qpx
JOIN sys.query_store_runtime_stats qrs on qsp.plan_id = qrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi on qrs.runtime_stats_interval_id=qsrsi.runtime_stats_interval_id
WHERE    
    qsp.query_plan like N'%ForcedIndex="1"%'
GROUP BY 
    qsq.query_id, qsq.query_hash
ORDER BY est_logical_reads DESC
OPTION (RECOMPILE);
GO
