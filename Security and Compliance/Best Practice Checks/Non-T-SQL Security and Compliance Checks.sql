
SELECT '3.5 Ensure the SQL Server’s MSSQL Service Account is Not an Administrator '  
SELECT '******************************************************************************'


/*
3.5 Ensure the SQL Server’s MSSQL Service Account is Not an
Administrator (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
The service account and/or service SID used by the MSSQLSERVER service for a default
instance or MSSQL$<InstanceName> service for a named instance should not be a member of
the Windows Administrator group either directly or indirectly (via a group). This also
means that the account known as LocalSystem (AKA NT AUTHORITY\SYSTEM) should not be
used for the MSSQL service as this account has higher privileges than the SQL Server
service requires.
Rationale:
Following the principle of least privilege, the service account should have no more
privileges than required to do its job. For SQL Server services, the SQL Server Setup will
assign the required permissions directly to the service SID. No additional permissions or
privileges should be necessary.
Audit:
Verify that the service account (in case of a local or AD account) and service SID are not
members of the Windows Administrators group.
Remediation:
In the case where LocalSystem is used, use SQL Server Configuration Manager to change
to a less privileged account. Otherwise, remove the account or service SID from the
Administrators group. You may need to run the SQL Server Configuration Manager if
underlying permissions had been changed or if SQL Server Configuration Manager was
not originally used to set the service account.
Impact:
The SQL Server Configuration Manager tool should always be used to change the SQL
Server’s service account. This will ensure that the account has the necessary privileges. If
the service needs access to resources other than the standard Microsoft defined directories
and registry, then additional permissions may need to be granted separately to those
resources.
Default Value:
By default, the Service Account (or Service SID) is not a member of the Administrators
group.
References:
1. https://technet.microsoft.com/en-us/library/ms143504(v=sql.120).aspx
CIS Controls:
5.1 Minimize and Sparingly Use Administrative Privileges
Minimize administrative privileges and only use administrative accounts when they are
required. Implement focused auditing on the use of administrative privileged functions
and monitor for anomalous behavior.
*/



SELECT 'Ensure the SQL Server’s SQLAgent Service Account is Not an Administrator'  
SELECT '******************************************************************************'


/*
3.6 Ensure the SQL Server’s SQLAgent Service Account is Not an
Administrator (Scored)
Profile Applicability:
• Level 1 - DatabaseEngine
Description:
The service account and/or service SID used by the SQLSERVERAGENT service for a default
instance or SQLAGENT$<InstanceName> service for a named instance should not be a
member of the Windows Administrator group either directly or indirectly (via a group).
This also means that the account known as LocalSystem (AKA NT AUTHORITY\SYSTEM)
should not be used for the SQLAGENT service as this account has higher privileges than the
SQL Server service requires.
Rationale:
Following the principle of least privilege, the service account should have no more
privileges than required to do its job. For SQL Server services, the SQL Server Setup will
assign the required permissions directly to the service SID. No additional permissions or
privileges should be necessary.
Audit:
Verify that the service account (in case of a local or AD account) and service SID are not
members of the Windows Administrators group.
Remediation:
In the case where LocalSystem is used, use SQL Server Configuration Manager to change
to a less privileged account. Otherwise, remove the account or service SID from the
Administrators group. You may need to run the SQL Server Configuration Manager if
underlying permissions had been changed or if SQL Server Configuration Manager was
not originally used to set the service account.
Impact:
The SQL Server Configuration Manager tool should always be used to change the SQL
Server’s service account. This will ensure that the account has the necessary privileges. If
the service needs access to resources other than the standard Microsoft-defined directories
and registry, then additional permissions may need to be granted separately to those
resources.

If using the auto restart feature, then the SQLAGENT service must be an Administrator.
Default Value:
By default, the Service Account (or Service SID) is not a member of the Administrators
group.
References:
1. https://technet.microsoft.com/en-us/library/ms143504(v=sql.120).aspx
CIS Controls:
5.1 Minimize and Sparingly Use Administrative Privileges
Minimize administrative privileges and only use administrative accounts when they are
required. Implement focused auditing on the use of administrative privileged functions
and monitor for anomalous behavior.
*/



SELECT 'Ensure the  SQL Server’s Full-Text Service Account  is Not an Administrator'  
SELECT '******************************************************************************'


