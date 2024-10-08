/*
This is an example script for restoring an encrypted database backup.
*/
:setvar MasterKeyPassword paste_password_here
USE [master]
GO
OPEN MASTER KEY DECRYPTION BY PASSWORD = '$(MasterKeyPassword)';
GO
RESTORE HEADERONLY FROM 
DISK = 'F:\MyDB_FULL_20200602_233000.bak'
WITH FILE = 1;
GO
RESTORE FILELISTONLY FROM 
DISK = 'F:\MyDB_FULL_20200602_233000.bak'
WITH FILE = 1;
GO
RESTORE DATABASE MyDB FROM 
DISK = 'F:\MyDB_FULL_20200602_233000.bak'
WITH MOVE 'MyDB_Data' TO 'F:\data\MyDB_Data.mdf',
     MOVE 'MyDB_Log'  TO 'G:\log\MyDB_Log.ldf',
FILE = 1, STATS = 5;
GO
CLOSE MASTER KEY;
GO