USE [msdb]
GO

/****** Object:  Job [Maintenance.CleanupMSDB]    Script Date: 23/12/2024 15:53:26 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Database Maintenance]    Script Date: 23/12/2024 15:53:26 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Maintenance.CleanupMSDB', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [DBMail]    Script Date: 23/12/2024 15:53:26 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DBMail', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'DECLARE @DeleteBeforeDate datetime = DATEADD(dd, -180, GETDATE());

SET NOCOUNT OFF;
DECLARE @MinDate datetime, @MaxDate datetime, @Msg nvarchar(4000)

SELECT @MinDate = MIN(log_date)
FROM msdb.dbo.sysmail_log

SET @Msg = CONVERT(nvarchar(19), @MinDate, 121)
RAISERROR(N''Oldest date in sysmail log: %s'',0,1,@Msg) WITH NOWAIT;

WHILE @MinDate < @DeleteBeforeDate
BEGIN
	SET @MaxDate = DATEADD(month, 1, @MinDate)

	IF @MaxDate > @DeleteBeforeDate SET @MaxDate = @DeleteBeforeDate;
	SET @Msg = CONVERT(nvarchar(19), @MaxDate, 121)

	RAISERROR(N''Deleting sysmail data older than: %s'',0,1,@Msg) WITH NOWAIT;

	EXECUTE msdb.dbo.sysmail_delete_mailitems_sp @sent_before = @MaxDate;  
	EXECUTE msdb.dbo.sysmail_delete_log_sp @logged_before = @MaxDate;  

	SET @MinDate = @MaxDate
END
', 
		@database_name=N'msdb', 
		@flags=8
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [MaintenancePlans]    Script Date: 23/12/2024 15:53:26 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'MaintenancePlans', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @DeleteBeforeDate datetime = DATEADD(dd, -180, GETDATE());

SET NOCOUNT OFF;
DECLARE @MinDate datetime, @MaxDate datetime, @Msg nvarchar(4000)

SELECT @MinDate = MIN(start_time)
FROM msdb.dbo.sysmaintplan_log

SET @Msg = CONVERT(nvarchar(19), @MinDate, 121)
RAISERROR(N''Oldest date in maintenance plan log: %s'',0,1,@Msg) WITH NOWAIT;

WHILE @MinDate < @DeleteBeforeDate
BEGIN
	SET @MaxDate = DATEADD(month, 1, @MinDate)

	IF @MaxDate > @DeleteBeforeDate SET @MaxDate = @DeleteBeforeDate;
	SET @Msg = CONVERT(nvarchar(19), @MaxDate, 121)

	RAISERROR(N''Deleting maintenance plan data older than: %s'',0,1,@Msg) WITH NOWAIT;

	EXECUTE msdb.dbo.sp_maintplan_delete_log @oldest_time = @MaxDate;  

	SET @MinDate = @MaxDate
END
', 
		@database_name=N'msdb', 
		@flags=8
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [BackupHistory]    Script Date: 23/12/2024 15:53:26 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'BackupHistory', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @DeleteBeforeDate datetime = DATEADD(dd, -180, GETDATE());

SET NOCOUNT OFF;
DECLARE @MinDate datetime, @MaxDate datetime, @Msg nvarchar(4000)

SELECT @MinDate = MIN(backup_start_date)
FROM msdb.dbo.backupset

SET @Msg = CONVERT(nvarchar(19), @MinDate, 121)
RAISERROR(N''Oldest date in backup history: %s'',0,1,@Msg) WITH NOWAIT;

WHILE @MinDate < @DeleteBeforeDate
BEGIN
	SET @MaxDate = DATEADD(month, 1, @MinDate)

	IF @MaxDate > @DeleteBeforeDate SET @MaxDate = @DeleteBeforeDate;
	SET @Msg = CONVERT(nvarchar(19), @MaxDate, 121)

	RAISERROR(N''Deleting backup history data older than: %s'',0,1,@Msg) WITH NOWAIT;

	EXECUTE msdb.dbo.sp_delete_backuphistory @oldest_date = @MaxDate;  

	SET @MinDate = @MaxDate
END
', 
		@database_name=N'msdb', 
		@flags=8
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [OutputFiles]    Script Date: 23/12/2024 15:53:26 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'OutputFiles', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'cmd /q /c "For /F "tokens=1 delims=" %v In (''ForFiles /P "$(ESCAPE_SQUOTE(SQLLOGDIR))" /m *_*_*_*.txt /d -180 2^>^&1'') do if EXIST "$(ESCAPE_SQUOTE(SQLLOGDIR))"\%v echo del "$(ESCAPE_SQUOTE(SQLLOGDIR))"\%v& del "$(ESCAPE_SQUOTE(SQLLOGDIR))"\%v"
', 
		@flags=8
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [JobHistory]    Script Date: 23/12/2024 15:53:26 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'JobHistory', 
		@step_id=5, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @DeleteBeforeDate datetime = DATEADD(dd, -180, GETDATE());

SET NOCOUNT OFF;
DECLARE @MinDate datetime, @MaxDate datetime, @Msg nvarchar(4000)

SELECT @MinDate = msdb.dbo.agent_datetime(MIN(run_date),0)
FROM msdb.dbo.sysjobhistory

SET @Msg = CONVERT(nvarchar(19), @MinDate, 121)
RAISERROR(N''Oldest date in job history: %s'',0,1,@Msg) WITH NOWAIT;

WHILE @MinDate < @DeleteBeforeDate
BEGIN
	SET @MaxDate = DATEADD(month, 1, @MinDate)

	IF @MaxDate > @DeleteBeforeDate SET @MaxDate = @DeleteBeforeDate;
	SET @Msg = CONVERT(nvarchar(19), @MaxDate, 121)

	RAISERROR(N''Deleting job history older than: %s'',0,1,@Msg) WITH NOWAIT;

	EXECUTE msdb.dbo.sp_purge_jobhistory @oldest_date = @MaxDate;  

	SET @MinDate = @MaxDate
END
', 
		@database_name=N'msdb', 
		@flags=8
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Maintenance_CleanupMSDB', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=16, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20241205, 
		@active_end_date=99991231, 
		@active_start_time=180000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


