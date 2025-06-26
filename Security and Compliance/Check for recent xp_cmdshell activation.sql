
-- Configuration: Set the number of hours to look back
DECLARE @HoursBack INT = 1;

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @StartTime DATETIME = DATEADD(HOUR, -@HoursBack, GETDATE());

-- Table to hold log file info
IF OBJECT_ID('tempdb..#LogFiles') IS NOT NULL DROP TABLE #LogFiles;
CREATE TABLE #LogFiles (
    ArchiveNumber INT,
    LogDate DATETIME,
    LogSize BIGINT
);

-- Get error log file details
INSERT INTO #LogFiles (ArchiveNumber, LogDate, LogSize)
EXEC sp_enumerrorlogs;

-- Temporary table to store error log entries
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;
CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo NVARCHAR(50),
    MsgText NVARCHAR(MAX),
    ArchiveNumber INT NULL
);

-- Loop through relevant logs based on time range
DECLARE @LogIndex INT, @LogDate DATETIME;

DECLARE log_cursor CURSOR
LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
SELECT ArchiveNumber, LogDate
FROM #LogFiles
WHERE LogDate >= @StartTime
   OR ArchiveNumber = 0 -- Always check the current log

OPEN log_cursor;

WHILE 1=1
BEGIN
    FETCH NEXT FROM log_cursor INTO @LogIndex, @LogDate;
    IF @@FETCH_STATUS <> 0 BREAK;

    BEGIN TRY
        RAISERROR(N'Checking log %d',0,1,@LogIndex) WITH NOWAIT;
        INSERT INTO #ErrorLog(LogDate, ProcessInfo, MsgText)
        EXEC xp_readerrorlog @LogIndex, 1, N'xp_cmdshell', N'', @StartTime;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(max)
        SET @ErrMsg = ERROR_MESSAGE()
        RAISERROR(N'Error reading log %d: %s',0,1,@LogIndex,@ErrMsg) WITH NOWAIT;
    END CATCH
    UPDATE #ErrorLog SET ArchiveNumber = @LogIndex WHERE ArchiveNumber IS NULL;
END

CLOSE log_cursor;
DEALLOCATE log_cursor;

-- Search for enabling messages
SELECT Msg = CONCAT(CONVERT(nvarchar(19),LogDate,121), ' - ', ProcessInfo, ' - ', MsgText), ArchiveNumber
FROM #ErrorLog
WHERE LogDate >= @StartTime
  AND MsgText LIKE '%Configuration option ''xp_cmdshell'' changed from 0 to 1%';

-- Cleanup
DROP TABLE #ErrorLog;
DROP TABLE #LogFiles;
