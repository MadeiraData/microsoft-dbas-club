USE ReportServer
GO
DECLARE
	@ReportName nvarchar(4000),
	@ReportPath nvarchar(4000),
	@ScheduleID uniqueidentifier;

SELECT @ScheduleID = RS.ScheduleID
FROM [Catalog] AS C
INNER JOIN ReportSchedule AS RS
ON C.ItemID = RS.ReportID
WHERE C.Path = N'/PeriodicReports/Monthly Report'

SELECT
@ReportName = N'Monthly Report ' + CONVERT(NVARCHAR(6),DATEADD(MM,-1,GETDATE()),112),
@ReportPath = N'\\CorporateNas\Public\MonthlyReports'

EXEC dbo.data_driven_subscription_file_share
		@scheduleID = @ScheduleID
		, @FileName = @ReportName
		, @FilePath = @ReportPath
		, @renderFormat = 'PDF'
		, @WriteMode = 'OverWrite'
GO