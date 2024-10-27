/*
Source: https://littlekendra.com/2017/01/24/how-to-find-queries-using-an-index-and-queries-using-index-hints/
 20/10/2024		Nirit Leibovitch	Change WHERE clause to include only palce which actually useses the index
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
    textplan.query_plan like '%Index="![IX_Client!]"%' ESCAPE '!'
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


/*
Another option:
Source: https://www.sqlskills.com/blogs/jonathan/finding-what-queries-in-the-plan-cache-use-a-specific-index/
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
DECLARE @IndexName AS NVARCHAR(128) = 'PK__TestTabl__FFEE74517ABC33CD';

-- Make sure the name passed is appropriately quoted
IF (LEFT(@IndexName, 1) <> '[' AND RIGHT(@IndexName, 1) <> ']') SET @IndexName = QUOTENAME(@IndexName);
--Handle the case where the left or right was quoted manually but not the opposite side
IF LEFT(@IndexName, 1) <> '[' SET @IndexName = '['+@IndexName;
IF RIGHT(@IndexName, 1) <> ']' SET @IndexName = @IndexName + ']';

-- Dig into the plan cache and find all plans using this index
;WITH XMLNAMESPACES
   (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')   
SELECT
stmt.value('(@StatementText)[1]', 'varchar(max)') AS SQL_Text,
obj.value('(@Database)[1]', 'varchar(128)') AS DatabaseName,
obj.value('(@Schema)[1]', 'varchar(128)') AS SchemaName,
obj.value('(@Table)[1]', 'varchar(128)') AS TableName,
obj.value('(@Index)[1]', 'varchar(128)') AS IndexName,
obj.value('(@IndexKind)[1]', 'varchar(128)') AS IndexKind,
cp.plan_handle,
query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
CROSS APPLY query_plan.nodes('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple') AS batch(stmt)
CROSS APPLY stmt.nodes('.//IndexScan/Object[@Index=sql:variable("@IndexName")]') AS idx(obj)
OPTION(MAXDOP 1, RECOMPILE);
GO 
