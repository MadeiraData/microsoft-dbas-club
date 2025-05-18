USE ReportServer
GO

IF OBJECT_ID(N'[dbo].[RunPseudoDataDrivenReport]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[RunPseudoDataDrivenReport]
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO
/*
-- Sample usage:
EXEC [RunPseudoDataDrivenReport] @ReportConfigID = 56, @ReportPath = N'/PeriodicReports/Monthly Report'
*/
CREATE PROCEDURE dbo.[RunPseudoDataDrivenReport]
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

DECLARE @DataDrivenConfig AS TABLE (ToList nvarchar(2000), CcList nvarchar(2000), BccList nvarchar(2000), IncludeReport bit, RenderFormat varchar(50), [Priority] nvarchar(10), [Subject] nvarchar(1000), Comment nvarchar(max), IncludeLink bit, ReportParameters XML)

INSERT INTO @DataDrivenConfig
EXEC dbo.ReportConfigGet @ReportConfigID

IF @@ROWCOUNT = 0
BEGIN
	RAISERROR(N'No Report Config found for ID %d',16,1,@ReportConfigID);
	RETURN -1;
END

DECLARE
	@ToList nvarchar(2000), 
	@CcList nvarchar(2000), 
	@BccList nvarchar(2000), 
	@IncludeReport bit, 
	@RenderFormat nvarchar(50), 
	@Priority nvarchar(10), 
	@Subject nvarchar(1000), 
	@Comment nvarchar(max), 
	@IncludeLink bit,
	@ReportParameters XML

DECLARE Configs CURSOR
LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
SELECT
	ToList,
	CcList,
	BccList,
	IncludeReport, 
	RenderFormat, 
	[Priority], 
	[Subject], 
	Comment, 
	IncludeLink,
	ReportParameters
FROM @DataDrivenConfig

WHILE 1=1
BEGIN
	FETCH NEXT FROM Configs INTO @ToList, @CcList, @BccList, @IncludeReport, @RenderFormat, @Priority, @Subject, @Comment, @IncludeLink, @ReportParameters
	IF @@FETCH_STATUS <> 0 BREAK;

	EXEC dbo.[data_driven_subscription]
						 @scheduleID	= @ScheduleID
						,@emailTO		= @ToList			
						,@emailCC		= @CcList			
						,@emailBCC		= @BccList
						,@IncludeReport	= @IncludeReport	
						,@renderFormat	= @RenderFormat	
						,@Priority		= @Priority		
						,@sub			= @Subject		
						,@emailBODY		= @Comment		
						,@IncludeLink	= @IncludeLink
						,@ParameterValues = @ReportParameters
END

CLOSE Configs;
DEALLOCATE Configs;
GO
