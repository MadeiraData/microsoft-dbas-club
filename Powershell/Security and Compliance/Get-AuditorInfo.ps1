import-module dbatools, importexcel;

Set-DbatoolsInsecureConnection -SessionOnly;

# This can take a very long time
<#
Scan types:
    Browser service
    SQL Services via WMI
    SPNs in Active Directory
    Probe TCP ports
    Connect directly to SQL Server
#>
Find-DbaInstance -ScanType SQLService -ComputerName FLEXO;

# I know I said we wouldn't talk about licensing...
Get-DbaComputerSystem -ComputerName Flexo | 
    Select-Object -Property ComputerName, NumberLogicalProcessors, TotalPhysicalMemory;

# Collect registered servers
Get-DbaRegisteredServer -SqlInstance flexo\sql19 -IncludeLocal -IncludeSelf | 
    Sort-Object Source | 
    Select-Object Name, ServerName, Source;

$AllInstances = Get-DbaRegisteredServer -SqlInstance flexo\sql19 -IncludeSelf | Select-Object -ExpandProperty ServerName;

# Collecting ErrorLog locations for your SIEM (security information and event management)
Get-DbaDefaultPath -SqlInstance $AllInstances | 
    Select-Object Computername, InstanceName, SqlInstance, ErrorLog;

# Check SQL Server patches
Update-DbaBuildReference;

Get-DbaBuild -SqlInstance $AllInstances |
    Select-Object SqlInstance, Build, NameLevel, SPLevel, CULevel, KBLevel, SupportedUntil |
    Sort-Object -Property SqlInstance;

Test-DbaBuild -SqlInstance $AllInstances -MaxBehind 1CU |
    Select-Object SqlInstance, Build, BuildTarget, NameLevel, SPLevel, SPTarget, CULevel, CUTarget, MaxBehind, Compliant, KBLevel, SupportedUntil |
    Sort-Object -Property SqlInstance;

# TLS connection encryption
<#
    New-SelfSignedCertificate -type SSLServerAuthentication -Subject "CN=$env:COMPUTERNAME" -FriendlyName "SQLServer TLS Connections"-DnsName "$env:computername",'localhost' -CertStoreLocation "Cert:\LocalMachine\My" -KeyLength 2048 -KeyAlgorithm RSA -hash 'SHA256'
#>
Get-DbaComputerCertificate $AllInstances;

# These have to be done in an elevated session because I'm looking at the local machine
Get-DbaNetworkCertificate $AllInstances;
Get-DbaForceNetworkEncryption $AllInstances |
    Sort-Object -Property SqlInstance;

# Database Inventory
Get-DbaDatabase -SqlInstance $AllInstances |
    Select-Object -Property SqlInstance, Name, Status, IsAccessible, Owner, SizeMB |
    Sort-Object SqlInstance, Name;

<#
New-DbaDbCertificate -SqlInstance $AllInstances -Name "TDE_2023_2024" -Database master -Subject "Certificate for database master keys for TDE" -StartDate (get-date) -ExpirationDate (get-date).AddYears(1)
#>
Get-DbaDbCertificate -Database master -SqlInstance $AllInstances |
    Where-Object { $PSItem.Name -notlike '##*' } |
    Select-Object -Property SqlInstance, Name, Subject, StartDate, ExpirationDate, LastBackupDate, PrivateKeyEncryptionType |
    Sort-Object -Property SqlInstance, Name;

Get-DbaDatabase -SqlInstance $AllInstances |
    Select-Object -Property SqlInstance, Name, EncryptionEnabled, `
        @{n = "EncryptionType"; e = { $_.DatabaseEncryptionKey.EncryptionType } }, `
        @{n = "EncryptionState"; e = { $_.DatabaseEncryptionKey.EncryptionState } }, `
        @{n = "EncryptionAlgorithm"; e = { $_.DatabaseEncryptionKey.EncryptionAlgorithm } }, `
        @{n = "EncryptorName"; e = { $_.DatabaseEncryptionKey.EncryptorName } } | 
    Sort-Object -Property SqlInstance, Name;

Get-DbaLogin -SqlInstance $AllInstances | 
    Select-Object SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled | 
    Sort-Object -Property SqlInstance, Name;
