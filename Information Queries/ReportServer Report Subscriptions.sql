USE ReportServer -- change database name here if different from the default
GO

SELECT
    c.Path                               AS ReportPath,
    c.Name                               AS ReportName,
    s.SubscriptionID,
    s.Description                        AS SubscriptionDescription,
    s.DeliveryExtension,
    s.EventType,
    s.LastStatus,
    s.LastRunTime,
    rs.ScheduleID,
    sc.Name                              AS ScheduleName,            -- null for non-shared schedules
    CASE 
        WHEN sc.ScheduleID IS NOT NULL THEN 'Shared Schedule'
        ELSE 'Subscription (Unshared) Schedule'
    END                                  AS ScheduleType,
    --sj.job_id                            AS SQLAgentJobID,
    sj.name                              AS SQLAgentJobName,         -- matches ScheduleID
    u.UserName                           AS SubscriptionOwner
FROM dbo.Subscriptions s
JOIN dbo.Catalog c
    ON c.ItemID = s.Report_OID
JOIN dbo.ReportSchedule rs
    ON rs.SubscriptionID = s.SubscriptionID
LEFT JOIN dbo.[Schedule] sc
    ON sc.ScheduleID = rs.ScheduleID          -- present for shared schedules
LEFT JOIN msdb.dbo.sysjobs sj
    ON sj.name IN ( CONVERT(NVARCHAR(128), rs.ScheduleID) COLLATE database_default, sc.Name COLLATE database_default )  -- job name = ScheduleID
LEFT JOIN ReportServer.dbo.[Users] u
    ON u.UserID = s.OwnerID
ORDER BY
    c.Path,
    ScheduleName;
