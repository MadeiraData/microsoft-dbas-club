DECLARE
	@PercentUsedMax float = 90

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

IF (SERVERPROPERTY('ProductVersion') <= '13')
	AND (SERVERPROPERTY('EngineEdition') NOT IN (5, 6, 8))
BEGIN
	PRINT 'Current SQL Server version (' + CAST((SERVERPROPERTY('ProductVersion')) AS VARCHAR) + ') does not have a Query Store feature.'
	PRINT 'The SQL Server Query Store is a relatively new feature introduced in SQL Server 2016 (13.x)'
	RAISERROR(N'Query Store in the current SQL Server version is not supported.',16,1)
END
ELSE IF NOT EXISTS
			(
				SELECT 1
				FROM
					sys.databases
				WHERE
					database_id > 4 
					AND is_query_store_on = 1
					AND HAS_DBACCESS([name]) = 1
			)
BEGIN
	RAISERROR(N'No databases with Query Store enabled were found on this instance.',16,1)
END
ELSE
BEGIN

	DECLARE
		@Command		NVARCHAR(MAX) = N'
	SELECT
		DB_NAME(),
		[desired_state],
		[actual_state],
		[readonly_reason],
		[current_storage_size_mb],
		[flush_interval_seconds],
		[interval_length_minutes],
		[max_storage_size_mb],
		[stale_query_threshold_days],
		[max_plans_per_query],
		[query_capture_mode],
		[size_based_cleanup_mode],
		[wait_stats_capture_mode],
		[actual_state_additional_info]
	FROM
		sys.database_query_store_options;
	';
	
	IF OBJECT_ID('tempdb..#QS_state', 'U') IS NOT NULL
	DROP TABLE #QS_state;

	CREATE TABLE #QS_state
						(
							[DataBase]							NVARCHAR(128),
							[desired_state]						SMALLINT, 
							[actual_state]						SMALLINT,
							[readonly_reason]					INT,
							[current_storage_size_mb]			BIGINT,
							[flush_interval_seconds]			BIGINT,
							[interval_length_minutes]			BIGINT,
							[max_storage_size_mb]				BIGINT,
							[stale_query_threshold_days]		BIGINT,
							[max_plans_per_query]				BIGINT,
							[query_capture_mode]				SMALLINT,
							[size_based_cleanup_mode]			SMALLINT,
							[wait_stats_capture_mode]			SMALLINT,
							[actual_state_additional_info]		NVARCHAR(MAX)
						);

	DECLARE
		@DB_Name		NVARCHAR(128),
		@spExecSQL		NVARCHAR(MAX);

	DECLARE database_cursor CURSOR
	LOCAL STATIC FORWARD_ONLY READ_ONLY
	FOR 
		SELECT
			[name] 
		FROM
			[sys].[databases]
		WHERE
			database_id > 4
		AND is_query_store_on = 1
		AND HAS_DBACCESS([name]) = 1

	OPEN database_cursor 

	WHILE 1=1
	BEGIN
			FETCH NEXT FROM database_cursor INTO @DB_Name 
			IF @@FETCH_STATUS <> 0 BREAK;

			SET @spExecSQL = QUOTENAME(@DB_Name) + N'..sp_executesql'

			INSERT INTO #QS_state
			EXEC @spExecSQL @Command;
	END 

	CLOSE database_cursor 
	DEALLOCATE database_cursor 



	SELECT
		[DataBase]							AS [Database Name],
		-- Description of the desired operation mode of Query Store, explicitly set by user
		CASE
			WHEN [desired_state] = 0 THEN 'Turned OFF'
			WHEN [desired_state] = 1 THEN 'Read only'
			WHEN [desired_state] = 2 THEN 'Read write'
			WHEN [desired_state] = 4 THEN 'READ_CAPTURE_SECONDARY'
			ELSE 'unknown'
		END									AS [Desired state],
		-- Description of the operation mode of Query Store. 
		-- In addition to list of desired states required by the user, actual state can be an error state.
		CASE	
			WHEN [actual_state] = 0 THEN 'Turned OFF'
			WHEN [actual_state] = 1 THEN 'Read only'
			WHEN [actual_state] = 2 THEN 'Read write'
			WHEN [actual_state] = 3 THEN 'ERROR'
			WHEN [actual_state] = 4 THEN 'READ_CAPTURE_SECONDARY'
			ELSE 'unknown'
		END									AS [Actual state],
		CASE
			WHEN [readonly_reason] = 0 THEN
											(
												CASE
													WHEN [desired_state] = 0	THEN 'Ok, can be eanbled'
													ELSE 'OK, work properly'
												END
											)
			WHEN [readonly_reason] = 1 THEN 'DB is in Read-Only mode.'
			WHEN [readonly_reason] = 2 THEN 'DB is in Single-User mode.'
			WHEN [readonly_reason] = 4 THEN 'DB is in Emergency mode.'
			WHEN [readonly_reason] = 8 THEN 'DB is Secondary replica in ' + (
																					CASE
																						WHEN SUBSTRING(@@VERSION, 1, CHARINDEX(' (', @@VERSION)) LIKE '%Azure%' THEN 'Azure SQL Database geo-replication.'
																						ELSE 'Always On.'
																					END
																					)
			WHEN [readonly_reason] = 65536 THEN 'Error 65536'
			--	The Query Store current storage size and has reached the size limit set by the MAX_STORAGE_SIZE_MB option. Run ALTER DATABASE [' + [DataBase] + N'] SET QUERY_STORE (OPERATION_MODE = READ_WRITE, MAX_STORAGE_SIZE_MB = ' + CAST(CAST(([max_storage_size_mb] * 1.1) AS INT) AS NVARCHAR(32)) + N')
			WHEN [readonly_reason] = 131072	THEN 'Error 131072'
			--	The number of different statements in Query Store has reached the internal memory limit. Consider removing queries that you do not need or upgrading to a higher service tier to enable transferring Query Store to read-write mode
			WHEN [readonly_reason] = 262144	THEN 'Error 262144'
			--	Size of in-memory items waiting to be persisted on disk has reached the internal memory limit. Query Store will be in read-only mode temporarily until the in-memory items are persisted on disk
			WHEN [readonly_reason] = 524288	THEN 'Error 524288'
			--	Database has reached disk size limit. Query Store is part of user database, so if there is no more available space for a database, that means that Query Store cannot grow further anymore.

			ELSE CAST([readonly_reason]	AS VARCHAR(1000))
		END									AS [Status],

		-- storage
		[max_storage_size_mb]				AS [Storage Assigned (MB)],
		[current_storage_size_mb]			AS [Storage in Use (MB)],

		[flush_interval_seconds]			AS [Flushing period (sec)],

		CASE
			WHEN [query_capture_mode] = 1 THEN 'All'
			WHEN [query_capture_mode] = 2 THEN 'Auto'	
			ELSE 'None'
			END								AS [Active capture mode],

		CASE
			WHEN [stale_query_threshold_days] = 0 THEN 'CleanUp disabled'
			ELSE 'Kept for ' + CAST([stale_query_threshold_days] AS VARCHAR) + ' days'
			END								AS [Query retention policy],

		[interval_length_minutes]			AS [Stats Aggregation Interval (min)],

		[max_plans_per_query]				AS [MAX Plans per Puery],
		CASE
			WHEN [size_based_cleanup_mode] = 1 THEN 'AUTO'
			ELSE 'OFF'
		END									AS [SizeBased Cleanup]
			,
		CASE
			WHEN [wait_stats_capture_mode] = 1 THEN 'Captured'
			ELSE 'Not Captured'
		END									AS [Wait Statistics],
		[actual_state_additional_info]
	FROM
		#QS_state
	WHERE
		@PercentUsedMax IS NULL
		OR [current_storage_size_mb] * 100.0 / [max_storage_size_mb] >= @PercentUsedMax
	GROUP BY
		[DataBase],
		[desired_state],
		[actual_state],
		[readonly_reason],
		[current_storage_size_mb],
		[flush_interval_seconds],
		[interval_length_minutes],
		[max_storage_size_mb],
		[stale_query_threshold_days],
		[max_plans_per_query],
		[query_capture_mode],
		[size_based_cleanup_mode],
		[wait_stats_capture_mode],
		[actual_state_additional_info]

END