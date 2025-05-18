USE ReportServer
GO
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO
CREATE TABLE dbo.ReportDataDrivenConfig (
    ReportConfigID INT,
    ToList NVARCHAR(2000),
    CcList NVARCHAR(2000),
    BccList NVARCHAR(2000),
    IncludeReport BIT,
	FileName nvarchar (2000),
	FilePath nvarchar (2000),
	WriteMode nvarchar (20),
    RenderFormat VARCHAR(50),
    [Priority] NVARCHAR(10),
    [Subject] NVARCHAR(1000),
    Comment NVARCHAR(MAX),
    IncludeLink BIT,
	ReportParameters XML,
	INDEX IX_C CLUSTERED (ReportConfigID)
);
GO
IF OBJECT_ID(N'[dbo].[ReportConfigEmailGet]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[ReportConfigEmailGet]
GO
CREATE PROCEDURE dbo.ReportConfigEmailGet
    @ReportConfigID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
    FROM 
        dbo.ReportDataDrivenConfig
    WHERE 
        ReportConfigID = @ReportConfigID
	OR @ReportConfigID IS NULL;
END;
GO
IF OBJECT_ID(N'[dbo].[ReportConfigEmailAdd]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[ReportConfigEmailAdd]
GO
CREATE PROCEDURE dbo.ReportConfigEmailAdd
	@ReportConfigID INT,
    @ToList NVARCHAR(2000),
    @CcList NVARCHAR(2000),
    @BccList NVARCHAR(2000),
    @IncludeReport BIT,
    @RenderFormat VARCHAR(50),
    @Priority NVARCHAR(10),
    @Subject NVARCHAR(1000),
    @Comment NVARCHAR(MAX),
    @IncludeLink BIT,
	@ReportParameters XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ReportDataDrivenConfig (
		ReportConfigID,
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
    )
    VALUES (
		@ReportConfigID,
        @ToList, 
        @CcList, 
        @BccList, 
        @IncludeReport, 
        @RenderFormat, 
        @Priority, 
        @Subject, 
        @Comment, 
        @IncludeLink,
		@ReportParameters
    );
END;
GO
IF OBJECT_ID(N'[dbo].[ReportConfigFileShareGet]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[ReportConfigFileShareGet]
GO
CREATE PROCEDURE dbo.ReportConfigFileShareGet
    @ReportConfigID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
		FileName,
		FilePath,
		WriteMode,
        RenderFormat, 
		ReportParameters
    FROM 
        dbo.ReportDataDrivenConfig
    WHERE 
        ReportConfigID = @ReportConfigID
	OR @ReportConfigID IS NULL;
END;
GO
IF OBJECT_ID(N'[dbo].[ReportConfigFileShareGet]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[ReportConfigFileShareGet]
GO
CREATE PROCEDURE dbo.ReportConfigFileShareGet
	@ReportConfigID INT,
    @FileName nvarchar (2000),
	@FilePath nvarchar (2000),
	@WriteMode nvarchar (20),
    @RenderFormat VARCHAR(50),
	@ReportParameters XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ReportDataDrivenConfig (
		ReportConfigID,
		FileName,
		FilePath,
		WriteMode, 
        RenderFormat,
		ReportParameters
    )
    VALUES (
		@ReportConfigID,
		@FileName,
		@FilePath,
		@WriteMode, 
        @RenderFormat, 
		@ReportParameters
    );
END;
GO
IF OBJECT_ID(N'[dbo].[ReportConfigRemove]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[ReportConfigRemove]
GO
CREATE PROCEDURE dbo.ReportConfigRemove
    @ReportConfigID INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.ReportDataDrivenConfig
    WHERE ReportConfigID = @ReportConfigID;
END;
GO
-- Based on script by Jason Selburg
-- https://www.sqlservercentral.com/Forums/Topic279460-150-1.aspx
-- http://www.sqlservercentral.com/scripts/Miscellaneous/31733/
USE ReportServer
GO
IF OBJECT_ID(N'[dbo].[get_data_driven_subscription_info]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[get_data_driven_subscription_info]
GO
CREATE PROCEDURE dbo.get_data_driven_subscription_info
@scheduleID uniqueidentifier
AS

SET NOCOUNT ON;

DECLARE
@subscriptionID uniqueidentifier,
@ReportID uniqueidentifier

-- set the subscription ID
SELECT @subscriptionID = SubscriptionID, @ReportID = ReportID
FROM ReportSchedule WHERE ScheduleID = @scheduleID

SELECT ItemID AS ReportID, [Path], [Name], @scheduleID AS [ScheduleID], ExtensionSettings, [Parameters]
FROM [Catalog] AS c, Subscriptions AS sub
WHERE sub.SubscriptionID = @SubscriptionID
AND c.ItemID = @ReportID

GO

IF OBJECT_ID(N'[dbo].[data_driven_subscription]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[data_driven_subscription]
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

CREATE PROCEDURE dbo.data_driven_subscription
(
@scheduleID uniqueidentifier,
@emailTO nvarchar (2000) = ' ',
@emailCC nvarchar (2000) = ' ',
@emailBCC nvarchar (2000) = ' ',
@emailReplyTO nvarchar (2000) = ' ',
@emailBODY nvarchar(max) = ' ',
@sub nvarchar(1000) = ' ',
@renderFormat nvarchar(50) = 'PDF',
@IncludeReport bit = 0,
@IncludeLink bit = 0,
@Priority nvarchar(10) = 'NORMAL',
@ParameterValues XML = NULL
/* @ParameterValues example:
'<ParameterValues>
 <ParameterValue><Name>' + @p1 + '</Name><Value>' + @param1 + '</Value></ParameterValue>
</ParameterValues>'
*/
)

AS

DECLARE
@ptrval binary(16), 
@PARAMptrval binary(16),
@TOpos int, 
@CCpos int, 
@BCCpos int, 
@RTpos int, 
@BODYpos int,
@PARAM1Pos int, 
@length int,
@subscriptionID uniqueidentifier,
@job_status int,
@I int, -- the rest were added by hugh 
@starttime datetime,
@lastruntime datetime,
@execTime datetime,
@dValues nvarchar (max),
@pValues nvarchar (max) = CONVERT(nvarchar(max), @ParameterValues)

set @starttime = DATEADD(second, -2, getdate())
set @job_status = 1
set @I = 1
set @emailTO = rtrim(@emailTO)
set @emailCC = rtrim(@emailCC)
set @emailBCC = rtrim(@emailBCC)
set @emailReplyTO = rtrim(@emailReplyTO)
set @emailBODY = rtrim(@emailBODY)
set @Priority = rtrim(@Priority)
set @renderFormat = rtrim(@renderFormat)


-- set the subscription ID
SELECT @subscriptionID = SubscriptionID
FROM ReportSchedule WHERE ScheduleID = @scheduleID


set @dValues = ''
set @pValues = ''


if IsNull(@emailTO, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>TO</Name><Value>' + @emailTO + '</Value></ParameterValue>' 

if IsNull(@emailCC, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>CC</Name><Value>' + @emailCC + '</Value></ParameterValue>' 

if IsNull(@emailBCC, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>BCC</Name><Value>' + @emailBCC + '</Value></ParameterValue>' 

if IsNull(@emailReplyTO, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>ReplyTo</Name><Value>' + @emailReplyTO + '</Value></ParameterValue>'

if IsNull(@emailBODY, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>Comment</Name><Value>' + @emailBODY + '</Value></ParameterValue>'

if IsNull(@sub, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>Subject</Name><Value>' + @sub + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>Priority</Name><Value>' + IsNull(NullIf(@Priority,''), 'NORMAL') + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> ''
set @dValues = @dValues + '<ParameterValue><Name>IncludeReport</Name><Value>' + CASE WHEN @IncludeReport = 1 THEN 'True' ELSE 'False' END + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> ''
set @dValues = @dValues + '<ParameterValue><Name>IncludeLink</Name><Value>' + CASE WHEN @IncludeLink = 1 THEN 'True' ELSE 'False' END + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> ''
set @dValues = '<ParameterValues>' + @dValues + '<ParameterValue><Name>RenderFormat</Name><Value>' + IsNull(@renderFormat, 'PDF') + '</Value></ParameterValue>' + 
'</ParameterValues>'


if IsNull(@dValues, '') <> ''
BEGIN

update Subscriptions set extensionsettings = '' WHERE SubscriptionID = @SubscriptionID


-- set the text point for this record
SELECT @ptrval = TEXTPTR(ExtensionSettings) 
FROM Subscriptions WHERE SubscriptionID = @SubscriptionID

UPDATETEXT Subscriptions.ExtensionSettings 
@ptrval 
null
null
@dValues

End

if IsNull(@pValues, '') <> ''
BEGIN
update Subscriptions set parameters = '' WHERE SubscriptionID = @SubscriptionID

-- set the text point for this record
SELECT @PARAMptrval = TEXTPTR(Parameters) 
FROM Subscriptions WHERE SubscriptionID = @SubscriptionID

UPDATETEXT Subscriptions.Parameters 
@PARAMptrval 
null
null
@pValues

End

-- run the job
exec msdb..sp_start_job @job_name = @scheduleID


-- this give the report server time to execute the job
SELECT @lastruntime = LastRunTime FROM Schedule WHERE ScheduleID = @scheduleID
While (@starttime > @lastruntime)
Begin
print '...'
print @lastruntime
WAITFOR DELAY '00:00:03'
SELECT @lastruntime = LastRunTime FROM Schedule WHERE ScheduleID = @scheduleID
End
GO
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO

----------------------------------------------------------
/* Use .WRITE instead of UPDATETEXT
The following example uses the .WRITE clause to update a partial value in DocumentSummary, 
an nvarchar(max) column in the Production.Document table.
The word components is replaced with the word features by specifying the replacement word,
the starting location (offset) of the word to be replaced in the existing data,
and the number of characters to be replaced (length). 
The example also uses the OUTPUT clause to return the before and after images of the DocumentSummary column to the @MyTableVar table variable.

USE AdventureWorks2012;  
GO  
DECLARE @MyTableVar table (  
    SummaryBefore nvarchar(max),  
    SummaryAfter nvarchar(max));  
UPDATE Production.Document  
SET DocumentSummary .WRITE (N'features',28,10)  
OUTPUT deleted.DocumentSummary,   
       inserted.DocumentSummary   
    INTO @MyTableVar  
WHERE Title = N'Front Reflector Bracket Installation';  
SELECT SummaryBefore, SummaryAfter   
FROM @MyTableVar;  
GO*/
                         
-- Based on script by Jason Selburg
-- https://www.sqlservercentral.com/Forums/Topic279460-150-1.aspx
-- http://www.sqlservercentral.com/scripts/Miscellaneous/31733/
USE ReportServer
GO

IF OBJECT_ID(N'[dbo].[data_driven_subscription_file_share]', 'P') IS NOT NULL
DROP PROCEDURE [dbo].[data_driven_subscription_file_share]
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

CREATE PROCEDURE dbo.data_driven_subscription_file_share
(
@scheduleID uniqueidentifier,
@FileName nvarchar (2000) = ' ',
@FilePath nvarchar (2000) = ' ',
@renderFormat nvarchar(50) = 'PDF',
@WriteMode nvarchar (20) = 'OverWrite',
@ParameterValues XML = NULL
/* @ParameterValues example:
'<ParameterValues>
 <ParameterValue><Name>' + @p1 + '</Name><Value>' + @param1 + '</Value></ParameterValue>
</ParameterValues>'
*/
)

AS

DECLARE
@ptrval binary(16), 
@PARAMptrval binary(16),
@subscriptionID uniqueidentifier,
@job_status int,
@I int, -- the rest were added by hugh 
@starttime datetime,
@lastruntime datetime,
@execTime datetime,
@dValues nvarchar (max),
@UserName nvarchar(4000),
@Password nvarchar(4000),
@CurrentExtensionSettings XML,
@pValues nvarchar (max) = CONVERT(nvarchar(max), @ParameterValues)

set @starttime = DATEADD(second, -2, getdate())
set @job_status = 1
set @I = 1
set @FileName = rtrim(@FileName)
set @FilePath = rtrim(@FilePath)
set @renderFormat = rtrim(@renderFormat)


-- set the subscription ID
SELECT @subscriptionID = SubscriptionID
FROM ReportSchedule WHERE ScheduleID = @scheduleID

SELECT @CurrentExtensionSettings = CONVERT(xml,extensionsettings)
FROM Subscriptions WHERE SubscriptionID = @SubscriptionID

SELECT @UserName = p.[USERNAME], @Password = p.[PASSWORD]
FROM
(
	SELECT
		X.query('.').value('(ParameterValue/Name/text())[1]', 'nvarchar(4000)') AS Nam,
		X.query('.').value('(ParameterValue/Value/text())[1]', 'nvarchar(4000)') AS Val
	FROM @CurrentExtensionSettings.nodes('ParameterValues/ParameterValue') as T(X)
	WHERE X.query('.').value('(ParameterValue/Name/text())[1]', 'nvarchar(4000)') IN ('USERNAME', 'PASSWORD')
) AS q
pivot (max(Val) for Nam in ([USERNAME], [PASSWORD])) p


set @dValues = ''


if IsNull(@FileName, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>FILENAME</Name><Value>' + @FileName + '</Value></ParameterValue>' 

if IsNull(@FilePath, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>PATH</Name><Value>' + @FilePath + '</Value></ParameterValue>' 

if IsNull(@UserName, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>USERNAME</Name><Value>' + @UserName + '</Value></ParameterValue>' 

if IsNull(@Password, '') <> '' 
set @dValues = @dValues + '<ParameterValue><Name>PASSWORD</Name><Value>' + @Password + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> ''
set @dValues = @dValues + '<ParameterValue><Name>WRITEMODE</Name><Value>' + IsNull(NullIf(@WriteMode,''), 'OverWrite') + '</Value></ParameterValue>' 

if IsNull(@dValues, '') <> ''
set @dValues = '<ParameterValues>' + @dValues + '<ParameterValue><Name>RENDER_FORMAT</Name><Value>' + IsNull(@renderFormat, 'PDF') + '</Value></ParameterValue>' + 
'</ParameterValues>'

if IsNull(@dValues, '') <> ''
BEGIN

update Subscriptions set extensionsettings = '' WHERE SubscriptionID = @SubscriptionID


-- set the text point for this record
SELECT @ptrval = TEXTPTR(ExtensionSettings) 
FROM Subscriptions WHERE SubscriptionID = @SubscriptionID

UPDATETEXT Subscriptions.ExtensionSettings 
@ptrval 
null
null
@dValues

if IsNull(@pValues, '') <> ''
BEGIN
update Subscriptions set parameters = '' WHERE SubscriptionID = @SubscriptionID

-- set the text point for this record
SELECT @PARAMptrval = TEXTPTR(Parameters) 
FROM Subscriptions WHERE SubscriptionID = @SubscriptionID

UPDATETEXT Subscriptions.Parameters 
@PARAMptrval 
null
null
@pValues

End

-- run the job
exec msdb..sp_start_job @job_name = @scheduleID


-- this give the report server time to execute the job
SELECT @lastruntime = LastRunTime FROM Schedule WHERE ScheduleID = @scheduleID
While (@starttime > @lastruntime)
Begin
print '...'
print @lastruntime
WAITFOR DELAY '00:00:03'
SELECT @lastruntime = LastRunTime FROM Schedule WHERE ScheduleID = @scheduleID
End
END
GO
SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO

----------------------------------------------------------
/* Use .WRITE instead of UPDATETEXT
The following example uses the .WRITE clause to update a partial value in DocumentSummary, 
an nvarchar(max) column in the Production.Document table.
The word components is replaced with the word features by specifying the replacement word,
the starting location (offset) of the word to be replaced in the existing data,
and the number of characters to be replaced (length). 
The example also uses the OUTPUT clause to return the before and after images of the DocumentSummary column to the @MyTableVar table variable.

USE AdventureWorks2012;  
GO  
DECLARE @MyTableVar table (  
    SummaryBefore nvarchar(max),  
    SummaryAfter nvarchar(max));  
UPDATE Production.Document  
SET DocumentSummary .WRITE (N'features',28,10)  
OUTPUT deleted.DocumentSummary,   
       inserted.DocumentSummary   
    INTO @MyTableVar  
WHERE Title = N'Front Reflector Bracket Installation';  
SELECT SummaryBefore, SummaryAfter   
FROM @MyTableVar;  
GO*/