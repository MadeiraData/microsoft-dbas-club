/*
	Created: Vitaly Bruk / MadeiraData
	Date:	2024-12-23
	
	Description:
		Query plans that have been forced in Query Store may end up with the forcing in a “failed” state for a variety of reasons.
		Sometimes this might be that a structure in the forced plan is no longer valid - maybe an index that had been selected in the plan has been dropped or its definition has changed.
		This script identifies queries with forced plans that have failed with GENERAL_FAILURE in Query Store.
		
		The script adapted to run on SQL Server (2008 and up), Azure SQL DB and Azure Managed Instance 

*/


SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE
	@WhatIf			BIT				= 0,		-- Set to 1 to only print the commands but not run them.
	@database_name	SYSNAME			= NULL,		-- Leave NULL to check all databases or choose specific one
	@sql			NVARCHAR(MAX);

IF OBJECT_ID('tempdb.dbo.#FailedForcedPlans', 'U') IS NOT NULL
BEGIN
	DROP TABLE #FailedForcedPlans;
END

-- Temporary table to collect failed forced plans across databases
CREATE TABLE #FailedForcedPlans
							(
								[database_name]			SYSNAME,
								query_id				INT,
								plan_id					INT,
								failure_reason			NVARCHAR(128),
								query_sql_text			NVARCHAR(MAX),
								force_failure_count		INT
							);

-- Cursor to loop through all user databases
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR

	SELECT 
		[name]
	FROM 
		sys.databases
	WHERE
		state_desc = 'ONLINE'						-- databases in online state only
		AND user_access = 0							-- accessable databases only
		AND is_query_store_on = 1					-- databases with QS enabled only
		AND database_id > 4							-- exclude system databases
		AND [name] != 'rdsadmin'					-- exclude AWS RDS system database
		AND
			(
				@database_name IS NULL 
				OR [name] = @database_name			-- specific databases only
			);

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @database_name;

WHILE @@FETCH_STATUS = 0
BEGIN
	BEGIN TRY
		SET @sql = '
			SELECT 
				' + QUOTENAME(@database_name) + ',
				qsqp.query_id,
				qsqp.plan_id,
				qsqp.last_force_failure_reason_desc,
				qsqt.query_sql_text,
				qsqp.force_failure_count
			FROM 
				' + QUOTENAME(@database_name) + '.sys.query_store_plan AS qsqp
				LEFT JOIN ' + QUOTENAME(@database_name) + '.sys.query_store_query AS qsq ON qsqp.query_id = qsq.query_id
				LEFT JOIN ' + QUOTENAME(@database_name) + '.sys.query_store_query_text AS qsqt ON qsq.query_text_id = qsqt.query_text_id
			WHERE 
				qsqp.is_forced_plan = 1
				AND qsqp.force_failure_count > 0
				AND qsqp.last_force_failure_reason_desc = ''GENERAL_FAILURE''
			OPTION (RECOMPILE);
		';

		IF @WhatIf != 0
		BEGIN
			PRINT @sql
		END
		ELSE
		BEGIN
            -- Execute dynamic SQL inside TRY block
			BEGIN TRY
                INSERT INTO #FailedForcedPlans ([database_name], query_id, plan_id, failure_reason, query_sql_text, force_failure_count)
                EXEC sp_executesql @sql;
            END TRY
            BEGIN CATCH
                PRINT 'Error executing dynamic SQL for database ' + @database_name + ': ' + ERROR_MESSAGE();
            END CATCH;
        END

    END TRY
    BEGIN CATCH
        PRINT 'Error processing database ' + @database_name + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @database_name;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

IF @WhatIf = 0
BEGIN
	-- Output results
	SELECT
		[database_name],
		query_id,
		plan_id,
		failure_reason,
		query_sql_text,
		force_failure_count,
		CONCAT	(
					CASE	
						WHEN CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)) BETWEEN 1 AND 4	-- SQL Server
							OR CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)) = 8				-- Azure SQL Managed Instance
								THEN CONCAT('USE ', QUOTENAME ([database_name]), '; ')
						WHEN CAST (SERVERPROPERTY('EngineEdition') AS NVARCHAR(128)) = 5				-- Azure SQL Database
								THEN ''
					END,
					'EXEC sp_query_store_unforce_plan @query_id = ', query_id, ', @plan_id = ', plan_id, '; '
				)	AS Script
	FROM
		#FailedForcedPlans
	ORDER BY
		[database_name],
		query_id;

END

-- Cleanup
DROP TABLE #FailedForcedPlans;
