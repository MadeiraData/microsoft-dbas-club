/*
Author: Eitan Blumin (t: @EitanBlumin | b: eitanblumin.com)
Date: 2025-05-18
Description:
This is a condensed SQL Server Checkup of most common and impactful best practices related to Security & Compliance.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 30;

DECLARE @Alerts AS table
(
	Category nvarchar(1000),
	SubCategory nvarchar(MAX),
	ObjectName nvarchar(MAX),
	Details nvarchar(MAX)
);


SELECT SERVERPROPERTY('ProductLevel') as SP_installed, SERVERPROPERTY('ProductVersion') as Version, SERVERPROPERTY('IsIntegratedSecurityOnly') as [login_mode];
/*
First column returns the installed Service Pack level, the second is the exact build number.
Remediation:
Identify the current version and patch level of your SQL Server instances and ensure they
contain the latest security fixes. Make sure to test these fixes in your test environments
before updating production instances.
The most recent SQL Server patches can be found here:
• Hotfixes and Cumulative updates: http://blogs.msdn.com/b/sqlreleaseservices/
• Service Packs: https://support.microsoft.com/en-us/kb/2958069
Default Value:
Service packs and patches are not installed by default.
References:
1. https://support.microsoft.com/en-us/kb/2958069
CIS Controls:
4 Continuous Vulnerability Assessment and Remediation
*/


IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 5
BEGIN
	PRINT 'Checking: Database Backup';

	INSERT INTO @Alerts
	SELECT 'Database Backup', 'Database has never been backed up', QUOTENAME(name), 'It''s recommended to have a backup plan for all databases, including user databases as well as the system databases MSDB and Master.'
	FROM sys.databases AS db
	WHERE database_id NOT IN (2,32767)
	AND state_desc = 'ONLINE'
	AND name NOT IN ('ReportServerTempDB', 'model')
	AND NOT EXISTS (SELECT NULL FROM msdb..backupset WHERE database_name = db.name)
END


DECLARE @RecentBackups AS TABLE (PhysicalPath NVARCHAR(4000), DeviceName NVARCHAR(4000))
DECLARE @CurrFile NVARCHAR(4000), @Exists INT;
 
PRINT 'Checking: Backups and database files in the same physical volume';
INSERT INTO @RecentBackups
SELECT DISTINCT physical_device_name, UPPER(SUBSTRING(physical_device_name, 0, CHARINDEX('\', physical_device_name, 3)))
FROM msdb.dbo.backupmediafamily AS bmf
INNER JOIN msdb.dbo.backupset AS bs
ON bmf.media_set_id = bs.media_set_id
WHERE bs.backup_start_date > DATEADD(dd, -@DaysBackToCheck, GETDATE())
AND physical_device_name IS NOT NULL
 
DECLARE Backups CURSOR LOCAL FAST_FORWARD FOR
SELECT PhysicalPath
FROM @RecentBackups
 
OPEN Backups
FETCH NEXT FROM Backups INTO @CurrFile
 
WHILE @@FETCH_STATUS = 0
BEGIN
	SET @Exists = 1;
	EXEC master.dbo.xp_fileexist @CurrFile, @Exists out;
 
	IF @Exists = 0
		DELETE FROM @RecentBackups WHERE PhysicalPath = @CurrFile;
 
	FETCH NEXT FROM Backups INTO @CurrFile
END
 
CLOSE Backups
DEALLOCATE Backups
 
INSERT INTO @Alerts
SELECT 'Database Backup', N'Backups and database files in the same physical volume'
, DeviceName
, N'The volumn Contains ' + CONVERT(nvarchar(4000), COUNT(DISTINCT bmf.PhysicalPath)) + N' backup file(s) and ' + CONVERT(nvarchar(4000), COUNT(DISTINCT mf.physical_name)) + N' database file(s).'
FROM @RecentBackups AS bmf
INNER JOIN sys.master_files AS mf
ON UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3))) COLLATE database_default = DeviceName
WHERE ([database_id] > 3 OR [database_id] = 2) AND [database_id] <> 32767
GROUP BY DeviceName

IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 5
BEGIN
	PRINT 'Checking: Database File(s) on Volume C';
	INSERT INTO @Alerts
	SELECT 'General', N'Database File(s) on Volume C'
	, 'Database ' + DB_NAME([database_id]) + N': ' + physical_name
	, 'Placing database files on the system volume puts the Operating System in danger when these files grow too much'
	FROM sys.master_files AS mf
	WHERE ([database_id] > 3 OR [database_id] = 2) AND [database_id] <> 32767
	AND UPPER(SUBSTRING(physical_name, 0, CHARINDEX('\', physical_name, 3))) = 'C:'
END

 
PRINT 'Checking: Failed Login Auditing';
DECLARE @AuditLevel INT
EXEC   xp_instance_regread
@rootkey    = 'HKEY_LOCAL_MACHINE',
@key        = 'Software\Microsoft\MSSQLServer\MSSQLServer',
@value_name = 'AuditLevel',
@value      = @AuditLevel OUTPUT
 
 
PRINT 'Checking: SQL Default Port Using system registry (dynamic port)';
DECLARE @portNo NVARCHAR(10)
EXEC   xp_instance_regread
@rootkey    = 'HKEY_LOCAL_MACHINE',
@key        =
'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
@value_name = 'TcpDynamicPorts',
@value      = @portNo OUTPUT
 
-- Using system registry (static port):
 
IF @portNo IS NULL
BEGIN
	PRINT 'Checking: SQL Default Port Using system registry (static port)';
	EXEC   xp_instance_regread
	@rootkey    = 'HKEY_LOCAL_MACHINE',
	@key        =
	'Software\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IpAll',
	@value_name = 'TcpPort',
	@value      = @portNo OUTPUT
END


PRINT 'Checking: HideInstance setting'
DECLARE @getValue INT;
EXEC master..xp_instance_regread
@rootkey = N'HKEY_LOCAL_MACHINE',
@key = N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib',
@value_name = N'HideInstance',
@value = @getValue OUTPUT;

INSERT INTO @Alerts
SELECT 'Security', N'HideInstance setting'
, @@SERVERNAME, N'HideInstance server setting should be enabled'
WHERE @getValue = 0

/*
Remediation:
Perform either the GUI or T-SQL method shown:
GUI Method
1. In SQL Server Configuration Manager, expand SQL Server Network
Configuration, right-click Protocols for <server instance>, and then select
Properties.
2. On the Flags tab, in the Hide Instance box, select Yes, and then click OK to close the
dialog box. The change takes effect immediately for new connections.
T-SQL Method
Execute the following T-SQL to remediate:
EXEC master..xp_instance_regwrite
@rootkey = N'HKEY_LOCAL_MACHINE',
@key = N'SOFTWARE\Microsoft\Microsoft SQL
Server\MSSQLServer\SuperSocketNetLib',
@value_name = N'HideInstance',
@type = N'REG_DWORD',
@value = 1;
Impact:
This method only prevents the instance from being listed on the network. If the instance is
hidden (not exposed by SQL Browser), then connections will need to specify the server and
port in order to connect. It does not prevent users from connecting to server if they know
the instance name and port.
If you hide a clustered named instance, the cluster service may not be able to connect to the
SQL Server. Please refer to the Microsoft documentation reference.
Default Value:
By default, SQL Server instances are not hidden.
References:
1. http://msdn.microsoft.com/en-us/library/ms179327(v=sql.120).aspx
CIS Controls:
9 Limitation and Control of Network Ports, Protocols, and Services
*/

PRINT 'Checking: Linked Server Security Vulnerability'
INSERT INTO @Alerts
SELECT 'Security', N'Linked Server Security Vulnerability'
, QUOTENAME(a.name), N'No login mapping configured (anyone can access it)'
FROM sys.servers a
INNER JOIN sys.linked_logins b ON b.server_id = a.server_id
WHERE b.local_principal_id = 0 -- default security context
AND uses_self_credential = 0 -- not use own credentials
AND a.server_id <> 0 -- not local
AND (a.is_data_access_enabled = 1 or a.is_distributor = 0);


PRINT 'Checking: Not recommended instance security configuration'
INSERT INTO @Alerts
SELECT 'Security', N'Not recommended instance security configuration', ObjectName, Report
FROM
(
SELECT N'TCPIP Port', N'SQL Sever port should not be the default 1433' WHERE @portNo = '1433'
UNION ALL SELECT N'Failed Logins Auditing', N'Failed Logins should be audited' WHERE @AuditLevel NOT IN (2,3)
UNION ALL SELECT N'SA login', N'SA server login should be renamed and/or disabled' FROM sys.server_principals WHERE sid = 0x01 AND name = 'sa' AND is_disabled = 0
) AS v(ObjectName, Report)
 
UNION ALL
 
SELECT 'Security', 'Not recommended instance security configuration',  R.setting
, R.errormsg
+ N' (current value: ' + CONVERT(nvarchar, c.[value]) + N', recommended value: ' + CONVERT(nvarchar,R.recommendedvalue) + ')'
FROM sys.configurations AS c
CROSS APPLY
(
SELECT 'clr enabled', 0, 'CLR Integration recommended to be disabled'
UNION ALL SELECT 'xp_cmdshell', 0, 'XP_CMDSHELL recommended to be disabled'
UNION ALL SELECT 'Ole Automation Procedures', 0, 'Ole Automation Procedures setting is not the recommended value' WHERE SERVERPROPERTY('IsClustered') = 0
UNION ALL SELECT 'remote admin connections', 1, 'Remote DAC listener should be enabled'
UNION ALL SELECT 'Ad Hoc Distributed Queries', 0, 'Ad Hoc Distributed Queries should be disabled'
UNION ALL SELECT 'cross db ownership chaining', 0, 'cross db ownership chaining should be disabled'
UNION ALL SELECT 'Database Mail XPs', 0, 'unless DBMail is explicitly required, Database Mail XPs should be disabled'
UNION ALL SELECT 'scan for startup procs', 0, 'scan for startup procs should be disabled'
UNION ALL SELECT 'default trace enabled', 1, 'default server trace should be enabled'
) AS R (setting, recommendedvalue, errormsg)
WHERE c.name = R.setting
AND CONVERT(int, c.[value]) <> R.recommendedvalue


PRINT 'Checking: Invalid database owner';
INSERT INTO @Alerts
SELECT 'General', 'Invalid database owner', QUOTENAME(db.name)
, 'Login may have been deleted, or the database was copied from another server. Please set a new valid owner for the database.'
FROM sys.databases db
LEFT JOIN sys.server_principals sp
ON db.owner_sid = sp.sid
WHERE sp.sid IS NULL
AND db.state = 0

PRINT 'Checking: Database Auto Close';
INSERT INTO @Alerts
SELECT 'General', 'Database Auto Close is ON', name, 'Strongly recommended to set Database Auto Close to OFF'
FROM sys.databases
WHERE state_desc = 'ONLINE'
AND is_auto_close_on = 1
AND containment <> 0


PRINT 'Checking: Orphaned User(s)';
SET NOCOUNT ON;
DECLARE @db SYSNAME, @user NVARCHAR(MAX);
INSERT INTO @Alerts
exec sp_MSforeachdb '
IF EXISTS (SELECT * FROM sys.databases WHERE state_desc = ''ONLINE'' AND name = ''?'')
SELECT ''Security'', ''Orphaned User(s) in [?]'', dp.name
, CASE WHEN dp.name IN (SELECT name COLLATE database_default FROM sys.server_principals) THEN ''Login with same name already exists'' ELSE ''Login with same name was not found'' END
FROM [?].sys.database_principals AS dp 
LEFT JOIN sys.server_principals AS sp ON dp.SID = sp.SID 
WHERE sp.SID IS NULL 
AND authentication_type_desc = ''INSTANCE''
;'


PRINT 'Checking: DB Page Verification';
INSERT INTO @Alerts
SELECT 'General', 'DB Page Verification different from CHECKSUM', QUOTENAME(name), 'Current setting: ' + page_verify_option_desc
FROM sys.databases
where name NOT IN ('model','tempdb')
AND state = 0
AND page_verify_option_desc <> 'CHECKSUM'


PRINT 'Checking: Trustworthy setting'
INSERT INTO @Alerts
SELECT 'Security', 'Database Trustworthy setting is enabled', QUOTENAME(name), 'Ensure Trustworthy Database Property is disabled'
FROM sys.databases
WHERE is_trustworthy_on = 1
AND name != 'msdb';


PRINT 'Checking: High Number of Failed Login Attempts';
DECLARE @log AS TABLE
  (
   logdate DATETIME,
   info    VARCHAR (25) ,
   data    VARCHAR (200)
  );
 
INSERT INTO @log
EXECUTE sp_readerrorlog 0, 1, 'Login failed';
 
IF (SELECT count(*) AS occurences
	FROM   @log
	WHERE  logdate > dateadd(minute, -@MinutesBackToCheck, getdate())
	) >= 10
BEGIN	
	INSERT INTO @Alerts
	SELECT 'Security', N'High Number of Failed Login Attempts', CONVERT(nvarchar(25), logdate, 121), data
	FROM   @log
	WHERE  logdate > dateadd(minute, -@MinutesBackToCheck, getdate())
END



/*
3.9 Ensure Windows BUILTIN groups are not SQL Logins (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Prior to SQL Server 2008, the BUILTIN\Administrators group was added a SQL Server
login with sysadmin privileges during installation by default. Best practices promote
creating an Active Directory level group containing approved DBA staff accounts and using
this controlled AD group as the login with sysadmin privileges. The AD group should be
specified during SQL Server installation and the BUILTIN\Administrators group would
therefore have no need to be a login.
Rationale:
The BUILTIN groups (Administrators, Everyone, Authenticated Users, Guests, etc) generally
contain very broad memberships which would not meet the best practice of ensuring only
the necessary users have been granted access to a SQL Server instance. These groups
should not be used for any level of access into a SQL Server Database Engine instance.
Audit:
Use the following syntax to determine if any BUILTIN groups or accounts have been added
as SQL Server Logins.
*/

INSERT INTO @Alerts
SELECT 'Security', N'Windows BUILTIN groups', pr.[name], 'Windows BUILTIN group ' + QUOTENAME(pr.[name]) COLLATE DATABASE_DEFAULT + N' has permission ' + pe.[permission_name]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name like 'BUILTIN%'
AND pe.[state_desc] = 'GRANT';

/*
This query should not return any rows.
Remediation:
1. For each BUILTIN login, if needed create a more restrictive AD group containing only
the required user accounts.
2. Add the AD group or individual Windows accounts as a SQL Server login and grant it
the permissions required.
3. Drop the BUILTIN login using the syntax below after replacing <name> in
[BUILTIN\<name>].
USE [master]
GO
DROP LOGIN [BUILTIN\<name>]
GO
Impact:
Before dropping the BUILTIN group logins, ensure that alternative AD Groups or Windows
logins have been added with equivalent permissions. Otherwise, the SQL Server instance
may become totally inaccessible.
Default Value:
By default, no BUILTIN groups are added as SQL logins.
CIS Controls:
14.4 Protect Information with Access Control Lists
All information stored on systems shall be protected with file system, network share,
claims, application, or database specific access control lists. These controls will enforce the
principle that only authorized individuals should have access to the information based on
their need to access the information as a part of their responsibilities.
*/



/*

3.10 Ensure Windows local groups are not SQL Logins (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Local Windows groups should not be used as logins for SQL Server instances.
Rationale:
Allowing local Windows groups as SQL Logins provides a loophole whereby anyone with
OS level administrator rights (and no SQL Server rights) could add users to the local
Windows groups and thereby give themselves or others access to the SQL Server instance.
Audit:
Use the following syntax to determine if any local groups have been added as SQL Server
Logins.
*/

INSERT INTO @Alerts
SELECT 'Security', N'Windows local groups', pr.[name], 'Windows local group ' + QUOTENAME(pr.[name]) COLLATE DATABASE_DEFAULT + N' has permission ' + pe.[permission_name]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.[principal_id] = pe.[grantee_principal_id]
WHERE pr.[type_desc] = 'WINDOWS_GROUP'
AND pr.[name] like CAST(SERVERPROPERTY('MachineName') AS sysname) + '%';

/*
This query should not return any rows.
Remediation:
1. For each LocalGroupName login, if needed create an equivalent AD group containing
only the required user accounts.
2. Add the AD group or individual Windows accounts as a SQL Server login and grant it
the permissions required.
3. Drop the LocalGroupName login using the syntax below after replacing <name>.
USE [master]
GO
DROP LOGIN [<name>]
GO

Impact:
Before dropping the local group logins, ensure that alternative AD Groups or Windows
logins have been added with equivalent permissions. Otherwise, the SQL Server instance
may become totally inaccessible.
Default Value:
By default, no local groups are added as SQL logins.
CIS Controls:
14.4 Protect Information with Access Control Lists
All information stored on systems shall be protected with file system, network share,
claims, application, or database specific access control lists. These controls will enforce the
principle that only authorized individuals should have access to the information based on
their need to access the information as a part of their responsibilities.

*/





/*
3.11 Ensure the public role in the msdb database is not granted access
to SQL Agent proxies (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
The public database role contains every user in the msdb database. SQL Agent proxies
define a security context in which a job step can run.
Rationale:
Granting access to SQL Agent proxies for the public role would allow all users to utilize the
proxy which may have high privileges. This would likely break the principle of least
privileges.
Audit:
Use the following syntax to determine if access to any proxies have been granted to the
msdb database's public role.
*/


INSERT INTO @Alerts
SELECT 'Security', N'Public role with access to SQL Agent Proxies', sp.name, 'The [public] database role has been granted access to SQL Agent proxies'
FROM msdb..sysproxylogin spl
JOIN sys.database_principals dp
ON dp.sid = spl.sid
JOIN msdb..sysproxies sp
ON sp.proxy_id = spl.proxy_id
WHERE principal_id = USER_ID('public');


/*
This query should not return any rows.
Remediation:
1. Ensure the required security principals are explicitly granted access to the proxy
(use sp_grant_login_to_proxy).
2. Revoke access to the <proxyname> from the public role.
USE [msdb]
GO
EXEC dbo.sp_revoke_login_from_proxy @name = N'public', @proxy_name =
N'<proxyname>';
GO

Impact:
Before revoking the public role from the proxy, ensure that alternative logins or
appropriate user-defined database roles have been added with equivalent permissions.
Otherwise, SQL Agent job steps dependent upon this access will fail.
Default Value:
By default, the msdb public database role does not have access to any proxy.
References:
1. https://support.microsoft.com/en-us/help/2160741/best-practices-in-configuringsql-server-agent-proxy-account
CIS Controls:
14.4 Protect Information with Access Control Lists
All information stored on systems shall be protected with file system, network share,
claims, application, or database specific access control lists. These controls will enforce the
principle that only authorized individuals should have access to the information based on
their need to access the information as a part of their responsibilities.

*/





/*
4.1 Ensure 'MUST_CHANGE' Option is set to 'ON' for All SQL
Authenticated Logins (Not Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Whenever this option is set to ON, SQL Server will prompt for an updated password the first
time the new or altered login is used.
Rationale:
Enforcing a password change after a reset or new login creation will prevent the account
administrators or anyone accessing the initial password from misuse of the SQL login
created without being noticed.
Audit:
1. Open SQL Server Management Studio.
2. Open Object Explorer and connect to the target instance.
3. Navigate to the Logins tab in Object Explorer and expand. Right click on the
desired login and select Properties.
4. Verify the User must change password at next login checkbox is checked.
Note: This audit procedure is only applicable immediately after the login has been created
or altered to force the password change. Once the password is changed, there is no way to
know specifically that this option was the forcing mechanism behind a password change.
Remediation:
Set the MUST_CHANGE option for SQL Authenticated logins when creating a login initially:
CREATE LOGIN <login_name> WITH PASSWORD = '<password_value>' MUST_CHANGE,
CHECK_EXPIRATION = ON, CHECK_POLICY = ON;
Set the MUST_CHANGE option for SQL Authenticated logins when resetting a password:
ALTER LOGIN <login_name> WITH PASSWORD = '<new_password_value>' MUST_CHANGE;
Impact:
CHECK_EXPIRATION and CHECK_POLICY options must both be ON. End users must have the
means (application) to change the password when forced.
Default Value:
ON when creating a new login via the SSMS GUI.
OFF when creating a new login using T-SQL CREATE LOGIN unless the MUST_CHANGE option is
explicitly included along with CHECK_EXPIRATION = ON.
References:
1. https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-login-transact-sql
2. https://docs.microsoft.com/en-us/sql/t-sql/statements/create-login-transact-sql
CIS Controls:
16 Account Monitoring and Control

*/


/*
4.2 Ensure 'CHECK_EXPIRATION' Option is set to 'ON' for All SQL
Authenticated Logins Within the Sysadmin Role (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Applies the same password expiration policy used in Windows to passwords used inside
SQL Server.
Rationale:
Ensuring SQL logins comply with the secure password policy applied by the Windows
Server Benchmark will ensure the passwords for SQL logins with sysadmin privileges are
changed on a frequent basis to help prevent compromise via a brute force attack. CONTROL
SERVER is an equivalent permission to sysadmin and logins with that permission should
also be required to have expiring passwords.
Audit:
Run the following T-SQL statement to find sysadmin logins with CHECK_EXPIRATION OFF. No
rows should be returned.
*/


INSERT INTO @Alerts
SELECT 'Security', N'sysadmin membership', l.[name], 'CHECK_EXPIRATION  Option should be set to ON  for All SQL Authenticated Logins Within the Sysadmin Role'
FROM sys.sql_logins AS l
WHERE IS_SRVROLEMEMBER('sysadmin',name) = 1
AND l.is_expiration_checked <> 1

UNION ALL

SELECT 'Security', N'sysadmin membership', l.[name], 'CHECK_EXPIRATION  Option should be set to ON  for All SQL Authenticated Logins With the CONTROL SERVER permission'
FROM sys.sql_logins AS l
JOIN sys.server_permissions AS p
ON l.principal_id = p.grantee_principal_id
WHERE p.type = 'CL' AND p.state IN ('G', 'W')
AND l.is_expiration_checked <> 1;

/*
Remediation:
For each <login_name> found by the Audit Procedure, execute the following T-SQL
statement:
ALTER LOGIN [<login_name>] WITH CHECK_EXPIRATION = ON;
Impact:
This is a mitigating recommendation for systems which cannot follow the recommendation
to use only Windows Authenticated logins.
Regarding limiting this rule to only logins with sysadmin and CONTROL SERVER privileges,
there are too many cases of applications that run with less than sysadmin level privileges
that have hard-coded passwords or effectively hard-coded passwords (whatever is set the
first time is nearly impossible to change). There are several lines of business applications
that are considered best of breed which has this failing.
Also, keep in mind that the password policy is taken from the computer's local policy,
which will take from the Default Domain Policy setting. Many organizations have a different
password policy with regards to service accounts. These are handled in AD by setting the
account's password not to expire and having some other process track when they need to
be changed. With this second control in place, this is perfectly acceptable from an audit
perspective. If you treat a SQL Server login as a service account, then you have to do the
same. This ensures that the password change happens during a communicated downtime
window and not arbitrarily.
Default Value:
CHECK_EXPIRATION is ON by default when using SSMS to create a SQL authenticated login.
CHECK_EXPIRATION is OFF by default when using T-SQL CREATE LOGIN syntax without
specifying the CHECK_EXPIRATION option.
References:
1. http://msdn.microsoft.com/en-us/library/ms161959(v=sql.120).aspx
CIS Controls:
16.2 All Accounts Have a Monitored Expiration Date
Ensure that all accounts have an expiration date that is monitored and enforced.
*/



SELECT '4.3 Ensure ''CHECK_POLICY'' Option is set to ''ON'' for All SQL Authenticated Logins (Scored) '
SELECT '****************************************************************************************************************'

/*
4.3 Ensure 'CHECK_POLICY' Option is set to 'ON' for All SQL
Authenticated Logins (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Applies the same password complexity policy used in Windows to passwords used inside
SQL Server.
Rationale:
Ensure SQL authenticated login passwords comply with the secure password policy applied
by the Windows Server Benchmark so that they cannot be easily compromised via brute
force attack.
Audit:
Use the following code snippet to determine the status of SQL Logins and if their password
complexity is enforced.
*/

INSERT INTO @Alerts
SELECT 'Security', N'CHECK_POLICY option', [name], 'CHECK_POLICY option should be set to "ON" for all SQL Authenticated logins'
FROM sys.sql_logins
WHERE is_policy_checked = 0;

/*
The is_policy_checked value of 0 indicates that the CHECK_POLICY option is OFF; value of 1
is ON. If is_disabled value is 1, then the login is disabled and unusable. If no rows are
returned then either no SQL Authenticated logins exist or they all have CHECK_POLICY ON.
Remediation:
For each <login_name> found by the Audit Procedure, execute the following T-SQL
statement:
ALTER LOGIN [<login_name>] WITH CHECK_POLICY = ON;
Impact:
This is a mitigating recommendation for systems which cannot follow the recommendation
to use only Windows Authenticated logins.
Weak passwords can lead to compromised systems. SQL Server authenticated logins will
utilize the password policy set in the computer's local policy, which is typically set by the
Default Domain Policy setting.
The setting is only enforced when the password is changed. This setting does not force
existing weak passwords to be changed.
Default Value:
CHECK_POLICY is ON
References:
1. http://msdn.microsoft.com/en-us/library/ms161959(v=sql.120).aspx
CIS Controls:
16 Account Monitoring and Control
*/



/*
5 Auditing and Logging
This section contains recommendations related to SQL Server's audit and logging
mechanisms.
5.1 Ensure 'Maximum number of error log files' is set to greater than or
equal to '12' (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
SQL Server error log files must be protected from loss. The log files must be backed up
before they are overwritten. Retaining more error logs helps prevent loss from frequent
recycling before backups can occur.
Rationale:
The SQL Server error log contains important information about major server events and
login attempt information as well.
Audit:
Perform either the GUI or T-SQL method shown:
GUI Method
1. Open SQL Server Management Studio.
2. Open Object Explorer and connect to the target instance.
3. Navigate to the Management tab in Object Explorer and expand. Right click on the
SQL Server Logs file and select Configure.
4. Verify the Limit the number of error log files before they are recycled checkbox
is checked
5. Verify the Maximum number of error log files is greater than or equal to 12

T-SQL Method
Run the following T-SQL. The NumberOfLogFiles returned should be greater than or equal
to 12.
*/

DECLARE @NumErrorLogs int;
EXEC master.sys.xp_instance_regread
N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'NumErrorLogs',
@NumErrorLogs OUTPUT;

INSERT INTO @Alerts
SELECT 'General', N'Number of SQL Server Error Logs', CONVERT(nvarchar(4000), ISNULL(@NumErrorLogs, -1)), 'Ensure ''Maximum number of error log files'' is set to greater than or equal to ''12'''
WHERE ISNULL(@NumErrorLogs, -1) < 12;

/*
Remediation:
Adjust the number of logs to prevent data loss. The default value of 6 may be insufficient for
a production environment. Perform either the GUI or T-SQL method shown:
GUI Method
1. Open SQL Server Management Studio.
2. Open Object Explorer and connect to the target instance.
3. Navigate to the Management tab in Object Explorer and expand. Right click on the
SQL Server Logs file and select Configure
4. Check the Limit the number of error log files before they are recycled
5. Set the Maximum number of error log files to greater than or equal to 12
T-SQL Method
Run the following T-SQL to change the number of error log files, replace <NumberAbove12>
with your desired number of error log files:
EXEC master.sys.xp_instance_regwrite
N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'NumErrorLogs',
REG_DWORD,
<NumberAbove12>;
Impact:
Once the max number of error logs is reached, the oldest error log file is deleted each time
SQL Server restarts or sp_cycle_errorlog is executed.
Default Value:
6 SQL Server error log files in addition to the current error log file are retained by defaul

References:
1. http://msdn.microsoft.com/en-us/library/ms177285(v=sql.120).aspx
CIS Controls:
6.3 Ensure Audit Logging Systems Are Not Subject to Loss (i.e. rotation/archive)
Ensure that all systems that store logs have adequate storage space for the logs generated
on a regular basis, so that log files will not fill up between log rotation intervals. The logs
must be archived and digitally signed on a periodic basis.*/





SELECT *
FROM @Alerts
ORDER BY 1, 2, 3