/*
3.7 Ensure the SQL Server’s Full-Text Service Account is Not an
Administrator (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
The service account and/or service SID used by the MSSQLFDLauncher service for a default
instance or MSSQLFDLauncher$<InstanceName> service for a named instance should not be
a member of the Windows Administrator group either directly or indirectly (via a group).
This also means that the account known as LocalSystem (AKA NT AUTHORITY\SYSTEM)
should not be used for the Full-Text service as this account has higher privileges than the
SQL Server service requires.
Rationale:
Following the principle of least privilege, the service account should have no more
privileges than required to do its job. For SQL Server services, the SQL Server Setup will
assign the required permissions directly to the service SID. No additional permissions or
privileges should be necessary.
Audit:
Verify that the service account (in case of a local or AD account) and service SID are not
members of the Windows Administrators group.
Remediation:
In the case where LocalSystem is used, use SQL Server Configuration Manager to change
to a less privileged account. Otherwise, remove the account or service SID from the
Administrators group. You may need to run the SQL Server Configuration Manager if
underlying permissions had been changed or if SQL Server Configuration Manager was
not originally used to set the service account.
Impact:
The SQL Server Configuration Manager tool should always be used to change the SQL
Server’s service account. This will ensure that the account has the necessary privileges. If
the service needs access to resources other than the standard Microsoft-defined directories
and registry, then additional permissions may need to be granted separately to those
resources.

Default Value:
By default, the Service Account (or Service SID) is not a member of the Administrators
group.
References:
1. https://technet.microsoft.com/en-us/library/ms143504(v=sql.120).aspx
CIS Controls:
5.1 Minimize and Sparingly Use Administrative Privileges
Minimize administrative privileges and only use administrative accounts when they are
required. Implement focused auditing on the use of administrative privileged functions
and monitor for anomalous behavior.
*/





SELECT '6.1 Ensure Sanitize Database and Application User Input is Sanitized '
SELECT '**********************************************************************************'


/*
6 Application Development
This section contains recommendations related to developing applications that interface
with SQL Server.
6.1 Ensure Sanitize Database and Application User Input is Sanitized
(Not Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Always validate user input received from a database client or application by testing type,
length, format, and range prior to transmitting it to the database server.
Rationale:
Sanitizing user input drastically minimizes risk of SQL injection.
Audit:
Check with the application teams to ensure any database interaction is through the use of
stored procedures and not dynamic SQL. Revoke any INSERT, UPDATE, or DELETE privileges
to users so that modifications to data must be done through stored procedures. Verify that
there's no SQL query in the application code produced by string concatenation.
Remediation:
The following steps can be taken to remediate SQL injection vulnerabilities:
• Review TSQL and application code for SQL Injection
• Only permit minimally privileged accounts to send user input to the server
• Minimize the risk of SQL injection attack by using parameterized commands and
stored procedures
• Reject user input containing binary data, escape sequences, and comment
characters
• Always validate user input and do not use it directly to build SQL statements
Impact:
Sanitize user input may require changes to application code or database object syntax.
These changes can require applications or databases to be taken temporarily off-line. Any

change to TSQL or application code should be thoroughly tested in testing environment
before production implementation.
References:
1. https://www.owasp.org/index.php/SQL_Injection
CIS Controls:
18.3 Sanitize Input for In-house Software
For in-house developed software, ensure that explicit error checking is performed and
documented for all input, including for size, data type, and acceptable ranges or formats.

*/



/*
Encryption
These recommendations pertain to encryption-related aspects of SQL Server.
7.1 Ensure 'Symmetric Key encryption algorithm' is set to 'AES_128' or
higher in non-system databases (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Per the Microsoft Best Practices, only the SQL Server AES algorithm options, AES_128,
AES_192, and AES_256, should be used for a symmetric key encryption algorithm.
Rationale:
The following algorithms (as referred to by SQL Server) are considered weak or deprecated
and should no longer be used in SQL Server: DES, DESX, RC2, RC4, RC4_128.
Many organizations may accept the Triple DES algorithms (TDEA) which use keying options
1 (3 key aka 3TDEA) or keying option 2 (2 key aka 2TDEA). In SQL Server, these are referred
to as TRIPLE_DES_3KEY and TRIPLE_DES respectively. Additionally, the SQL Server
algorithm named DESX is actually the same implementation as the TRIPLE_DES_3KEY option.
However, using the DESX identifier as the algorithm type has been deprecated and its usage
is now discouraged.
Audit:
Run the following code for each individual user database:
USE [<database_name>]
GO
SELECT db_name() AS Database_Name, name AS Key_Name
FROM sys.symmetric_keys
WHERE algorithm_desc NOT IN ('AES_128','AES_192','AES_256')
AND db_id() > 4;
GO
For compliance, no rows should be returned.
Remediation:
Refer to Microsoft SQL Server Books Online ALTER SYMMETRIC KEY entry:
http://msdn.microsoft.com/en-US/library/ms189440.aspx
Impact:
Eliminates use of weak and deprecated algorithms which may put a system at higher risk of
an attacker breaking the key.
Encrypted data cannot be compressed, but compressed data can be encrypted. If you use
compression, you should compress data before encrypting it.
Default Value:
None
References:
1. https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-symmetric-keytransact-sql
2. http://support.microsoft.com/kb/2162020
CIS Controls:
14.2 Encrypt All Sensitive Information Over Less-trusted Networks
All communication of sensitive information over less-trusted networks should be
encrypted. Whenever information flows over a network with a lower trust level, the
information should be encrypted.
*/


