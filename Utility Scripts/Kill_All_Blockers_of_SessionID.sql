DECLARE @KillBlockersOfSessionID int = 1234 -- replace with the session id that's being blocked by multiple blockers that should be killed

DECLARE @CMD nvarchar(max);

WHILE 1=1
BEGIN
	SET @CMD = NULL;
	SELECT @CMD = ISNULL(@CMD + CHAR(10), '')
			 + CONCAT(N'KILL ', blocking_session_id)
	FROM sys.dm_exec_requests
	WHERE session_id = @KillBlockersOfSessionID

	IF @CMD IS NULL BREAK;
	RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;
	IF @CMD <> 'KILL 0' EXEC(@CMD);
END