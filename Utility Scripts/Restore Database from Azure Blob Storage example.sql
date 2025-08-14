use [master]
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'EnterStrongPasswordHere';
GO
-- Example:
CREATE CREDENTIAL [https://msfttutorial.blob.core.windows.net/containername]
WITH IDENTITY='SHARED ACCESS SIGNATURE'
 , SECRET = 'sv=2023-11-03&spr=https&st=2025-08-05T10%3A46%3A03Z&se=2025-08-06T10%3A46%3A03Z&sr=b&sp=r&sig=sharedaccesssignature'
GO
RESTORE DATABASE MyDB
FROM URL = 'https://msfttutorial.blob.core.windows.net/containername/MyDB.bak'
GO
