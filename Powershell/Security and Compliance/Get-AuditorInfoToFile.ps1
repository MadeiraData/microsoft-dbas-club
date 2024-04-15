import-module dbatools, importexcel, burnttoast;

$AllInstances = Get-DbaRegisteredServer -SqlInstance flexo\sql19 -IncludeSelf | Select-Object -ExpandProperty ServerName;

# Collecting ErrorLog locations for your SIEM (security information and event management)
Write-Information -MessageData "Getting ErrorLog paths";
$ErrorLogPaths = Get-DbaDefaultPath -SqlInstance $AllInstances | Select-Object Computername, InstanceName, SqlInstance, ErrorLog;

# Check SQL Server patches
#Update-DbaBuildReference;
Write-Information -MessageData "Checking patch levels";
$CurrentPatchLevels = Test-DbaBuild -SqlInstance $AllInstances -MaxBehind 1CU | Select-Object SqlInstance, Build, BuildTarget, NameLevel, SPLevel, SPTarget, CULevel, CUTarget, MaxBehind, Compliant, KBLevel, SupportedUntil;

# Database Inventory
Write-Information -MessageData "Database Inventory";
$DatabaseInventory = Get-DbaDatabase -SqlInstance $AllInstances | Select-Object -Property SqlInstance, Name, Status, IsAccessible, Owner, SizeMB | Sort-Object SqlInstance, Name;

# Database Encryption
Write-Information -MessageData "Master DB Certs";
$MasterDBCerts = Get-DbaDbCertificate -Database master -SqlInstance $AllInstances | Where-Object { $PSItem.Name -notlike '##*' } | Select-Object -Property SqlInstance, Name, Subject, StartDate, ExpirationDate, LastBackupDate, PrivateKeyEncryptionType | Sort-Object -Property SqlInstance, Name;
Write-Information -MessageData "Database Encryption";
$DatabaseEncryption = Get-DbaDatabase -SqlInstance $AllInstances |
Select-Object -Property SqlInstance, Name, EncryptionEnabled, `
@{n = "EncryptionType"; e = { $_.DatabaseEncryptionKey.EncryptionType } }, `
@{n = "EncryptionState"; e = { $_.DatabaseEncryptionKey.EncryptionState } }, `
@{n = "EncryptionAlgorithm"; e = { $_.DatabaseEncryptionKey.EncryptionAlgorithm } }, `
@{n = "EncryptorName"; e = { $_.DatabaseEncryptionKey.EncryptorName } } | Sort-Object -Property SqlInstance, Name;

Write-Information -MessageData "Instance level security";
$InstanceLogins = Get-DbaLogin -SqlInstance $AllInstances | Select-Object -Property SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled | Sort-Object -Property SqlInstance, Name;
$ServerRoles = Get-DbaServerRole -SqlInstance $AllInstances | Select-Object -Property SqlInstance, Name, Owner, IsFixedRole | Sort-Object -Property SqlInstance, Name;
$ServerRoleMembers = Get-DbaServerRoleMember -SqlInstance $AllInstances | Select-Object -Property SqlInstance, Role, Name | Sort-Object -Property SqlInstance, Role, Name;

$PSDefaultParameterValues.Add('Get-Dba*:SqlInstance', $AllInstances);
$PSDefaultParameterValues.Add('Select-Object:ExcludeProperty', @("RowError", "RowState", "Table", "ItemArray", "HasErrors"));

Write-Information -MessageData "Database level security";
$DatabaseUsers = Get-DbaDbUser -ExcludeSystemUser | Select-Object -Property SqlInstance, Database, Name, Login, LoginType, HasDbAccess, CreateDate, DateLastModified | Sort-object -Property SqlInstance, Database, Name;
$DatabaseRoles = Get-DbaDbRole -ExcludeFixedRole | Select-Object -Property SqlInstance, Database, Name | Sort-Object -Property SqlInstance, Database, Name;
$DatabaseRoleMembers = Get-DbaDbRoleMember | Select-Object -Property SqlInstance, Database, Role, UserName | Sort-Object -Property SqlInstance, Database, Role;

Write-Information -MessageData "All Permissions";
$AllPermissions = Get-DbaPermission -IncludeServerLevel | Select-Object -Property SqlInstance, Database, Grantee, SecurableType, Securable, PermissionName, PermState | Sort-Object -Property SqlInstance, Database, Grantee, SecurableType, Securable, PermissionName;

# Backups
Write-Information -MessageData "Last backup"
$LastBackup = Get-DbaLastBackup | Select-Object -Property SqlInstance, Database, LastFullBackup, LastDiffBackup, LastLogBackup | Sort-Object -Property SqlInstance, Database;

