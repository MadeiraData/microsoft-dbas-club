/*
----------------------------------------------------------------------------
		Shrink a Database File in Specified Increments
----------------------------------------------------------------------------
Author: Eitan Blumin (t: @EitanBlumin | b: eitanblumin.com)
Creation Date: 2020-01-05
----------------------------------------------------------------------------
Description:
	This script uses small intervals to shrink a file (in the current database)
	down to a specific size or percentage (of used space).

	This can be useful when shrinking files with large heaps and/or LOBs
	that can cause regular shrink operations to get stuck.

	Change the parameter values below to customize the behavior.
	
----------------------------------------------------------------------------
	!!! DON'T FORGET TO SET THE CORRECT DATABASE NAME !!!
----------------------------------------------------------------------------

Change log:
	2025-06-18 - Eitan - Added new parameters: @MaxActiveTranLogSizeMB, @MaxActiveTranLogSizePct, and @ActiveTranLogSeverity
	2024-09-29 - Vitaly - Added a time limit (maximum execution duration) for the process (@TimeLimit and @RunStartTime parameters) 
	2021-09-17 - Eitan - Renamed @MinPercentFree to @MaxPercentUsed, some code-quality fixes
	2021-09-17 - Eitan - added shrink with TRUNCATEONLY attempt when conditions favor it
	2021-09-17 - Eitan - added linked server connectivity test. moved recovery queue check to start of loop.
	2020-08-23 - Eitan - Added new parameters: @AGReplicaLinkedServer, @MaxReplicaRecoveryQueue, @RecoveryQueueSeverity, and @WhatIf
	2020-06-22 - Eitan - Added @RegrowOnError5240 parameter
	2020-06-21 - Eitan - Added @DelayBetweenShrinks and @IterationMaxRetries parameters
	2020-03-18 - Eitan - Added @DatabaseName parameter
	2020-01-30 - Eitan - Added @MinPercentFree, and made all parameters optional
	2020-01-05 - Eitan - First version
----------------------------------------------------------------------------

Parameters:
----------------------------------------------------------------------------
*/
DECLARE
	 @DatabaseName		SYSNAME = NULL		-- Leave NULL to use current database context
	,@FileName		SYSNAME	= NULL		-- Leave NULL to shrink the file with the highest % free space
	,@FileType		SYSNAME	= NULL		-- Optionally specify the type of file to shrink (ROWS | LOG). This is ignored if @FileName is specified.
	,@TargetSizeMB		INT	= 20000		-- Leave NULL to rely on @MaxPercentUsed exclusively.
	,@MaxPercentUsed	INT	= 80		-- Leave NULL to rely on @TargetSizeMB exclusively.
								-- Either @TargetSizeMB or @MaxPercentUsed must be specified.
								-- If both @TargetSizeMB and @MaxPercentUsed are provided, the largest of them will be used.
	,@IntervalMB		INT	= 50		-- Leave NULL to shrink the file in a single interval
	,@DelayBetweenShrinks	VARCHAR(12) = '00:00:01' -- Delay to wait between shrink iterations (in 'hh:mm[[:ss].mss]' format). Leave NULL to disable delay. For more info, see the 'time_to_execute' argument of WAITFOR DELAY: https://docs.microsoft.com/sql/t-sql/language-elements/waitfor-transact-sql#arguments
	,@IterationMaxRetries	INT	= 3		-- Maximum number of attempts per iteration to shrink a file, when cannot successfuly shrink to desired target size
	,@RegrowOnError5240	BIT	= 1		-- Error 5240 may be resolved by temporarily increasing the file size before shrinking it again.

	,@AGReplicaLinkedServer	SYSNAME	= NULL		-- Linked Server name of the AG replica to check. Leave as NULL to ignore.
	,@MaxReplicaRecoveryQueue INT	= 10000		-- Maximum recovery queue of AG replica (in KB). Use this to prevent overload on the AG.
	,@RecoveryQueueSeverity INT	= 16		-- Error severity to raise when @MaxReplicaRecoveryQueue is breached.

	,@MaxActiveTranLogSizeMB	INT = NULL		-- Maximum active log size (in MB). Use this to prevent overload on the transaction log or on the AG. Leave as NULL to ignore.
	,@MaxActiveTranLogSizePct	INT = NULL		-- Maximum active log size (in Percent). Use this to prevent overload on the transaction log or on the AG. Leave as NULL to ignore.
	,@ActiveTranLogSeverity		INT = 16		-- Error severity to raise when @MaxActiveTranLogSizeMB or @MaxActiveTranLogSizePct are breached.

	,@TimeLimit					INT 		= 86400				-- Set a maximum execution duration in second (3600 = 1 hour / 86400 = 24 hours) / NULL - no limmit!

	,@WhatIf		BIT	= 0		-- Set to 1 to only print the commands but not run them.

