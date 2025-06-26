-- Replace with your specific SPID and time range
DECLARE
      @TargetSPID   INT      = 55
    , @StartTime    DATETIME = '2025-06-26 16:00:00'
    , @EndTime      DATETIME = '2025-06-26 17:00:00'

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @TracePath NVARCHAR(260);

-- Get the path of the default trace
SELECT @TracePath = path
FROM sys.traces
WHERE is_default = 1;

-- Query the default trace
SELECT 
    TE.name AS EventName,
    T.DatabaseName,
    T.ObjectName,
    T.TextData,
    T.ApplicationName,
    T.LoginName,
    T.SPID,
    T.StartTime,
    T.EndTime
FROM fn_trace_gettable(@TracePath, DEFAULT) AS T
INNER JOIN sys.trace_events AS TE
    ON T.EventClass = TE.trace_event_id
WHERE 
    T.SPID = @TargetSPID
    AND T.StartTime BETWEEN @StartTime AND @EndTime
ORDER BY T.StartTime;
