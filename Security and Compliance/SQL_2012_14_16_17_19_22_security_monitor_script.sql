/**************************************************************************************
Script Name		SQL_2012_14_16_17_19_22_security_monitor_script.sql
Author:			Dadid Itshak 


Purpose :		Monitor  SQL 2012/14/16/17/19  using trace file for 
				SQL SERVER – Who Dropped Table or Database?
				Find failed login events in SQL Server error log and trace files 
				Get the List of Logins Having System Admin


			
Usage  :	Run this script From Microsot SQL Server Management Studio 
				as server role sysadmin in SQL Server . 
		
				


Author:			David Itshak 
Email :			shaked19@gmail.com			
Date Created:	01/12/2015

Modification History:
Date          	Who              What

Author:			David Itshak 
Email :					
Date Created:	01/12/2015

Modification History:
Date          	Who              What

=============  ===============  ===================================================================
13/1/2015		David	itshak	Created Ver 1 
16/2/2015		David	itshak  Updated Ver 2 
16/7/2020		David	itshak  Updated Ver 3
      
*/

--Optional :  Change this var by find and replace D:\sqldata\Audit with you audit data dir (example I:\sqldata\Audit)
-- :setvar Audit_data_files_path "t:\sqldata\Audit"

-- Do not show rowcounts in the results
SET NOCOUNT ON;

SELECT value  as 'Default trace path '
FROM sys.fn_trace_getinfo(0)
WHERE property = 2;


/*
SQL SERVER – SSMS: Configuration Changes History
====================================================
This SSMS report, it is second in the list from Server node -> Standard reports.
Purpose of the  report:  
Changes made to Server Configuration using sp_configure
Changes to trace flags (Enable or Disable) done via T-SQL

The information from this report is fetched from “default trace” which runs by default in every SQL installation. 
If the default setting is disabled enable it as follows : 

sp_configure 'default trace enabled', 1
GO
RECONFIGURE WITH override
GO
*/

/*
Report uses fn_trace_gettable to read default trace and get event class 22 and 116.
*/


SELECT name
FROM sys.trace_events
WHERE trace_event_id IN (22, 116)
/*
ErrorLog
Audit DBCC Event
*/

/*
From the trace events, it means whenever a change is made using DBCC TraceStatus or sp_configure, 
they are recorded in default trace under “ErrorLog” and “Audit DBCC Event”.
*/



/*
SQL SERVER – SSMS: Schema Change History Report
https://blog.sqlauthority.com/2014/07/07/sql-server-ssms-schema-change-history-report/


How can I know, who created/dropped/altered the database?
How can I know, who created/dropped/altered the objects?

?
The report location can be found from Server node -> Right Click -> Reports -> Standard Reports -> “Schema Changes History”.
One problem in the report is, even if one database is inaccessible, it would give error and fails to report anything for remaining databases.


When  default trace disabled use the following query 
====================================================
look at each database and find objects which were created or altered in last 7 days

use <DB_name>
GO
SELECT o.name AS OBJECT_NAME,
o.type_desc,
o.create_date,
s.name AS schema_name
FROM sys.all_objects o
LEFT OUTER JOIN sys.schemas s
ON ( o.schema_id = s.schema_id)
WHERE create_date > ( GETDATE() - 7);

Output example : 
OBJECT_NAME								type_desc										create_date	schema_name
=====================					=================================				============================
fnGetLicensedDevices					SQL_INLINE_TABLE_VALUED_FUNCTION				2020-06-10 19:25:31.060	dbo
sp_ClearDeviceLicense					SQL_STORED_PROCEDURE							2020-06-10 19:25:31.240	dbo
DF__pnConfGue__sendP__0757E033			DEFAULT_CONSTRAINT								2020-06-10 19:25:33.857	dbo
pnSysSwitchControllerBrands				USER_TABLE										2020-06-10 19:25:34.427	dbo
PK_pnSysSwitchControllerBrands			PRIMARY_KEY_CONSTRAINT							2020-06-10 19:25:34.460	dbo

*/


/*
SQL SERVER – Who Dropped Table or Database?
===========================================
https://blog.sqlauthority.com/2015/09/12/sql-server-who-dropped-table-or-database/
Who dropped table in the database? From which application? When?
Who dropped database? What was the date and time?
Who created database on production server?
Who altered the database?
Who dropped the schema?
Who altered the schema?

Here are few usage of default traces which are via SSMS.

SQL SERVER – SSMS: Configuration Changes History

SQL SERVER – SSMS: Schema Change History Report 

*/
select 'Events captured by the default trace'

