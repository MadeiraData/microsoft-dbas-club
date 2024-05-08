/*
Source: https://littlekendra.com/2017/01/24/how-to-find-queries-using-an-index-and-queries-using-index-hints/
*/

/* Search for queries in the execution plan cache using a specific index */
SELECT 
    querystats.plan_handle,
    querystats.query_hash,
    SUBSTRING(sqltext.text, (querystats.statement_start_offset / 2) + 1, 
                (CASE querystats.statement_end_offset 
                    WHEN -1 THEN DATALENGTH(sqltext.text) 
                    ELSE querystats.statement_end_offset 
                END - querystats.statement_start_offset) / 2 + 1) AS sqltext, 
    querystats.execution_count,
    querystats.total_logical_reads,
    querystats.total_logical_writes,
    querystats.creation_time,
    querystats.last_execution_time,
    CAST(query_plan AS xml) as plan_xml
FROM sys.dm_exec_query_stats as querystats
CROSS APPLY sys.dm_exec_text_query_plan
    (querystats.plan_handle, querystats.statement_start_offset, querystats.statement_end_offset) 
    as textplan
CROSS APPLY sys.dm_exec_sql_text(querystats.sql_handle) AS sqltext 
WHERE 
    textplan.query_plan like '%PK_Sales_Invoices%'
ORDER BY querystats.last_execution_time DESC
OPTION (RECOMPILE);
GO

/* Search the execution plan cache for index hints */
SELECT 
    querystats.plan_handle,
    querystats.query_hash,
    SUBSTRING(sqltext.text, (querystats.statement_start_offset / 2) + 1, 
                (CASE querystats.statement_end_offset 
                    WHEN -1 THEN DATALENGTH(sqltext.text) 
                    ELSE querystats.statement_end_offset 
                END - querystats.statement_start_offset) / 2 + 1) AS sqltext, 
    querystats.execution_count,
    querystats.total_logical_reads,
    querystats.total_logical_writes,
    querystats.creation_time,
    querystats.last_execution_time,
    CAST(query_plan AS xml) as plan_xml
FROM sys.dm_exec_query_stats as querystats
CROSS APPLY sys.dm_exec_text_query_plan
    (querystats.plan_handle, querystats.statement_start_offset, querystats.statement_end_offset) 
    as textplan
CROSS APPLY sys.dm_exec_sql_text(querystats.sql_handle) AS sqltext 
WHERE 
    textplan.query_plan like N'%ForcedIndex="1"%'
    and UPPER(sqltext.text) like N'%INDEX%'
OPTION (RECOMPILE);
GO
