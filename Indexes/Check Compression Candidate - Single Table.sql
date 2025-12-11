/*
Compression Savings Estimation Check for a Single Table
=======================================================
Author: Eitan Blumin, Madeira Data Solutions
Date: 2021-09-17
Last updated: 2025-12-11
*/
DECLARE @TableName			sysname		= 'MyTableName'		-- change to your table name
DECLARE @DoSavingsEstimationCheck	bit		= 0			-- change to 1 to perform estimation checks



/****** do not change anything below this line ******/



SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @SqlStartTime DATETIME, @UpTimeDays INT, @SqlStartTimeString VARCHAR(25);
SELECT @SqlStartTime = sqlserver_start_time FROM sys.dm_os_sys_info;
SET @UpTimeDays = DATEDIFF(dd, @SqlStartTime, GETDATE())
SET @SqlStartTimeString = CONVERT(varchar(25), @SqlStartTime, 121)

RAISERROR(N'--- SQL Server is operational since %s (~%d days)', 0, 1, @SqlStartTimeString, @UpTimeDays) WITH NOWAIT;


DECLARE @estimationResults AS TABLE
(object_name sysname, schema_name sysname, index_id int, partition_number int
, size_with_current_compression_settings_KB int, size_with_requested_compression_setting_KB int
, sample_size_with_current_compression_setting_KB int, sample_size_with_requested_compression_setting_KB int
, compression_level sysname null);


IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;

SELECT
	  database_name = DB_NAME()
	, schema_name = OBJECT_SCHEMA_NAME(p.object_id)
	, table_name = OBJECT_NAME(p.object_id)
	, p.object_id
	, p.index_id
	, index_name = ix.name
	, p.partition_number
	, range_scans_percent = ISNULL(
				FLOOR(SUM(ISNULL(ios.range_scan_count,0)) * 1.0 /
				NULLIF(SUM(
					ISNULL(ios.range_scan_count,0) +
					ISNULL(ios.leaf_delete_count,0) + 
					ISNULL(ios.leaf_insert_count,0) + 
					ISNULL(ios.leaf_page_merge_count,0) + 
					ISNULL(ios.leaf_update_count,0)
				), 0) * 100.0), 0)
	, updates_percent = ISNULL(
				CEILING(SUM(ISNULL(ios.leaf_update_count, 0)) * 1.0 /
				NULLIF(SUM(
					ISNULL(ios.range_scan_count,0) +
					ISNULL(ios.leaf_delete_count,0) + 
					ISNULL(ios.leaf_insert_count,0) + 
					ISNULL(ios.leaf_page_merge_count,0) + 
					ISNULL(ios.leaf_update_count,0)
				), 0) * 100.0), 0)
	, size_MB = CEILING(SUM(ISNULL(sps.in_row_data_page_count,0) + ISNULL(sps.row_overflow_used_page_count,0) + ISNULL(sps.lob_reserved_page_count,0)) / 128.0)
	, in_row_percent = ISNULL(
				FLOOR(SUM(ISNULL(sps.in_row_data_page_count,0)) * 1.0 
				/ NULLIF(SUM(ISNULL(sps.in_row_data_page_count,0) + ISNULL(sps.row_overflow_used_page_count,0) + ISNULL(sps.lob_reserved_page_count,0)),0)
				* 100.0), 0)
	, row_estimation_check = N'EXEC ' + QUOTENAME(DB_NAME()) + '.sys.sp_estimate_data_compression_savings ' + N'
						 @schema_name		= ''' + OBJECT_SCHEMA_NAME(p.object_id) + N''',  
						 @object_name		= ''' + OBJECT_NAME(p.object_id) + N''',
						 @index_id		= ' + CONVERT(nvarchar(max), p.index_id) + N',
						 @partition_number	= ' + CONVERT(nvarchar(max), p.partition_number) + N',   
						 @data_compression	= ''ROW'';'
	, row_rebuild_command		= N'USE ' + QUOTENAME(DB_NAME()) + N'; ALTER ' + ISNULL(N'INDEX ' + QUOTENAME(ix.name) + N' ON ', N'TABLE ') + QUOTENAME(OBJECT_SCHEMA_NAME(p.object_id)) + '.' + QUOTENAME(OBJECT_NAME(p.object_id)) 
				+ N' REBUILD PARTITION = ' + ISNULL(CONVERT(nvarchar(max),p.partition_number), N'ALL') 
				+ N' WITH (DATA_COMPRESSION = ROW);'
	, page_estimation_check = N'EXEC ' + QUOTENAME(DB_NAME()) + '.sys.sp_estimate_data_compression_savings ' + N'
						 @schema_name		= ''' + OBJECT_SCHEMA_NAME(p.object_id) + N''',  
						 @object_name		= ''' + OBJECT_NAME(p.object_id) + N''',
						 @index_id		= ' + CONVERT(nvarchar(max), p.index_id) + N',
						 @partition_number	= ' + CONVERT(nvarchar(max), p.partition_number) + N',   
						 @data_compression	= ''PAGE'';'
	, page_rebuild_command		= N'USE ' + QUOTENAME(DB_NAME()) + N'; ALTER ' + ISNULL(N'INDEX ' + QUOTENAME(ix.name) + N' ON ', N'TABLE ') + QUOTENAME(OBJECT_SCHEMA_NAME(p.object_id)) + '.' + QUOTENAME(OBJECT_NAME(p.object_id)) 
				+ N' REBUILD PARTITION = ' + ISNULL(CONVERT(nvarchar(max),p.partition_number), N'ALL') 
				+ N' WITH (DATA_COMPRESSION = PAGE);'
