<#    


.SYNOPSIS
    This script initializes a Transactional Replication subscriber from a backup.
    This script assumes a publication already exists.
    This script assumes the publication is hosted by a DisPub, that is the Distributor and the Publisher components are installed on the same instance.
    
    https://learn.microsoft.com/en-us/sql/relational-databases/replication/initialize-a-transactional-subscription-from-a-backup?view=sql-server-ver16

.DESCRIPTION
    The scripts peforms the following steps:
     1. Set the publication(s) immediate_sync proprty to True.
     2. Takes a full database backup of the Published database at the Publisher.
     3. Restores the full database backup of the Published database at the Subscriber.
     4. Delete the current Distribution Agent jobs at the Distribuor.
     5. Creates Push subscriptions at the Distribuor.
     6. Drops any DDL triggers at the subscription database at the Subscriber.
     7. Set the recovery model to SIMPLE at the subscription database at the Subscriber.
     8. Drops any DML triggers at the subscription database at the Subscriber.
     9. Drops any FKs at the subscription database at the Subscriber.
    10. Set the idenity property of all identity columns as NFR (Not For Replication) at the subscription database at the Subscriber.
    11. Change the job owner of the Distribution Agent jobs at the Distribuor to sa.


    Key Features (by piority):    
    Prevents human errors.
    Lets you seat back relaxed while staring at the screen.


.PARAMETER 
    [string]$publisher
    The publisher sql server instance.

.PARAMETER 
    [string]$subscriber
    The subscriber sql server instance.

.PARAMETER 
    [string]$publisher_database 
    The published database located at the Publisher.

.PARAMETER 
    [string]$subsciber_database 
    The subsciber database located at the Subscriber.

.PARAMETER 
    [int]$number_of_backup_files
    The number of files to be used as the backup destination in the DISK clause.
    If the IO subsystem permits a backup to multiple files speeds the backup/restore time.

.PARAMETER 
    [string]$backup_path
    The backup path for the backup destination.

.PARAMETER 
    [switch]$execute
    When specified all commands will be executed.
    When ommited all commands will be printed and nothing gets executed.

    

.EXAMPLE    
    Printing commands only since the -execute switch is ommited.
    .\replication_Inititialize_from_backup.ps1 -publisher serverA -subscriber serverB -publisher_database DBA -subscriber_database DBA -number_of_backup_files 4 -backup_path 'B:\Backup'

    Printing and executing commands since the -execute switch is specified.
    .\replication_Inititialize_from_backup.ps1 -publisher serverA -subscriber serverB -publisher_database DBA -subscriber_database DBA -number_of_backup_files 4 -backup_path 'B:\Backup' -execute


.NOTES
    Author: Yaniv Etrogi - 20241125
    License: MIT
    Version: 2.0       

#>

param
(
    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=0)] 
    [string]$publisher,

    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=1)] 
    [string]$subscriber,

    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=2)] 
    [string]$publisher_database,

    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)] 
    [string]$subscriber_database,

    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)] 
    [int]$number_of_backup_files = 10,

    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=5)] 
    [string]$backup_path,

    [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)] 
    [switch]$execute

)



