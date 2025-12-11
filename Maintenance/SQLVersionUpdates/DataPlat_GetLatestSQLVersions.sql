SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
Get Latest SQL Server Versions from DataPlat.Github.io
=======================================================
Author: Eitan Blumin
Date: 2025-09-01
Source:
https://dataplat.github.io/builds
https://raw.githubusercontent.com/dataplat/dbatools/refs/heads/development/bin/dbatools-buildref-index.json
*/
CREATE PROCEDURE [dbo].[UpdateVersions_DataPlat]
AS
SET TEXTSIZE 2147483647;
SET QUOTED_IDENTIFIER, NOCOUNT, ARITHABORT, XACT_ABORT ON;

DECLARE @url nvarchar(4000) = 'https://dataplat.github.io/assets/dbatools-buildref-index.json'

DECLARE @response nvarchar(max)

SELECT @response = dbo.clr_http_request('GET', @Url, NULL, NULL, 300000, 0, 0).value('/Response[1]/Body[1]', 'NVARCHAR(MAX)')
OPTION(RECOMPILE);

DECLARE @LastUpdated DATETIME
SET @LastUpdated = JSON_VALUE(@response, '$.LastUpdated')

DROP TABLE IF EXISTS #data;
CREATE TABLE #data
(
	rowID int IDENTITY(1,1),
	[Version] varchar(50) COLLATE DATABASE_DEFAULT NOT NULL,
	[Name] varchar(50)COLLATE DATABASE_DEFAULT NULL,
	[SP] varchar(50) COLLATE DATABASE_DEFAULT NULL,
	[CU] varchar(50) COLLATE DATABASE_DEFAULT NULL,
	[SupportedUntil] datetime NULL,
	[KB] varchar(50) COLLATE DATABASE_DEFAULT NULL
)

INSERT INTO #data
([Version],[Name],[SP],[CU],[SupportedUntil],[KB])
SELECT  
 JSON_VALUE([value], '$.Version') AS [Version]
,JSON_VALUE([value], '$.Name') AS [Name]
,JSON_VALUE([value], '$.SP') AS [SP]
,JSON_VALUE([value], '$.CU') AS [CU]
,JSON_VALUE([value], '$.SupportedUntil') AS SupportedUntil
,KB = (SELECT MAX(KB)
	FROM
	(
	SELECT CONVERT(int, JSON_VALUE(r.[value], '$.KBList')) AS KB
	WHERE JSON_VALUE(r.[value], '$.KBList') IS NOT NULL
	UNION ALL
	SELECT MAX(CONVERT(int, KBList.[value]))
	FROM OPENJSON(JSON_QUERY(r.[value], '$.KBList')) AS KBList
	WHERE JSON_QUERY(r.[value], '$.KBList') IS NOT NULL
	) AS k
	)
FROM OPENJSON(@response, '$.Data') AS r
WHERE JSON_VALUE([value], '$.Retired') IS NULL
AND (
   JSON_VALUE([value], '$.KBList') IS NOT NULL
OR JSON_VALUE([value], '$.Name') IS NOT NULL
OR JSON_VALUE([value], '$.SP') IS NOT NULL
OR JSON_QUERY([value], '$.KBList') IS NOT NULL
);


WITH BaseVersions
AS
(
SELECT *
, NextBaseVersionRowID = LEAD(rowID) OVER(ORDER BY rowID ASC)
FROM #data
WHERE [Name] IS NOT NULL
),
LatestVersions
AS
(
SELECT b.[Name] AS VersionName
--, b.rowID
--, b.NextBaseVersionRowID
, sp.SP AS LatestSP
, cu.CU AS LatestCU
, ver.KB AS LatestKB, ISNULL(ver.Version, lastver.Version) AS LatestKBVersion
, LatestMajorVersion = PARSENAME(ISNULL(ver.Version, lastver.Version),3)
, LatestMinorVersion = PARSENAME(ISNULL(ver.Version, lastver.Version),2)
, LatestBuildVersion = PARSENAME(ISNULL(ver.Version, lastver.Version),1)
, LatestVersionUrl = 'https://support.microsoft.com/en-us/help/' + ver.KB
FROM BaseVersions AS b
OUTER APPLY
(
	SELECT TOP 1 *
	FROM #data AS s
	WHERE s.rowID > b.rowID
	AND (s.rowID < b.NextBaseVersionRowID OR b.NextBaseVersionRowID IS NULL)
	AND s.SP IS NOT NULL
	ORDER BY s.rowID DESC
) AS sp
OUTER APPLY
(
	SELECT TOP 1 *
	FROM #data AS s
	WHERE s.rowID > b.rowID
	AND (s.rowID < b.NextBaseVersionRowID OR b.NextBaseVersionRowID IS NULL)
	AND s.CU IS NOT NULL
	ORDER BY s.rowID DESC
) AS cu
OUTER APPLY
(
	SELECT TOP 1 *
	FROM #data AS s
	WHERE s.rowID > b.rowID
	AND (s.rowID < b.NextBaseVersionRowID OR b.NextBaseVersionRowID IS NULL)
	AND s.KB IS NOT NULL
	ORDER BY s.rowID DESC
) AS ver
OUTER APPLY
(
	SELECT TOP 1 *
	FROM #data AS s
	WHERE s.rowID > b.rowID
	AND (s.rowID < b.NextBaseVersionRowID OR b.NextBaseVersionRowID IS NULL)
	ORDER BY s.rowID DESC
) AS lastver
)
--SELECT @LastUpdated AS LastUpdated, * FROM LatestVersions
MERGE INTO [dbo].[SQLVersions] as trg
USING (SELECT * FROM LatestVersions) as src
ON  trg.[MinorVersionNumber] = src.LatestMinorVersion
AND trg.[MajorVersionNumber] = src.LatestMajorVersion
AND trg.[BuildVersionNumber] = src.LatestBuildVersion
	
WHEN MATCHED and exists (select src.LatestVersionUrl EXCEPT select trg.[DownloadUrl]) THEN
	UPDATE SET [DownloadUrl] = src.LatestVersionUrl, [ReleaseDate] = @LastUpdated
WHEN NOT MATCHED THEN
INSERT 
([Version],[BuildNumber],[ReleaseDate],[MajorVersionNumber],[MinorVersionNumber],[BuildVersionNumber],[DownloadUrl])
VALUES
(src.[VersionName],src.LatestKBVersion,@LastUpdated,src.LatestMajorVersion,src.LatestMinorVersion,src.LatestBuildVersion,src.LatestVersionUrl)
;

RAISERROR(N'Affected build versions: %d',0,1,@@ROWCOUNT) WITH NOWAIT;

DROP TABLE #data;
GO