/*
 	Created: Vitaly Bruk / MadeiraData
	Date:	2024-12-26
	
	Description:
		This script identifies job step failures within SQL Server Agent jobs. 
		This alert ensures timely detection and resolution of failures, even when the overall job status indicates success.

	Will not work on Azure SQL database!

*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

USE msdb;
GO

;WITH RecentJobExecutions AS (
    SELECT
        j.job_id,
        j.name AS job_name,
        h.instance_id,
        ROW_NUMBER() OVER (PARTITION BY j.job_id ORDER BY h.run_date DESC, h.run_time DESC) AS row_num
    FROM
        sysjobs j
		INNER JOIN sysjobhistory h ON j.job_id = h.job_id
    WHERE
        h.step_id = 0 -- Overall job execution record
),
FailedSteps AS 
(
    SELECT
        j.name AS job_name,
        js.step_id,
        js.step_name,
        h.run_date,
        h.run_time,
        h.run_duration,
        h.[message]
    FROM
        msdb.dbo.sysjobhistory h
		INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
		LEFT JOIN msdb.dbo.sysjobsteps AS js ON j.job_id = js.job_id
		INNER JOIN RecentJobExecutions r ON h.instance_id = r.instance_id
    WHERE
        h.run_status = 0 -- Step failure
        AND r.row_num = 1 -- Most recent execution
)
SELECT
    job_name,
    step_id,
    step_name,
	msdb.dbo.agent_datetime([run_date],[run_time]) AS run_datetime,
    run_duration,
    [message]
FROM
    FailedSteps
ORDER BY
    job_name ASC, 
	run_date DESC, 
	run_time DESC;

