
/**************************************************************************************
Script Name		SQL 2012_14_16_17_19_22 security remediation script.sql
Author:			Dadid Itshak 


Purpose :		SQL Server 2012  Audit Repository  Reporting  and security 
				Deployment script for  SQL 2012-2022

			
Installation :	Run this script From Microsot SQL Server Management Studio in SQLCMD Mode    
				as server role sysadmin in SQL Server . 
				Change Audit Path according to your env .
				
				The size of Audit data files path = MAXSIZE * MAX_ROLLOVER_FILES in  CREATE SERVER AUDIT [Security Audit] . In our case
				MAXSIZE = 100 MB
				MAX_ROLLOVER_FILES = 1000
				100M X1000=100G

				Give SQL server Database Engine Account  , SQL server Agent Account and DBA Group in AD full permission on Audit_data_files_path.
				Otherwise you will get the following error : 
				Msg 33201, Level 17, State 1, Line 150
				An error occurred in reading from the audit file or file-pattern: 'd:\sqldata\Audit\*'. The SQL service account may not have Read permission on the files, or the pattern may be returning one or more corrupt files.


Author:			David Itshak 
Email :			shaked19@gmail.com			
Date Created:	01/12/2015

Modification History:
Date          	Who              What

=============  ===============  ===================================================================
13/1/2015		David	itshak	Created Ver 1 
16 /2/2015		David	itshak  Updated Ver 2 
      
*/

-- Change this var by find and replace D:\sqldata\Audit with you audit data dir (example I:\sqldata\Audit)
:setvar Audit_data_files_path "T:\sqldata\Audit"

-- Do not show rowcounts in the results
SET NOCOUNT ON;



-- Check that user has the permission to run the script
use master
go

set nocount on
IF (IS_SRVROLEMEMBER(N'sysadmin') <>  1 )
    BEGIN			
			SELECT 1 
			RAISERROR(21089, 16, 1)
			RETURN 
	END
GO

/*
You will get the following error , if you are not member of sysadmin server role  :
Msg 21089, Level 16, State 1, Line 51
Only members of the sysadmin fixed server role can perform this operation.
*/



/*
SQL Server version
==================
There are many different ways to find the SQL Server version. Here are some of them:
*/

/*
select 'SQL Server version . Check that  is updated . '
SELECT @@VERSION
SELECT SERVERPROPERTY('ProductVersion') AS ProductVersion,
 SERVERPROPERTY('ProductLevel') AS ProductLevel
 */



DECLARE  @str NVARCHAR(200);
SELECT @str=''
+	CASE WHEN CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2012%SP1%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2012%SP2%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2012%SP3%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2014%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2014%SP1%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2014%SP2%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2016%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2017%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2019%'
	OR CONVERT(VARCHAR(200), @@VERSION) LIKE N'%2022%'
	THEN ''
ELSE 
	' Test 001 .  Failure ! INSTALL SQL 2017 with  SP1 or  higher  '
END
SELECT @@VERSION, @str ; 


 /* 
 The 'ProductLevel' property above will show Service Pack level as well (if it has been installed).
 */

 
/*
Set  SQL Server Audit level to Both failed and successful logins 
================================================================
*/


USE [master]
GO
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', REG_DWORD, 3
GO


/*
Check SQL Server Audit level
=============================
This will check to see what your current login audit level is set to capture.
*/



DECLARE @AuditLevel int
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', 
   N'Software\Microsoft\MSSQLServer\MSSQLServer', 
   N'AuditLevel', @AuditLevel OUTPUT
SELECT CASE WHEN @AuditLevel = 0 THEN 'None'
   WHEN @AuditLevel = 1 THEN 'Test 002 : Successful logins only- Failure '
   WHEN @AuditLevel = 2 THEN 'Test 002 : Failed logins only- Failure '
   WHEN @AuditLevel = 3 THEN 'Test 002 : Both failed and successful logins - OK ' 
   END AS [AuditLevel]


/*
Configure number of SQL Server logs 
===================================
This script will change the setting so that you stored 15 SQL Server error log archives.  This will allow us to have a good amount of history from our error logs.
*/

EXEC master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', 
       N'Software\Microsoft\MSSQLServer\MSSQLServer', 
       N'NumErrorLogs', REG_DWORD, 15




/*
Check if BUILTIN\Administrators group exists as login on SQL Server.
===================================================================

The BUILTIN\Administrators can easily be removed from SQL Server to prevent this security issue, but heed the warnings below prior to removing the group from SQL Server.
What steps should I take prior to considering removing this group?
1.	Verify that you know the "sa" password by logging into the SQL Server with the "sa" account with either Query Analyzer or Management Studio on the SQL Server you want to modify. 
2.	Validate other Windows groups or Windows logins are assigned SQL Server System Administrator rights on this SQL Server. 
3.	Review the rights assigned to the BUILTIN\Administrators group. 
4.	Research the members of the Windows Local Administrators group. 
5.	Figure out if an additional group should be created in Active Directory and assigned rights in SQL Server or if specific logins should be assigned rights to SQL Server. 
6.	If necessary, create the additional logins and groups in Active Directory and assign rights in SQL Server to ensure a minimum of 1 login and/or the "sa" login has SQL Server System Administrator rights. 
7.	Validate that the members of the BUILTIN\Administrators group do not own any databases, objects, Jobs, etc and that none of the logins are connected to SQL Server. 
8.	If any of these steps were not completed, repeat the needed steps.  If all of these steps have been followed and you are confident that removing the BUILTIN\Administrators group will not cause any issues proceed to the next set of directions.
*** NOTE *** - Do not remove the BUILTIN\Administrators group from SQL Server if other logins or groups do not have SQL Server System Administrator rights or if you do not know the "sa" password.
Remove the BUILTIN\Administrators group as follows : 
 
Method								Directions	   

T-SQL Commands						DROP LOGIN [BUILTIN\Administrators]	


This command will check to see if the builtin administrator account has been removed.
*/


IF EXISTS
(
	SELECT r.name  as SrvRole, u.name  as LoginName  
	FROM sys.server_role_members m JOIN
	  sys.server_principals r ON m.role_principal_id = r.principal_id  JOIN
	  sys.server_principals u ON m.member_principal_id = u.principal_id 
	WHERE u.name = 'BUILTIN\Administrators'
)
BEGIN
		select ' Test 003 : Failure :  BUILTIN\Administrators group exists as login on SQL Server. '
		select ' Members of the Local Administrators  group on SQL Server' 
		/*
		Find members of the "Local Administrators" group on SQL Server
		================================================================
		If for some reason you want to keep the BUILTIN\Administrators login you need to check who are the members of the "Local Administrators" group. 

		Note, that you will get results from the extended procedure below only if the BUILTIN\Administrators group exists as login on SQL Server.
		*/
		EXEC master.sys.xp_logininfo 'BUILTIN\Administrators','members'
		-- Remove BUILTIN\Administrators group 
		DROP LOGIN [BUILTIN\Administrators]	
		select ' Builtin\Administrators group was removed '
END
GO






/*
Find db_owner database role's members in each database
=======================================================
This will give you a list of database owners for each database.
*/

/*
select ''
select ' Find db_owner database role''s members in each database '
select '=========================================================='
EXEC master.sys.sp_MSforeachdb '
PRINT ''?''
SELECT  ''?''
SELECT  ''============================''
EXEC [?].dbo.sp_helprolemember ''db_owner'''
*/



/*
Find logins mapped to the "dbo" user in each database
=====================================================
This will find all users that are mapped to the dbo schema.
*/

/*
EXEC master.sys.sp_MSforeachdb '
PRINT ''?''
SELECT  ''?''
SELECT  ''============================''
EXEC [?].dbo.sp_helpuser ''dbo'''
*/



 /*
 Check that sample databases (AdventureWorks, Pubs etc.) are not present on Production SQL Servers 
 =================================================================================================
This will check to see if these sample databases are present on your server.
*/


IF EXISTS
(SELECT name FROM master.sys.databases 
 WHERE name IN ('pubs', 'Northwind') OR name LIKE 'AdventureWorks%'
 )
 BEGIN
	select  'Test 004 : Failure : Sample databases (AdventureWorks, Pubs etc.) are  present on Production SQL Servers. Drop them !  ';
 END
 

 
/*
xp_cmdshell
===========
An configurable option, xp_cmdshell, exists to allow you to execute command-line statements from
within the database engine. If your application needs to run command-line statements, then you can
enable xp_cmdshell by using the statement below.
EXEC sys.sp_configure 'xp_cmdshell' ,1 ;
GO;
RECONFIGURE;
Be careful! By default, the xp_cmdshell stored procedure is disabled during install and should
remain disabled if it is not required by the application. Think about it once a user gains access to your
system, he/s

The xp_cmdshell extended stored procedure allows access to the underlying operating
system from SQL code. You can issue shell commands, as shown in the following example:
exec xp_cmdshell 'DIR c\*.*';
It has the same security permissions as the SQL Server service account. So it is crucial to limit
access to this procedure, and to ensure limited privileges of the service account.

To allow access to xp_cmdshell for non-sysadmin logins, you could encapsulate it in a
stored procedure that uses the EXECUTE AS elevation. If you want to allow them to issue
arbitrary commands, you need to define a proxy account. xp_cmdshell will then run under
the rights of this account for non-sysadmin logins. The following code snippet creates the
##xp_cmdshell_proxy_account## credential:
EXEC sp_xp_cmdshell_proxy_account 'DOMAIN\user','user password';
You can issue the following statement to query it:
SELECT *
FROM sys.credentials
WHERE name = '##xp_cmdshell_proxy_account##';
You can use the following command to remove it:
EXEC sp_xp_cmdshell_proxy_account NULL;

You cannot prevent a sysadmin member from using xp_cmdshell
Even if xp_cmdshell is disabled, someone connected with a login that is in the sysadmin
server role can re-enable and use it. It is crucial that the service account running SQL Server
does not have elevated rights on the computer and on the domain. The following is an
example that demonstrates how easy it is to gain access to the domain if the service
account has administrative rights on Active Directory:
EXEC sp_configure 'show advanced options', 1
RECONFIGURE
EXEC sp_configure 'xp_cmdshell', 1
RECONFIGURE
EXEC xp_cmdshell 'dsadd.exe user "CN=me, CN=Users, DC=domain, DC=com"'
EXEC xp_cmdshell 'dsmod.exe group "CN=domain admins, CN=Users, DC=domain,
DC=com" -addmbr "CN=me, CN=Users, DC=domain, DC=com"'
This code re-enables xp_cmdshell, and uses commands to create a user on the Active
Directory and to add it in the Domain Admins group.
*/

/*
Ad hoc distributed queries
=======================
Ad hoc distributed queries allow the use of connection strings to other data sources inside
a T-SQL statement. You can see it as a one-time linked server. It uses the OPENROWSET or
OPENDATASOURCE keywords to access distant databases through OLEDB. The following is
an example:
SELECT a.*
FROM OPENROWSET('SQLNCLI', 'Server=SERVER2;Trusted_Connection=yes;',
'SELECT * FROM AdventureWorks.Person.Contact') AS a;
The rights applied depend on the authentication type. In the case of a SQL Server login, the
SQL Server service account is used. In the case of a Windows Authentication login, the rights
of the Windows account are applied
*/

