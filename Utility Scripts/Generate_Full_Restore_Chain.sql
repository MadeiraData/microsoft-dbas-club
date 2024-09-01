/*
This stored procedure creates Restore commands for a database that was backuped using Full / Diff / Log method.
Alternative ways to use this stored Procedure And get the restore commands in the "Messages" pane:
Exec	P_RestoreDB @DB='MyDB';
Exec	P_RestoreDB @DB='MyDB',@DataPath='D:\Data\',@LogPath='L:\Log\';
You can automatically execute the restore command by assigning @JustPrint=0 (not recommended).

Author: Geri Reshef
Date: 2024-09-01
*/
CREATE OR ALTER PROC P_RestoreDB
		@DB Sysname = Null,
		@NewDB Sysname=Null,
		@DataPath Varchar(4000)=Null,
		@LogPath Varchar(4000)=Null,
		@JustPrint Bit=1
AS
Declare	@SQL Varchar(Max);
Set		@DB=IsNull(@DB,DB_Name())
Set		@NewDB=IsNull(@NewDB,Concat(@DB,'_',Format(GetDate(),'yyyyMMdd_HHmmss')));

If		@DataPath Is Null
		Select	Top (1) @DataPath=Stuff(filename,Len(filename)-CharIndex('\',Reverse(filename))+2,CharIndex('\',Reverse(filename))-1,'')
		From	sys.sysaltfiles
		Where	dbid=DB_ID(@DB)
				And filename Like '%.mdf';

If		@LogPath Is Null
		Select	Top (1) @LogPath=Stuff(filename,Len(filename)-CharIndex('\',Reverse(filename))+2,CharIndex('\',Reverse(filename))-1,'')
		From	sys.sysaltfiles
		Where	dbid=DB_ID(@DB)
				And filename Like '%.ldf';

Declare	@LastFull DateTime;
Select Top (1) @LastFull=backup_start_date
From	msdb.dbo.backupset
Where	database_name=@DB
		And type='D'
Order By backup_start_date Desc;

Declare	@LastDiff DateTime;
Select Top (1) @LastDiff=backup_start_date
From	msdb.dbo.backupset
Where	database_name=@DB
		And type='I'
Order By backup_start_date Desc;

Declare	@LastLog DateTime;
Select Top (1) @LastLog=backup_start_date
From	msdb.dbo.backupset
Where	database_name=@DB
		And type='L'
Order By backup_start_date Desc;

DECLARE Cr CURSOR LOCAL FAST_FORWARD FOR
With T As
(Select	B.database_name,
		Case B.type When 'D' Then 'Database'
				When 'I' Then 'Differential database'
				When 'L' Then 'Log'
				When 'F' Then 'File or filegroup'
				When 'G' Then 'Differential file'
				When 'P' Then 'Partial'
				When 'Q' Then 'Differential partial'
				Else Null
				End BackupType,
		MF.physical_device_name,
		B.backup_set_id,
		Max(Iif(B.type='D',B.backup_start_date,Null)) Over() LastFullBackup,
		Max(Iif(B.type='I',B.backup_start_date,Null)) Over() LastDiffBackup,
		Max(Iif(B.type='L',B.backup_start_date,Null)) Over() LastLogBackup,
		B.backup_start_date
From	msdb.dbo.backupset B
Left Join msdb.dbo.backupmediafamily MF
		On B.media_set_id=MF.media_set_id
Where	B.backup_start_date >= @LastFull
		And B.database_name=@DB)
Select	Case T.BackupType
			When 'Database' Then Concat('RESTORE DATABASE ', QUOTENAME(@NewDB),' FROM DISK=''',physical_device_name,''' ',Iif(@LastFull>Isnull(@LastDiff,0) And @LastFull>Isnull(@LastLog,0),'WITH RECOVERY','WITH NORECOVERY'),',',OA1.Mv,';')
			When 'Differential database' Then Concat('RESTORE DATABASE ',QUOTENAME(@NewDB),' FROM DISK=''',physical_device_name,''' ',Iif(@LastDiff>IsNull(@LastLog,0),'WITH RECOVERY','WITH NORECOVERY'),';')
			When 'Log' Then Concat('RESTORE LOG ',QUOTENAME(@NewDB),' FROM DISK=''',physical_device_name,'''',Iif(T.LastLogBackup=T.backup_start_date,'',' WITH NORECOVERY'),';')
			End SQL
From	T
Outer Apply (Select String_Agg(Concat('MOVE ''',logical_name,''' TO ''',Iif(F.file_type='D',@DataPath,@LogPath),Concat(logical_name,'_',Format(GetDate(),'yyyyMMdd_HHmmss')),Iif(F.file_type='D','.mdf','.ldf'),''''),',') Mv
			From	msdb.dbo.backupfile F
			Where	F.backup_set_id=T.backup_set_id) OA1
Where	1=1
		And ((T.BackupType='Database' And T.backup_start_date>=T.LastFullBackup)
			Or (T.BackupType = 'Differential database' And T.backup_start_date>=T.LastDiffBackup And T.backup_start_date>=T.LastFullBackup)
			Or (T.BackupType = 'Log' And T.backup_start_date>=ISNULL(T.LastDiffBackup, T.LastFullBackup)))
Order By T.database_name,
		T.backup_start_date;

Open Cr;
Fetch Next From Cr Into @SQL;
While	@@Fetch_Status=0
		Begin
		If		@JustPrint=1
				Print(@SQL);
		Else
				Exec(@SQL);
		Fetch	Next From Cr Into @SQL;
		End

Close	Cr;
Deallocate Cr;
Go