/*
Get Partition Gaps Status
=========================
Author: Eitan Blumin
Date: 2024-04-02
Description:
This script will output the current status of partition ranges close to
being exhausted based on the total number of partitions of the partition function.
Use this script to detect situations where data in table(s) is close to fill up
all partition ranges, indicating that it's most likely about time to create new
partition ranges.
*/
DECLARE
	  @FilterByPartitionFunction	SYSNAME	= NULL	-- optionally filter by a specific partition function name
	, @MinGapFromEnd				INT		= 3		-- what's the minimum gap of populated partitions from total number of partitions

SELECT *
FROM
(
SELECT
  database_name				= DB_NAME()
, partition_function		= pf.name
, boundary_side				= CASE WHEN pf.boundary_value_on_right = 1 THEN 'RIGHT' ELSE 'LEFT' END
, total_partitions_fanout	= pf.fanout
, min_with_rows_partition_number		= MIN(CASE WHEN p.rows > 0 THEN p.partition_number END)
, min_with_rows_partition_range_value	= MIN(CASE WHEN p.rows > 0 THEN prv.value END)
, max_with_rows_partition_number		= MAX(CASE WHEN p.rows > 0 THEN p.partition_number END)
, max_with_rows_partition_range_value	= MAX(CASE WHEN p.rows > 0 THEN prv.value END)
FROM sys.partition_functions AS pf
INNER JOIN sys.partition_schemes as ps on ps.function_id=pf.function_id
INNER JOIN sys.indexes as si on si.data_space_id=ps.data_space_id
INNER JOIN sys.partitions as p on si.object_id=p.object_id and si.index_id=p.index_id
LEFT JOIN sys.partition_range_values as prv on prv.function_id=pf.function_id AND p.partition_number= 
		CASE pf.boundary_value_on_right WHEN 1
			THEN prv.boundary_id + 1
		ELSE prv.boundary_id
		END
WHERE
	(@FilterByPartitionFunction IS NULL OR pf.name = @FilterByPartitionFunction)
	AND si.index_id <= 1
GROUP BY
	pf.name, pf.boundary_value_on_right, pf.fanout
) AS q
WHERE min_with_rows_partition_number > 2
OR total_partitions_fanout - max_with_rows_partition_number <= @MinGapFromEnd
OPTION(RECOMPILE)