/*

OLE automation
==============
OLE automation procedures are system-stored procedures that allow the T-SQL code to use
OLE automation objects, and then run the code outside of the SQL Server context. Procedures
such as sp_OACreate are used to instantiate an object and manipulate it. The following
example demonstrates how to delete a folder using OLE automation procedures. This will
succeed, provided the SQL Server service account has the rights to do it:
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Role Automation Procedures', 1;
RECONFIGURE;
GO
DECLARE @FSO int, @OLEResult int;
EXECUTE @OLEResult = sp_OACreate 'Scripting.FileSystemObject', @FSO
OUTPUT;
EXECUTE @OLEResult = sp_OAMethod @FSO, 'DeleteFolder', NULL, 'c:\
sqldata';
SELECT @OLEResult;
EXECUTE @OLEResult = sp_OADestroy @FSO;
Only members of the sysadmin server role can use these procedures. As any sysadmin
member can re-enable the option with sp_configure, there is in fact no real way to disable
them for good.
*/



/*
Defining Code Access Security for .NET modules 
==============================================

Since SQL Server 2005, you can create .NET modules in SQL Server. In other words, you can
create stored procedures, triggers, data types and others, that are not T-SQL modules, but
.NET classes and methods, compiled into assemblies, that are stored and declared as
first-level modules in SQL Server. It is out of the scope of this book to detail how to create
the .NET code and how to use it in SQL Server. We will just address the security options of
this functionality.
Of course, this recipe makes sense only if you have some assembly to declare in SQL
Server, or if you plan to add some functionality to SQL Server in the form of .NET code.
This code itself needs to be developed with two things in mind: performance and security.
Performance because it will be used in a multiuser and set-oriented environment. For
example, a user-defined function called in the SELECT part of a query will be entered for
each returned line of the result set. Security because a .NET assembly can potentially
access all of your computer and network environment.

Getting ready
===============
SQL Server has .NET code execution disabled by default. Before running .NET modules,
you need to enable it by using the following code:
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled', 1 ;
RECONFIGURE;
EXEC sp_configure 'show advanced options', 0
RECONFIGURE;

To see the current value, use sp_configure with only the first parameter:
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled' ;
RECONFIGURE;
EXEC sp_configure 'show advanced options', 0
RECONFIGURE;
Or use the sys.configurations catalog view:
SELECT value_in_use
FROM sys.configurations
WHERE name = 'clr enabled';
You can also use the Facets functionality to change this value:
1. In SQL Server Management Studio, in Object Explorer, right-click on the server
node and select Facets in the contextual menu.
2. Choose the Surface Area Configuration facet, and change the value of the
ClrIntegrationEnabled to True:

How to do it...
We have developed a .NET scalar function that allows to make changes in a VARCHAR
using regular expressions. We have compiled it in a SQLRegex.dll assembly that we
copied on the database server. Now we want to declare it in SQL Server and we will do
it with the following code:
CREATE ASSEMBLY SQLRegex
FROM 'd:\sqlserver_assemblies\SQLRegex.dll'
WITH PERMISSION_SET = SAFE;
The PERMISSION_SET option specifies what kind of access the assembly will be able to
have in SQL Server context.
When this is done, we can create the function as we would create a function in TSQL,
but instead of writing some T-SQL code in it, we map the function to a .NET function in
the assembly:
CREATE FUNCTION dbo.rxReplace (@str nvarchar(4000), @regex
nvarchar(4000))
RETURNS nvarchar(4000)
AS EXTERNAL NAME [SQLRegex].[Packt.SQLServer2012SecurityCookbook.
frxReplace].[fRxReplace];
In this example, it is created like a regular T-SQL function; you just bind the function to an
external name.
The EXTERNAL NAME must be in this format: [assembly name].
[namespace].[method name]. Here, the namespace has dots; we
delimit the entire namespace name with []. Don't confuse the dots between
assembly, namespace, and method name with the dots of the namespace.
You can see the module in the catalog view, sys.assembly_modules.

How it works...
When you import the assembly with CREATE ASSEMBLY, you define the .NET
Code Access Security (CAS), which is the .NET framework access model.
Then, when you create the module from the assembly method, you can define
the SQL Server execution permission. These two levels allow you to effectively
control execution of the modules.

When you register an assembly in SQL Server with the CREATE ASSEMBLY command, you
store it inside SQL Server. The binary will be kept in a system table inside the database, and
it will be executed in the context of SQL Server, by a .NET CLR (Common Language Runtime),
the .NET virtual machine, integrated into SQL Server. This is called CLR integration.
It means that the .NET modules will be executed in the SQL Server memory space, but unlike
extended procedures (the stored procedures prefixed by xp_, that are in fact non-managed
DLL, usually written in C), they normally could do no harm to the SQL Server memory because
the .NET code is sandboxed by the CLR.
The PERMISSION_SET option of CREATE ASSEMBLY controls the access level of the
assembly code. There are three options:
ff SAFE   The code is strictly confined inside SQL Server. It cannot access external
resources such as disk, network, or registry.
ff EXTERNAL_ACCESS   When you want to access external resources, for example,
a web page or a file on the disk, you need to choose this option.
ff UNSAFE   This allows not only external access for the .NET code, but also to call
unmanaged code and libraries from the managed code.
Code Access Security in .NET 4.0Code Access Security is being
deprecated in .NET 4.0. But, even if the CLR integration of SQL Server
2012 is based on .NET 4.0, it continues to use the CAS model defined
in CLR version 2.0, due to the SQL Server security requirements.
If PERMISSION_SET is not specified, SAFE is the default. It is the recommended option for
most of the .NET code. As soon as you need to access system or network resources, you have
to give the assembly more permissions, if you want to call a web service, for example. It is
advisable, anyway, to keep these actions in your client application code rather than putting
in at the database layer.
If you set your assembly to EXTERNAL_ACCESS, the .NET code will be able to access external
resources normally under the security context of the SQL Server service account (other rules
apply; refer to CLR Integration Code Access Security:
http://msdn.microsoft.com/en-us/library/ms345101.aspx for more details). Grant permissions to execute such
modules only to trusted users.
UNSAFE code can call nonmanaged code, binaries that can wander outside of the .NET and
SQL Server security systems and call low-level and operating system functions. Avoid doing
that! Most of the time there is no solid reason for an UNSAFE assembly in SQL Server. Only
members of sysadmin can create UNSAFE assemblies. Also notice that partially contained
databases cannot contain assemblies using EXTERNAL_ACCESS of UNSAFE permissions.

A module from an assembly cannot be created
WITH ENCRYPTION.

*/

/*
Configuring cross-database security
===================================
If you reference an object from another database in a view or a procedure, then
the user must also be a user in the other database, and have permissions upon this object.
This is the best choice security-wise. If your databases are tightly linked, you can allow crossdatabase
ownership chaining. There are several steps to follow, and we will detail them here
How to do it...
1. First, you need to set the databases that need to participate in the chaining as
trustworthy, as follows:
ALTER DATABASE marketing SET TRUSTWORTHY ON;
ALTER DATABASE tools SET TRUSTWORTHY ON;
2. You also need to make sure that all the objects belong to the same owner. The most
basic choice is to ensure that the objects belong to dbo, and that the database
owner is the same:
ALTER AUTHORIZATION ON DATABASE::marketing TO sa;
ALTER AUTHORIZATION ON DATABASE::tools TO sa;
3. Then, you need to explicitly allow cross-database ownership chaining. You can do it
for the whole instance, or for specific databases.
4. To change it for the instance, go to SQL Server Management Studio, in Object
Explorer. Right-click on the instance node, and click on Properties. Go to the
Security page and check the Cross Database Ownership Chaining option;
it is the last option on the page.
5. If you want to allow it only for the desired database, run the following code:
EXEC sp_configure 'cross db ownership chaining', 1;
RECONFIGURE;
-- or, for databases
ALTER DATABASE marketing SET DB_CHAINING ON;
ALTER DATABASE tools SET DB_CHAINING ON;
There is a Cross Database Ownership Chaining Enabled option in
the Options page of the Properties dialog box of a database, but it
is grayed out; you need to do it by code.
How it works...
What does a trustworthy database mean? The goal is to ensure the default protection for
databases. When created, a database has trustworthy set to off, and if you restore a backup
of a database that has this set to on, it will clear the trustworthy bit during the restore. In
other words, the DBA must always set this value manually for cross-database impersonation
to work; a human decision has to be taken. It is nothing other than that Boolean setting that
will be tested by SQL Server when it checks cross-database permissions.
Then, you can allow chaining for all databases or only the one involved. If you are serious
about security, it is better to enable it at the database level, especially if your server hosts
databases used by different groups of people. If you allow cross-database ownership chaining
at the server level, SQL Server ignores the value of individual DB_CHAINING settings at the
database level. All databases will be allowed to participate.
You can check for databases that have these options enabled, as follows:
SELECT name, s_trustworthy_on, is_db_chaining_on
FROM master.sys.databases
ORDER BY name;
There's more...
If you want to tighten security and limit chaining to some procedures, you can use
certificates to sign the procedure and authenticate on the other database, instead of
allowing ownership chaining.
*/