SELECT DISTINCT Trace.EventID, TraceEvents.NAME AS Event_Desc
FROM   ::fn_trace_geteventinfo(1) Trace
,sys.trace_events TraceEvents
WHERE Trace.eventID = TraceEvents.trace_event_id

select 'Find who  ho dropped / created or altered object in database or database itself.'
select 'read all available traces.'
DECLARE @current VARCHAR(500);
DECLARE @start VARCHAR(500);
DECLARE @indx INT;
SELECT @current = path
FROM sys.traces
WHERE is_default = 1;
SET @current = REVERSE(@current)
SELECT @indx = PATINDEX('%\%', @current)
SET @current = REVERSE(@current)
SET @start = LEFT(@current, LEN(@current) - @indx) + '\log.trc';
-- CHNAGE FILER AS NEEDED
SELECT CASE EventClass
WHEN 46 THEN 'Object:Created'
WHEN 47 THEN 'Object:Deleted'
WHEN 164 THEN 'Object:Altered'
END, DatabaseName, ObjectName, HostName, ApplicationName, LoginName, StartTime
FROM::fn_trace_gettable(@start, DEFAULT)
WHERE EventClass IN (46,47,164) AND EventSubclass = 0 AND DatabaseID <> 2
ORDER BY StartTime DESC






/*
Find failed login events in SQL Server error log
=================================================
This will allow us to search the SQL Server error log for failed logins.  This command below will search the active SQL Server error log.
*/


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


/*
Finding the Details Missing from the SQL Server Failed Logins Audit
===================================================================
https://eitanblumin.com/2020/03/09/finding-details-missing-sql-server-failed-logins-audit/

failed logins  are logged in the SQL Server error log. 
Details are limited to an IP address and, in the best-case scenario, a username.

The  default server trace also records information about failed login events ncludes very useful information such as the client hostname, 
program name, login name, target database, and even the host process ID.

To get ll the “Login Failed” event types  from the default server trace,  query all the events with EventClass=20. 

*/


SELECT  trc.*
FROM fn_trace_getinfo(default) AS inf
CROSS APPLY fn_trace_gettable (convert(nvarchar(255), inf.value),default ) AS trc
WHERE inf.property = 2
AND trc.EventClass= 20 
ORDER BY trc.StartTime DESC


/*
example : 
TextData	BinaryData	DatabaseID	TransactionID	LineNumber	NTUserName	NTDomainName	HostName	ClientProcessID	ApplicationName	LoginName	SPID	Duration	StartTime	EndTime	Reads	Writes	CPU	Permissions	Severity	EventSubClass	ObjectID	Success	IndexID	IntegerData	ServerName	EventClass	ObjectType	NestLevel	State	Error	Mode	Handle	ObjectName	DatabaseName	FileName	OwnerName	RoleName	TargetUserName	DBUserName	LoginSid	TargetLoginName	TargetLoginSid	ColumnPermissions	LinkedServerName	ProviderName	MethodName	RowCounts	RequestID	XactSequence	EventSequence	BigintData1	BigintData2	GUID	IntegerData2	ObjectID2	Type	OwnerID	ParentName	IsSystem	Offset	SourceDatabaseID	SqlHandle	SessionLoginName	PlanHandle	GroupID
Login failed for user 'RF\RF16CP1$'. Reason: Could not find a login matching the name provided. [CLIENT: <local machine>]	NULL	1	NULL	NULL	RF16CP1$	RF	RF16CP1	4516	.Net SqlClient Data Provider	RF\RF16CP1$	436	NULL	2020-06-17 15:29:04.353	NULL	NULL	NULL	NULL	NULL	NULL	1	NULL	0	NULL	NULL	RF16CSQLP	20	NULL	NULL	5	18456	NULL	NULL	NULL	master	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	NULL	0	NULL	47038278	NULL	NULL	NULL	NULL	NULL	1	NULL	NULL	NULL	NULL	NULL	NULL	RF\RF16CP1$	NULL	NULL
*/


 Select ' Get the List of Logins Having System Admin '

SELECT 'Name' = sp.name
    ,sp.is_disabled AS [Is_disabled]
FROM sys.server_role_members rm
    ,sys.server_principals sp
WHERE rm.role_principal_id = SUSER_ID('sysadmin')
    AND rm.member_principal_id = sp.principal_id
	and sp.sid <> 0x01
	and sp.name not like 'NT SERVICE\%'
	and sp.name not in 
	(
		-- Optional : exclude known DBA team , SCOM service  , Commvault SQL Server virtual account, etc. 
		'ORG-DOM\SVC_COMMVAULT' , 'ORG-DOM\sqladmin' , 'NT AUTHORITY\SYSTEM'
	)
