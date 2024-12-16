/*
Copyright 2024 by niritl@madeiradata. all rights reserved
---------------------------------------------------------------------------
Log reader is an executable which executes from the distributor and scans the T-Log of the publisher database. 
There are two threads that do the work:
Reader Thread - Reads the T-Log via the stored procedure, sp_replcmds. 
	This scans the T-Log and identifies the commands to be replicated by skipping not-to-be replicated commands.
Writer Thread - Writes the transactions identified by the reader thread into the distribution database via sp_MSadd_replcmds.

This alert checks 2 issues on transaction replication log reader.
1. High latency - higher than 10 seconds
2. Log reader job is not active

This script should run on the publisher server.
Output:
		0 - All is good
		1 - Latency higher than 10 seconds
		2 - Log reader job is not active

In order to find the job name of the log reader, run: use <>; exec  sp_helplogreader_agent 

More details can be found by running the following on the distribution database:
exec sp_replmonitorhelppublication @publication_type = 0

Links:
https://www.mssqltips.com/sqlservertip/3598/troubleshooting-transactional-replication-latency-issues-in-sql-server/
https://www.brentozar.com/archive/2014/07/monitoring-sql-server-transactional-replication/
https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-replcounters-transact-sql?view=sql-server-ver16
*/

DECLARE @Output INT = 0
	, @LastCheckTime datetime;

IF OBJECT_ID('tempdb..#replcounters') IS NOT NULL
    DROP TABLE #replcounters;
CREATE TABLE #replcounters (
	CheckTime		datetime default (getdate())
	, DBName		sysname
	, ReplTran		int
	, ReplRate		float
	, ReplLatency	float
	, ReplBeginlsn	binary(10)
	, ReplNextlsn	binary(10));

INSERT INTO #replcounters(DBName, ReplTran, ReplRate, ReplLatency, ReplBeginlsn, ReplNextlsn)
EXEC sp_replcounters;

IF @@ROWCOUNT > 0 
BEGIN 
    -- Check latency
	SELECT TOP 1 @Output = 1
	FROM #replcounters
	WHERE 1=1
		AND ReplLatency > 10;

    SELECT @LastCheckTime = Max(CheckTime) 
	FROM #replcounters;

	WAITFOR DELAY '00:00:05';

	INSERT INTO #replcounters(DBName, ReplTran, ReplRate, ReplLatency, ReplBeginlsn, ReplNextlsn)
	EXEC sp_replcounters;

	-- Check activation 
	SELECT TOP 1 @Output = 2
	FROM (
		SELECT DBName, ReplTran, ReplBeginlsn
		FROM #replcounters
		WHERE CheckTIme <= @LastCheckTime
	)a
	INNER JOIN (
		SELECT DBName, ReplTran, ReplBeginlsn
		FROM #replcounters
		WHERE CheckTime > @LastCheckTime
	)b
		ON a.DBName = b.DBName
	WHERE 1=1
		AND a.ReplTran < b.ReplTran -- # of replicated transaction is growing
		AND a.ReplBeginlsn = b.ReplBeginlsn;
END

SELECT @Output;
