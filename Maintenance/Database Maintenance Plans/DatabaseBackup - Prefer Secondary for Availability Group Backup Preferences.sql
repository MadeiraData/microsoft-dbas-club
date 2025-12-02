/*
FULL Backup job commands for Availability Groups with Backup Preference of Secondary
====================================================================================
Crucial parameters:
@Databases = '...,-AVAILABILITY_GROUP_DATABASES' -- to backup non-AG databases
vs:
@Databases = 'AVAILABILITY_GROUP_DATABASES' -- to backup AG databases
, @CopyOnly = 'Y' -- crucial when doing FULL backups on SECONDARY
*/

-- step 1: non-AG databases

EXECUTE [dbo].[DatabaseBackup]
@Databases = 'USER_DATABASES,-AVAILABILITY_GROUP_DATABASES',
@Directory = N'\\backupsrv\sqlbackups',
@BackupType = 'FULL',
@Verify = 'Y',
@CleanupTime = 24,
@Checksum = 'Y',
@LogToTable = 'Y'

-- step 2: AG databases
EXECUTE [dbo].[DatabaseBackup]
@Databases = 'AVAILABILITY_GROUP_DATABASES',
@Directory = N'\\backupsrv\sqlbackups',
@BackupType = 'FULL',
@CopyOnly = 'Y', -- this is crucial when backup preference is on secondary
@Verify = 'Y',
@CleanupTime = 24,
@Checksum = 'Y',
@LogToTable = 'Y'