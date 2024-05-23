/*
How This Helps Identify Performance-Impacting Queries:

1. Parallel Queries: Queries with a high total_dop value indicate parallel execution. While parallel execution can speed up individual queries, it can also lead to resource contention, especially if many queries run in parallel simultaneously.
2. High-Volume Queries: Queries with a high execution_count value but low total_dop are typically executed with MAXDOP 1. If these queries are executed frequently, they can still significantly impact the overall performance of the database.

By identifying both types of queries, database administrators can take actions such as query optimization, indexing, or adjusting the degree of parallelism settings to improve overall database performance.

Source:
https://techcommunity.microsoft.com/t5/azure-database-support-blog/lesson-learned-487-identifying-parallel-and-high-volume-queries/ba-p/4141248
*/
WITH QueryStats AS (
    SELECT 
        query_hash,
        SUM(total_worker_time) AS total_worker_time,
        SUM(total_elapsed_time) AS total_elapsed_time,
        SUM(execution_count) AS execution_count,
        MAX(max_dop) AS total_dop
    FROM 
        sys.dm_exec_query_stats
    GROUP BY 
        query_hash
)
SELECT TOP (20)
    qs.query_hash,
    qs.execution_count,
    qs.total_worker_time,
    qs.total_elapsed_time,
    qs.total_dop,
    SUBSTRING(st.text, 
              (qs_statement.statement_start_offset/2) + 1, 
              ((CASE qs_statement.statement_end_offset 
                  WHEN -1 THEN DATALENGTH(st.text) 
                  ELSE qs_statement.statement_end_offset 
               END - qs_statement.statement_start_offset)/2) + 1) AS query_text,
	p.query_plan
FROM 
    QueryStats qs
CROSS APPLY 
    (SELECT TOP 1 * 
     FROM sys.dm_exec_query_stats qs_statement 
     WHERE qs.query_hash = qs_statement.query_hash) qs_statement
CROSS APPLY 
    sys.dm_exec_sql_text(qs_statement.sql_handle) AS st
CROSS APPLY 
    sys.dm_exec_query_plan(qs_statement.plan_handle) AS p
ORDER BY 
    qs.total_worker_time DESC;