/*
contained database
================================

Creating a contained database
In SQL Server, there are two levels of security: server and database. A server login is mapped
to a user in the database. Authentication is managed at the server level, and when the login
is connected, he can access databases where he is a user. The mapping between the login
and user is made with an internal SID. When you copy a database to another server, even if
the username is the same, the link is broken if the SID is different. To solve the dependency
a database has with its server, Microsoft implemented the concept of contained databases
in SQL Server 2012. A contained database does not depend on any external definition, and
can be moved between servers without requiring any configuration on the new server. Several
levels of containment could exist, and a few of them are listed as follows:

1. Non-contained: The database depends on the server. On the positive side, a user can
be seen across databases

2.Partially-contained: The user is defined inside the database, so the database is
independent, but it also can access resources outside the database

3. Fully-contained: The database is independent, and users cannot access resources
outside it

SQL Server 2012 supports only partially-contained databases as of now.
The partially-contained database solve two problems: login/user mapping
discrepancies, and collation of temporary tables. When you create a local temporary
table (a table prefixed with #) in the context of a contained database, the collation
used for CHAR/VARCHAR columns is one of the calling databases, not the default
collation of tempdb, as it is in non-contained databases.

Getting ready
=============
Before creating contained databases, you need to enable contained database authentication
on your instance, either in your instance properties, in the Advanced page, as shown in the
following screenshot, or by T-SQL

To do it by T-SQL, execute the following code:
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'contained database authentication', 1;
RECONFIGURE;
GO
sp_configure 'show advanced options', 0;
RECONFIGURE;
GO
This setting is also necessary on a server where you want to restore or attach a
contained database.

How to do it...
To create a partially-contained database, follow these steps:
1. In SQL Server Management Studio Object Explorer, right-click on the Databases
node, and click on New database....
2. In the Options page of the New database dialog box, select Partial as the value for
Containment type
The following T-SQL example does it by code:
CREATE DATABASE containedDb
CONTAINMENT = PARTIAL;
3. Then, you can create contained users in the database, as shown in the following
T-SQL examples, for a user with password first, and for a Windows account on the
second line:
USE containedDb;
CREATE USER Fred WITH PASSWORD = N'Strong Password', DEFAULT_
SCHEMA = dbo;
CREATE USER [DOMAIN\Fred];
4. To find a list of contained users in your database, execute the following code:
SELECT name, type_desc, authentication_type_desc
FROM sys.database_principals
WHERE authentication_type = 2;
5. The Dynamic Management View (DMV) sys.dm_exec_sessions will show you
what type of authentication was used, as follows:
SELECT
session_id,
login_time,
login_name,
87
DB_NAME(database_id) as db,
IIF(authenticating_database_id = 1,
'server login',
QUOTENAME(DB_NAME(authenticating_database_id)) + ' user '
+ QUOTENAME(original_login_name))
as authentication_type
FROM sys.dm_exec_sessions
WHERE is_user_process = 1;
In this query, in the case of a contained user, login_name will be a string version of the SID.
This same SID string will be displayed in error messages where a login name is expected and
as a result of calling the SYSTEM_USER or SUSER_SNAME().




How it works...
===============
Contained databases bring some changes to the SQL Server traditional security model.
Previously, only logins could be used for authenticating a connection. Now, users can be
independent of any login, and be authenticated directly.
The password at the database level does take advantage of the strong password policies that
can be set at the server level. It cannot use Kerberos authentication too. Also, as it is stored
in the contained database, if the contained database user is a Windows account, he will not
be able to go outside of the database, provided he has no login at the server level. If he has a
login, he will be granted permissions given to the server login too.
A contained user has no default database, so a connection cannot be made if a database
is not explicitly set during the connection. The database must be defined in the connection
properties in the Connection dialog box of SSMS, or in a connection string in your application.
For example, with the SQL Server Native Client ODBC driver:
Driver={SQL Server Native Client 11.0};Server=SERVER\SQL2012;Database=
ContainedDB;Uid=Fred;Pwd=iamaweakpassword;
We named the database ContainedDb in the previous example.


Contained databases could also be a threat to security
======================================================
Contained databases could also be a threat to security, because a user in the contained
database, having the ALTER ANY USER permission, can create users who would have
access to SQL Server without any knowledge of server administrators. As the database is only
partially-contained for now, this could lead to users having access to some part of the whole
instance, or even a possible denial of service attack.
Why denial of service? Because, if a contained user is created with the same name as an
existing SQL login at the server level, then the contained user will take precedence over
the server-level login. If an attempt is made to connect with the server-level password while
mentioning the contained database as the initial database, the connection will be refused.
The contained database authentication server option exists to prevent those problems. If this
option is set to 1, all logins having the ALTER ANY DATABASE permission can change the
containment type of a database.
You could also create a DDL trigger firing when the containment type of an existing database
is changed, or when a contained user is created with the same name as an existing SQL login.
A DDL trigger or a policy could also be used to prevent changing the AUTO_CLOSE database
option. Databases in AUTO_CLOSE need additional resources to check the password in a
login attempt (it needs to open the database each time), so AUTO_CLOSE could be used in
a denial of service attack.
An example of a logon trigger to help detecting unwanted connections is
available in the blog entry at:
http://blogs.msdn.com/b/sqlsecurity/archive/2010/12/06/contained-database-authenticationhow-to-control-which-databases-are-allowed-toauthenticate-users-using-logon-triggers.aspx.
If you are concerned about this risk when attaching or restoring a contained database,
you can put it in the RESTRICTED_USER mode, which will prevent contained users
from connecting:
ALTER DATABASE containedDb SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE;
Only users with a server-level login will be able to enter the database.




There's more...
==============
It is difficult to ensure real containment of a database. What do you do, for example, with
views or stored procedures referencing a table from another database, or synonyms doing
the same, or server level system objects?
It is still possible in a contained database to do something like the following:
CREATE SYNONYM dbo.marketing_prospect FOR marketing.dbo.prospect;
But, this command will break when the database is moved. That is why the containment
is said to be partial. You can query such objects with the sys.dm_db_uncontained_
entities DMV. The following is a code example borrowed from Aaron Bertrand
(http://sqlblog.com/blogs/aaron_bertrand/archive/2010/11/16/sql-server-vnext-denali-contained-databases.aspx):
SELECT
e.feature_name,
[object] = COALESCE(
QUOTENAME(SCHEMA_NAME(o.[schema_id])) + '.' + QUOTENAME(o.
[name]),
QUOTENAME(SCHEMA_NAME(s.[schema_id])) + '.' + QUOTENAME(s.
[name])
),
[line] = COALESCE(e.statement_line_number, 0),
[statement / synonym target / route / user/login] = COALESCE(
s.[base_object_name],
SUBSTRING(
m.[definition],
e.statement_offset_begin / 2,
e.statement_offset_end / 2 - e.statement_offset_begin / 2
) COLLATE CATALOG_DEFAULT,
r.[name],
'User : ' + p.[name] + ' / Login : ' + sp.[name]
)
FROM sys.dm_db_uncontained_entities AS e
LEFT JOIN sys.objects AS o ON e.major_id = o.object_id AND e.class = 1
LEFT JOIN sys.sql_modules AS m ON e.major_id = m.object_id AND e.class
= 1
LEFT JOIN sys.synonyms AS s ON e.major_id = s.object_id AND e.class =
1
LEFT JOIN sys.routes AS r ON e.major_id = r.route_id AND e.class = 19
LEFT JOIN sys.database_principals AS p ON e.major_id = p.principal_id
AND e.class = 4
LEFT JOIN sys.server_principals AS sp ON p.[sid] = sp.[sid];
A list of uncontained objects and T-SQL commands is available in Books
Online (BOL) at http://msdn.microsoft.com/en-us/library/ff929118.aspx
It is better to avoid uncontained code altogether, because execution of this code
will be denied to contained SQL users anyway, as they have no privileges outside
the database scope.

ALTER DATABASE in contained databases
=======================================
When you store some ALTER DATABASE code in, let's say, a stored
procedure inside the contained database, you need to use the special syntax
ALTER DATABASE CURRENT instead of the traditional ALTER DATABASE
<databaseName>. This will ensure that the command will work even if the
database is moved or renamed.


How to convert a database to contained
======================================
You can convert a database to contained simply by setting its CONTAINMENT property,
as follows:
USE [master]
GO
ALTER DATABASE [marketing] SET CONTAINMENT = PARTIAL;
If you have users mapped to SQL logins, use the sp_migrate_user_to_contained system
procedure to convert them to contained database users.
To automatize it, you can refer to the code snippet provided in the BOL at
http://msdn.microsoft.com/en-us/library/ff929275.aspx ,
or you can generate some code similar to the following:
SELECT 'EXEC sp_migrate_user_to_contained @username = N''' + dp.name +
''',
@rename = N''keep_name'',
@disablelogin = N''do_not_disable_login'' ;'
FROM sys.database_principals AS dp
JOIN sys.server_principals AS sp
ON dp.sid = sp.sid
WHERE dp.authentication_type = 1 AND sp.is_disabled = 0;
This code returns lines of varchars that you just have to copy-and-paste in a query window
to execute.

*/


IF EXISTS
(
SELECT name FROM sys.databases WHERE containment > 0
)
BEGIN 
	SELECT 'Test 005 .  Contained databases. Convert it to regular DB and rerun the script !'
	SELECT name FROM sys.databases WHERE containment > 0
END



IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'allow updates' and value_in_use=1
	WHERE configuration_id IN (102) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : allow updates Enabled is enabled .  The script will Disable  it . Enable it manually only when you need it !'
END

IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'cross db ownership chaining' and value_in_use=1
	WHERE configuration_id IN (400) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : cross db ownership chaining is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END

IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'clr enabled' and value_in_use=1
	WHERE configuration_id IN (1562) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : SQL Server has .NET code execution  (clr enabled) is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END


IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'Database Mail XPs' and value_in_use=1
	WHERE configuration_id IN (16386) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : Database Mail XPs is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END


IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'xp_cmdshell' and value_in_use=1
	WHERE configuration_id IN (16390) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : xp_cmdshell	 is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END


IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'Ad Hoc Distributed Queries' and value_in_use=1
	WHERE configuration_id IN (16391) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : Ad Hoc Distributed Queries	 is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END

IF EXISTS
(
	SELECT name,value_in_use
	FROM sys.configurations
	-- WHERE name = 'contained database authentication' and value_in_use=1
	WHERE configuration_id IN (16393) and value_in_use=1
)
BEGIN 
	SELECT 'Test 005 . Failure : contained database authentication	 is enabled . The script will Disable  it . Enable it manually only when you need it !   '
END



 /*
The run_value is 1 if it is enabled. You can disable or enable it by changing the
value to 0 (disabled) or 1 (enabled), and issue a RECONFIGURE command to apply
the change:
*/

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'Ad Hoc Distributed Queries', 0;
EXEC sp_configure 'Ole Automation Procedures', 0;
EXEC sp_configure 'xp_cmdshell', 0;
EXEC sp_configure 'Database Mail XPs', 0;
EXEC sp_configure 'cross db ownership chaining', 0;
RECONFIGURE;
GO

/*
Output :
=======
Configuration option 'show advanced options' changed from 0 to 1. Run the RECONFIGURE statement to install.
Configuration option 'Ad Hoc Distributed Queries' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'Ole Automation Procedures' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'xp_cmdshell' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'Database Mail XPs' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'cross db ownership chaining' changed from 0 to 0. Run the RECONFIGURE statement to install.
*/


-- Disable  contained database authentication on your instance,
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO
EXEC sp_configure 'contained database authentication', 0;
RECONFIGURE;
GO
sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

/*
Output:
Configuration option 'show advanced options' changed from 1 to 1. Run the RECONFIGURE statement to install.
Configuration option 'contained database authentication' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'show advanced options' changed from 1 to 0. Run the RECONFIGURE statement to install.
*/


-- SQL Server has .NET code execution disabled by default. Before running .NET modules,
--  Disable  it by using the following code:
-- Enable it manually only when you need 
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled', 0 ;
RECONFIGURE;
EXEC sp_configure 'show advanced options', 0
RECONFIGURE;

/*
Output:
Configuration option 'show advanced options' changed from 0 to 1. Run the RECONFIGURE statement to install.
Configuration option 'clr enabled' changed from 0 to 0. Run the RECONFIGURE statement to install.
Configuration option 'show advanced options' changed from 1 to 0. Run the RECONFIGURE statement to install.
*/


/*
Check server configuration options
======================================
This will check different server configuration settings such as: allow updates, cross db ownership chaining, clr enabled, SQL Mail XPs, Database Mail XPs, xp_cmdshell and Ad Hoc Distributed Queries
Configuration_id 16393 is to check if "Contained Databases Authentication" option is enabled on SQL Server 2012. There are some potential security threats associated with contained databases that DBAs have to understand. 
*/


select '  Test 005: The following server configuration settings were disabled (value_in_use=0 ). Enable them manually only on demand with restrictions !' 
SELECT name, value_in_use ,configuration_id FROM  master.sys.configurations
 WHERE configuration_id IN (16391, 102, 400, 1562, 16386, 16385, 16390, 16393)
 /*
 name									value_in_use	configuration_id
allow updates							0				102
cross db ownership chaining				0				400
clr enabled								0				1562
Database Mail XPs						0				16386
xp_cmdshell	0	16390
Ad Hoc Distributed Queries				0				16391
contained database authentication		0				16393
*/




/*
The list of system objects that are impacted by each facet property can be retrieved
by querying the sys.system_components_surface_area_configuration
catalog view, as shown in the following example:
*/


/*

SELECT *
FROM sys.system_components_surface_area_configuration
WHERE component_name IN
(
'Ole Automation Procedures',
'xp_cmdshell'
);
*/


/*
Outpul Example :
===============
component_name				database_name				schema_name				object_name			state	type	type_desc
Ole Automation Procedures	mssqlsystemresource			sys						sp_OASetProperty	0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OAMethod			0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OAGetErrorInfo	0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OAStop			0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OADestroy		0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OACreate			0		X 		EXTENDED_STORED_PROCEDURE
Ole Automation Procedures	mssqlsystemresource			sys						sp_OAGetProperty	0		X 		EXTENDED_STORED_PROCEDURE
xp_cmdshell					mssqlsystemresource			sys						xp_cmdshell			0		X 		EXTENDED_STORED_PROCEDURE
*/