----------------------------------------------------------------------------
		-- DON'T CHANGE ANYTHING BELOW THIS LINE --
----------------------------------------------------------------------------

SET NOCOUNT, ARITHABORT, XACT_ABORT ON;
SET ANSI_WARNINGS OFF;
DECLARE @CurrSizeMB INT, @sp_executesql NVARCHAR(1000), @CMD NVARCHAR(MAX), @SpaceUsedMB INT, @SpaceUsedPct VARCHAR(10), @TargetPct VARCHAR(10);
DECLARE @NewSizeMB INT, @RetryNum INT, @RunStartTime datetime;
SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
SET @RetryNum = 0;

IF @DatabaseName IS NULL
BEGIN
	RAISERROR(N'Database "%s" was not found on this server.',16,1,@DatabaseName);
	GOTO Quit;
END

IF DATABASEPROPERTYEX(@DatabaseName, 'Updateability') <> 'READ_WRITE'
BEGIN
	RAISERROR(N'Database "%s" is not writeable.',16,1,@DatabaseName);
	GOTO Quit;
END

IF @TargetSizeMB IS NULL AND @MaxPercentUsed IS NULL
BEGIN
	RAISERROR(N'Either @TargetSizeMB or @MaxPercentUsed must be specified!', 16, 1);
	GOTO Quit;
END

IF @IntervalMB < 1
BEGIN
	RAISERROR(N'@IntervalMB must be an integer value of 1 or higher (or NULL if you want to shrink using a single interval)', 16,1)
	GOTO Quit;
END

SET @sp_executesql = QUOTENAME(@DatabaseName) + '..sp_executesql'

DECLARE @RecoveryQueueCheckCmd NVARCHAR(4000), @RecoveryQueueCheckParams NVARCHAR(4000), @PartnerServer SYSNAME, @RecoveryQueue INT
DECLARE @RecoveryQueueCheckExec NVARCHAR(4000);