# Two ways to get backup history
# #1 - Get history from MSDB
Write-Information -MessageData "Backup history 1";
$MSDBBackupHistory = Get-DbaDbBackupHistory | Select-Object SqlInstance, Database, Type, Start, End | Sort-Object -Property SqlInstance, Database, Start;

# #2 - Get history from Ola's CommandLog table
Write-Information -MessageData "Backup history 2";
$BackupJobHistory = Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAthings -Query "select DatabaseName,CommandType,StartTime,EndTime,ErrorNumber,ErrorMessage from CommandLog where CommandType like 'BACKUP_%';" | Sort-Object -Property ServerInstance, DatabaseName, StartTime | Select-Object -Property *;

# Last time we did a DBCC CHECKDB?
Write-Information -MessageData "Last checkdb";
$LastGoodCheckDB = Get-DbaLastGoodCheckDb -ExcludeDatabase tempdb | Select-Object -Property SqlInstance, Database, DatabaseCreated, LastGoodCheckDb, Status | Sort-Object -Property SqlInstance, Database;

# All the DBCC CHECKDBs?
Write-Information -MessageData "All checkdbs"
$AllCheckDBs = Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAthings -Query "select DatabaseName,CommandType,StartTime,EndTime,ErrorNumber,ErrorMessage from CommandLog where CommandType = 'DBCC_CHECKDB';" | Select-Object -Property *;

# Backup tests?
Write-Information -MessageData "Database restore tests";
$BackupRestoreTests = Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAThings -Query "select SourceServer,TestServer,[Database],FileExists,Size,RestoreResult,DbccResult,RestoreStart,RestoreEnd,DbccStart,DbccEnd,BackupDates,BackupFiles from BackupTestResults" | Select-Object -Property *;

Write-Information -MessageData "Export results";
$ReportFileName = "c:\temp\AuditInfo $((get-date).ToString("yyyy-MM-dd HHmmss")).xlsx";
$PSDefaultParameterValues.Add('Export-Excel:Path', $ReportFileName);
$PSDefaultParameterValues.Add('Export-Excel:AutoSize', $true);
$PSDefaultParameterValues.Add('Export-Excel:AutoFilter', $true);
$PSDefaultParameterValues.Add('Export-Excel:FreezeTopRow', $true);

$AllInstances | Export-Excel -WorksheetName "MSSQL Instances";
$ErrorLogPaths | Export-Excel -WorksheetName "ErrorLog Paths";
$CurrentPatchLevels | Export-Excel -WorksheetName "MSSQL Updates";
$MasterDBCerts | Export-Excel -WorksheetName "Master DB Certificates";
$DatabaseInventory | Export-Excel -WorksheetName "Database Inventory";
$DatabaseEncryption | Export-Excel -WorksheetName "Database Encryption";
$InstanceLogins | Export-Excel -WorksheetName "Instance Logins";
$ServerRoles | Export-Excel -WorksheetName "Instance Roles";
$ServerRoleMembers | Export-Excel -WorksheetName "Instance Rolemembers";
$DatabaseUsers | Export-Excel -WorksheetName "Database Users"
$DatabaseRoles  | Export-Excel -WorksheetName "Database Roles"
$DatabaseRoleMembers | Export-Excel -WorksheetName "Database Rolemembers";
$AllPermissions | Export-Excel -WorksheetName "All Permissions";
$LastBackup | Export-Excel -WorksheetName "Latest Backups";
$MSDBBackupHistory | Export-Excel -WorksheetName "Backup History 1";
$BackupJobHistory | Export-Excel -WorksheetName "Backup History 2";
$LastGoodCheckDB | Export-Excel -WorksheetName "Last Good CheckDB";
$AllCheckDBs | Export-Excel -WorksheetName "CheckDB Job History";
$BackupRestoreTests | Export-Excel -WorksheetName "Backup Restore Tests";
Invoke-Item -Path $ReportFileName;
New-BurntToastNotification `
    -Text "Hello, SQL Saturday Boston!", "Audit export is complete" `
    -ExpirationTime (get-date).AddMinutes(10) `
    -AppLogo "c:\users\andy\onedrive\Social media profile pic 2023.jpeg";

$PSDefaultParameterValues.Remove('Get-Dba*:SqlInstance');
$PSDefaultParameterValues.Remove('Export-Excel:Path');
$PSDefaultParameterValues.Remove('Export-Excel:AutoSize');
$PSDefaultParameterValues.Remove('Export-Excel:AutoFilter');
$PSDefaultParameterValues.Remove('Export-Excel:FreezeTopRow');
$PSDefaultParameterValues.Remove('Select-Object:ExcludeProperty');