/*
To check and modify the status of these options with the T-SQL code, use the
following statements:
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ad Hoc Distributed Queries';
EXEC sp_configure 'Ole Automation Procedures';
EXEC sp_configure 'xp_cmdshell';

The run_value is 1 if it is enabled. You can disable or enable it by changing the
value to 0 (disabled) or 1 (enabled), and issue a RECONFIGURE command to apply
the change:
EXEC sp_configure 'Ad Hoc Distributed Queries', 0;
EXEC sp_configure 'Ole Automation Procedures', 0;
EXEC sp_configure 'xp_cmdshell', 0;
RECONFIGURE;
*/






/*
The Guest User
==============
The guest account is a special user in SQL Server that does not exist as a login. Essentially, if you grant
the guest account access to your database, anyone who has a login into SQL Server will implictly have
access to your database and be given any rights to which the guest account has been granted. Granting
the guest account access to your database creates a security hole in your database, so this should never
be done. The only databases that should ever have the guest account enabled are the master, msdb, and
tempdb databases. These enable users access to create jobs, create temporary objects, and connect to
SQL Server.

Note : We cannot disable access to the guest user in master or tempdb so  I catch Msg 15182  to prevent the following message : 
Msg 15182, Level 16, State 1, Line 276
Cannot disable access to the guest user in master or tempdb.
Msg 15182, Level 16, State 1, Line 276
Cannot disable access to the guest user in master or tempdb.
*/
USE master
go
BEGIN TRY
	EXEC sp_MSforeachdb 'USE [?];
	REVOKE CONNECT FROM GUEST ;'
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 15182
	BEGIN
		PRINT ''
		-- 'Msg 15182 ,Cannot disable access to the guest user inGuest or tempdb.  Ignore this message  becuase We cannot disable access to the guest user in master or tempdb . ';
	END
END CATCH;
GO


 /*
 CONNECT or other permissions granted to the "guest" user
 =======================================================
This will list what permission the guest user has.
Guest user by default has CONNECT permissions to the master, msdb and tempdb databases. Any other permissions will be returned by this query as potential problem.
*/


SET NOCOUNT ON
IF OBJECT_ID('tempdb.dbo.#guest_perms') IS NOT NULL
DROP TABLE dbo.#guest_perms;
GO
CREATE TABLE #guest_perms 
 ( db SYSNAME, class_desc SYSNAME, 
  permission_name SYSNAME, ObjectName SYSNAME NULL)
EXEC master.sys.sp_MSforeachdb
'INSERT INTO #guest_perms
 SELECT ''?'' as DBName, p.class_desc, p.permission_name, 
   OBJECT_NAME (major_id, DB_ID(''?'')) as ObjectName
 FROM [?].sys.database_permissions p JOIN [?].sys.database_principals l
  ON p.grantee_principal_id= l.principal_id 
 WHERE l.name = ''guest'' AND p.[state] = ''G'''
 

IF EXISTS
(SELECT *  FROM #guest_perms WHERE permission_name NOT LIKE   'CONNECT')
BEGIN 
	SELECT 'Test 006'
	select ''
	SELECT 'Failure : guest user granted  CONNECT  or other permissions . Manually remove the permission in permission_name column  from guest user in DB in DatabaseName column where column CheckStatus=Potential Problem! ';
	SELECT 'Note : Guest user by default has CONNECT permissions to the master, msdb and tempdb databases '
	SELECT db AS DatabaseName, class_desc, permission_name, 
		CASE WHEN class_desc = 'DATABASE' THEN db ELSE ObjectName END as ObjectName, 
		CASE WHEN DB_ID(db) IN (1, 2, 4) AND permission_name = 'CONNECT' THEN 'Default' 
		ELSE 'Potential Problem!' END as CheckStatus
	FROM #guest_perms
	DROP TABLE #guest_perms
END


/*
Output  example : 
DatabaseName	class_desc				permission_name		ObjectName	CheckStatus
master			DATABASE				CONNECT				master		Default
tempdb			DATABASE				CONNECT				tempdb		Default
msdb			DATABASE				CONNECT				msdb		Default
testdb 			OBJECT_OR_COLUMN		SELECT				Table1		Potential Problem!
*/

  


/*
SQL Server Authentication mode
===============================
If this returns 0 the server uses both Windows and SQL Server security.  If the value is 1 it is only setup for Windows Authentication.
*/



select 'Test 007 : SQL Server Authentication mode : Mixed=0 Windows Authentication=1 . The better option : Only Windows Authentication  '
SELECT SERVERPROPERTY ('IsIntegratedSecurityOnly')



/*
Database users, permissions and application roles
==================================================
This will give a list of permissions for each user.
*/

/*

select ' Database users, permissions and application roles '
select '================================================== '
-- list of the users
EXEC master.sys.sp_helpuser
-- database permissions
EXEC  master.sys.sp_helprotect
-- roles membership
EXEC  master.sys.sp_helprolemember
-- list of the database application roles
SELECT name FROM sys.database_principals WHERE type = 'A'

*/




IF NOT EXISTS 
	(SELECT * FROM sys.dm_server_services WHERE service_account LIKE  '%NT Service%' AND is_clustered  LIKE '%N' )
BEGIN 
	select ' Test 008 : SQL Server Services Startup mode , status , service account , is_clustered and cluster_nodename'
	SELECT '  On  standalone installation use the following Services account for SQL Server '
	SELECT '  SQL Server Database Engine . Virtual Accounts : SERVICE\MSSQLSERVER. Named instance: NT SERVICE\MSSQL$InstanceName  or Domain account only if youu need to to external resou Example : Domain\sqlsrv '
	SELECT '  SQL Server Agent  . Virtual Accounts : Service\SQLSERVERAGENT. Named instance: NT Service\SQLAGENT$InstanceName  or Domain account only if you need to to external resou Example : Domain\sqlagent '
	SELECT '  SSRS  . Virtual Accounts : SERVICE\ReportServer. Named instance: NT SERVICE\$InstanceName   or Domain account only if youu nee to to external resou Example : Domain\sqlssrs '
	SELECT '  SSIS .  Virtual Accounts : Default instance and named instance: NT SERVICE\MsDtsServer120. Integration Services does not have a separate process for a named instance  or Domain account only if youu nee to to external resou Example : Domain\sqlssis '
	SELECT '  Full-text search:  Virtual Accounts :  Default instance: NT Service\MSSQLFDLauncher. Named instance: NT Service\ MSSQLFDLauncher$InstanceName. No  Domain account '
	SELECT '  SQL Server Browser :  LOCAL SERVICE . SQL Server Browser does not have a separate process for a named instance. '
	SELECT * FROM sys.dm_server_services 
END


/*
Check enabled Network Protocols
===============================
The query below will show if the Named Pipes protocol is enabled on SQL Server instance:
*/
Declare @NamedPipesEnabled int 
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
  N'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib\Np', 
  N'Enabled', 
  @NamedPipesEnabled OUTPUT
  
IF  CONVERT(INTEGER, @NamedPipesEnabled) <> 0 
select ' Test 009 . Failure : Named Pipes protocol is enabled on SQL Server instance . Go to : Microsoft  SQL Server 2012 -> Configuration Tools -> SQL Server Network Configuration -> Protocols for MSSQLSERVER and Disable Named Pipe Protocol . Restart SQL Server  '


/*
Default TCP Port
================
It s widely known that SQL Server 2005 and 2008 listen on TCP port 1433. Keeping this default gives hackers a potential way of attacking your server.
This alert is raised when you are using the default port of 1433 which is a known security risk. 
You should consider modifying the port to a non-standard, non-default port in order to thoroughly secure your systems.
*/

DECLARE @KeyValue VarChar(500),  

        @Data Varchar(255),  

        @InstanceName VarChar(200)  

   

SET @InstanceName = CONVERT(VarChar(200), ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER'))  

SET @KeyValue = 'SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' 

EXEC xp_regread 'HKEY_LOCAL_MACHINE',  

                @KeyValue,  

                @InstanceName,  

                @InstanceName OUTPUT 

   

SET @Data = NULL 

SET @KeyValue = 'SOFTWARE\Microsoft\Microsoft SQL Server\' + @InstanceName + '\MSSQLServer\SuperSocketNetLib\Tcp\IPAll\'  

EXEC xp_regread 'HKEY_LOCAL_MACHINE',  

                @KeyValue,  

                'TcpPort',  

                @Data OUTPUT 



IF (COALESCE(@Data,1433) = 1433)  
BEGIN
  -- SELECT 1 AS IsDefaultTCPPort  
  select ' Test 010 . you are using the default port of 1433 which is a known security risk. modifying the port to a non-standard, non-default port !'
END



/*
IF (COALESCE(@Data,1433) = 1433)  

  SELECT 1 AS IsDefaultTCPPort  

ELSE  

  SELECT 0 AS IsDefaultTCPPort 
  
 */




/*
Find specific ports used by SQL Server
=======================================
An endpointcan be used for T-SQL communication, Service Broker, or Database Mirroring. You can see which ports need to be opened .
*/


IF EXISTS
(		SELECT name, protocol_desc, port, state_desc
		FROM sys.tcp_endpoints
		WHERE type_desc IN ('SERVICE_BROKER', 'DATABASE_MIRRORING') 
)
BEGIN 

	SELECT 'Test 011 : Find specific ports used by SQL Server for DATABASE MIRRORING and SERVICE BROKER . This ports  should be openned in Fire Wall. '
	SELECT name, protocol_desc, port, state_desc
	FROM sys.tcp_endpoints
	WHERE type_desc IN ('SERVICE_BROKER', 'DATABASE_MIRRORING')

END

/*
Output Example :
name				protocol_desc	port	state_desc
MirroringEndPoint	TCP				10111	STARTED
*/


/*
sys.database_mirroring_endpoints
=================================
The following query returns information about database mirroring endpoints such as port number,
whether encryption is enabled or not, authentication type, and endpoint state:
*/

IF EXISTS
(	
SELECT
dme.name AS EndPointName
FROM sys.database_mirroring_endpoints dme
JOIN sys.tcp_endpoints te
ON dme.endpoint_id = te.endpoint_id
where dme.is_encryption_enabled = 1
)
BEGIN 
SELECT 'Test 012 : Database mirroring endpoints. Encryption is not enabled . '
SELECT
	dme.name AS EndPointName
	,dme.protocol_desc
	,dme.type_desc AS EndPointType
	,dme.role_desc AS MirroringRole
	,dme.state_desc AS EndPointStatus
	,te.port AS PortUsed
	,CASE WHEN dme.is_encryption_enabled = 1
	THEN 'Yes'
	ELSE 'No'
	END AS Is_Encryption_Enabled
	,dme.encryption_algorithm_desc
	,dme.connection_auth_desc
	FROM sys.database_mirroring_endpoints dme
	JOIN sys.tcp_endpoints te
	ON dme.endpoint_id = te.endpoint_id
END 


/*

 Check that  SQL Server  use Kerberos for Windows Authentication.
 ==========================================================

In the Active Directory world, there are 2 authentication mechanisms: NTLM and Kerberos.
The legacy NT LAN Manager (NTLM)  Microsoft advises not to use it anymore.Kerberos should be already used by default. To check that the SQL
Server user sessions use Kerberos, issue the following T-SQL command:
If a connection from the same domain or a trusted domain uses the NTLM authentication
scheme, you need to investigate why it cannot use Kerberos.
*/


IF EXISTS

	(SELECT auth_scheme, net_transport, client_net_address FROM sys.dm_exec_connections WHERE auth_scheme LIKE '%NTLM%' and client_net_address NOT LIKE '%local%machine%')
BEGIN
select ' Test 013 : Check that  SQL Server  use Kerberos  for Windows Authentication from remotr Client  run the following query '
select 'SELECT auth_scheme, net_transport, client_net_address FROM sys.dm_exec_connections WHERE auth_scheme LIKE ''%NTLM%'''
select 'The desired check is from remot client under  auth_scheme column  all results should be KERBEROS'
print  'Current output from Sql  query : '
SELECT auth_scheme, net_transport, client_net_address FROM sys.dm_exec_connections WHERE auth_scheme LIKE '%NTLM%' 
END 