IF @AGReplicaLinkedServer IS NOT NULL AND @MaxReplicaRecoveryQueue IS NOT NULL
BEGIN
	IF NOT EXISTS (SELECT * FROM sys.servers WHERE server_id > 0 AND name = @AGReplicaLinkedServer)
	BEGIN
		RAISERROR(N'Specified linked server "%s" was not found.', 16,1, @AGReplicaLinkedServer);
		GOTO Quit;
	END
	
	IF @RecoveryQueueSeverity IS NULL OR @RecoveryQueueSeverity NOT BETWEEN 0 AND 16
	BEGIN
		RAISERROR(N'@RecoveryQueueSeverity "%d" is invalid. Must be between an integer 0 and 16.', 16, 1, @RecoveryQueueSeverity);
		GOTO Quit;
	END

	BEGIN TRY
		EXEC sp_testlinkedserver @AGReplicaLinkedServer;
	END TRY
	BEGIN CATCH
		DECLARE @ErrMsg nvarchar(max) = ERROR_MESSAGE()
		RAISERROR(N'Linked server "%s" is inaccessible. Reason: %s', @RecoveryQueueSeverity, 1, @AGReplicaLinkedServer, @ErrMsg);
		GOTO Quit;
	END CATCH

	SET @RecoveryQueueCheckParams = N'@DBNAME SYSNAME, @CounterName VARCHAR(1000), @PartnerServer SYSNAME OUTPUT, @CounterValue INT OUTPUT'
	SET @RecoveryQueueCheckCmd = N'SELECT @PartnerServer = @@SERVERNAME, @CounterValue = cntr_value
	FROM sys.dm_os_performance_counters
	WHERE object_name LIKE ''%:Database Replica%''
	AND counter_name = @CounterName AND instance_name = @DBNAME'

	SET @RecoveryQueueCheckExec = QUOTENAME(@AGReplicaLinkedServer) + '.' + @sp_executesql

	IF @WhatIf = 1 PRINT @RecoveryQueueCheckCmd;
	EXEC @RecoveryQueueCheckExec @RecoveryQueueCheckCmd, @RecoveryQueueCheckParams, @DatabaseName, 'Recovery Queue', @PartnerServer OUTPUT, @RecoveryQueue OUTPUT

	IF @RecoveryQueue IS NULL
	BEGIN
		RAISERROR(N'Unable to fetch "Recovery Queue" for database "%s" via linked server "%s".', @RecoveryQueueSeverity, 1, @DatabaseName, @AGReplicaLinkedServer);
		GOTO Quit;
	END
	ELSE
	BEGIN
		RAISERROR(N'-- Successfully connected to replica server "%s". Current recovery queue for databsae "%s": %d KB.', 0, 1, @PartnerServer, @DatabaseName, @RecoveryQueue) WITH NOWAIT;
	END
END

DECLARE @ActiveTranLogCheckCmd NVARCHAR(MAX), @ActiveTranLogCheckParams NVARCHAR(MAX), @ActiveTranLogSizeMB INT, @TotalTranLogSizeMB INT

IF @MaxActiveTranLogSizeMB IS NOT NULL OR @MaxActiveTranLogSizePct IS NOT NULL
BEGIN
	IF OBJECT_ID('sys.dm_db_log_stats') IS NULL
	BEGIN
		RAISERROR(N'Sorry, @MaxActiveTranLogSizeMB and @MaxActiveTranLogSizePct are not supported on this SQL Server instance. Please change both of them to NULL.',16,1);
		GOTO Quit;
	END

	SET @ActiveTranLogCheckCmd = N'SELECT @ActiveTranLogSizeMB = active_log_size_mb, @TotalTranLogSizeMB = total_log_size_mb FROM sys.dm_db_log_stats(DB_ID(@DatabaseName))'
	SET @ActiveTranLogCheckParams = N'@ActiveTranLogSizeMB INT OUTPUT, @TotalTranLogSizeMB INT OUTPUT, @DatabaseName sysname'
	
	EXEC @sp_executesql @ActiveTranLogCheckCmd, @ActiveTranLogCheckParams, @ActiveTranLogSizeMB OUTPUT, @TotalTranLogSizeMB OUTPUT, @DatabaseName;

	IF @ActiveTranLogSizeMB IS NULL
	BEGIN
		RAISERROR(N'Unable to retrieve the active transaction log size for database "%s".', 16, 1, @DatabaseName);
		GOTO Quit;
	END
	ELSE
	BEGIN
		RAISERROR(N'-- Current active transaction log size of database "%s" is %d MB out of %d MB in total.',0,1,@DatabaseName, @ActiveTranLogSizeMB, @TotalTranLogSizeMB) WITH NOWAIT;
	END
END

SET @CMD = N'
SELECT TOP 1
	 @FileName = [name]
	,@CurrSizeMB = size / 128
	,@SpaceUsedMB = CAST(FILEPROPERTY([name], ''SpaceUsed'') AS int) / 128.0
FROM sys.database_files
WHERE ([name] = @FileName OR @FileName IS NULL)
AND ([size] / 128 > @TargetSizeMB OR @TargetSizeMB IS NULL OR [name] = @FileName)
AND type IN (0,1) -- data and log files only
AND (@FileType IS NULL OR @FileName IS NOT NULL OR [type_desc] = @FileType)
ORDER BY size - CAST(FILEPROPERTY([name], ''SpaceUsed'') AS float) DESC;'

