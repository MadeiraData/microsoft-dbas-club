/*
	Created: Vitaly Bruk / MadeiraData
	Date:	2024-12-25
	
	Description:
		This T-SQL script is designed to calculate the optimal batch size for bulk load operations in SQL Server (2008 and later versions). 
		It provides the necessary values to optimize bulk inserts, ensuring efficient use of storage and minimizing performance bottlenecks. 
		By determining the average row size and calculating the optimal batch size, this script helps improve the efficiency and speed of bulk data operations.

		The script multiplies the calculated rows per extent by a factor (e.g., 10) to determine the optimal batch size. 
		This factor can be adjusted based on workload testing to find the best performance for your specific environment.
*/


-- Replace 'YourSchema' and 'YourTableName' with your schema and table name
DECLARE
	@Schema		NVARCHAR(128) = 'YourSchema',
	@TableName	NVARCHAR(128) = 'YourTableName';

-- Variables to hold table and row data
DECLARE
	@AvgRowSizeBytes	FLOAT, 
    @RowsPerExtent		INT, 
    @BatchSize			INT, 
    @ExtentSizeBytes	INT		= 64 * 1024; -- 64 KB

-- Check if the schema and table exist
IF NOT EXISTS
			(
				SELECT 1
				FROM
					sys.schemas s
					INNER JOIN sys.tables t ON s.[schema_id] = t.[schema_id]
				WHERE
					s.name = @Schema
					AND t.name = @TableName
			)
BEGIN
    RAISERROR('The specified schema or table does not exist.', 16, 1);
    RETURN;
END

-- Get average row size in bytes using sys.dm_db_index_physical_stats and sys.dm_db_partition_stats
SELECT 
    @AvgRowSizeBytes = SUM(ps.used_page_count * 8.0 * 1024.0) / SUM(ps.row_count) -- Page size (8 KB) converted to bytes
FROM 
    sys.dm_db_partition_stats ps
	INNER JOIN sys.partitions p ON ps.[partition_id] = p.[partition_id]
	INNER JOIN sys.objects o ON p.[object_id] = o.[object_id]
WHERE 
    SCHEMA_NAME(o.[schema_id]) = @Schema
    AND OBJECT_NAME(p.[object_id]) = @TableName
    AND p.index_id IN (0, 1);						-- Include heap or clustered index

-- Calculate rows per extent and batch size
SET @RowsPerExtent = @ExtentSizeBytes / @AvgRowSizeBytes;
SET @BatchSize = @RowsPerExtent * 10; -- Multiply by a factor (e.g., 10) for optimization

-- Output the results
SELECT 
    @Schema				AS SchemaName,
    @TableName			AS TableName,
    @AvgRowSizeBytes	AS AvgRowSizeBytes,
    @RowsPerExtent		AS RowsPerExtent,
    @BatchSize			AS OptimalBatchSize;