/*

If you run the following query 
SELECT auth_scheme, net_transport, client_net_address FROM sys.dm_exec_connections 

auth_scheme	net_transport	client_net_address
=========== ============	==================
NTLM		Shared memory	<local machine>

The desired check is from remot client under  auth_scheme column  all results should be KERBEROS

auth_scheme	net_transport	client_net_address
==========  =============   =================
KERBEROS	TCP				2.8.77.60

for SQL 
auth_scheme	net_transport	client_net_address
==========  =============   =================
SQL			Session			2.8.77.100
*/




/*
Windows Principals 
 =====================  
Windows logins apply only at the server operating system level: you can t grant Windows principals access to
specific database objects. To grant permissions based on Windows logins, you need to create a database user and
associate it with the login.
*/


/*
 Viewing Windows Logins
 =======================
 You can view Windows logins and groups by querying the sys.server_principals system catalog view. This
shows the name of each Windows login and group with access to SQL Server, along with the security
identifier (sid). Each principal in the system catalog view has an sid, which helps uniquely identify it on the SQL
Server instance
Exclude SQL Server accounts like virtual accounts. Example : 
NT SERVICE\SQLWriter
NT SERVICE\Winmgmt
NT Service\MSSQLSERVER
NT AUTHORITY\SYSTEM
NT SERVICE\SQLSERVERAGENT
*/


select  'Test 014 : Viewing Windows Logins :  Check their permissions manually  '
USE master;
GO
SELECT name, sid
FROM sys.server_principals
WHERE type_desc IN ('WINDOWS_LOGIN', 'WINDOWS_GROUP')
and  name NOT LIKE ('%NT SERVICE%') AND  name  NOT LIKE ('%NT AUTHORITY\SYSTEM%')
ORDER BY type_desc;
GO




/*
SQL Server Principals 
===================== 
As with Windows logins, SQL Server logins apply only at the server level; you can t grant permissions on
them to specific database objects. Unless you are granted membership to a fixed server role such as sysadmin,
you must create database users associated to the login before you can begin working with database objects.
*/




 /*
 Verify that "sa" login has been renamed and/or disabled and has password policy/expiration enabled
 =====================================================================================================
This will check whether the sa password exists and if it does if the password policy is turned on for this login.
*/



IF EXISTS 
(
	SELECT l.name
	FROM sys.server_principals AS l
	 LEFT OUTER JOIN sys.sql_logins AS s ON s.principal_id = l.principal_id
	WHERE l.sid = 0x01 and l.name = 'sa' 
)
BEGIN
	
	select 'Test 015 : Failure : Verify that sa login has been renamed and/or disabled and has password policy/expiration enabled ' 
		SELECT l.name, CASE WHEN l.name = 'sa' THEN 'NO' ELSE 'YES' END as Renamed,
	  s.is_policy_checked, s.is_expiration_checked, l.is_disabled
	FROM sys.server_principals AS l
	 LEFT OUTER JOIN sys.sql_logins AS s ON s.principal_id = l.principal_id
	WHERE l.sid = 0x01
	ALTER LOGIN sa WITH NAME=rafsa;
	select 'sa was rename to rafsa with : ALTER LOGIN sa WITH NAME=rafsa; '
END 

/*
Expected output : 
name	Renamed	is_policy_checked	is_expiration_checked	is_disabled
rafsa	YES		1					0						0
*/


/*
Viewing SQL Server Logins
==========================
The query returned the name and sid of each SQL login on the SQL Server instance by querying the
sys.server_principals catalog view
*/

USE master;
GO
select ' test 016 : Viewing SQL Server Logins :  Check their permissions manually  '
SELECT name, sid
FROM sys.server_principals
WHERE type_desc IN ('SQL_LOGIN')
and  name not like '%##MS_%##'
-- Exclude internal logins like ##MS_PolicyEventProcessingLogin## or ##MS_PolicyTsqlExecutionLogin## 
ORDER BY name;
GO



/*
Managing a Login s Password
============================
Problem
You have multiple users that are unable to log in to SQL Server. You would like to check the password settings for these users.
Solution
Use the LOGINPROPERTY function to retrieve login policy settings.
SQL Server provides the LOGINPROPERTY function to return information about login and password policy
settings and state. Using this function, you can determine the following qualities of a SQL login:
	  Whether the login is locked or expired
	  Whether the login has a password that must be changed
	  Bad password counts and the last time an incorrect password was given
	  Login lockout time
	  The last time a password was set and the length of time the login has been tracked using
	password policies
	  The password hash for use in migration (to another SQL instance, for example)
	This function takes two parameters: the name of the SQL login and the property to be checked. 
*/
	
	




/*
Check password policies and expiration for the SQL logins
==========================================================
This will check whether the password policy is turn on or off.
Note the SQL Logins 
You should ensure that there is  a procurdure to change it manually on regular basis . 
*/
/*
select 'check whether the password policy is turn on or off.  You should ensure that there is  a procurdure to change it manually on regular basis .  ' 
SELECT name  FROM sys.sql_logins 
 WHERE  is_policy_checked=0 OR is_expiration_checked = 0
 */


IF EXISTS
(
	SELECT name  FROM sys.sql_logins  WHERE  is_policy_checked=0 and  name not like '%##MS_%##'
 ) 

 BEGIN
	SELECT 'TEST 017 : Check whether the password policy is turn on or off.  You should ensure that there is  a procurdure to change it manually on regular basis .  ' 
	-- Exclude internal logins like ##MS_PolicyEventProcessingLogin## or ##MS_PolicyTsqlExecutionLogin## 
	SELECT name  FROM sys.sql_logins WHERE  is_policy_checked=0 OR is_expiration_checked = 0  and  name not like '%##MS_%##'
 END



-- Retutn  properties for logins to determine whether the login may be locked out or expired '
/*
USE master;
GO
SELECT p.name, ca.IsLocked, ca.IsExpired, ca.IsMustChange, ca.BadPasswordCount,
ca.BadPasswordTime, ca.HistoryLength,
ca.LockoutTime,ca.PasswordLastSetTime,ca.DaysUntilExpiration
From sys.server_principals p
CROSS APPLY (SELECT IsLocked = LOGINPROPERTY(p.name, 'IsLocked') ,
IsExpired = LOGINPROPERTY(p.name, 'IsExpired') ,
IsMustChange = LOGINPROPERTY(p.name, 'IsMustChange') ,
BadPasswordCount = LOGINPROPERTY(p.name, 'BadPasswordCount') ,
BadPasswordTime = LOGINPROPERTY(p.name, 'BadPasswordTime') ,
HistoryLength = LOGINPROPERTY(p.name, 'HistoryLength') ,
LockoutTime = LOGINPROPERTY(p.name, 'LockoutTime') ,
PasswordLastSetTime = LOGINPROPERTY(p.name, 'PasswordLastSetTime') ,
DaysUntilExpiration = LOGINPROPERTY(p.name, 'DaysUntilExpiration')
) ca
WHERE p.type_desc = 'SQL_LOGIN'
AND p.is_disabled = 0;
GO
*/



/*
 Check that PasswordHashAlgorithm property  of  LOGINPROPERTY function is SHA-1 or SHA-2
 =======================================================================================
In SQL 2012, the PasswordHashAlgorithm property has been added  for the LOGINPROPERTY function . This property returns the algorithm
used to hash the password. 

How It Works
LOGINPROPERTY allows you to validate the properties of a SQL login. You can use it to manage password rotation,
for example, checking the last time a password was set and then modifying any logins that haven t changed
within a certain period of time.
You can also use the password hash property in conjunction with CREATE LOGIN and the hashed_password
HASHED argument to re-create a SQL login with the preserved password on a new SQL Server instance.
In each of the examples, I queried the sys.server_principals catalog view and then used a CROSS APPLY
with a subquery that utilized the LOGINPROPERTY function.
FROM sys.server_principals p
CROSS APPLY (SELECT PasswordHash = LOGINPROPERTY(p.name, 'PasswordHash') ,
DefaultDatabase = LOGINPROPERTY(p.name, 'DefaultDatabase') ,
DefaultLanguage = LOGINPROPERTY(p.name, 'DefaultLanguage') ,
PasswordHashAlgorithm = LOGINPROPERTY(p.name, 'PasswordHashAlgorithm')
) ca
This method was used so I could retrieve information about multiple SQL logins at once. Rather than pass
each login name into the first parameter of the LOGINPROPERTY function, I referenced the outer catalog view,
sys.server_principals. This allows me to retrieve the properties for multiple logins simultaneously.
To limit the query to just SQL Server logins, I added the following in the WHERE clause:
WHERE p.type_desc = 'SQL_LOGIN'
AND p.is_disabled = 0;
I aliased the CROSS APPLY subquery and used the aliases to reference the columns I needed to return in the
SELECT clause.
SELECT p.name,ca.DefaultDatabase,ca.DefaultLanguage,ca.PasswordHash
,PasswordHashAlgorithm = Case ca.PasswordHashAlgorithm
WHEN 1
THEN 'SQL7.0'
WHEN 2
THEN 'SHA-1'
WHEN 3
THEN 'SHA-2'
ELSE 'login is not a valid SQL Server login'
END
Here, you will also see that I utilized a case statement. This was done to render the output more easily
understood than the numeric assignments of those values.

*/

USE master;
GO

IF EXISTS
(
		SELECT p.name,ca.DefaultDatabase,ca.DefaultLanguage,ca.PasswordHash,PasswordHashAlgorithm
		FROM sys.server_principals p
		CROSS APPLY (SELECT PasswordHash = LOGINPROPERTY(p.name, 'PasswordHash') ,
		DefaultDatabase = LOGINPROPERTY(p.name, 'DefaultDatabase') ,
		DefaultLanguage = LOGINPROPERTY(p.name, 'DefaultLanguage') ,
		PasswordHashAlgorithm = LOGINPROPERTY(p.name, 'PasswordHashAlgorithm')
		) ca
		WHERE p.type_desc = 'SQL_LOGIN'
		AND p.is_disabled = 0
		AND PasswordHashAlgorithm NOT IN (1,2)
)

BEGIN
		select ' Test 018 : Check that PasswordHashAlgorithm property  of  LOGINPROPERTY function is SHA-1 or SHA-2'
		SELECT p.name,ca.DefaultDatabase,ca.DefaultLanguage,ca.PasswordHash
		,PasswordHashAlgorithm = Case ca.PasswordHashAlgorithm
		WHEN 1
		THEN 'SQL7.0'
		WHEN 2
		THEN 'SHA-1'
		WHEN 3
		THEN 'SHA-2'
		ELSE 'login is not a valid SQL Server login'
		END
		FROM sys.server_principals p
		CROSS APPLY (SELECT PasswordHash = LOGINPROPERTY(p.name, 'PasswordHash') ,
		DefaultDatabase = LOGINPROPERTY(p.name, 'DefaultDatabase') ,
		DefaultLanguage = LOGINPROPERTY(p.name, 'DefaultLanguage') ,
		PasswordHashAlgorithm = LOGINPROPERTY(p.name, 'PasswordHashAlgorithm')
		) ca
		WHERE p.type_desc = 'SQL_LOGIN'
		AND p.is_disabled = 0;
END
GO



