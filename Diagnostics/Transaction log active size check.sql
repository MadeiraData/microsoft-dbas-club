SELECT
	DB.[name] AS DBName,
	ls.number_of_vlfs AS VLFsCount,
	ls.total_log_size_in_bytes AS TotalFileSize,
	ls.active_log_size_in_bytes AS ActiveFileSize,
	TotalFileSize_MB = ls.total_log_size_in_bytes / 1024.0 / 1024,
	ActiveFileSize_MB = ls.active_log_size_in_bytes / 1024.0 / 1024,
	ActiveFileSize_PCT = CONVERT(smallmoney, ls.active_log_size_in_bytes * 1.0 / ls.total_log_size_in_bytes * 100),
	DB.log_reuse_wait_desc,
	RemediationCommand =
		CASE ls.log_reuse_wait_desc
			WHEN 'REPLICATION' THEN CONCAT(
				'-- Confirm replication/CDC status, then consider: ',
				'USE [', DB.[name], ']; EXEC sp_repldone NULL, NULL, 0,0,1; CHECKPOINT;')
			WHEN 'LOG_BACKUP' THEN CONCAT(
				'-- Commit all open transactions and run a transaction log backup: ',
				'USE [', DB.[name], ']; CHECKPOINT; BACKUP LOG [', DB.[name], '] TO DISK = ''<your_backup_location>'';')
			WHEN 'CDC' THEN CONCAT(
				'-- Investigate CDC cleanup needs: ',
				'USE [', DB.[name], ']; EXEC sys.sp_cdc_cleanup_change_table;')
			WHEN 'CHANGE_TRACKING' THEN CONCAT(
				'-- Consider resetting change tracking: ',
				'ALTER DATABASE [', DB.[name], '] SET CHANGE_TRACKING = OFF; -- Then back ON as needed and re-enable for relevant tables')
			WHEN 'AVAILABILITY_REPLICA' THEN CONCAT(
				'-- Investigate AG lag: ',
				'SELECT * FROM sys.dm_hadr_database_replica_states WHERE database_id = ', DB.database_id)
			WHEN 'ACTIVE_BACKUP_OR_RESTORE' THEN
				'-- A backup or restore is in progress; monitor completion: SELECT * FROM sys.dm_exec_requests WHERE command LIKE ''%BACKUP%'';'
			WHEN 'XTP_CHECKPOINT' THEN CONCAT(
				'-- Review XTP checkpoint backlog: ',
				'USE [', DB.[name], ']; ',
				'SELECT * FROM sys.dm_db_xtp_checkpoint_stats; -- Look at target_bytes vs last_checkpoint_end_lsn_bytes')
			ELSE '-- Manual investigation required based on log_reuse_wait_desc.'
		END
FROM sys.databases AS DB
CROSS APPLY sys.dm_db_log_stats(DB.database_id) AS ls
WHERE DB.log_reuse_wait_desc <> 'NOTHING'
AND HAS_DBACCESS(DB.[name]) = 1
AND DB.state = 0
ORDER BY ActiveFileSize_PCT DESC;