Begin
{
    [string]$newline = [System.Environment]::NewLine;

    # Add a back slash at the end of the path if needed.
    if(-not ($backup_path[-1] -eq '\')) {$backup_path += '\';}


    # Construct the DISK bit for the backup/restore.
    for($i=1; $i -le $number_of_backup_files; $i++)
    {    
        [string]$backup_file = "$($publisher_database)_FULL_$i.bak";

        if($i -eq 1)
        {
            $path += ' DISK = ''' + $backup_path + $backup_file + '''' + $newline;
        }
        else
        {
            # Add a comma before DISK
            $path += ',DISK = ''' + $backup_path + $backup_file + '''' + $newline;
        }    
    }
}


Process
{
    try
    {
        # 1.
        # immediate_sync
        [string]$query = 'SELECT * FROM syspublications;';
        if($execute) {$publications = Invoke-Sqlcmd -ServerInstance $publisher -Database $publisher_database -Query $query; }
        foreach($publication in $publications)
        {
            [string]$query = 'EXEC sp_changepublication @publication = ''{0}'', @property = ''immediate_sync'', @value = ''true'';' -f $publication.name;
            Write-Host $query -ForegroundColor Green;
            if($execute) {Invoke-Sqlcmd -ServerInstance $publisher -Database $publisher_database -Query $query };
        }

        
        # 2.
        # Backup.
        $query = 
        "BACKUP DATABASE $($publisher_database) TO $($newline)$($path) WITH COMPRESSION;";
        Write-Host $query -ForegroundColor Green;
        if($execute) {Invoke-Sqlcmd -ServerInstance $publisher -Database master -Query $query -QueryTimeout 9999};

        
        # 3.
        # Restore.
        $query = 
        "USE [$($subscriber_database)]; ALTER DATABASE [$($subscriber_database)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        USE master;
        RESTORE DATABASE [$($subscriber_database)] FROM $($newline)$($path) WITH REPLACE;";
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database master -Query $query -QueryTimeout 9999};


        # 4.
        # Remove old distribution agent jobs at the distributor.
        $query =
        'SELECT j.name from msdb.dbo.sysjobs j WHERE j.category_id = 10 AND name LIKE ''REPL-%''';
        Write-Host $query -ForegroundColor Green;
        if($execute) {$jobs = Invoke-Sqlcmd -ServerInstance $publisher -Database msdb -Query $query; }
        foreach($job in $jobs)
        {   
            $query = 'EXEC sp_delete_job @job_name = ''{0}''' -f $job.name;
            Write-Host $query -ForegroundColor Green;
            if($execute) {Invoke-Sqlcmd -ServerInstance $publisher -Database msdb -Query $query; }
        }


        # 5.
        # Create Push subscriber at the distributor
        foreach($publication in $publications)
        {  
            $query = 
            'DECLARE @publication sysname = ''{0}'', @subscriber sysname = ''{1}'', @destination_db sysname = ''{2}''
            EXEC sp_addsubscription 
		             @publication 			= @publication
		            ,@subscriber  			= @subscriber
		            ,@article	 			= ''all''
		            ,@destination_db   		= @destination_db
		            ,@sync_type				= N''initialize with backup''
		            ,@backupdevicename		= N''\\admonissqlprod\Backup\ADMONISSQLPROD\AMS\AMS_FULL_1.bak''
		            ,@backupdevicetype		= N''Disk''
		            ,@subscription_type 	= N''push''
		            ,@update_mode			= N''read only''
		            ,@subscriber_type		= 0
		            ,@subscriptionstreams	= 1;		

            EXEC sp_addpushsubscription_agent 
		             @publication				    = @publication
		            ,@subscriber				    = @subscriber
		            ,@subscriber_db				    = @destination_db
		            ,@enabled_for_syncmgr		    = N''False''
		            ,@dts_package_location		    = N''Distributor''
		            ,@subscriber_security_mode      = 0
		            ,@subscriber_login				= N''ReplUser''
		            ,@subscriber_password			= N''ReplUser123''
		            ,@frequency_type				= 4		
		            ,@frequency_interval			= 1	
		            ,@frequency_relative_interval	= 0
		            ,@frequency_recurrence_factor	= 0	
		            ,@frequency_subday				= 4		
		            ,@frequency_subday_interval 	= 1 		
		            ,@active_start_time_of_day		= 0
		            ,@active_end_time_of_day		= 235959
		            ,@active_start_date				= 0
		            ,@active_end_date				= 0;' -f $publication.name, $subscriber, $subscriber_database;
  
            Write-Host $query -ForegroundColor Green;
            if($execute) {Invoke-Sqlcmd -ServerInstance $publisher -Database $publisher_database -Query $query -QueryTimeout 9999; }
        }

        
        # 6.
        # Drop DDL triggers at the subscriber
        $query = 
        'SELECT name FROM sys.triggers WHERE is_ms_shipped = 0 AND parent_class_desc = ''DATABASE'';';
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {$ddl_triggers = Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        foreach($ddl_trigger in $ddl_triggers)
        {   
            $query = "DROP TRIGGER [$($ddl_trigger)] ON DATABASE;";
            Write-Host $query -ForegroundColor Yellow;
            if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        }

        
        # 7.
        # recovery simple
        $query = 
        'ALTER DATABASE [{0}] SET RECOVERY SIMPLE;' -f $subscriber_database;
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        

        # 8.
        # Drop DML triggers.
        $query = 
        'SELECT 
	        ''DROP TRIGGER '' + schema_name(t.schema_id) + ''.'' + tr.name AS command 
        FROM sys.triggers tr
        JOIN sys.tables t ON t.object_id = tr.parent_id;';
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {$triggers = Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        foreach($trigger in $triggers)
        {   
            $query = $trigger.command;
            Write-Host $query -ForegroundColor Yellow;
            if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        }


        # 9.
        # Drop FKs.
        $query =
        'SELECT 
	        ''ALTER TABLE ['' + SCHEMA_NAME(a.schema_id) + ''].['' + object_name(a.parent_object_id) + ''] DROP CONSTRAINT ['' + a.name + ''];''  AS command 
        FROM sys.foreign_keys a
        INNER JOIN sys.foreign_key_columns b ON a.object_id = b.constraint_object_id
        ORDER BY OBJECT_NAME(a.parent_object_id);';
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {$fks = Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        foreach($fk in $fks)
        {   
            $query = $fk.command;
            Write-Host $query -ForegroundColor Yellow;
            if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        }
        

        # 10.
        # Identity NFR.
        $query =
        'EXEC sp_msforeachtable @command1 = ''DECLARE @int int; SET @int = OBJECT_ID("?") EXEC sys.sp_identitycolumnforreplication @int, 1''';
        Write-Host $query -ForegroundColor Yellow;
        if($execute) {Invoke-Sqlcmd -ServerInstance $subscriber -Database $subscriber_database -Query $query; }
        

        # 11.
        # change Distribution Agent job owner to sa at the Distributor.
        $query =
        'SELECT j.name from msdb.dbo.sysjobs j WHERE j.category_id = 10 AND owner_sid <> 0x01';
        Write-Host $query -ForegroundColor Green;
        if($execute) {$jobs = Invoke-Sqlcmd -ServerInstance $publisher -Database msdb -Query $query; }
        foreach($job in $jobs)
        {   
            $query = 'EXEC msdb.dbo.sp_update_job @job_name=N''{0}'', @owner_login_name=N''sa'';' -f $job.name;
            Write-Host $query -ForegroundColor Green;
            if($execute) {Invoke-Sqlcmd -ServerInstance $publisher -Database msdb -Query $query; }
        }


        Write-Host 'After the queued commands have been delivered set @immediate_sync back to false to reduce distribution database size.' -ForegroundColor Cyan;
    }

    catch
    {
        $exception = $_.Exception.Message;
        Write-Host -ForegroundColor Red $exception;
    }
}