/*
Output Example on SQL 2012/2014   :

name		DefaultDatabase		DefaultLanguage		PasswordHash	PasswordHashAlgorithm
rafsa		master				us_english			0x0200B9BD46...	SHA-1

Note On SQL 2008 you get on PasswordHashAlgorithm  : login is not a valid SQL Server login
Example : 

name	DefaultDatabase	DefaultLanguage			PasswordHash	PasswordHashAlgorithm
rafsa	master			us_english				0x01006CAB...	login is not a valid SQL Server login
*/




/*
Managing Server Role Members
=============================
You need to report on all users who are members of the sysadmin fixed server role.
Details the permissions granted to each fixed server role as follows : 

Server Role							Granted Permissions
sysadmin							GRANT option (can GRANT permissions to others), CONTROL SERVER
setupadmin							ALTER ANY LINKED SERVER
serveradmin							ALTER SETTINGS, SHUTDOWN, CREATE ENDPOINT, ALTER SERVER STATE, ALTER ANY ENDPOINT,ALTER RESOURCES
securityadmin						ALTER ANY LOGIN
processadmin						ALTER SERVER STATE, ALTER ANY CONNECTION
diskadmin							ALTER RESOURCES
dbcreator							CREATE DATABASE
bulkadmin							ADMINISTER BULK OPERATIONS

*/

/*
Reporting Fixed Server Role Information
========================================
*/

/*
select  'Reporting Fixed Server Role Information'
select	'======================================='
USE master;
GO
SELECT name
FROM sys.server_principals
WHERE type_desc = 'SERVER_ROLE';
GO
*/





/*
You can also view a list of fixed server roles by executing the sp_helpserverrole system stored procedure.
*/

/*
select  'Reporting Fixed Server Role Information with  sp_helpserverrole'
select	'================================================================'
USE master;
GO
EXECUTE sp_helpsrvrole;
GO
*/


/*
output example : 
ServerRole		Description
sysadmin		System Administrators
securityadmin	Security Administrators
serveradmin		Server Administrators
setupadmin		Setup Administrators
processadmin	Process Administrators
diskadmin		Disk Administrators
dbcreator		Database Creators
bulkadmin		Bulk Insert Administrators
*/




/*
To see the members of a fixed server role, you can execute the sp_helpsrvrolemember system stored procedure.
*/

/*
Find Sysadmins server role's members (and other server level roles)
===================================================================
This will show all logins and what server level roles each login has been assigned.
*/

/*
select ' Find Sysadmins server role ''s members (and other server level roles) '
select ' ===================================================================== '


select ' use sp_helpsrvrolemember to see the members of a fixed server role sysadmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'sysadmin'

select ' use sp_helpsrvrolemember to see the members of a fixed server role securityadmin'
select '================================================================================='
EXECUTE sp_helpsrvrolemember 'securityadmin'


select ' use sp_helpsrvrolemember to see the members of a fixed server role serveradmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'serveradmin'


select ' use sp_helpsrvrolemember to see the members of a fixed server role setupadmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'setupadmin'



select ' use sp_helpsrvrolemember to see the members of a fixed server role processadmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'processadmin'


select ' use sp_helpsrvrolemember to see the members of a fixed server role diskadmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'diskadmin'



select ' use sp_helpsrvrolemember to see the members of a fixed server role dbcreator'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'dbcreator'



select ' use sp_helpsrvrolemember to see the members of a fixed server role bulkadmin'
select '============================================================================'
EXECUTE sp_helpsrvrolemember 'bulkadmin'


select 'Alternatively, to see the members of a fixed server role, you can query the sys.server_role_members catalog view.'
select '================================================================================================================='
USE master;
GO
SELECT SUSER_NAME(SR.role_principal_id) AS ServerRole
, SUSER_NAME(SR.member_principal_id) AS PrincipalName
, SP.sid
FROM sys.server_role_members SR
INNER JOIN sys.server_principals SP
ON SR.member_principal_id = SP.principal_id
WHERE SUSER_NAME(SR.role_principal_id) = 'sysadmin';
GO


*/




/*
Database Principals
=======================
Database principals are the objects that represent users to which you can assign permissions to access databases
or particular objects within a database. Where logins operate at the server level and allow you to perform actions
such as connecting to a SQL Server, database principals operate at the database level and allow you to select or
manipulate data, to perform DDL statements on objects within the database, and to manage users  permissions
at the database level. SQL Server recognizes four types of database principals:
  Database users: Database user principals are the database-level security context under
which requests within the database are executed and are associated with either SQL
Server or Windows logins.
  Database roles: Database roles come in two flavors, fixed and user-defined. Fixed
database roles are found in each database of a SQL Server instance and have databasescoped
permissions assigned to them (such as SELECT permission on all tables or the
ability to CREATE tables). User-defined database roles are those that you can create
yourself, allowing you to manage permissions to securables more easily than if you had to
individually grant similar permissions to multiple database users.
  Application roles: Application roles are groupings of permissions that don t allow
members. Instead, you can  log in  as the application role. When you use an application
role, it overrides all of the other permissions your login would otherwise have, giving you
only those permissions granted to the application role.
*/




/*
Fixing Orphaned Database Users
================================
Problem
You have restored a database to a different server. The database users in the restored database have lost their
association to the server logins. You need to restore the association between login and database user.
Solution
*/


/*
Find broken database users on all databases (SQL logins mapping is broken)
==========================================================================
These users are known as orphaned users because the associated link between the login and user is broken. 
*/

/*
select ' Find broken database users on all databases (SQL logins mapping is broken)  '
select ' ============================================================================'
EXEC master.sys.sp_msforeachdb '
print ''?''
EXEC [?].dbo.sp_change_users_login ''report'''
*/


/*
Find orphaned users in all of the databases (no logins exist for the database users)
====================================================================================
Make sure you ran the previous check and fixed SQL Server logins before running this check.

When you migrate a database to a new server (by using BACKUP/RESTORE, for example), the relationship between
logins and database users can break. A login has a security identifier, which uniquely identifies it on the SQL
Server instance. This sid is stored for the login s associated database user in each database that the login has
access to. Creating another SQL login on a different SQL Server instance with the same name will not re-create
the same sid unless you specifically designated it with the sid argument of the CREATE LOGIN statement.
*/




SET NOCOUNT ON
CREATE TABLE #orph_users (db SYSNAME, username SYSNAME, 
    type_desc VARCHAR(30),type VARCHAR(30))
EXEC master.sys.sp_msforeachdb  
'INSERT INTO #orph_users
 SELECT ''?'', u.name , u.type_desc, u.type
 FROM  [?].sys.database_principals u 
  LEFT JOIN  [?].sys.server_principals l ON u.sid = l.sid 
 WHERE l.sid IS NULL 
  AND u.type NOT IN (''A'', ''R'', ''C'') -- not a db./app. role or certificate
  AND u.principal_id > 4 -- not dbo, guest or INFORMATION_SCHEMA
  AND u.name NOT LIKE ''%DataCollector%'' 
  AND u.name NOT LIKE ''mdw%'' -- not internal users in msdb or MDW databases'


 IF EXISTS
	(  
		SELECT * FROM #orph_users
	)
	BEGIN
		select ' Test 20 : Find orphaned users in all of the databases (no logins exist for the database users)  '
		select ' Drop them or fix them with the following T SQL :  ALTER USER USERNAME  WITH LOGIN = USERNAME;'
		select ' use USERRNAME from the following output . Run it in the DB from the following output '
		SELECT * FROM #orph_users

	END
DROP TABLE #orph_users
GO



 /*
 Beginning with SQL Server 2005 Service Pack 2, you can use the ALTER USER WITH LOGIN command to
remap login/user associations. This applies to both SQL and Windows accounts, which is very useful if the
underlying Windows user or group has been re-created in Active Directory and now has an identifier that no
longer maps to the generated sid on the SQL Server instance.
The following query demonstrates remapping the orphaned database user Sonja to the associated server
login:
USE TestDB;
GO
ALTER USER Apollo WITH LOGIN = Apollo;
GO

The next example demonstrates mapping a database user ([Phoebus]) to the login [ROIS\Phoebus]
(assuming that the user became orphaned from the Windows account or the sid of the domain account was
changed because of a drop/re-create outside of SQL Server):

USE TestDB;
GO
ALTER USER [Phoebus]
WITH LOGIN = [ROIS\Phoebus];
GO
This command also works with remapping a user to a new login whether or not that user is orphaned.

In previous versions of SQL Server, you could use the sp_change_users_login stored procedure to perform
and report on sid remapping. This stored procedure has been deprecated in favor of ALTER USER WITH LOGIN.
*/




/* Securables, Permissions, and Auditing */
/* ===================================== */


/*
Querying sys.server_permissions and sys.server_principals returns all server-scoped permissions for logins.
===========================================================================================================
In the SELECT clause, I returned the class of the permission, the
permission name, and the associated state of the permission.
SELECT p.class_desc, p.permission_name, p.state_desc
In the FROM clause, I joined the two catalog views by the grantee s principal ID. The grantee is the target
recipient of granted or denied permissions
*/

/*
select ' returns all server-scoped permissions for logins '
select '=================================================== ' 
USE master;
GO
SELECT s.name, p.class_desc, p.permission_name, p.state_desc
FROM sys.server_permissions p
INNER JOIN sys.server_principals s
ON p.grantee_principal_id = s.principal_id
order by 1,2,3 ;
GO
*/






/*
Reporting Permissions by Securable Scope
=========================================
Solution
You can report on all permissions for the currently connected user by using the fn_my_permissions function.
In this recipe, I ll demonstrate using the fn_my_permissions function to return the assigned permissions for
the currently connected principal. The syntax for this function is as follows:
fn_my_permissions ( securable , 'securable_class')


 fn_my_permissions Arguments
argument															Description
securable															The name of the securable to verify. Use NULL if you are
																	checking permissions at the server or database scope.

securable_class														The securable class that you are listing permissions for

*/

/*
select ''
select ' Report on all permissions for the currently connected user  '
select ' ============================================================================'
SELECT permission_name
FROM sys.fn_my_permissions(NULL, N'SERVER')
ORDER BY permission_name;
GO

*/