IF @WhatIf = 1 PRINT @CMD;
EXEC @sp_executesql @CMD, N'@FileName SYSNAME OUTPUT, @CurrSizeMB INT OUTPUT, @SpaceUsedMB INT OUTPUT, @FileType SYSNAME, @TargetSizeMB INT'
			, @FileName OUTPUT, @CurrSizeMB OUTPUT, @SpaceUsedMB OUTPUT, @FileType, @TargetSizeMB

SET @TargetSizeMB = (
			SELECT MAX(val)
			FROM (VALUES
				(@TargetSizeMB),(CEILING(@SpaceUsedMB / (CAST(@MaxPercentUsed as float) / 100.0)))
				) AS v(val)
			)

SET @SpaceUsedPct = CAST( CEILING(@SpaceUsedMB * 100.0 / @CurrSizeMB) as varchar(10)) + '%'
SET @TargetPct = CAST( CEILING(@SpaceUsedMB * 100.0 / @TargetSizeMB) as varchar(10)) + '%'

IF @SpaceUsedMB IS NOT NULL
	RAISERROR(N'
-- Database "%s", File "%s" current size: %d MB, used space: %d MB (%s), target size: %d MB (%s)',0,1,@DatabaseName,@FileName,@CurrSizeMB,@SpaceUsedMB,@SpaceUsedPct,@TargetSizeMB,@TargetPct) WITH NOWAIT;

SET @RunStartTime = GETDATE();
SET @CMD = CONVERT(VARCHAR(19), (DATEADD(SECOND, @TimeLimit, @RunStartTime)), 121)
RAISERROR(N'-- Time limit is: %s

',0,1,@CMD) WITH NOWAIT;


IF @SpaceUsedMB IS NULL OR @CurrSizeMB <= @TargetSizeMB
BEGIN
	RAISERROR(N'-- Nothing to shrink in database "%s"',0,1,@DatabaseName)
	GOTO Quit;
END

IF @SpaceUsedMB < @TargetSizeMB AND @SpaceUsedPct <= @TargetPct
BEGIN
	-- attempt to perform shrink with TRUNCATEONLY
	SET @CMD = N'DBCC SHRINKFILE (N' + QUOTENAME(@FileName, N'''') + N' , ' + CONVERT(nvarchar(max), @TargetSizeMB) + N', TRUNCATEONLY) WITH NO_INFOMSGS; -- ' + CONVERT(nvarchar(25),GETDATE(),121)

	RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;
	IF @WhatIf = 1
		PRINT N'-- @WhatIf was set to 1. Skipping execution.'
	ELSE
		EXEC @sp_executesql @CMD

	-- Re-check new file size
	EXEC @sp_executesql N'SELECT @NewSizeInMB = [size]/128 FROM sys.database_files WHERE [name] = @FileName;'
				, N'@FileName SYSNAME, @NewSizeInMB FLOAT OUTPUT', @FileName, @CurrSizeMB OUTPUT
END


WHILE @CurrSizeMB > @TargetSizeMB
	AND (@TimeLimit IS NULL OR DATEADD(SECOND, @TimeLimit, @RunStartTime) > GETDATE())
BEGIN
	-- Check recovery queue of AG partner
	IF @AGReplicaLinkedServer IS NOT NULL AND @MaxReplicaRecoveryQueue IS NOT NULL
	BEGIN
		SET @RecoveryQueue = NULL;
		EXEC @RecoveryQueueCheckExec @RecoveryQueueCheckCmd, @RecoveryQueueCheckParams, @DatabaseName, 'Recovery Queue', @PartnerServer OUTPUT, @RecoveryQueue OUTPUT
	
		IF @RecoveryQueue > @MaxReplicaRecoveryQueue
		BEGIN
			RAISERROR(N'-- Stopping because the recovery queue in server "%s" has reached %d KB.', @RecoveryQueueSeverity, 1, @PartnerServer, @RecoveryQueue);
			GOTO Quit;
		END
	END

	-- Check active transaction log size
	IF @ActiveTranLogCheckCmd IS NOT NULL
	BEGIN
		SET @ActiveTranLogSizeMB = NULL;
		EXEC @sp_executesql @ActiveTranLogCheckCmd, @ActiveTranLogCheckParams, @ActiveTranLogSizeMB OUTPUT, @TotalTranLogSizeMB OUTPUT, @DatabaseName;

		IF (@ActiveTranLogSizeMB >= @MaxActiveTranLogSizeMB) OR (@ActiveTranLogSizeMB * 100.0 / @TotalTranLogSizeMB >= @MaxActiveTranLogSizePct)
		BEGIN
			RAISERROR(N'-- Stopping because the active transaction log size of database "%s" has reached %d MB out of %d MB in total.', @ActiveTranLogSeverity, 1, @DatabaseName, @ActiveTranLogSizeMB, @TotalTranLogSizeMB);
			GOTO Quit;
		END
	END

	SET @CurrSizeMB = @CurrSizeMB-@IntervalMB
	IF @CurrSizeMB < @TargetSizeMB OR @IntervalMB IS NULL SET @CurrSizeMB = @TargetSizeMB
	
	SET @CMD = N'DBCC SHRINKFILE (N' + QUOTENAME(@FileName, N'''') + N' , ' + CONVERT(nvarchar(1000), @CurrSizeMB) + N') WITH NO_INFOMSGS; -- ' + CONVERT(nvarchar(25),GETDATE(),121)
	RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;

	IF @WhatIf = 1
		PRINT N'-- @WhatIf was set to 1. Skipping execution.'
	ELSE
	BEGIN
		BEGIN TRY
				EXEC @sp_executesql @CMD
		END TRY
		BEGIN CATCH
			-- File ID %d of database ID %d cannot be shrunk as it is either being shrunk by another process or is empty.
			IF @RegrowOnError5240 = 1 AND ERROR_NUMBER() = 5240
			BEGIN
				-- This error can be solved by increasing the file size a bit before shrinking again
				SET @CMD = N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + N' MODIFY FILE (NAME = ' + QUOTENAME(@FileName, N'''') + N', SIZE = ' + CONVERT(nvarchar(1000), @CurrSizeMB + @IntervalMB) + N'MB); -- ' + CONVERT(nvarchar(25),GETDATE(),121)
			
				PRINT N'-- Error 5240 encountered. Regrowing:'
				RAISERROR(N'%s',0,1,@CMD) WITH NOWAIT;
			
				EXEC @sp_executesql @CMD
			END
			ELSE
				THROW;
		END CATCH

		-- Re-check new file size
		EXEC @sp_executesql N'SELECT @NewSizeInMB = [size]/128 FROM sys.database_files WHERE [name] = @FileName;'
					, N'@FileName SYSNAME, @NewSizeInMB FLOAT OUTPUT', @FileName, @NewSizeMB OUTPUT
	
		-- See if target size was successfully reached
		IF @NewSizeMB > @CurrSizeMB
		BEGIN
			IF @RetryNum >= @IterationMaxRetries
			BEGIN
				RAISERROR(N'-- Unable to shrink below %d MB. Stopping operation after %d retries.', 12, 1, @NewSizeMB, @RetryNum) WITH NOWAIT;
				BREAK;
			END
			ELSE
			BEGIN
				SET @RetryNum = @RetryNum + 1;
				SET @CurrSizeMB = @NewSizeMB;
				RAISERROR(N'-- Unable to shrink below %d MB. Retry attempt %d...', 0, 1, @NewSizeMB, @RetryNum) WITH NOWAIT;
			END
		END
		ELSE
			SET @RetryNum = 0;
	
		-- Sleep between iterations
		IF @DelayBetweenShrinks IS NOT NULL
			WAITFOR DELAY @DelayBetweenShrinks;
	END
END

PRINT N'-- Done - ' + CONVERT(nvarchar(25),GETDATE(),121)
Quit: