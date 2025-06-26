USE [master]
GO
IF (SELECT parent_directory_exists FROM sys.dm_os_file_exists('C:\SQLAuditLogs')) = 0
    EXEC xp_create_subdir 'C:\SQLAuditLogs'
GO
-- 1. Create the Server Audit with a filter on object_name
CREATE SERVER AUDIT Audit_XpCmdshell
TO FILE (
    FILEPATH = 'C:\SQLAuditLogs\',
    MAXSIZE = 100 MB,
    MAX_FILES = 50,
    RESERVE_DISK_SPACE = OFF
)
WITH (ON_FAILURE = CONTINUE)
WHERE 
    object_name = 'xp_cmdshell';
GO

ALTER SERVER AUDIT Audit_XpCmdshell WITH (STATE = ON);

GO
-- 2. Create the Audit Specification
CREATE SERVER AUDIT SPECIFICATION AuditSpec_XpCmdshell
FOR SERVER AUDIT Audit_XpCmdshell
ADD (SCHEMA_OBJECT_ACCESS_GROUP)
WITH (STATE = ON);

GO

-- 3. View audit entries related to xp_cmdshell
SELECT
    event_time,
    action_id,
    succeeded,
    session_id, server_principal_name, client_ip, application_name, host_name,
    object_name,
    statement
FROM sys.fn_get_audit_file('C:\SQLAuditLogs\Audit_XpCmdshell*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time DESC;
GO