/*
If you have IMPERSONATE permissions on the login or database user, you can also check the permissions of
another principal other than your own by using the EXECUTE AS command. Chapter 19 demonstrated how to
use EXECUTE AS to specify a stored procedure s security context. You can also use EXECUTE AS in a stand-alone
fashion, using it to switch the security context of the current database session. You can then switch back to your
original security context by issuing the REVERT command.
The simplified syntax for EXECUTE AS is as follows:
EXECUTE AS { LOGIN | USER } = 'name' [ WITH { NO REVERT } ]


Argument											Description
{ LOGIN | USER } = 'name'								Select LOGIN to impersonate a SQL or Windows login or USER to impersonate
														a database user. The name value is the actual login or user name.

NO REVERT If NO REVERT									If NO REVERT is designated, you cannot use the REVERT command to switch
														back to your original security context.


To demonstrate the power of EXECUTE AS, the previous query is reexecuted, this time by using the security
context of the Apollo login.
USE master;
GO
EXECUTE AS LOGIN = N'Apollo'
GO
SELECT permission_name
FROM sys.fn_my_permissions(NULL, N'SERVER')
ORDER BY permission_name;
GO
REVERT;
GO
This returns a much smaller list of server permissions, because you are no longer executing the call under a
login with sysadmin permissions.
CONNECT SQL
VIEW ANY DATABASE
This next example demonstrates returning database-scoped permissions for the Apollo database user:
USE TestDB;
GO
EXECUTE AS USER = N'Apollo';
GO
SELECT permission_name
FROM sys.fn_my_permissions(N'TestDB', N'DATABASE')
ORDER BY permission_name;
GO
REVERT;
GO
This query returns the following:
ALTER ANY ASSEMBLY
ALTER ANY CERTIFICATE
CONNECT
CREATE ASSEMBLY
CREATE CERTIFICATE

In this next example, permissions are checked for the current connection on the Production.Culture table,
this time showing any subentities of the table (meaning any explicit permissions on table columns):
USE AdventureWorks2012;
GO
SELECT subentity_name, permission_name
FROM sys.fn_my_permissions(N'Production.Culture', N'OBJECT')
ORDER BY permission_name, subentity_name;
GO
This returns the following results (when the subentity_name is populated, this is a column reference):
subentity_name permission_name
ALTER
CONTROL
DELETE
EXECUTE
INSERT
RECEIVE
REFERENCES
CultureID REFERENCES
ModifiedDate REFERENCES
Name REFERENCES
SELECT
CultureID SELECT
ModifiedDate SELECT
Name SELECT
TAKE OWNERSHIP
UPDATE
CultureID UPDATE
ModifiedDate UPDATE
Name UPDATE
VIEW CHANGE TRACKING
VIEW DEFINITION

How It Works
This recipe demonstrated how to return permissions for the current connection using the fn_my_permissions
function. The first example used a NULL in the first parameter and SERVER in the second parameter in order to
return the server-scoped permissions of the current connection.
FROM sys. fn_my_permissions(NULL, N'SERVER')
I then used EXECUTE AS to execute the same query, this time under the Apollo login s context, which
returned server-scoped permissions for his login.

EXECUTE AS LOGIN = N'Apollo';
GO
REVERT;
GO
The next example showed database-scoped permissions by designating the database name in the first
parameter and DATABASE in the second parameter.
FROM sys.fn_my_permissions(N'TestDB', N'DATABASE')
The last example checked the current connection s permissions to a specific table.
FROM sys.fn_my_permissions(N'Production.Culture', N'OBHECT')
This returned information at the table level and column level. For example, the ALTER and CONTROL
permissions applied to the table level, while those rows with a populated entity_name (for example, CulturelD
and ModifiedDate) refer to permissions at the table s column level.


*/











/*
default trace
=============
In SQL Server, there is a feature enabled by default, which is called the default trace. It is
a continuously running SQL trace that stores its result in the SQL server log directory, in the
log.trc, log_1.trc,  files. 


The default trace logs 30 events to five trace files that work as a First-In, First-Out buffer, with the
oldest fi le being deleted to make room for new events in the next trc fi le.
The default trace fi les live in the SQL Server log folder. Among the SQL Server Error log fi les you can
fi nd fi ve trace fi les. These are just regular SQL Server trace fi les, so you can open them in SQL Profi ler.
The key thing is to have some idea of what events are recorded in the default trace, and remember to
look at it when something happens to SQL Server. The events captured in the default trace fall into
six categories:

Database: These events are for examining data and log fi le growth events, as well as
database mirroring state changes.

Errors and warnings: These events capture information about the error log and query
execution based warnings around missing column stats, join predicates, sorts, and hashes.

Full-Text: These events show information about full text crawling, when a crawl starts,
stops, or is aborted.

Objects: These events capture information around User object activity, specifi cally Create,
Delete, and Alter on any user object. If you need to know when a particular object was
created, altered, or deleted, this could be the place to go look.


Security Audit: This captures events for the major security events occurring in SQL Server.
There is quite a comprehensive list of sub events (not listed here).If you re looking for
security based information, then this should be the fi rst place you go looking.


Server: The server category contains just one event, Server Memory Change. This event
indicates when SQL Server memory usage increases or decreases by 1MB, or 5% of max
server memory, whichever is larger.

You can see these categories by opening one of the default trace fi les in SQL Server Profi ler and
examining the trace fi le properties. By default, you don t have permission to open the trace fi les
while they live in the Logs folder, so either copy the fi le to another location, or alter the permissions
on the fi le that you want to open in profi ler.
When you open the trace fi le properties, you see that for each category all event columns are
selected for all the events in the default trace.

*/



/*
To see the default trace status and to enable it if needed, use the following code:
EXEC sp_configure 'show advanced options', 1;

-- Turn OFF default trace
exec sp_configure  default trace enabled ,  0 
reconfigure with override
go
-- Turn OFF advanced options
exec sp_configure  show advanced options ,  0 
reconfigure with override
go
*/



EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
-- Turn ON  default trace
EXEC sp_configure 'default trace enabled', 1 ;
RECONFIGURE;
EXEC sp_configure 'show advanced options', 0
RECONFIGURE;

/*
The path for the default trace can be found in the trace properties as follows:
*/


select ' Test 020 : Get the current trace rollover file'
SELECT * FROM ::fn_trace_getinfo(0)
/*
What does the output indicate?
Result Set	Description
Traceid				Unique identifier for the trace
Property = 1		Configured trace options 
Property = 2		Trace file name
Property = 3		Max file size for the *.trc file
Property = 4		Stop time for the trace session
Property = 5		Current trace status (1 = On and 0 = Off)
Value				Current value for the traceid\property combination
*/

/*
SELECT value  as 'Default trace path '
FROM sys.fn_trace_getinfo(0)
WHERE property = 2;
*/






/*
Configuring SQL Server auditing
===============================

Server Audit		All editions					Whole server		Security changes at server level    Audit log file


Database audit		Enterprise Edition				Per	database		Security changes at					Audit log file or Windows event log

																		database level and all
																		operations on tables,
																		including SELECT



Choosing Your Audit Type
=========================
SQL Server Audit allows you to monitor your server from two different aspects: at the server level and the
database level. Database level audits are only available in SQL Server 2012 s Enterprise, DataCenter, and
Developer Editions. When trying to determine what kind of audit you want to create, there are a several
things to think about. Use the following list to help you decide which type of audit to create.

Choose a server audit if you want to monitor the following:
  Actions that impact the entire server
  Actions that monitor changes across all databases
  Actions that monitor changes to schemas to all databases


Choose database audit specifications if you want to monitor
  Actions specific to a database, object, or schema
  Specific actions of a principal within a database
  Specific actions (SELECT, DELETE, UPDATE, and other Data Manipulation Language
[DML] statements) within a database

Once you figure out the type of auditing you want to capture the required information, follow the
steps in the next couple of sections to create your audit and store that information.


Creating SQL Server Audits with T-SQL
=========================================
Before you can define server-level or database-level actions to audit, you must create a SQL Server audit,
which is shown in Listing 14-1.
Listing 14-1. Syntax for Creating a SQL Server Audit CREATE SERVER AUDIT audit name
TO { [ FILE (<file_options> [, ...n]) ] | APPLICATI0N_L0G | SECURITY_L0G } [ WITH (
<audit_options> [, ...n] ) ]
WHERE [ < predicate_expresssions]
As you can see from the syntax, creating a SQL Server audit defines the setup information for an
audit. The audit does not contain any information about the actions either at the database level or the
server level within its definition. Actually, server-level and database-level audits must be added to a SQL
Server audit to define how and where the information is captured and stored. Now, let s take a closer
look at the syntax for creating an SQL Server audit.
After you name the audit, determine if you want the captured data written to a file, application log,
or security log. If you decide to write the data to a file, then you need to specify the file path and name,
the maximum size of the file, the number of rollover files, and if you want to reserve the maximum file
size on disk.
The configurable audit options consist of a QUEUE_DELAY, 0N_FAILURE, and AUDIT_GUID. The
QUEUE_DELAY option sets the time that can pass before an audit action processes. The representation of
time is in milliseconds with the minimal and default value of 1000 milliseconds or 1 second. The
ON_FAILURE option decides what to do if the target (location of the audit files) is unreachable. The two
configurable options are CONTINUE and SHUTDOWN. The default value is CONTINUE. The AUDIT_GUID option
allows you to specify the globally unique identifier (GUID) of an existing audit for purposes where the
GUID needs to be the same from environment to environment.
Once you have determined the settings for your SQL Server audit, then creating an audit is fairly
simple and straightforward, as shown in Listing 14-2.
Listing 14-2. SQL Script That Creates a SQL Server Audit
USE master; GO
CREATE SERVER AUDIT exampleAudit
TO FILE
( FILEPATH = 'C:\', MAXSIZE = 1 GB
)
WITH( ON_FAILURE = CONTINUE)
GO



USE [master]

GO

CREATE SERVER AUDIT [Aecurity Audit]
TO FILE 
(	FILEPATH = N'T:\Audit'
	,MAXSIZE = 0 MB
	,MAX_ROLLOVER_FILES = 2147483647
	,RESERVE_DISK_SPACE = OFF
)
WITH
(	QUEUE_DELAY = 1000
	,ON_FAILURE = CONTINUE
)

GO


Creating Server Audit Specifications
In order to audit server-level information, then you have to create a server audit specification. A server
audit specification consists of server-level action groups. We will discuss server-level action groups in
more detail in the next section. For now, just understand that the server-level action groups identify
what you are auditing from a server level. The server audit specifications are tracked across the entire
instance of SQL Server. There are not any boundaries within the SQL Server instance. Because of this
lack of boundaries, you cannot filter down to specific databases within server audits. To create a server
audit specification, use the syntax in the following :

CREATE SERVER AUDIT SPECIFICATION audit_specification_name FOR SERVER AUDIT auditjname
ADD (audit_action_group_name ), ...n,
WITH ( STATE= ON|OFF)
To create the server audit specification, you have to specify which SQL Server audit to associate the
server audit specification to. Once you assign the server specification to the server audit, then you add
the server-level auditactiongroup name to the server audit specification. Once you have added all of the
server-level auditactiongroup names that you want to monitor, determine if you want to enable the
audit during creation. If you don t, then you must enable it when you are ready to capture the actions in
the audit.


Server-Level Action Groups
==============================
Server-level action groups are the predefined groups used to audit your server from a server perspective.
Since server-level action groups are predefined, then you can t customize the actions that each group
captures. The only level of customization you have for a server-level audit comes from deciding which
server-level action groups you add to an audit.
There are a large number of server-level actions groups, so we won t discuss all of them here.
However, we list some of the server-level action groups that we frequently like to use for our server audits.
  Successful_Login_Group: Tracks successful principal logins into the instance of
SQL Server.
  Failed_Login_Group: Identifies unsuccessful principal failures against the instance
of SQL Server.
  Server_Role_Member_Change_Group: Captures the addition and removal of logins
from fixed server roles.
  Database_Role_Member_Change_Group: Tracks the addition and removal of logins to
database roles.
  Server_Object_Change_Group: Captures create, alter, or drop permissions on
server objects.
  Server_Principal_Change_Group: Tracks the creation, deletion, or alteration of
server principals.
  Database_Change_Group: Identifies the creation, alteration, or deletion of databases.
  Database_Object_Change_Group: Captures create, alter, or delete actions against
objects within a database.
  Database_Principal_Change_Group: Tracks the creation, modification, or deletion
of database principals.
  Server_Permission_Change_Group: Identifies when principals grant, revoke, or
deny permissions to server objects.
  Database_Object_Permission_Change_Group: Captures grant, revoke, or deny
permission changes to database objects.
As you can see, server-level audit action groups of SQL Server Audit allow you to monitor a number
of actions that occur from a server level. Please review SQL Server Books Online and search for
 SQLServer Audit Action Groups and Actions  for a complete list of the groups. Understanding the
available options enables you to capture the relevant actions in your environment. If you do not know
what is available to monitor, then chances are good that you will miss something that could have saved
you time when trying to identify the cause of a problem.

Listing  shows an example of creating a server audit specification with server-level audit action
groups.
Listing 14-4. SQL Code That Creates a Server Audit Specification
CREATE SERVER AUDIT SPECIFICATION serverSpec
FOR SERVER AUDIT exampleAudit
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
GO
*/






