USE master;


DROP TABLE IF EXISTS dbo.SynchronizeSQLServerObjectsLog;
CREATE TABLE SynchronizeSQLServerObjectsLog
(
	 Id INT IDENTITY NOT NULL CONSTRAINT PK_SynchronizeSQLServerObjectsLog PRIMARY KEY NONCLUSTERED
	,StartTime DATETIME NOT NULL
	,EndtTime DATETIME NULL
	,SourcesServer VARCHAR(64) NOT NULL
	,DestinationServer VARCHAR(64) NOT NULL
	,ScriptFileName VARCHAR(64) NOT NULL
	,Error varchar(max) NULL
	,IsSuccess BIT NOT NULL
)
GO


DROP PROCEDURE IF EXISTS dbo.InsertSynchronizeSQLServerObjectsLog
GO	
CREATE OR ALTER PROCEDURE InsertSynchronizeSQLServerObjectsLog 
(
	 @SourcesServer VARCHAR(64)
	,@DestinationServer VARCHAR(64)
	,@ScriptFileName VARCHAR(64)
	,@IsSuccess bit
)
/*
	@IsSuccess: 0 = Success; 1 = Failure.
*/
AS
SET NOCOUNT ON;


INSERT dbo.SynchronizeSQLServerObjectsLog
(
    StartTime
   ,EndtTime
   ,SourcesServer
   ,DestinationServer
   ,ScriptFileName
   ,Error
   ,IsSuccess
)
VALUES
(   
	CURRENT_TIMESTAMP
   ,NULL				-- EndtTime - datetime
   ,@SourcesServer      -- SourcesServer - varchar(64)
   ,@DestinationServer  -- DestinationServer - varchar(64)
   ,@ScriptFileName     -- ScriptFileName - varchar(64)
   ,NULL				-- Error - varchar(max)
   ,@IsSuccess			-- IsSuccess bit
)


SELECT SCOPE_IDENTITY();
GO


DROP PROCEDURE IF EXISTS dbo.InsertSynchronizeSQLServerObjectsLog
GO
CREATE OR ALTER PROCEDURE UpdateSynchronizeSQLServerObjectsLog 
(
	 @Id INT
    ,@Error VARCHAR(max) = NULL
	,@IsSuccess BIT	
)
AS
SET NOCOUNT ON;


UPDATE dbo.SynchronizeSQLServerObjectsLog SET 
	 EndtTime	= CURRENT_TIMESTAMP
	,Error		= @Error  
	,IsSuccess  = @IsSuccess
WHERE id = @Id;
GO


DROP PROCEDURE IF EXISTS dbo.GetSynchronizeSQLServerObjectsLogFailedExecutions
GO
CREATE OR ALTER PROCEDURE GetSynchronizeSQLServerObjectsLogFailedExecutions
(
	 @dt DATETIME
)
/*
	Get failed executions
*/
AS
SET NOCOUNT ON;


SELECT 
	 DestinationServer
	,ScriptFileName
	--,IsSuccess
FROM dbo.SynchronizeSQLServerObjectsLog
INNER JOIN (
			SELECT MAX(l.StartTime)StartTime, l.Id FROM dbo.SynchronizeSQLServerObjectsLog l GROUP BY l.Id
			) last_row ON last_row.Id = SynchronizeSQLServerObjectsLog.Id
WHERE IsSuccess = 1
AND SynchronizeSQLServerObjectsLog.StartTime > @dt;

