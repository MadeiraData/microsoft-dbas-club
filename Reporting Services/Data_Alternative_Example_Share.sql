USE ReportServer
GO

IF OBJECT_ID(N'[dbo].[RunPseudoDataDrivenFileShareReport]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[RunPseudoDataDrivenFileShareReport]
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO
/*
-- Sample usage:
EXEC [RunPseudoDataDrivenFileShareReporte] @ReportConfigID = 56, @ReportPath = N'/PeriodicReports/Monthly Report'
*/
CREATE PROCEDURE dbo.[RunPseudoDataDrivenFileShareReport]
	@ReportConfigID		INT,
	@ReportPath			NVARCHAR(850)
AS
DECLARE @ScheduleID uniqueidentifier;

SELECT @ScheduleID = RS.ScheduleID
FROM [Catalog] AS C
INNER JOIN ReportSchedule AS RS
ON C.ItemID = RS.ReportID
WHERE C.Path = @ReportPath

IF @ScheduleID IS NULL
BEGIN
	RAISERROR(N'No subscription schedule found for report %s',16,1,@ReportPath);
	RETURN -1;
END

DECLARE @DataDrivenConfig AS TABLE (FileName nvarchar(2000), FilePath nvarchar(2000), WriteMode nvarchar(20), RenderFormat varchar(50), ReportParameters XML)

INSERT INTO @DataDrivenConfig
EXEC dbo.ReportConfigFileShareGet @ReportConfigID

IF @@ROWCOUNT = 0
BEGIN
	RAISERROR(N'No Report Config found for ID %d',16,1,@ReportConfigID);
	RETURN -1;
END

DECLARE
	@FileName nvarchar(2000),
	@FilePath nvarchar(2000),
	@WriteMode nvarchar(20),
	@RenderFormat nvarchar(50), 
	@ReportParameters XML

DECLARE Configs CURSOR
LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
SELECT
	FileName,
	FilePath,
	WriteMode,
    RenderFormat, 
	ReportParameters
FROM @DataDrivenConfig

WHILE 1=1
BEGIN
	FETCH NEXT FROM Configs INTO @FileName, @FilePath, @WriteMode, @RenderFormat, @ReportParameters
	IF @@FETCH_STATUS <> 0 BREAK;

	EXEC dbo.[data_driven_subscription_file_share]
						 @scheduleID	= @ScheduleID
						,@FileName		= @FileName			
						,@FilePath		= @FilePath			
						,@WriteMode		= @WriteMode
						,@renderFormat	= @RenderFormat
						,@ParameterValues = @ReportParameters
END

CLOSE Configs;
DEALLOCATE Configs;
GO
