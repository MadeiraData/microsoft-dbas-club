USE msdb
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('KillBadSessions_Log') IS NOT NULL
BEGIN
	create table KillBadSessions_Log
	(
		cmd varchar(max),
		bit bit,
		duration datetime,
		login_time datetime,
		open_transaction_count smallint,
		status smallint,
		last_request_start_time datetime,
		last_request_end_time datetime,
		program_name sysname,
		host_name sysname,
		error_audit nvarchar(max),
		sqltext nvarchar(max),
		timestamp_utc datetime DEFAULT(GETUTCDATE())
	);
	CREATE CLUSTERED INDEX IX ON KillBadSessions_Log (timestamp_utc)
END
GO
/*

Author:	Sagi Amichai
Date:	6 Nov 19
Description:
From the app side - sometimnes sessions are not closed completley from the app side. 
A seassion is left with an open transaction count > 0 and old last requet end time. 
Those sessions usually lock critical tables. From the appside the session is left open until we kill it. 
This job kills sessions with  transaction not committed thats is locking other sessions 

*/
CREATE procedure [dbo].[KillBadSession]
as

/*		
create table KillBadSessions_Log
(
	cmd varchar(max),
	bit bit,
	duration datetime,
	login_time datetime,
	open_transaction_count smallint,
	status smallint,
	last_request_start_time datetime,
	last_request_end_time datetime,
	program_name sysname,
	host_name sysname,
	error_audit nvarchar(max),
	sqltext nvarchar(max),
	timestamp_utc datetime DEFAULT(GETUTCDATE()),
	INDEX IX CLUSTERED (timestamp_utc)
)
*/
begin try
	declare @cmd varchar(max) =''
	declare @SessionsToKill AS table
	(
		session_id int, 
		duration datetime,
		login_time datetime,
		open_transaction_count smallint,
		status varchar(100),
		last_request_start_time datetime,
		last_request_end_time datetime,
		program_name nvarchar(128),
		host_name nvarchar(128),
		sqltext nvarchar(max) null
	)

	INSERT INTO @SessionsToKill
	SELECT
		session_id, 
		duration ,
		login_time,
		open_transaction_count,
		status,
		last_request_start_time,
		last_request_end_time,
		program_name,
		host_name,
		text
	from 
	
	(
		select 
			es.session_id, 
			getdate() - es.last_request_end_time Duration,
			es.login_time, 
			es.open_transaction_count, 
			es.status, 
			es.last_request_start_time,
			es.last_request_end_time,
			es.program_name,
			es.host_name,
			t.text
		from sys.dm_exec_sessions AS es
		LEFT JOIN sys.dm_exec_connections AS ec ON es.session_id = ec.session_id
		OUTER APPLY sys.dm_exec_sql_text (ec.most_recent_sql_handle) AS t
		where
			es.session_id in 
					(select blocking_session_id 
					from sys.dm_exec_requests rq 
					where rq.session_id>50 and database_id =16 and rq.session_id <> rq.blocking_session_id)
			and es.session_id > 50
			and es.database_id = 16
			AND es.is_user_process = 1
			and es.status = 'sleeping'
			and es.program_name NOT LIKE 'SolarWinds%'
			and es.program_name NOT LIKE 'SQL Sentry%'
			and es.last_request_end_time < DATEADD(hour,-3,getdate())
	) tbl
	where duration > DATEADD(minute, 2, 0)
	and [text] NOT LIKE N'%p_hiuvim%'

	select @cmd += 'kill '+cast( session_id as varchar) + '; '
	from @SessionsToKill
	where session_id IN (select session_id from sys.dm_exec_sessions)
	 
	--print (@cmd) 
	
	exec (@cmd)


	if (@cmd <> '')
	begin

		insert into dbo.KillBadSessions_Log 
		(
			cmd, duration, login_time, open_transaction_count, status, 
			last_request_start_time, last_request_end_time, program_name, host_name, sqltext
			, [timestamp_utc]
		)
		select
			 @cmd
			,duration					
			,login_time					
			,open_transaction_count		
			,status						
			,last_request_start_time	
			,last_request_end_time		
			,program_name				
			,host_name	
			,sqltext
			,GETUTCDATE()
		from @SessionsToKill
	end
end try
begin catch
	declare @err nvarchar(max)
	SET @err = N'Error ' + CONVERT(nvarchar,ERROR_NUMBER()) + N', severity ' + CONVERT(nvarchar, ERROR_SEVERITY()) + N', state ' + CONVERT(nvarchar, ERROR_STATE())
	SET @err = @err + ISNULL(N', procedure ' + ERROR_PROCEDURE(), N'')
	SET @err = @err + ISNULL(N', line ' + CONVERT(nvarchar, ERROR_LINE()), N'')
	SET @err = @err + N': ' + ERROR_MESSAGE();

	insert into [dbo].[KillBadSessions_Log] 
	(
		cmd, duration, login_time, open_transaction_count, status, 
		last_request_start_time, last_request_end_time, program_name, host_name, sqltext
		, error_audit, [timestamp_utc]
	)
	select
			@cmd
		,duration					
		,login_time					
		,open_transaction_count		
		,status						
		,last_request_start_time	
		,last_request_end_time		
		,program_name				
		,host_name	
		,sqltext
		,@err
		,GETUTCDATE()
	from @SessionsToKill

	IF @@ROWCOUNT = 0
		insert into [dbo].[KillBadSessions_Log] (cmd, login_time, status, error_audit, [timestamp_utc])
		values (@cmd, getdate(),'this is an error from the try-catch of the job', @err, GETUTCDATE())
end catch
