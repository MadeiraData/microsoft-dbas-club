SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @ThresholdBytes int = 2 * 1024 * 1024; -- TODO: set threshold (bytes), e.g. 5 MB

/*  Flag reference (from common Agent bitmask conventions):
      8  = Write log to table (overwrite existing)
     16  = Write log to table (append to existing)
    For "Log to table" + "Append output..." we filter on bit 16.
*/

;WITH TargetSteps AS
(
    SELECT
        j.job_id,
        j.name        AS job_name,
        s.step_id,
        s.step_name,
        s.subsystem,
        s.database_name,
        s.step_uid
    FROM msdb.dbo.sysjobs AS j
    INNER JOIN msdb.dbo.sysjobsteps AS s
        ON s.job_id = j.job_id
    WHERE (s.flags & 16) = 16
),
StepLogs AS
(
    SELECT
        t.job_id,
        t.job_name,
        t.step_id,
        t.step_name,
        t.subsystem,
        t.database_name,
        COALESCE(NULLIF(l.log_size, 0), DATALENGTH(l.log)) AS LogBytes -- bytes (per table definition)
    FROM TargetSteps AS t
    INNER JOIN msdb.dbo.sysjobstepslogs AS l
        ON l.step_uid = t.step_uid
)
SELECT
    Msg = CONCAT(N'Job "', job_name, '", step ', step_id, ' ("', step_name,'") has accumulated a high history output size. Consider disabling "Log to table" or "Append output to existing entry".'),
    LogBytes
FROM StepLogs
WHERE LogBytes > @ThresholdBytes
ORDER BY LogBytes DESC;
