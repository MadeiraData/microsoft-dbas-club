/*
Check for (existing) backup files located on the same physical volume as database files
========================================================================================
Author: Eitan Blumin
Create Date: 2018-06-04
Last Update: 2022-12-26
*/
SET NOCOUNT, ARITHABORT, XACT_ABORT, QUOTED_IDENTIFIER ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @ShowDetails bit = 1;

DECLARE @RecentBackups AS TABLE (ID INT PRIMARY KEY IDENTITY(1,1), PhysicalPath NVARCHAR(4000), DeviceName NVARCHAR(4000), DBFilesCount INT NULL);
DECLARE @DBDevices AS TABLE (DeviceName NVARCHAR(4000) NOT NULL PRIMARY KEY, NumOfFiles int);
DECLARE @CurrID INT, @CurrFile NVARCHAR(4000), @DeviceName nvarchar(4000), @DBFilesCount INT, @Exists INT;

-- Get distinct list of devices used by DB files
INSERT INTO @DBDevices
SELECT UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3))), COUNT(*)
FROM sys.master_files AS mf
WHERE [database_id] NOT IN (1,3,32767)
GROUP BY UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3)))

-- Get list of relevant backup files to check
INSERT INTO @RecentBackups(PhysicalPath, DeviceName)
SELECT DISTINCT physical_device_name, UPPER(SUBSTRING(physical_device_name, 0, CHARINDEX('\', physical_device_name, 3)))
FROM msdb.dbo.backupmediafamily AS bmf
INNER JOIN msdb.dbo.backupset AS bs
ON bmf.media_set_id = bs.media_set_id
AND physical_device_name IS NOT NULL
AND physical_device_name NOT LIKE 'C:\ClusterStorage\%'
AND physical_device_name NOT LIKE '{%}%'
AND EXISTS (SELECT * FROM @DBDevices AS d WHERE d.DeviceName = UPPER(SUBSTRING(physical_device_name, 0, CHARINDEX('\', physical_device_name, 3))))

-- Check which backup files still exist on disk
DECLARE Backups CURSOR LOCAL READ_ONLY STATIC FORWARD_ONLY FOR
SELECT bmf.ID, bmf.PhysicalPath
FROM @RecentBackups AS bmf
WHERE bmf.PhysicalPath NOT LIKE 'C:\ClusterStorage\%'
 
OPEN Backups
 
WHILE 1=1
BEGIN
	FETCH NEXT FROM Backups INTO @CurrID, @CurrFile
	IF @@FETCH_STATUS <> 0 BREAK;

 SET @Exists = 1;
 EXEC master.dbo.xp_fileexist @CurrFile, @Exists out;
 
 IF @Exists = 0
  DELETE FROM @RecentBackups WHERE ID = @CurrID;
 
END
 
CLOSE Backups
DEALLOCATE Backups

-- Enrich data
UPDATE bmf SET DBFilesCount = d.NumOfFiles
FROM @RecentBackups AS bmf
INNER JOIN @DBDevices AS d
ON d.DeviceName = bmf.DeviceName
WHERE d.NumOfFiles > 0;

-- Output results
IF @ShowDetails = 0 AND EXISTS
  (SELECT NULL FROM @RecentBackups
   WHERE DBFilesCount > 0
   HAVING SUM(DBFilesCount) > 10 AND COUNT(DISTINCT PhysicalPath) <= 10)
BEGIN
 SELECT N'In server ' + @@SERVERNAME + N': Volume "' + bmf.DeviceName + N'" contains backup file "'
  + bmf.PhysicalPath + N'" and '
  + CONVERT(nvarchar(4000), bmf.DBFilesCount) + N' database file(s).'
 , bmf.DBFilesCount
 FROM @RecentBackups AS bmf
END
ELSE IF @ShowDetails = 1 OR (SELECT SUM(DBFilesCount) FROM @RecentBackups) <= 10
BEGIN
 SELECT DeviceName, bmf.PhysicalPath AS backup_file_path, mf.physical_name AS database_file_path
 , DB_NAME(mf.database_id) AS [database_name], mf.name AS [file_name]
 FROM @RecentBackups AS bmf
 INNER JOIN sys.master_files AS mf
 ON UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3))) = DeviceName
 WHERE [database_id] NOT IN (1,3,32767)
END
ELSE
BEGIN
 SELECT N'In server ' + @@SERVERNAME + N': Volume "' + DeviceName + N'" contains '
  + CONVERT(nvarchar(4000), COUNT(DISTINCT bmf.PhysicalPath)) + N' backup file(s) and '
  + CONVERT(nvarchar(4000), COUNT(DISTINCT mf.physical_name)) + N' database file(s).'
 , 1
 FROM @RecentBackups AS bmf
 INNER JOIN sys.master_files AS mf
 ON UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3))) = DeviceName
 WHERE [database_id] NOT IN (1,3,32767)
 GROUP BY DeviceName
END
