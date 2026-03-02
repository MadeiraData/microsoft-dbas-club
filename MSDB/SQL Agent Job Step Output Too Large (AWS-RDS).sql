SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @ThresholdBytes int = 2 * 1024 * 1024; -- TODO: set threshold (bytes), e.g. 5 MB

/*  Flag reference (common Agent bitmask conventions):
      8  = Write log to table (overwrite existing)
     16  = Write log to table (append to existing)

    We filter on bit 16 ("append").
*/

IF OBJECT_ID('tempdb..#Jobs') IS NOT NULL DROP TABLE #Jobs;
CREATE TABLE #Jobs
(
    job_id   uniqueidentifier NOT NULL,
    job_name sysname          NOT NULL
);

/* Holds raw output of sp_help_jobstep (no job_id/job_name columns are returned by the proc) */
IF OBJECT_ID('tempdb..#JobStepRaw') IS NOT NULL DROP TABLE #JobStepRaw;
CREATE TABLE #JobStepRaw
(
    step_id               int            NULL,
    step_name             sysname        NULL,
    subsystem             nvarchar(40)   NULL,
    command               nvarchar(max)  NULL,
    flags                 int            NULL,
    cmdexec_success_code  int            NULL,
    on_success_action     tinyint        NULL,
    on_success_step_id    int            NULL,
    on_fail_action        tinyint        NULL,
    on_fail_step_id       int            NULL,
    server                sysname        NULL,
    database_name         sysname        NULL,
    database_user_name    sysname        NULL,
    retry_attempts        int            NULL,
    retry_interval        int            NULL,
    os_run_priority       int            NULL,
    output_file_name      nvarchar(200)  NULL,
    last_run_outcome      int            NULL,
    last_run_duration     int            NULL,
    last_run_retries      int            NULL,
    last_run_date         int            NULL,
    last_run_time         int            NULL,
    proxy_id              int            NULL
);

/* Steps we care about (flags & 16 = 16) */
IF OBJECT_ID('tempdb..#TargetSteps') IS NOT NULL DROP TABLE #TargetSteps;
CREATE TABLE #TargetSteps
(
    job_id         uniqueidentifier NOT NULL,
    job_name       sysname          NOT NULL,
    step_id        int              NOT NULL,
    step_name      sysname          NOT NULL,
    subsystem      nvarchar(40)     NULL,
    database_name  sysname          NULL,
    flags          int              NOT NULL
);

/* Raw output of sp_help_jobsteplog */
IF OBJECT_ID('tempdb..#JobStepLogRaw') IS NOT NULL DROP TABLE #JobStepLogRaw;
CREATE TABLE #JobStepLogRaw
(
    job_id        uniqueidentifier NULL,
    job_name      sysname          NULL,
    step_id       int              NULL,
    step_name     sysname          NULL,
    step_uid      uniqueidentifier NULL,
    date_created  datetime         NULL,
    date_modified datetime         NULL,
    log_size      float            NULL,      -- MB per proc contract
    log           nvarchar(max)    NULL
);

--------------------------------------------------------------------------------
-- 1) Get all jobs (proc, no msdb table reads)
--------------------------------------------------------------------------------
INSERT INTO #Jobs (job_id, job_name)
SELECT job_id, name FROM msdb.dbo.sysjobs_view

--------------------------------------------------------------------------------
-- 2) For each job, get steps via sp_help_jobstep and filter on (flags & 16) = 16
--------------------------------------------------------------------------------
DECLARE @job_id uniqueidentifier, @job_name sysname;

DECLARE job_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT job_id, job_name FROM #Jobs;

OPEN job_cur;
FETCH NEXT FROM job_cur INTO @job_id, @job_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    TRUNCATE TABLE #JobStepRaw;

    INSERT INTO #JobStepRaw
    EXEC msdb.dbo.sp_help_jobstep @job_id = @job_id;

    INSERT INTO #TargetSteps (job_id, job_name, step_id, step_name, subsystem, database_name, flags)
    SELECT
        @job_id,
        @job_name,
        r.step_id,
        r.step_name,
        r.subsystem,
        r.database_name,
        r.flags
    FROM #JobStepRaw AS r
    WHERE (r.flags & 16) = 16;

    FETCH NEXT FROM job_cur INTO @job_id, @job_name;
END

CLOSE job_cur;
DEALLOCATE job_cur;

--------------------------------------------------------------------------------
-- 3) For jobs that have target steps, pull step log metadata via sp_help_jobsteplog
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM #TargetSteps)
BEGIN
    DECLARE @job_id2 uniqueidentifier;

    DECLARE log_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT job_id FROM #TargetSteps;

    OPEN log_cur;
    FETCH NEXT FROM log_cur INTO @job_id2;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #JobStepLogRaw
        EXEC msdb.dbo.sp_help_jobsteplog @job_id = @job_id2;

        FETCH NEXT FROM log_cur INTO @job_id2;
    END

    CLOSE log_cur;
    DEALLOCATE log_cur;
END

--------------------------------------------------------------------------------
-- 4) Final report
--------------------------------------------------------------------------------
;WITH StepLogs AS
(
    SELECT
        t.job_name,
        t.step_id,
        t.step_name,
        t.subsystem,
        t.database_name,
        l.log_size AS LogBytes
    FROM #TargetSteps AS t
    LEFT JOIN #JobStepLogRaw AS l
        ON l.job_id  = t.job_id
       AND l.step_id = t.step_id
)
SELECT
    Msg = CONCAT(
        N'Job "', job_name, N'", step ', step_id, N' ("', step_name,
        N'") has accumulated a high history output size. Consider disabling "Log to table" or "Append output to existing entry".'
    ),
    LogBytes
FROM StepLogs
WHERE LogBytes > @ThresholdBytes
ORDER BY LogBytes DESC;