INTO #Results
FROM sys.partitions AS p WITH(NOLOCK)
INNER JOIN sys.indexes AS ix WITH(NOLOCK) ON p.object_id = ix.object_id AND p.index_id = ix.index_id
OUTER APPLY sys.dm_db_index_operational_stats(db_id(),p.object_id,p.index_id,p.partition_number) AS ios
LEFT JOIN sys.dm_db_partition_stats AS sps WITH(NOLOCK) ON sps.partition_id = p.partition_id
WHERE p.object_id = OBJECT_ID(@TableName)
-- Ignore indexes or tables with unsupported LOB/FILESTREAM columns
AND NOT EXISTS
(
SELECT NULL
FROM sys.columns AS c
INNER JOIN sys.types AS t 
ON c.system_type_id = t.system_type_id
AND c.user_type_id = t.user_type_id
LEFT JOIN sys.index_columns AS ixc
ON ixc.object_id = c.object_id
AND ixc.column_id = c.column_id
AND ix.index_id = ixc.index_id
WHERE (t.[name] in ('text', 'ntext', 'image') OR c.is_filestream = 1)
AND ix.object_id = c.object_id
AND (ix.index_id IN (0,1) OR ixc.index_id IS NOT NULL)
)
GROUP BY
	  p.object_id
	, p.index_id
	, ix.name
	, p.partition_number
ORDER BY
	size_MB DESC
OPTION (RECOMPILE, MAXDOP 1);

IF @DoSavingsEstimationCheck = 1
BEGIN

	DECLARE @IndexId INT, @PartitionNumber INT, @RowCheckCmd NVARCHAR(MAX), @PageCheckCMD NVARCHAR(MAX)
	DECLARE cur CURSOR
	LOCAL STATIC FORWARD_ONLY READ_ONLY
	FOR
	SELECT index_id, partition_number, row_estimation_check, page_estimation_check
	FROM #Results

	OPEN cur;

	WHILE 1=1
	BEGIN
		FETCH NEXT FROM cur INTO @IndexId, @PartitionNumber, @RowCheckCmd, @PageCheckCMD;
		IF @@FETCH_STATUS <> 0 BREAK;

		INSERT INTO @estimationResults
		(object_name, schema_name, index_id, partition_number
		, size_with_current_compression_settings_KB, size_with_requested_compression_setting_KB
		, sample_size_with_current_compression_setting_KB, sample_size_with_requested_compression_setting_KB)
		EXEC (@RowCheckCmd);

		UPDATE @estimationResults SET compression_level = 'ROW'
		WHERE compression_level IS NULL AND index_id = @IndexId AND partition_number = @PartitionNumber

	
		INSERT INTO @estimationResults
		(object_name, schema_name, index_id, partition_number
		, size_with_current_compression_settings_KB, size_with_requested_compression_setting_KB
		, sample_size_with_current_compression_setting_KB, sample_size_with_requested_compression_setting_KB)
		EXEC (@PageCheckCMD);

		UPDATE @estimationResults SET compression_level = 'PAGE'
		WHERE compression_level IS NULL AND index_id = @IndexId AND partition_number = @PartitionNumber
	END

	CLOSE cur;
	DEALLOCATE cur;
	

	SELECT R.*
	, CurentTotalSize_KB = ISNULL(esPage.size_with_current_compression_settings_KB, esRow.size_with_current_compression_settings_KB)
	, SizeWithPageCompression_KB = esPage.size_with_requested_compression_setting_KB
	, Compression_Ratio_Page = esPage.size_with_requested_compression_setting_KB * 1.0 / esPage.size_with_current_compression_settings_KB
	, Compression_Save_Estimation_Page_KB = esPage.size_with_current_compression_settings_KB - esPage.size_with_requested_compression_setting_KB
	, SizeWithRowCompression_KB = esRow.size_with_requested_compression_setting_KB
	, Compression_Ratio_Row = esRow.size_with_requested_compression_setting_KB * 1.0 / esRow.size_with_current_compression_settings_KB
	, Compression_Save_Estimation_Row_KB = esRow.size_with_current_compression_settings_KB - esRow.size_with_requested_compression_setting_KB
	FROM #Results AS R
	LEFT JOIN @estimationResults AS esPage ON R.index_id = esPage.index_id AND R.partition_number = esPage.partition_number AND esPage.compression_level = 'PAGE'
	LEFT JOIN @estimationResults AS esRow ON R.index_id = esRow.index_id AND R.partition_number = esRow.partition_number AND esRow.compression_level = 'ROW'

END
ELSE
BEGIN
	SELECT * FROM #Results;
END