/*
7.2 Ensure Asymmetric Key Size is set to 'greater than or equal to 2048'
in non-system databases (Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
Microsoft Best Practices recommend to use at least a 2048-bit encryption algorithm for
asymmetric keys.
Rationale:
The RSA_2048 encryption algorithm for asymmetric keys in SQL Server is the highest bitlevel
provided and therefore the most secure available choice (other choices are RSA_512
and RSA_1024).
Audit:
Run the following code for each individual user database:
USE <database_name>;
GO
SELECT db_name() AS Database_Name, name AS Key_Name
FROM sys.asymmetric_keys
WHERE key_length < 2048
AND db_id() > 4;
GO
For compliance, no rows should be returned.
Remediation:
Refer to Microsoft SQL Server Books Online ALTER ASYMMETRIC KEY entry:
http://msdn.microsoft.com/en-us/library/ms187311.aspx
Impact:
The higher-bit level may result in slower performance, but reduces the likelihood of an
attacker breaking the key.
Encrypted data cannot be compressed, but compressed data can be encrypted. If you use
compression, you should compress data before encrypting it.
Default Value:
None
References:
1. https://docs.microsoft.com/en-us/sql/t-sql/statements/alter-asymmetric-keytransact-sql
2. http://support.microsoft.com/kb/2162020
CIS Controls:
14.2 Encrypt All Sensitive Information Over Less-trusted Networks
All communication of sensitive information over less-trusted networks should be
encrypted. Whenever information flows over a network with a lower trust level, the
information should be encrypted.

*/



/*
8 Appendix: Additional Considerations
This appendix discusses possible configuration options for which no recommendation is
being given.
8.1 Ensure 'SQL Server Browser Service' is configured correctly (Not
Scored)
Profile Applicability:
• Level 1 - Database Engine
Description:
No recommendation is being given on disabling the SQL Server Browser service.
Rationale:
In the case of a default instance installation, the SQL Server Browser service is disabled by
default. Unless there is a named instance on the same server, there is no typically reason
for the SQL Server Browser service to be running. In this case it is strongly suggested that
the SQL Server Browser service remain disabled.
When it comes to named instances, given that a security scan can fingerprint a SQL Server
listening on any port, it's therefore of limited benefit to disable the SQL Server Browser
service.
However, if all connections against the named instance are via applications and are not
visible to end users, then configuring the named instance to listening on a static port,
disabling the SQL Server Browser service, and configuring the apps to connect to the
specified port should be the direction taken. This follows the general practice of reducing
the surface area, especially for an unneeded feature.
On the other hand, if end users are directly connecting to databases on the instance, then
typically having them use ServerName\InstanceName is best. This requires the SQL Server
Browser service to be running. Disabling the SQL Server Browser service would mean the
end users would have to remember port numbers for the instances. When they don't that
will generate service calls to IT staff. Given the limited benefit of disabling the service, the
trade-off is probably not worth it, meaning it makes more business sense to leave the SQL
Server Browser service enabled.

Audit:
Check the SQL Browser service's status via services.msc or similar methods.
Remediation:
Enable or disable the service as needed for your environment.
Default Value:
The SQL Server Browser service is disabled if only a default instance is installed on the
server. If a named instance is installed, the default value is for the SQL Server Browser
service to be configured as Automatic for startup.
CIS Controls:
9.1 Limit Open Ports, Protocols, and Services
Ensure that only ports, protocols, and services with validated business needs are running
on each system.
*/
