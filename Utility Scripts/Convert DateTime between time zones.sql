/*
Convert datetime between time zones
===================================
Author: Eitan Blumin
Date: 2025-03-25

For SQL Server instances version 2016 and newer:
	This script uses the AT TIME ZONE syntax to convert a datetime between time zones.

For SQL Server instances versions 2014 and older:
	This script can only support time zone conversion between server time and UTC and vice versa.
	Other time zones are not supported.
	This conversion is implemented using the current gap between getdate() and getutcdate()
	This also means that daylight saving time differences cannot be taken into consideration,
	unless the difference is the same as it is at the time of running this script.
*/
DECLARE
	 @SourceTimeZone		VARCHAR(50)	= NULL	-- Leave NULL to use server's local time zone as default
	,@TargetTimeZone		VARCHAR(50)	= 'UTC'	-- Leave NULL to use server's local time zone as default
	,@SourceDateTime		DATETIME	= NULL	-- Leave NULL to use current server time as default





DECLARE @sqlmajorver INT
SET @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff)

DECLARE @TargetDateTime	DATETIME = NULL;

SET @SourceDateTime = ISNULL(@SourceDateTime, GETDATE())

-- If SQL 2016 and newer, use AT TIME ZONE syntax:
IF @sqlmajorver >= 13
BEGIN
	-- If no custom time zone specified, use the server local timezone
	IF @SourceTimeZone IS NULL
	BEGIN
		EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',
		'SYSTEM\CurrentControlSet\Control\TimeZoneInformation',
		'TimeZoneKeyName',@SourceTimeZone OUT
	END
	IF @TargetTimeZone IS NULL
	BEGIN
		EXEC master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',
		'SYSTEM\CurrentControlSet\Control\TimeZoneInformation',
		'TimeZoneKeyName',@TargetTimeZone OUT
	END

	EXEC sp_executesql N'
	SET @TargetDateTime = @SourceDateTime AT TIME ZONE @SourceTimeZone AT TIME ZONE @TargetTimeZone;'
		, N'@SourceDateTime DATETIME, @SourceTimeZone VARCHAR(50), @TargetTimeZone VARCHAR(50), @TargetDateTime DATETIME OUTPUT'
		, @SourceDateTime, @SourceTimeZone, @TargetTimeZone, @TargetDateTime OUTPUT
END
ELSE IF @SourceTimeZone IS NULL AND @TargetTimeZone = 'UTC'
BEGIN
	SET @TargetDateTime = DATEADD(minute, DATEDIFF(minute, GETDATE(), GETUTCDATE()), @SourceDateTime);
END
ELSE IF @SourceTimeZone = 'UTC' AND @TargetTimeZone IS NULL
BEGIN
	SET @TargetDateTime = DATEADD(minute, DATEDIFF(minute, GETUTCDATE(), GETDATE()), @SourceDateTime);
END
ELSE
BEGIN
	RAISERROR(N'Specified time zone(s) not supported in this version of SQL Server',16,0);
END


SELECT @SourceDateTime AS [@SourceDateTime], @TargetDateTime AS [@TargetDateTime], @SourceTimeZone AS [@SourceTimeZone], @TargetTimeZone AS [@TargetTimeZone], @sqlmajorver AS [@sqlmajorver]