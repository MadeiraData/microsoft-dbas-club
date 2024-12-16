/*
Copyright 2024 by niritl@madeiradata. all rights reserved
---------------------------------------------------------------------------
The distribution database is where the transaction replication is taking place.
This db responsible for reading the transaction data which came from the Log reader and applying it at the subscriber/s.

This alert checks 2 issues: 
1. High latency - more commands for replication are generated than the number of commands applied on some subscribers.
2. Distribution is not active for one or more subscriptions.

This script should run on the distribution db server.
Output:
		0 - All is good
		1 - High latency
		2 - Distribution is not active for one or more subscriptions

More details can be found by running the following on the distribution database:
exec sp_replmonitorhelpsubscription @publication_type = 0, @mode=3

Links:
https://www.mssqltips.com/sqlservertip/3598/troubleshooting-transactional-replication-latency-issues-in-sql-server/
https://www.brentozar.com/archive/2014/07/monitoring-sql-server-transactional-replication/
https://learn.microsoft.com/en-us/sql/relational-databases/replication/monitor/programmatically-monitor-replication?view=sql-server-ver16
*/

DECLARE @Output INT = 0
	, @LastCheckTime datetime;

IF OBJECT_ID('tempdb..#distribution_status') IS NOT NULL
    DROP TABLE #distribution_status;
CREATE TABLE #distribution_status (
	CheckTime		datetime default (getdate())
	, article_id			int 
	, agent_id				int
	, UndelivCmdsInDistDB	int
	, DelivCmdsInDistDB		int);

INSERT INTO #distribution_status(article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB )
SELECT article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB
FROM  distribution.dbo.MSdistribution_status 
WHERE 1=1
    AND UndelivCmdsInDistDB > 10000;

IF @@ROWCOUNT > 0 
BEGIN 

    SELECT @LastCheckTime = Max(CheckTime) 
	FROM #distribution_status;
	
	WAITFOR DELAY '00:00:05';

	INSERT INTO #distribution_status(article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB )
	SELECT article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB
	FROM  distribution.dbo.MSdistribution_status 
	WHERE 1=1
		AND UndelivCmdsInDistDB > 10000;

	SELECT @Output = CASE 
			WHEN b.UndelivCmdsInDistDB - a.UndelivCmdsInDistDB > b.DelivCmdsInDistDB - a.DelivCmdsInDistDB 
			THEN 1			
			WHEN a.UndelivCmdsInDistDB <= b.UndelivCmdsInDistDB 
				AND a.DelivCmdsInDistDB = b.DelivCmdsInDistDB
			THEN 2
			ELSE 0
		END
	FROM (
		SELECT article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB
		FROM #distribution_status
		WHERE CheckTIme <= @LastCheckTime
	)a
	INNER JOIN (
		SELECT article_id, agent_id, UndelivCmdsInDistDB, DelivCmdsInDistDB
		FROM #distribution_status
		WHERE CheckTIme > @LastCheckTime
	)b
		ON a.article_id = b.article_id
		AND a.agent_id = b.agent_id
	WHERE 1=1
		AND a.UndelivCmdsInDistDB < b.UndelivCmdsInDistDB -- # of replicated transaction is growing
		AND a.DelivCmdsInDistDB = b.DelivCmdsInDistDB;
END

SELECT @Output;