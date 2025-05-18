DECLARE
	@PercentUsedMax float = 90

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

IF (SERVERPROPERTY('ProductVersion') < '13')
	AND (SERVERPROPERTY('EngineEdition') NOT IN (5, 6, 8))
BEGIN
	PRINT 'Current SQL Server version (' + CAST((SERVERPROPERTY('ProductVersion')) AS VARCHAR) + ') does not have a Query Store feature.'
	PRINT 'The SQL Server Query Store is a relatively new feature introduced in SQL Server 2016 (13.x)'
	RAISERROR(N'Query Store in the current SQL Server version is not supported.',16,1)
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
		[max_storage_size_mb]
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
							[max_storage_size_mb]				BIGINT
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
		AND [state] = 0
		AND HAS_DBACCESS([name]) = 1

	OPEN database_cursor 

	WHILE 1=1
	BEGIN
			FETCH NEXT FROM database_cursor INTO @DB_Name 
			IF @@FETCH_STATUS <> 0 BREAK;

			SET @spExecSQL = QUOTENAME(@DB_Name) + N'..sp_executesql'

			INSERT INTO #QS_state
			EXEC @spExecSQL @Command WITH RECOMPILE;
	END 

	CLOSE database_cursor 
	DEALLOCATE database_cursor 



	SELECT
		CONCAT(N'Query store of database ', QUOTENAME([DataBase]), N' (desired state: ',
		-- Description of the desired operation mode of Query Store, explicitly set by user
		CASE
			WHEN [desired_state] = 0 THEN 'Turned OFF'
			WHEN [desired_state] = 1 THEN 'Read only'
			WHEN [desired_state] = 2 THEN 'Read write'
			WHEN [desired_state] = 4 THEN 'READ_CAPTURE_SECONDARY'
			ELSE 'unknown'
		END, N', actual state: ',
		-- Description of the operation mode of Query Store. 
		-- In addition to list of desired states required by the user, actual state can be an error state.
		CASE	
			WHEN [actual_state] = 0 THEN 'Turned OFF'
			WHEN [actual_state] = 1 THEN 'Read only'
			WHEN [actual_state] = 2 THEN 'Read write'
			WHEN [actual_state] = 3 THEN 'ERROR'
			WHEN [actual_state] = 4 THEN 'READ_CAPTURE_SECONDARY'
			ELSE 'unknown'
		END, 
		CASE
			WHEN [readonly_reason] = 1 THEN ' - DB is in Read-Only mode.'
			WHEN [readonly_reason] = 2 THEN ' - DB is in Single-User mode.'
			WHEN [readonly_reason] = 4 THEN ' - DB is in Emergency mode.'
			WHEN [readonly_reason] = 8 THEN ' - DB is Secondary replica in ' + (
																					CASE
																						WHEN SUBSTRING(@@VERSION, 1, CHARINDEX(' (', @@VERSION)) LIKE '%Azure%' THEN 'Azure SQL Database geo-replication.'
																						ELSE 'Always On.'
																					END
																					)
			WHEN [readonly_reason] = 65536  THEN ' - Error 65536' --	The Query Store current storage size and has reached the size limit set by the MAX_STORAGE_SIZE_MB option. Run ALTER DATABASE [' + [DataBase] + N'] SET QUERY_STORE (OPERATION_MODE = READ_WRITE, MAX_STORAGE_SIZE_MB = ' + CAST(CAST(([max_storage_size_mb] * 1.1) AS INT) AS NVARCHAR(32)) + N')
			WHEN [readonly_reason] = 131072	THEN ' - Error 131072' --	The number of different statements in Query Store has reached the internal memory limit. Consider removing queries that you do not need or upgrading to a higher service tier to enable transferring Query Store to read-write mode
			WHEN [readonly_reason] = 262144	THEN ' - Error 262144' --	Size of in-memory items waiting to be persisted on disk has reached the internal memory limit. Query Store will be in read-only mode temporarily until the in-memory items are persisted on disk
			WHEN [readonly_reason] = 524288	THEN ' - Error 524288' --	Database has reached disk size limit. Query Store is part of user database, so if there is no more available space for a database, that means that Query Store cannot grow further anymore.

			ELSE N''
		END, N') has ', [current_storage_size_mb], N' MB used out of ', [max_storage_size_mb], N' MB'
		)
		, PercentUsed = CONVERT(float, [current_storage_size_mb] * 100.0 / [max_storage_size_mb])
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
		[max_storage_size_mb]
	OPTION (RECOMPILE);
END