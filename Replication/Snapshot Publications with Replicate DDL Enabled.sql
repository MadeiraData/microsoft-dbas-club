/*
Detect Snapshot Replications on all databases that have "Replicate Schema Changes" enabled
==========================================================================================
Author: Eitan Blumin
Date: 2025-01-21
Based on: https://blog.sqlauthority.com/2016/04/07/sql-server-huge-transaction-log-snapshot-replication/
*/
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @majorver int, @buildver int
SET @majorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SET @buildver = ISNULL(CONVERT(int, SERVERPROPERTY('ProductBuild')), 0);

DECLARE @ReplCheck AS TABLE (
	dbname SYSNAME NULL,
    pubid INT NULL,
    name SYSNAME NULL,
    restricted INT NULL,
    status TINYINT NULL,
    task NVARCHAR(255) NULL,
    replication_frequency TINYINT NULL,
    synchronization_method TINYINT NULL,
    description NVARCHAR(255) NULL,
    immediate_sync BIT NULL,
    enabled_for_internet BIT NULL,
    allow_push BIT NULL,
    allow_pull BIT NULL,
    allow_anonymous BIT NULL,
    independent_agent BIT NULL,
    immediate_sync_ready BIT NULL,
    allow_sync_tran BIT NULL,
    autogen_sync_procs BIT NULL,
    snapshot_jobid BINARY(16) NULL,
    retention INT NULL,
    has_subscription BIT NULL,
    allow_queued_tran BIT NULL,
    snapshot_in_defaultfolder BIT NULL,
    alt_snapshot_folder NVARCHAR(255) NULL,
    pre_snapshot_script NVARCHAR(255) NULL,
    post_snapshot_script NVARCHAR(255) NULL,
    compress_snapshot BIT NULL,
    ftp_address SYSNAME NULL,
    ftp_port INT NULL,
    ftp_subdirectory NVARCHAR(255) NULL,
    ftp_login SYSNAME NULL,
    allow_dts BIT NULL,
    allow_subscription_copy BIT NULL,
    centralized_conflicts BIT NULL,
    conflict_retention INT NULL,
    conflict_policy INT NULL,
    queue_type NVARCHAR(255) NULL,
    backward_comp_level NVARCHAR(255) NULL,
    publish_to_AD BIT NULL,
    allow_initialize_from_backup BIT NULL,
    replicate_ddl INT NULL,
    enabled_for_p2p INT NULL,
    publish_local_changes_only INT NULL,
    enabled_for_het_sub INT NULL,
    enabled_for_p2p_conflictdetection INT NULL,
    originator_id INT NULL,
    p2p_continue_onconflict INT NULL,
    allow_partition_switch INT NULL,
    replicate_partition_switch INT NULL,
    enabled_for_p2p_lastwriter_conflictdetection INT NULL, /* new in SQL2019 */
	allow_drop BIT NULL /* relevant to SQL Server 2014 (12.x) SP 2 or above and SQL Server 2016 (13.x) SP 1 and above */
);


DECLARE @CurrDB sysname, @spExec sysname;

DECLARE dbs CURSOR
LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
select [name]
from sys.databases
WHERE is_published = 1
AND HAS_DBACCESS([name]) = 1

OPEN dbs;

WHILE 1=1
BEGIN
	FETCH NEXT FROM dbs INTO @CurrDB;
	IF @@FETCH_STATUS <> 0 BREAK;

	SET @spExec = QUOTENAME(@CurrDB) + '..sp_helppublication'

	IF @majorver >= 15
	BEGIN
		INSERT INTO @ReplCheck
		(pubid, name, restricted, status, task, replication_frequency, synchronization_method, description, immediate_sync, enabled_for_internet, allow_push, allow_pull, allow_anonymous, independent_agent, immediate_sync_ready, allow_sync_tran, autogen_sync_procs, snapshot_jobid, retention, has_subscription, allow_queued_tran, snapshot_in_defaultfolder, alt_snapshot_folder, pre_snapshot_script, post_snapshot_script, compress_snapshot, ftp_address, ftp_port, ftp_subdirectory, ftp_login, allow_dts, allow_subscription_copy, centralized_conflicts, conflict_retention, conflict_policy, queue_type, backward_comp_level, publish_to_AD, allow_initialize_from_backup, replicate_ddl, enabled_for_p2p, publish_local_changes_only, enabled_for_het_sub, enabled_for_p2p_conflictdetection, originator_id, p2p_continue_onconflict, allow_partition_switch, replicate_partition_switch, enabled_for_p2p_lastwriter_conflictdetection)
		EXEC @spExec
	END
	ELSE IF (@majorver = 12 AND @buildver >= 5000) OR (@majorver = 13 AND @buildver >= 6300)
	BEGIN
		INSERT INTO @ReplCheck
		(pubid, name, restricted, status, task, replication_frequency, synchronization_method, description, immediate_sync, enabled_for_internet, allow_push, allow_pull, allow_anonymous, independent_agent, immediate_sync_ready, allow_sync_tran, autogen_sync_procs, snapshot_jobid, retention, has_subscription, allow_queued_tran, snapshot_in_defaultfolder, alt_snapshot_folder, pre_snapshot_script, post_snapshot_script, compress_snapshot, ftp_address, ftp_port, ftp_subdirectory, ftp_login, allow_dts, allow_subscription_copy, centralized_conflicts, conflict_retention, conflict_policy, queue_type, backward_comp_level, publish_to_AD, allow_initialize_from_backup, replicate_ddl, enabled_for_p2p, publish_local_changes_only, enabled_for_het_sub, enabled_for_p2p_conflictdetection, originator_id, p2p_continue_onconflict, allow_partition_switch, replicate_partition_switch, allow_drop)
		EXEC @spExec
	END
	ELSE
	BEGIN
		INSERT INTO @ReplCheck
		(pubid, name, restricted, status, task, replication_frequency, synchronization_method, description, immediate_sync, enabled_for_internet, allow_push, allow_pull, allow_anonymous, independent_agent, immediate_sync_ready, allow_sync_tran, autogen_sync_procs, snapshot_jobid, retention, has_subscription, allow_queued_tran, snapshot_in_defaultfolder, alt_snapshot_folder, pre_snapshot_script, post_snapshot_script, compress_snapshot, ftp_address, ftp_port, ftp_subdirectory, ftp_login, allow_dts, allow_subscription_copy, centralized_conflicts, conflict_retention, conflict_policy, queue_type, backward_comp_level, publish_to_AD, allow_initialize_from_backup, replicate_ddl, enabled_for_p2p, publish_local_changes_only, enabled_for_het_sub, enabled_for_p2p_conflictdetection, originator_id, p2p_continue_onconflict, allow_partition_switch, replicate_partition_switch)
		EXEC @spExec
	END

	UPDATE @ReplCheck SET dbname = @CurrDB WHERE dbname IS NULL;

END

CLOSE dbs;
DEALLOCATE dbs;

SELECT dbname, [name] as publication_name, replicate_ddl
, RemeidationCmd = N'USE ' + QUOTENAME(dbname) + N'; EXEC sp_changepublication @publication = N''' + [name] + N''', @property = N''replicate_ddl'', @value = 0;'
FROM @ReplCheck
WHERE replication_frequency = 1
AND replicate_ddl = 1