/*
In order to set up SQL Server Audit, follow these steps:
1. In SSMS Object Explorer, go to the Security node under the instance node,
and right-click on Audits. Click on New audit .


2. There, enter a name for your audit, and add a file path where the audit file will
be written:

3. Click on OK to create the server audit, then right-click on the node right below, named
Server Audit Specifications. Click on New Audit Specification.


4. In the New Audit Specification window, choose a name, bind the specification to the
audit we just created, and add relevant action types:

5. Then, right-click on the audit specification we just created and click on Enable Server
Audit Specification. Right-click on the audit we just created and click on Enable
Server Audit.
6. You can also set audit specification at a database level. Go to a database, in the
security node, and right-click on Database Audit Specifications. Click on New
Database Audit Specification.
Like at server level, you can create only one specification on an
audit per database. So, for an audit, you can have one server audit
specification, and one database audit specification per database.
7. You can then view the audit log by right-clicking on the audit and clicking on View
Audit Log.


Or you can read it from a query by using the sys.fn_get_audit_file() function:
SELECT * FROM sys.fn_get_audit_file
('f:\sqldata\Audit\*', default, default);
This query reads all audit files found in the f:\sqldata\Audit\ directory and
returns them in a recordset.

How it works...
In audit specifications, you add groups of actions. These groups match the profiler Security
Audit event classes we have covered in the Using the profiler to audit SQL Server access
recipe in this chapter. Description of groups and actions is available in the BOL (Books Online)
at SQL Server Audit Action Groups and Actions
(http://msdn.microsoft.com/en-us/library/cc280663.aspx).
Behind the scenes, it uses Extended Events, which is the event
framework that aims to replace SQL trace. Depending on the action groups you chose to audit,
you could end up with large log files, so don't let the log directory go unmonitored.
Depending on your audit policy, you can choose to keep operation SQL server on audit failure
(for example, if the audit log partition is full), or to fail the operation audited with an exception,
and even to shut down the SQL Server service.
Of course, auditing can be created and managed by T-SQL code. The following is an example
of the creation of an audit and its server audit specification:
USE [master];
CREATE SERVER AUDIT [Security Audit]
TO FILE
(FILEPATH = N'f:\sqldata\Audit'
,MAXSIZE = 0 MB
,MAX_ROLLOVER_FILES = 2147483647
,RESERVE_DISK_SPACE = OFF
)


WITH
(QUEUE_DELAY = 1000
,ON_FAILURE = CONTINUE
);
GO
CREATE SERVER AUDIT SPECIFICATION [Security Audit Specification]
FOR SERVER AUDIT [Security Audit]
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
ADD (DATABASE_PERMISSION_CHANGE_GROUP),
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
ADD (DATABASE_OWNERSHIP_CHANGE_GROUP),
ADD (USER_CHANGE_PASSWORD_GROUP)
WITH (STATE = ON);
Audit and audit specifications can be enabled or disabled by a right-click on them in the SSMS
Object Explorer, or by T-SQL, as follows:
-- disable the audit
ALTER SERVER AUDIT [Security Audit] WITH (STATE = OFF);
-- enable the audit
ALTER SERVER AUDIT [Security Audit] WITH (STATE = ON);
Of course, metadata can be queried by catalog views. The following is an example query
illustrating the catalog views and relationships:
SELECT *
FROM sys.server_audits sa
JOIN sys.server_file_audits sfa
ON sa.audit_guid = sfa.audit_guid
JOIN sys.dm_server_audit_status sast
ON sa.audit_id = sast.audit_id
LEFT JOIN sys.server_audit_specifications sas
ON sa.audit_guid = sas.audit_guid
LEFT JOIN sys.server_audit_specification_details sasd
ON sas.server_specification_id =
sasd.server_specification_id
LEFT JOIN marketing.sys.database_audit_specifications das
ON sa.audit_guid = das.audit_guid
LEFT JOIN marketing.sys.database_audit_specification_details dasd
ON das.database_specification_id =
dasd.database_specification_id;

*/


:setvar Audit_data_file_path "t:\sqldata\Audit"
select ' Test 019'
select 'creation of an audit and its server audit specification. Change FILEPATH according to your ENV '



USE [master];
SELECT 'Create the server audit '
select 'Disable and then drop SERVER AUDIT SPECIFICATION and disable then drop SERVER AUDIT    '
USE [master]
GO


IF  EXISTS (SELECT * FROM sys.server_audit_specifications WHERE name = N'Security Audit Specification')
BEGIN
	ALTER SERVER AUDIT SPECIFICATION [Security Audit Specification] WITH (STATE = OFF)
	DROP SERVER AUDIT SPECIFICATION [Security Audit Specification]
END
GO



IF  EXISTS (SELECT * FROM sys.server_audits WHERE name = N'Security Audit')
BEGIN
	ALTER SERVER AUDIT [Security Audit] WITH (STATE = OFF)
	DROP SERVER AUDIT [Security Audit]
END
GO

/*

Audits (General Page) 
===================
Source :  SQL 2008 R2  BOL
  
Audit name 
The name of the audit. This is generated automatically when you create a new audit but is editable.

Queue delay (in milliseconds) 
Specifies the amount of time in milliseconds that can elapse before audit actions are forced to be processed. A value of 0 indicates synchronous delivery. The default minimum value is 1000 (1 second). The maximum is 2,147,483,647 (2,147,483.647 seconds or 24 days, 20 hours, 31 minutes, 23.647 seconds).

Shut down server on audit failure 
Forces a server shut down when the server instance writing to the target cannot write data to the audit target. The login issuing this must have the SHUTDOWN permission. If the logon does not have this permission, this function will fail and an error message will be raised. 

As a best practice, this should only be used in cases where an audit failure could compromise the security or integrity of the system.

Audit destination 
Specifies the target for auditing data. The available options are a binary file, the Windows Application log, or the Windows Security log. SQL Server cannot write to the Windows Security log without configuring additional settings in Windows. For more information, see How to: Write Server Audit Events to the Security Log.

File path 
Specifies the location of the folder where audit data is written when the Audit destination is a file. 



Maximum rollover files 
Specifies the maximum number of audit files to retain in the file system. When the setting of MAX_ROLLOVER_FILES=UNLIMITED, there is no limit imposed on the number of rollover files that will be created. The default value is UNLIMITED. The maximum number of files that can be specified is 2,147,483,647.

Maximum file size (MB) 
Specifies the maximum size, in megabytes (MB), for an audit file. The minimum size that you can specify is 1024 KB and the maximum is 2,147,483,647 terabytes (TB). You can also specify UNLIMITED, which does not place a limit on the size of the file. Specifying a value lower than 1024 KB will raise the error MSG_MAXSIZE_TOO_SMALL. The default setting is UNLIMITED.

Reserve disk space 
Specifies that space is pre-allocated on the disk equal to the specified maximum file size. This setting can only be used if MAXSIZE is not equal to UNLIMITED. The default setting is OFF.

Remarks
When you first create an audit, it is disabled. You should enable the audit after you create a server or database audit specification that uses this audit.

File as Audit Destination
The SQL Server service account must have CREATE FILE permissions on the directory where the audit log file is created.

When File is chosen as the Audit destination, SQL Server Audit generates the audit log file name for you and creates using the path that you specify in File path. This is done to ensure that similarly-named audits do not generate conflicting file names. The audit log file name is constructed using the following elements:

AuditName - The name of the audit provided when the audit is created.


AuditGUID - The GUID that identifies the audit that is stored in the metadata.


PartitionNumber - A number generated by SQL Server Extended Events to partition file sets.


TimeStamp - A 64 bit integer generated by converting the UTC time when the audit file is created.


File extension - sqlaudit



Permissions
To create, alter, or drop a server audit, principals require ALTER ANY AUDIT or CONTROL SERVER permission.
*/


DECLARE @AUDIT_FLAG VARCHAR(100) ;
SELECT @AUDIT_FLAG=
CASE WHEN CONVERT(VARCHAR(100), SERVERPROPERTY('Edition')) LIKE 'Data Center%'
OR CONVERT(VARCHAR(100), SERVERPROPERTY('Edition')) LIKE 'Enterprise%'
OR CONVERT(VARCHAR(100), SERVERPROPERTY('Edition')) LIKE 'Developer%'
THEN 'AUDIT '
ELSE 'NOAUDIT'
END
PRINT @AUDIT_FLAG

:setvar Audit_data_file_path "t:\sqldata\Audit"
select 'Create  SERVER AUDIT [Security Audit]   '
select '======================================== '
CREATE SERVER AUDIT [Security Audit]
TO FILE
(FILEPATH = N't:\sqldata\Audit'
,MAXSIZE = 100 MB
,MAX_ROLLOVER_FILES = 1000
,RESERVE_DISK_SPACE = OFF
)
WITH
(QUEUE_DELAY = 1000
,ON_FAILURE = CONTINUE
);
GO

ALTER SERVER AUDIT [Security Audit] WITH (STATE = OFF)
GO


select 'Create the server audit specification '
CREATE SERVER AUDIT SPECIFICATION [Security Audit Specification]
FOR SERVER AUDIT [Security Audit]
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
ADD (DATABASE_PERMISSION_CHANGE_GROUP),
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
ADD (DATABASE_OWNERSHIP_CHANGE_GROUP)
--ADD (USER_CHANGE_PASSWORD_GROUP)
WITH (STATE = ON);


/*
Audit and audit specifications can be enabled or disabled by a right-click on them in the SSMS
Object Explorer, or by T-SQL, as follows:
*/


-- disable the audit
ALTER SERVER AUDIT [Security Audit] WITH (STATE = OFF);
-- enable the audit
ALTER SERVER AUDIT [Security Audit] WITH (STATE = ON);
/*
Of course, metadata can be queried by catalog views. The following is an example query
illustrating the catalog views and relationships:
*/


/*
To review the contents of the audit, use the fn_get_audit_file function. The following code allows
you to see the results of Listing p. Only if audit was declared  .
*/


USE master;
:setvar Audit_data_file_path "t:\sqldata\Audit"
IF  EXISTS (SELECT * FROM sys.server_audit_specifications WHERE name = N'Security Audit Specification')
BEGIN
IF  EXISTS (SELECT * FROM sys.server_audits WHERE name = N'Security Audit')
		BEGIN
					SELECT event_time,server_principal_name, object_name, statement,* FROM fn_get_audit_file ('t:\sqldata\Audit\*',NULL, NULL)
		END
END
GO



/*
Monitor SQL server
===================
*/



/*
Find failed login events in SQL Server error log
=================================================
This will allow us to search the SQL Server error log for failed logins.  This command below will search the active SQL Server error log.
*/


select 'TEST 21' 
select 'Find failed login events in SQL Server error log'
EXEC master.dbo.xp_readerrorlog 0, 1, "login failed", null, NULL, NULL, N'desc'
/* output example :
LogDate	ProcessInfo	Text
2014-12-17 11:21:42.260	Logon	Login failed for user ''. Reason: An attempt to login using SQL authentication failed. Server is configured for Windows authentication only. [CLIENT: 100.2.104.40]
2014-12-17 11:16:00.700	Logon	Login failed for user ''. Reason: An attempt to login using SQL authentication failed. Server is configured for Windows authentication only. [CLIENT: 100.2.104.40]
2014-12-17 10:54:29.410	Logon	Login failed for user 'phonebook'. Reason: Could not find a login matching the name provided. [CLIENT: 100.2.333.17]
2014-12-17 07:32:51.450	Logon	Login failed for user 'DbUser'. Reason: Password did not match that for the login provided. [CLIENT: 2.99.99.444]
2014-12-17 07:32:51.240	Logon	Login failed for user 'DbUser'. Reason: Password did not match that for the login provided. [CLIENT: 2.99.99.444]
*/







