DECLARE @LogInfo AS TABLE
(RecoveryUnitId bigint, FileId int, FileSize bigint, StartOffset bigint, FSeqNo bigint, [Status] int, Parity int, CreateLSN numeric(25,0))

INSERT INTO @LogInfo
EXEC('DBCC LOGINFO')


SELECT * FROM @LogInfo;


select database_name, recovery_model, backup_start_date, type, checkpoint_lsn, database_backup_lsn, first_lsn, last_lsn
, li.*
from msdb..backupset
INNER JOIN 
(
SELECT MIN(CreateLSN) MinActiveTranLogLSN, MAX(CreateLSN) MaxActiveTranLogLSN
FROM @LogInfo
WHERE [Status] > 0 -- active VLF
AND CreateLSN > 0
) AS li
ON (li.MaxActiveTranLogLSN > first_lsn)
AND li.MinActiveTranLogLSN <= last_lsn
where database_name = DB_NAME()
order by backup_start_date ASC