Get-DbaServerRole -SqlInstance $AllInstances | 
    Select-Object SqlInstance, Name, Owner, IsFixedRole | 
    Sort-Object -Property SqlInstance, Name;
Get-DbaServerRoleMember -SqlInstance $AllInstances | 
    Select-Object -Property SqlInstance, Role, Name | 
    Sort-Object -Property SqlInstance, Role, Name;

# Find-DbaLoginInGroup

$PSDefaultParameterValues.Add('Get-Dba*:SqlInstance', $AllInstances);

Get-DbaDbUser -ExcludeSystemUser | 
    Select-Object -Property SqlInstance, Database, Name, Login, LoginType, HasDbAccess, CreateDate, DateLastModified | 
    Sort-object -Property SqlInstance, Database, Name;
Get-DbaDbRole -ExcludeFixedRole | 
    Select-Object -Property SqlInstance, Database, Name | 
    Sort-Object -Property SqlInstance, Database, Name;
Get-DbaDbRoleMember | 
    Select-Object -Property SqlInstance, Database, Role, UserName | 
    Sort-Object -Property SqlInstance, Database, Role;

Get-DbaPermission -IncludeServerLevel | 
    Select-Object -Property SqlInstance, Database, Grantee, SecurableType, Securable, PermissionName, PermState -first 100| 
    Sort-Object -Property SqlInstance, Database, Grantee, SecurableType, Securable, PermissionName;


# When was the last backup?
Get-DbaLastBackup | 
    Select-Object -Property SqlInstance, Database, LastFullBackup, LastDiffBackup, LastLogBackup | 
    Sort-Object -Property SqlInstance, Database;

# Two ways to get backup history
# #1 - Get history from MSDB
# This could take a minute
Get-DbaDbBackupHistory | 
    Select-Object SqlInstance, Database, Type, Start, End -first 100 | 
    Sort-Object -Property SqlInstance, Database, Start;

# #2 - Get history from Ola's CommandLog table
Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAthings `
    -Query "select DatabaseName,CommandType,StartTime,EndTime,ErrorNumber,ErrorMessage from CommandLog where CommandType like 'BACKUP_%';" | 
    Sort-Object -Property ServerInstance, DatabaseName, StartTime;

# Last time we did a DBCC CHECKDB?
Get-DbaLastGoodCheckDb -ExcludeDatabase tempdb | 
    Select-Object -Property SqlInstance, Database, DatabaseCreated, LastGoodCheckDb, Status | 
    Sort-Object -Property SqlInstance, Database;

Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAthings `
    -Query "select DatabaseName,CommandType,StartTime,EndTime,ErrorNumber,ErrorMessage from CommandLog where CommandType = 'DBCC_CHECKDB';" | 
    Sort-Object -Property ServerInstance, DatabaseName, StartTime;

# Backup tests?
<#
Test-DbaLastBackup -SqlInstance flexo\sql17 -EnableException | Write-DbaDataTable -SqlInstance flexo\sql17 -Database DBAThings -Table BackupTestResults -Schema dbo -AutoCreateTable -UseDynamicStringLength -EnableException;
Test-DbaLastBackup -SqlInstance flexo\sql19 -EnableException | Write-DbaDataTable -SqlInstance flexo\sql19 -Database DBAThings -Table BackupTestResults -Schema dbo -AutoCreateTable -UseDynamicStringLength -EnableException;
Test-DbaLastBackup -SqlInstance flexo\sql22 -EnableException | Write-DbaDataTable -SqlInstance flexo\sql22 -Database DBAThings -Table BackupTestResults -Schema dbo -AutoCreateTable -UseDynamicStringLength -EnableException;
#>
Invoke-DbaQuery -SqlInstance $AllInstances -AppendServerInstance -Database DBAThings `
    -Query "select SourceServer,TestServer,[Database],FileExists,Size,RestoreResult,DbccResult,RestoreStart,RestoreEnd,DbccStart,DbccEnd,BackupDates,BackupFiles from BackupTestResults";

$PSDefaultParameterValues.Remove('Get-Dba*:SqlInstance');