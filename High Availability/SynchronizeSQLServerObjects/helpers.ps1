
function Write-Log 
{
    [CmdletBinding()]
    param
    (
        [Parameter()] [ValidateNotNullOrEmpty()] 
        [string]$Message, 
        [Parameter()] [ValidateNotNullOrEmpty()] [ValidateSet('Info','Warn','Error')] 
        [string]$Severity = 'Info'
    )

 
    [PSCustomObject]@{
        Time = (Get-Date -f g)
        Message = $Message
        Severity = $Severity
    } | Export-Csv -Path "$PSScriptRoot\LogFile.csv" -Append -NoTypeInformation;
 }


function Write-Message
{
    [CmdletBinding()]
    [Alias()]    
    [OutputType([string])]
    Param
    (   
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=0)] [ValidateSet('Info','Warn','Error')] 
        [string]$Severity = 'Info',

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] 
        [string]$Text,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=2)]
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=3)]
        [Switch]$LogToFile,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=4)]
        [string]$LogFileName,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=5)]
        [switch]$LogToConsole

    )
    Begin
    {
        try
        {
            [bool]$user_interactive = [Environment]::UserInteractive;


            # If this is not a user session and we do not log to file exit here.
            if(-not $user_interactive -and $LogToFile -eq $false ) {return; }


            [string]$dt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss');

            # Different padding for Error sevirity because it is 1 char longer than Info.
            if ($Severity -eq 'Error' )
            {
                [string]$message = '{0}  {1} {2}' -f $dt, $Severity, $Text; 
            }
            else
            {
                [string]$message = '{0}  {1}  {2}' -f $dt, $Severity, $Text; 
            }

            

            if ($user_interactive) {Write-Host -ForegroundColor $ForegroundColor $message; };   


            
            if ($LogToFile) 
            {
                #[string]$log_file = $LogFile;
                #[string]$log_file_full_name = '{0}\{1}' -f $PSScriptRoot, $LogFileName;
                                
                
                if (Test-Path -Path $LogFileName)
                {
                    Add-Content -Path $LogFileName -Value $message;
                }
                else
                {
                     Set-Content -Path $LogFileName -Value $message;
                }
            }        
        }
        catch
        {       
            throw;
        }
    }
}


function get-files-count
{
    [CmdletBinding()]
    [Alias()]    
   
    Param
    (    
         [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] [string]$path       
        ,[Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)] [ValidateNotNullOrEmpty()] [string[]]$files_exentions      
    )
    Begin
    {
        try
        {   
            foreach($file_ext in $files_exentions)    
            {       
                $files_count += (Get-ChildItem $path -recurse -include $file_ext | Measure-Object ).Count;

            }
                    
            return $files_count;                              
        }
        catch
        {       
            throw;
        }
    }
}

<#
    20220209 Yaniv Etrogi
    
    Move files that were already copied by the log shipping copy job from the log shipping folder located at the Primary server to the backup folder located at the Primary server where they get uploaded to Amazone s3.

#>
function copy-log-shipping-files
{
    [CmdletBinding()]
    [Alias()]    
   
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] 
        [string]$database_name       
    )
    Begin
    {
        try
        {
            Set-Location C:
            $UserInteractive = [Environment]::UserInteractive;

            [string]$helpers_file_full_name = Join-Path $PSScriptRoot 'helpers.ps1';
            . $helpers_file_full_name;

            $source_path = Join-Path 'B:\LogShipping' $database_name;
            $destination_path = Join-Path 'B:\Backup' $database_name;            
            
            $server  = 'DB30'; # secondary log shipping server
            $database = 'msdb';            
            $query = 'EXEC DBA.dbo.get_log_shipping_details @database = ''Billing'''; 
            $command_type = 'DataSet';
            $sql_login = 'sql_server_agent_jobs_owner';
            $sql_password = '9t1h7DG89r$Sq$aGzL5';
            $integrated_security = $false;


            # Get the last copied file time so we can move files that were already copied from the log shipping folder to the backup folder where they get uploaded to Amazone s3.
            # Executed on the Secondary server
            $ds = Exec-Sql $server $database $query $command_type $integrated_security $sql_login $sql_password;    

            foreach ($Row in $ds.Tables[0].Rows)
            {           
    
                [datetime]$last_copied_date = $Row.Item('last_copied_date');    
            }


            # Get the trn files that were already copied.
            $files = Get-ChildItem $source_path -recurse -include *.trn | Where-Object {$_.LastWriteTime -lt $last_copied_date -and $_.PSIsContainer -eq $False} 
            foreach($file in $files)
            {                   
                if ($UserInteractive -eq $true) {Write-Host -ForegroundColor Yellow $file.FullName  ' | ' $file.LastWriteTime}   
                
                # Move files to the backup folder
                Move-Item -Path $file.FullName $destination_path;
            }                    
        }
        catch
        {       
            throw;
        }
    }
}


function writemetrictofile($objarr, $name)
{
    $processing_path = $config_file.processing_path
    $ready_path = $config_file.ready_path
    $customername = $config_file.customername
    $file = $customername +"-" + $name +"-" + $(Get-date -Format yyyyMMdd-HHmmssffff) +'.csv' 
    $full_path = $processing_path + '\' + $file
    $hostn = get-content env:computername 
    
    $now = Get-Date ([datetime]::UtcNow) -Format s
    $now = $now.ToString()+"Z"
    
    foreach ($obj in $objarr)
    {    
        $obj | Add-Member -MemberType NoteProperty -Name FormatedTimestamp -Value $now
        $obj | Add-Member -MemberType NoteProperty -Name Computer -Value $hostn.trim() -Force;
    }
    $objarr | Export-Csv -Path $full_path -NoTypeInformation;
    $target_file = $ready_path + '\' + $file
    Move-Item $full_path $target_file    
}


function Get-TimeStamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
    #return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    #return (Get-Date).ToString("yyyy-MM-dd'T'HH:mm:sssz")
    };


# Return date only
function Get-CurrentDate {
    return (Get-Date).ToUniversalTime().ToString('yyyy.MM.dd');
    };
       

# Extract the string inside the brackets of the input string
function extract-metric
{
    [CmdletBinding()]
    [Alias()]    
    [OutputType([string])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] [string]$path          
    )
    Begin
    {
        try
        {
            [string]$input_path = $path;

            # Extract the string inside the brackets
            $pos1 = $input_path.IndexOf('(') + 1;
            $pos2 = $input_path.IndexOf(')');              
            $input_path = $input_path.Substring($pos1, $pos2-$pos1);                 


            ## Remove the extracted string from the materic path
            #$str1 = $path.Substring(0, $pos1);
            #$str2 = $path.Substring($pos2, $path.Length-$pos2);
            #$path = $str1 + $str2;            
            #
            #$path = $path.Substring($pos1, $pos2-$pos1);
            return $input_path;                        
        }
        catch
        {       
            throw;
        }
    }
}


# Extract the string inside the brackets of the input string
function remove-metric
{
    [CmdletBinding()]
    [Alias()]    
    [OutputType([string])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] [string]$path          
    )
    Begin
    {
        try
        {           
            [string]$input_path = $path;

            $pos1 = $input_path.IndexOf('(') + 1;
            $pos2 = $input_path.IndexOf(')');              
            #$database_name = $path.Substring($pos1, $pos2-$pos1);    

            # Remove the extracted string from the materic path
            $str1 = $input_path.Substring(0, $pos1);
            $str2 = $input_path.Substring($pos2, $input_path.Length-$pos2);
            $input_path = $str1 + $str2;            
            
            return $input_path;                        
        }
        catch
        {       
            throw;
        }
    }
}


function get-smtpclient
{
    [CmdletBinding()]
    [Alias()]    
    [OutputType([Net.Mail.SmtpClient])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)] [ValidateNotNullOrEmpty()] [ValidateSet($false,$true)]
        [bool]$use_default_credentials,        

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)] [ValidateNotNullOrEmpty()] 
        [string]$user,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)] [ValidateNotNullOrEmpty()] 
        [string]$password,        
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)] [ValidateNotNullOrEmpty()] 
        [string]$smtpserver,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)] [ValidateNotNullOrEmpty()] 
        [int]$port = 25,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)] [ValidateNotNullOrEmpty()] [ValidateSet($false,$true)]
        [bool]$ssl = $false            
    )
    Begin
    {
        #if( [bool]::IsNullOrEmpty($use_default_credentials)) {Throw 'The ''$use_default_credentials'' variable does not contain a valid value'}
        if( [string]::IsNullOrEmpty($User)) {Throw 'The ''$User'' variable does not contain a valid value'}
        if( [string]::IsNullOrEmpty($Password)) {Throw 'The ''$password'' variable does not contain a valid value'}
        
        if( [string]::IsNullOrEmpty($smtpserver)) {Throw 'The ''$smtpserver'' variable does not contain a valid value'}
        #if( [int16]::IsNullOrEmpty($port)) {Throw 'The ''$port'' variable does not contain a valid value'}
        #if( [bool]::IsNullOrEmpty($ssl)) {Throw 'The ''$ssl'' variable does not contain a valid value'}


        try
        {
            [Net.Mail.SmtpClient]$smtpclient = New-Object Net.Mail.SmtpClient($smtpserver);

            if($use_default_credentials -eq $true)
            {
                [SecureString]$secuered_password = ConvertTo-SecureString $password -AsPlainText -Force;
                [System.Management.Automation.PSCredential]$credential = New-Object System.Management.Automation.PSCredential ($user, $secuered_password);
                [object]$smtpclient.Credentials  = $credential;
            }                      
          
            [int32]$smtpclient.Port     = $port;
            [bool]$smtpclient.EnableSsl = $ssl;

            return $smtpclient;                        
        }
        catch
        {       
            throw;
        }
    }
}



<#
.Synopsis
   Executes sql command
.DESCRIPTION
   A generic code to execute sql commands
.EXAMPLE
   ExecuteScalar
        $command_type = 'Scalar';
        $val = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType $command_type -IntegratedSecurity $windows_authentication -Credentials $credentials;     
   DataSet        
    $command_type = 'DateSet';        
        $ds = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType $command_type -IntegratedSecurity $windows_authentication -Credentials $credentials;     

#>
function Exec-Sql
{
    [CmdletBinding()]
    [Alias()]
    #[OutputType([System.Data.DataSet])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database = 'master',

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [string]$CommandText,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=3)][ValidateSet('NonQuery' ,'Scalar' ,'DataSet')] 
        [string]$CommandType,       

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=4)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [System.Data.SqlClient.SqlCredential]$Credentials,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)]
        [int32]$CommandTimeOut = 0,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [string]$ApplicationIntent        
    )

    Begin
    {
        $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";
        
        if($CommandType -notin ('NonQuery' ,'Scalar' ,'DataSet') )
        {
            Throw 'The ''$CommandType'' parameter contains an invalid value Valid values are: ''NonQuery'' ,''Scalar'' ,''DataSet''';
        }

        try
        {
            if ($IntegratedSecurity)
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            }
            else
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString, $Credentials);
                $SqlConnection.Credential = $Credentials;
            }

            
            $SqlCommand = $sqlConnection.CreateCommand();            
            $SqlCommand.CommandText = $CommandText;         
            $SqlCommand.CommandTimeout = $CommandTimeOut;   
            $SqlConnection.Open();          
                  
            # NonQuery
            if($CommandType -eq 'NonQuery')
            {      
                $sqlCommand.ExecuteNonQuery();                
                return;
            }

            # Scalar
            if($CommandType -eq 'Scalar')
            {                                   
                $Val = $sqlCommand.ExecuteScalar();                  
                return $Val;
            }
            
            # DataSet
            if($CommandType -eq "DataSet")
            {
                $DataSet = New-Object System.Data.DataSet;
                $SqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
                $SqlDataAdapter.SelectCommand = $SqlCommand;    
                $SqlDataAdapter.Fill($DataSet);                  
                return $DataSet;   
            }
        }
        catch
        {       
            Throw;
        }
        finally
        {
            #$SqlConnection.Close();   
            $SqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
}


function Insert-Sql
{
    [CmdletBinding()]
    [Alias()]
    #[OutputType([int])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [string]$User,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$Password,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [int32]$CommandTimeOut = 300,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=6)]
        [string]$CommandType,      

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationName = "PowerShell-Maintenance",    

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [bool]$ApplicationIntent = $false,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=9)]
        [string]$DestinationTable,  

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=10)]
        [System.Data.DataTable]$DataTable         
    )
    Begin
    {
        if($IntegratedSecurity -eq $true)
        {
            $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";
        }
        else
        {
            # Validate the credentials were supplied            
            if( [string]::IsNullOrEmpty($Password)) {Throw 'The input variable ''$User'' does not contain a valid value at file Helpers.ps, function: ' + $MyInvocation.MyCommand.Name.Split(".")[0] + '.'}
            if( [string]::IsNullOrEmpty($Password)) {Throw 'The input variable ''$Password'' does not contain a valid value at file Helpers.ps, function: ' + $MyInvocation.MyCommand.Name.Split(".")[0] + '.'}

            $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; User=$User; Password=$Password; Application Name=$ApplicationName;";
        }        

        if($CommandType -notin ('BulkCopy', 'Insert') )
        {
            throw 'The ''$CommandType'' parameter contains an invalid value Valid values are: ''BulkCopy'',''Insert'' ';
        }

        try
        {
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $SqlConnection.Open();

            if($CommandType -eq 'BulkCopy')
            {
                #$KeepIdentity = [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity;                
                #$KeepNulls = [System.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls;                

                $SqlBulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy -ArgumentList $SqlConnection #, ([System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity), ([System.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls);
                #$SqlBulkCopy = New-Object ("System.Data.SqlClient.SqlBulkCopy")$SqlConnection ;            
                $SqlBulkCopy.DestinationTableName = $DestinationTable;
                $SqlBulkCopy.BulkCopyTimeout = 0; #unlimmited
                
                $SqlBulkCopy.WriteToServer($DataTable);               
            }

             $SqlConnection.Close();
        }
        catch
        {       
            #if($SqlConnection.State -eq ){ $SqlConnection.Close();}           
            throw;
        }
    }
}


function Get-SqlBackupInfo
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([System.Data.DataSet])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials,        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$ApplicationName = "CloudMonitoring",        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [int]$BackupSetId = 0,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=6)][ValidateSet('Full','Differential','Log')] 
        [string]$BackupType,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        $Lsn = 00000000000000001                  
    )
    Begin
    {
        # If logs we return all the log backups.
        if($BackupType -eq 'Log') 
        {
            $top = 20000;
            $sort_order = 'ASC';
            $backup_type = 'L';     
        } 
        # For any other backup type we only need the last backupsetid.
        if($BackupType -eq 'Full') 
        {
            $top = 1;
            $sort_order = 'DESC';
            $backup_type = 'D';     
        }

         if($BackupType -eq 'Differential') 
        {
            $top = 1;
            $sort_order = 'DESC';
            $backup_type = 'I';     
        }

        try
        {
           $query = 
            'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;         
            SELECT TOP ({3})
	             b.backup_start_date
	            ,f.physical_device_name
	            ,b.type
                ,b.backup_set_id
               ,b.backup_size /1024 /1024 AS backup_size_mb
            FROM msdb.dbo.backupset b
            INNER JOIN msdb.dbo.backupmediafamily f ON b.media_set_id = f.media_set_id            
            WHERE b.database_name LIKE ''{0}''
            AND b.type = ''{1}''
            AND b.backup_set_id > {2}
            AND is_copy_only = 0
            AND first_lsn >= {5}
            --AND last_lsn >= {5}
            ORDER BY b.backup_start_date {4};' -f $Database, $backup_type, $BackupSetId, $top, $sort_order, $Lsn;
            
            #Write-Message -Text $query -ForegroundColor Green;
            $ds = Exec-Sql -Server $Server -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
                
                      
                        
            if ($ds.Count -eq 0) 
            {
                return;
            }
            
            # Rerun the query useing the backup_set_id of the last full/diff backup we just retreived.
            # This is needed to get the physical_device_name for backup sets containing more than a single file.
            if($backup_type -in ('D', 'I') )
            {                  
                $backup_set_id = $ds.Tables[0].Rows[0].backup_set_id;
                $top = 30;

                 $query = 
                'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;         
                SELECT TOP ({3})
	                 b.backup_start_date
	                ,f.physical_device_name
	                ,b.type
                    ,b.backup_set_id
                   ,b.backup_size /1024 /1024 AS backup_size_mb
                FROM msdb.dbo.backupset b
                INNER JOIN msdb.dbo.backupmediafamily f ON b.media_set_id = f.media_set_id            
                WHERE b.database_name LIKE ''{0}''
                AND b.type = ''{1}''
                AND b.backup_set_id = {2}
                AND is_copy_only = 0
                AND first_lsn >= {5}
                --AND last_lsn >= {5}
                ORDER BY b.backup_start_date {4};' -f $Database, $backup_type, $backup_set_id, $top, $sort_order, $Lsn;

                #Write-Message -Text $query -ForegroundColor Cyan;
                $ds = Exec-Sql -Server $Server -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
            }


            return $ds;
        }
        catch [Exception]
        {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}


function Exec-SqlRestore
{
    [CmdletBinding()]
    [Alias()]        
    [OutputType([int])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$SourceServer,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$TargetServer,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=3)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [System.Data.SqlClient.SqlCredential]$Credentials,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [int32]$CommandTimeOut = 0,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)]
        [string]$ApplicationName = "CloudMonitoring",
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationIntent,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [int]$BackupSetId = 0,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=9)][ValidateSet('Full','Differential','Log')] 
        [string]$BackupType,         

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=10)]#[ValidateSet('RECOVERY','NORECOVERY')] 
        [bool]$Recovery = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=11)]
        $Lsn = 00000000000000001     
    )
    Begin
    {
        [string]$recovery_mode;
        if($Recovery)
        {
            $recovery_mode = 'RECOVERY';
        }
        else
        {
            $recovery_mode = 'NORECOVERY';
        }

        try
        {
            [string]$newline = [System.Environment]::NewLine;    
            $ds = Get-SqlBackupInfo -Server $SourceServer -Database $Database -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType $BackupType -BackupSetId $BackupSetId -Lsn $Lsn ;

            # If there is no info we exit here.
            if ($ds.Tables[0].Rows.Count -eq 0)
            {
                return;
            }


            foreach($Row in $ds.Tables[0].Rows)
            {            
                [string]$physical_device_name = $Row.Item('physical_device_name');     
                [string]$type       = $Row.Item('type'); 
                [int]$backup_set_id = $Row.Item('backup_set_id');                      

                #Write-Message -Text $physical_device_name -ForegroundColor Cyan;
                $from_disk += ',DISK = ''{0}''{1}' -f $physical_device_name, $newline; 
            }
            # Remove the first comma.
            $from_disk = $from_disk.Substring(1, $from_disk.Length-1);


            # Restore Log
            if($BackupType -eq 'Log')
            {
                $counter = 1;
                foreach ($Row in $ds.Tables[0].Rows)        
                {    
                    [string]$physical_device_name = $Row.Item('physical_device_name');    
                    [string]$backup_size_mb = $Row.Item('backup_size_mb');            
                    #[string]$file_name = [System.IO.Path]::GetFileName($Row.Item('physical_device_name'));
                    #$backup_path_unc = '{0}\{1}\{2}\{3}' -f $backup_path, $source_server, $database_name, $file_name;
                
                    $query = 'RESTORE LOG [{0}] FROM DISK=''{1}'' WITH NORECOVERY,STOPAT=''{2}'';' -f $Database, $physical_device_name, $stopat;
                    $text = '#{0}  {1}  size_mb: {2}' -f $counter, $query, $backup_size_mb;                
                    Write-Message -Text $text -ForegroundColor Yellow;
                    $val = Exec-Sql -Server $TargetServer -Database 'master' -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName; 
                    $counter++;  
                }

                return;
            }
            
            # Restore Full + Diff     
            if($BackupType -in ('Full', 'Differential') )
            {
                [string]$with_move = Get-SqlWithMove -Server $SourceServer -Database $Database -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;;
                
                $query = 'RESTORE DATABASE [{0}] FROM {3} {1} WITH {4}, REPLACE {3}{2}; '-f $Database , $from_disk, $with_move, $newline, $recovery_mode;            
                Write-Message -Text $query -ForegroundColor Yellow;
                $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;      
            } 
         

            return $backup_set_id;        
        }
       catch [Exception]
       {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}


function Exec-SqlBackup
{
    [CmdletBinding()]
    [Alias()]    
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=3)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [System.Data.SqlClient.SqlCredential]$Credentials,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [int32]$CommandTimeOut = 0,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationIntent,
        
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=8)]
        [string]$BackupFileFullName,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=9)][ValidateSet('Full','Differential','Log')] 
        [string]$BackupType,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=10)]
        [bool]$Compression = $true

    )
    Begin
    {
        try
        {  
            # Full
            if ($BackupType -eq 'Full')
            {                     
                if($Compression)
                {
                    $query = 'BACKUP DATABASE [{0}] TO DISK = ''{1}'' WITH COMPRESSION, INIT;' -f $Database, $BackupFileFullName;
                }
                else
                {
                    $query = 'BACKUP DATABASE [{0}] TO DISK = ''{1}'' WITH INIT;' -f $Database, $BackupFileFullName;
                }
            }


            # Diff
            if ($BackupType -eq 'Differential')
            { 
                if($backup_compression)
                {
                    $query = 'BACKUP DATABASE [{0}] TO DISK = ''{1}'' WITH COMPRESSION, INIT, DIFFERENTIAL;' -f $Database, $BackupFileFullName;
                }
                else
                {
                    $query = 'BACKUP DATABASE [{0}] TO DISK = ''{1}'' WITH INIT, DIFFERENTIAL;' -f $Database, $BackupFileFullName;
                }
            }


            Write-Message -Text $query -ForegroundColor Green;
            $val = Exec-Sql -Server $Server -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;        
        }
        catch [Exception]
        {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}


function Get-SqlWithMove
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([string])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials,        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$ApplicationName        
    )
    Begin
    {
        try
        {           
            $query = 'SELECT name, type_desc, physical_name FROM sys.master_files WHERE DB_NAME(database_id) = ''{0}'';' -f $database_name;            
            Write-Message -Text $query -ForegroundColor Green;
            $ds = Exec-Sql -Server $Server -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
    
            # Construct the WITH MOVE bit.
            [string]$with_move = $null;
            foreach ($Row in $ds.Tables[0].Rows)        
            {    
                [string]$logical_name = [System.IO.Path]::GetFileName($Row.Item('name'));
                [string]$physical_name_path = Split-Path -Path $Row.Item('physical_name') -Parent;
                [string]$physical_name_ext = [System.IO.Path]::GetFileName($Row.Item('physical_name')).Split('.')[1];;
                [string]$physical_name_file = [System.IO.Path]::GetFileNameWithoutExtension($Row.Item('physical_name'));
                [string]$type_desc = $Row.Item('type_desc');        

                
                if($type_desc -eq 'ROWS')
                {
                    if( [string]::IsNullOrEmpty($physical_name_ext) ) {$physical_name_ext = 'mdf'; }
                    $with_move += ',MOVE ''{0}'' TO ''{1}\{2}.{3}''{4}' -f $logical_name, $data_path, $physical_name_file, $physical_name_ext, $newline; # data files
                }
                else
                {   if( [string]::IsNullOrEmpty($physical_name_ext) ) {$physical_name_ext = 'ldf'; }     
                    $with_move += ',MOVE ''{0}'' TO ''{1}\{2}.{3}''{4}' -f $logical_name, $log_path, $physical_name_file, $physical_name_ext, $newline; # log files
                }        
            }
            
            return $with_move;            
        }
        catch [Exception]
        {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}



function Exec-SqlKill
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([string])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials,        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$ApplicationName = "CloudMonitoring"        
    )
    Begin
    {
        try
        {           
            $query = 'SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND DB_NAME(database_id) = N''{0}'' AND session_id > 50;' -f $Database;        
            Write-Message -Text $query -ForegroundColor Yellow;
            $ds = Exec-Sql -Server $Server -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
            foreach ($Row in $ds.Tables[0].Rows)        
            {    
                #$spid = $null;
                [string]$session_id = $Row.Item('session_id');
                $query = 'KILL ' + $session_id + ';';            
                Write-Message -Text $query;
                $val = Exec-Sql -Server $Server -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
            }          
        }
        catch [Exception]
        {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}


function Exec-SqlSetReadOnly
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([string])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials,        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$ApplicationName        
    )
    Begin
    {
        try
        {  
            # Get the is_read_only state.
            $query = 'IF EXISTS(SELECT * FROM sys.databases WHERE name = ''{0}'' AND is_read_only = 1) SELECT 1 AS bit ELSE SELECT 0 AS bit;' -f $Database; 
            Write-Message -Text $query;
            [bool]$bit = Exec-Sql -Server $Server -CommandText $query -CommandType Scalar -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;  
        
            
            # If the database is already in the read_only state we do nothing here.
            if($bit)
            {
                $message = 'The database {0} is already in the read_only state.' -f $Database;
                Write-Message -Text $message;
                return;
            }
            

            # Kill all connections to the database prior to settting READ_ONLY    .         
            Exec-SqlKill -Server $Server -Database $Database -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                     
            $query = 'ALTER DATABASE [{0}] SET READ_ONLY WITH ROLLBACK IMMEDIATE;' -f $Database;                    
            Write-Message -Text $query;
            $val = Exec-Sql -Server $Server -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;             
        }
        catch [Exception]
        {
            [string]$message = 'Exception at: {0}. Exception.Message: {1}' -f $MyInvocation.MyCommand, $_.Exception.Message;
            Write-Message -Text $message -ForegroundColor Red;

            Throw;
       }       
    }
}


function Copy-SqlDatabases
{
    <#
    .SYNOPSIS
        Copies SQL Server databases from a source SQL Server instance to a target SQL Server instance.

    .DESCRIPTION
        This script provides the ability to copy databases using backup/restore.                 

    .PARAMETER SourceServer
        Source SQL Server.

    .PARAMETER TargetServer
        Target SQL Server. 

    .PARAMETER Credential
        Login to the source and target instances using sql credentials or windows authentication.

    .PARAMETER IncludeDatabase
        Copies only specified databases.

    .PARAMETER ExcludeDatabase
        Excludes specified databases.

    .PARAMETER BackupPath
        Specifies the network location for the backup files. The SQL Server service accounts must have read/write permission to this path.

    .PARAMETER Recovery
        If this is true, the database will be recovered after the restore is completed

    .PARAMETER SetSourceDatabaseReadOnly
        If this is true, all copied databases are set to ReadOnly on Source prior to the differential backup.

    .PARAMETER UseLastBackup
        Use the last full, diff and logs instead of taking backups. 

    .EXAMPLE
        Copy-SqlDatabases -SourceServer $source_server -TargetServer $target_server -IntegratedSecurity $windows_authentication -Credentials $credentials `
                    -DataFilesPath $data_path -LogFilesPath $log_path -BackupPath $backup_path `
                    -UseLastBackup $true -RestoreFullBackup $true -RestoreDifferentialBackup $true -RestoreLogBackup $true `
                    -SkipTargetDatabaseIfExists $false -DropTargetDatabaseIfExists $false -CheckIfSubcriptionDatabase $false -RecoverDatabase $false  `
                    -IncludeDatabase yaniv_test

        Copies a single user database yaniv_test using the exiting full, diff and log backups.


    .EXAMPLE
        Copy-SqlDatabases -SourceServer $source_server -TargetServer $target_server -IntegratedSecurity $windows_authentication -Credentials $credentials `
                    -DataFilesPath $data_path -LogFilesPath $log_path -BackupPath $backup_path `
                    -UseLastBackup $true -RestoreFullBackup $true -RestoreDifferentialBackup $true -RestoreLogBackup $true `
                    -SkipTargetDatabaseIfExists $false -DropTargetDatabaseIfExists $false -CheckIfSubcriptionDatabase $false -RecoverDatabase $false  `
                    -IncludeDatabase yaniv_test

        Copies a single user database yaniv_test using the exiting full, diff and log backups.


        
        Copy-SqlDatabases -SourceServer $source_server -TargetServer $target_server -IntegratedSecurity $windows_authentication -Credentials $credentials `
                    -DataFilesPath $data_path -LogFilesPath $log_path -BackupPath $backup_path `
                    -UseLastBackup $true -RestoreFullBackup $true -RestoreDifferentialBackup $true -RestoreLogBackup $true `
                    -SkipTargetDatabaseIfExists $false -DropTargetDatabaseIfExists $false -CheckIfSubcriptionDatabase $false -RecoverDatabase $false  `
                    -ExcludeDatabase yaniv_test, DBA

        Copies all databases excluding yaniv_testand DBA using the exiting full, diff and log backups.    
    #>

    [CmdletBinding()]
    [Alias()]    
    Param
    (     
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$SourceServer,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$TargetServer,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,          
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials, 
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]         
        [string]$ApplicationName = 'FSX',        

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=5)]
        [string]$DataFilesPath,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=6)]
        [string]$LogFilesPath,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$BackupPath,
        
        # Set the source db read only before taking the differential backup
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]        
        [bool]$SetSourceDatabaseReadOnly = $false, 

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=9)]
        [bool]$UseLastBackup = $true,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=9)]
        [bool]$BackpCompression = $true,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=10)]
        [bool]$RestoreFullBackup,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=11)]
        [bool]$RestoreDifferentialBackup,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=12)]
        [bool]$RestoreLogBackup,
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=13)]
        [string]$StopAt = '2055-03-03 00:00:04.000',
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=14)]
        [bool]$RecoverDatabase = $false,        
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=15)]
        [bool]$SkipTargetDatabaseIfExists = $true,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=16)]
        [bool]$DropTargetDatabaseIfExists = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=17)]
        [bool]$CheckIfSubcriptionDatabase = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=18)]
        [System.Object]$IncludeDatabase,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=19)]
        [System.Object]$ExcludeDatabase                
    )

    [bool]$user_interactive = [Environment]::UserInteractive;

    [string]$helpers_backup_file_full_name = Join-Path $PSScriptRoot 'helpers.ps1'
    . $helpers_backup_file_full_name;



    if ($IncludeDatabase -and $ExcludeDatabase)
    {
        $text = 'You cannot select both IncludeDatabase and ExcludeDatabase';
        Write-Message -Text $text -ForegroundColor Cyan;
        return;
    }

     if ($DropTargetDatabaseIfExists -and -not $RestoreFullBackup)
    {
        $text = 'You cannot select both DropTargetDatabaseIfExists and RestoreFullBackup';
        Write-Message -Text $text -ForegroundColor Cyan;
        return;
    }


    # Force a pop up in order to verify the configuration before we proceed.
    if($SetSourceDatabaseReadOnly)
    {
        # Get the user confirmation before we proceed
        Add-Type -AssemblyName PresentationFramework;
        $message = 'You have selected to set the source database READ_ONLY. ' + [Environment]::NewLine + 'Press Yes to proceed or No to cancel.';
        $caption = 'Confirmation';
        $input = [System.Windows.MessageBox]::Show($message, $caption, 'YesNo');
        if($input -eq 'No') {return; }
    }

    #$text = '--Source_server: {0}  |  Target_server: {1}' -f $SourceServer, $TargetServer;
    #Write-Message -Text $text -ForegroundColor Cyan;

    #$text = 'is_read_only:{0} use_last_backup:{1}  restore_full_backup:{2}  restore_differential_backup:{3}  restore_log_backup{4}  stopat:{5} backup_compression:{6}  skip_target_database_if_exists:{7}  drop_target_database_if_exists:{8}  check_is_subscription_database:{9}  recover_database:{10}' `
    #     -f $SetSourceDatabaseReadOnly, $UseLastBackup, $RestoreFullBackup, $RestoreDifferentialBackup, $RestoreLogBackup, $StopAt, $BackpCompression, $SkipTargetDatabaseIfExists,`
    #      $DropTargetDatabaseIfExists, $CheckIfSubcriptionDatabase, $RecoverDatabase;
    #Write-Message -Text $text -ForegroundColor Cyan -LogToConsole $false;

    try
    {
        # Disable ddl server triggers.
        [string]$query = 'SELECT name FROM sys.server_triggers WHERE is_disabled = 0;';    
        Write-Message -Text $query -ForegroundColor Green;
        $ds_server_triggers = Exec-Sql -Server $TargetServer -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName; 
        foreach ($Row in $ds_server_triggers.Tables[0].Rows)        
        {
            [string]$trigger_name = $Row.Item('name');

            $query = 'DISABLE TRIGGER [{0}] ON ALL SERVER;' -f $trigger_name;        
            Write-Message -Text $query -ForegroundColor Yellow;
            $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;   
        }  
       

        # Get the list of databases tpo process from the sourve server.    
              
        [string]$query = 
        'SELECT name AS database_name
         FROM sys.databases d WHERE d.database_id > 4 AND d.source_database_id IS NULL AND d.is_distributor = 0 AND d.is_published = 0 
         AND d.is_read_only = 0 AND d.state_desc = N''ONLINE'' 
         --AND replica_id IS NULL
         ORDER BY database_name;';
       
        
        $ds_databases = Exec-Sql -Server $SourceServer -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
        foreach ($Row in $ds_databases.Tables[0].Rows)        
        {
            try
            {
                $database_name = $Row.Item('database_name');

                # Skip these iteration            
                if ($ExcludeDatabase -contains $database_name ) { continue; }


                if ($IncludeDatabase -contains $database_name -or $IncludeDatabase -eq $null) 
        	    {
	
                    # Check if the database exists
	                $query = 'IF EXISTS(SELECT * FROM sys.databases WHERE name = ''{0}'') SELECT 1 AS bit ELSE SELECT 0 AS bit;' -f $database_name;        
                    Write-Message -Text $query -ForegroundColor Yellow;
                    [bool]$database_exists = Exec-Sql -Server $TargetServer -CommandText $query -CommandType Scalar -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
        
                    # Find if this is a subscription database of Transactional REplication  
                    if ($CheckIfSubcriptionDatabase)
                                                                                    {
                    if ($database_exists)
                    {                   
                        $query = 'USE [{0}]; IF EXISTS (SELECT * FROM sys.tables WHERE name = ''MSreplication_objects'') SELECT 1 AS bit ELSE SELECT 0 AS bit;' -f $database_name;
                        Write-Message -Text $query -ForegroundColor Yellow;
                        $bit = Exec-Sql -Server $TargetServer -CommandText $query -CommandType Scalar -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
        
                        # If this is a Subscription database we skip it. 
                        # KEEP_REPLICATION and KEEP_CDC are conflicting options with NORECOVERY so we do not restore these databases but rather handle them manually.
                        if($bit) 
                        {
                            $message = 'Skipping the Subscription database [{0}]' -f $database_name;
                            Write-Message -Text $query -ForegroundColor Cyan;
                            continue; 
                        }
                    }
                }        
    
    
                    if($database_exists)
                                                                                                {
                    if ($DropTargetDatabaseIfExists)
                    {
                        # Drop the target database if exists. 
                        $query = 'DROP DATABASE [{0}];' -f $database_name;                
                        Write-Message -Text $query -ForegroundColor Yellow;
                        $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                    }
                    else
                    {
                        # Skip the database if exists. 
                        # Do not process this database
                        if ($SkipTargetDatabaseIfExists) 
                        {
                            $text = 'Skipping database {0}.' -f $database_name;                    
                            Write-Message -Text $text -ForegroundColor Yellow;
                            Continue; 
                        }
                    }
                }
                          

                    # Bakup Full.
                    if(-not $UseLastBackup)
                                        {
                    [string]$backup_file_full_name = Join-Path $backup_path $database_name;
                    $backup_file_full_name += '.bak';    
                        
                    Exec-SqlBackup -Server $SourceServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName; -BackupFileFullName $backup_file_full_name -BackupType Full;   
                }
            
        
                    # Kill all connections for the given database prior to the restore.     
                    # We do this only once on the target server as it may be required prior to the restore to allow exculsive access. When the database is in the RESTOREING mode there is typically no need.
                    Exec-SqlKill -Server $TargetServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                
        
                    if($RestoreFullBackup)
                    {
                        $backup_set_id = $null;
                        #$backup_type = 'D';                    
                        $val = Exec-SqlRestore -SourceServer $SourceServer -TargetServer $TargetServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType Full;      
                        [int]$backup_set_id = $val[1];       
                    }
                
                 
                    #region <Restore Differential>                
                    if($RestoreDifferentialBackup)
                    {             
                        #$backup_type = 'I'; 

                        if (-not $UseLastBackup)
                        {
                            # READ_ONLY
                            # Set the source database READ_ONLY before we take the diffrential backup to assure no data is written to the database after the backup.
                            if($SetSourceDatabaseReadOnly)
                            {   
                                Exec-SqlSetReadOnly -Server $SourceServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                            }


                            # Backup Differential.
                            $backup_file_full_name = $backup_file_full_name.Replace('.bak', '.dif');
               
                            Exec-SqlBackup -Server $SourceServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName; -BackupFileFullName $backup_file_full_name -BackupType Differential;   
                        }                
            
                        Exec-SqlRestore -SourceServer $SourceServer -TargetServer $TargetServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType Differential -BackupSetId $backup_set_id;      
                    }
                    #endregion
                              

                    #region <Restore Logs>                
                    if($RestoreLogBackup)
                    {
                        # No Full or Differential backups were restored we restore logs only starting from the current database lsn.
                        if ($RestoreFullBackup -eq $false -and $RestoreDifferentialBackup -eq $false )
                        {
                            # Get the is_read_only state.
                            $query = 'SELECT ISNULL(MIN(redo_start_lsn), 1) FROM sys.master_files WHERE /*type_desc = ''ROWS'' AND */ DB_NAME(database_id) = ''{0}'';' -f $database_name; 
                            Write-Message -Text $query -ForegroundColor Yellow;
                            $lsn = Exec-Sql -Server $TargetServer -CommandText $query -CommandType Scalar -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                        
                            # If we got an lsn value we can pass it on and restore logs from that lsn onwards.
                            # If there is no lsn value it means the database is recovered and so we cannot restore logs.
                            if ($lsn -gt 1)
                            {
                                Exec-SqlRestore -SourceServer $SourceServer -TargetServer $TargetServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType Log -BackupSetId $backup_set_id -Lsn $lsn;
                            }
                            else
                            {
                                [string]$message = 'Database {0} does not have an lsn value in sys.master_files. This is most likly beacuse the database is not in a state that allowes restoring logs.' -f $database_name;
                                Write-Message -Text $message -ForegroundColor Yellow;
                            }
                        }
                        # Full or Differential backups were restored we start restoring logs from the last Full or Differential.
                        else
                        {
                            if ($RestoreDifferentialBackup) {$backup_type = 'Differential'} else {$backup_type = 'Full'}
            
                            # Get the last backup_set_id for the differential or full backup.
                            $ds = Get-SqlBackupInfo -Server $SourceServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType $backup_type;            
            
                            if($ds.Count -gt 0)
                            {
                                # READ_ONLY
                                # Set the source database READ_ONLY before we take the log backup to assure no data is written to the database after the backup.
                                if($SetSourceDatabaseReadOnly)
                                {
                                    Exec-SqlSetReadOnly -Server $SourceServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                                }
                                [int]$backup_set_id = $ds.tables[0].Rows[0].backup_set_id;   
                                Exec-SqlRestore -SourceServer $SourceServer -TargetServer $TargetServer -Database $database_name -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName -BackupType Log -BackupSetId $backup_set_id # -Lsn $lsn;                                                    
                            }
                        }            
                    }
                    #endregion
        

                    # Database roperties
                    $query = 'SELECT d.name, d.is_broker_enabled, d.is_trustworthy_on, d.is_published, d.owner_sid, SUSER_SNAME(d.owner_sid ) AS db_owner FROM sys.databases d  WHERE d.name = ''{0}'';' -f $database_name;        
                    Write-Message -Text $query -ForegroundColor Green;
                    $ds = Exec-Sql -Server $SourceServer -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                    foreach ($Row in $ds.Tables[0].Rows)        
                    {    
                        [bool]$is_broker_enabled = $Row.Item('is_broker_enabled');
                        [bool]$is_trustworthy_on = $Row.Item('is_trustworthy_on');
                        [bool]$is_published = $Row.Item('is_published');
                        [string]$db_owner = $Row.Item('db_owner');    
                    }
                                                                                                                                                                                                                                                                                                    <#
            # is_auto_update_stats_async_on 
            # In case the database property is set on we turn it to off as it makes getting the single user easier.
            $query = 'IF (SELECT is_auto_update_stats_async_on FROM sys.databases WHERE name = ''{0}'') = 1 SELECT 1 AS auto_update_stats_async ELSE SELECT 0 AS auto_update_stats_async;' -f $database_name;
            if ($user_interactive) {Write-Host -ForegroundColor Green $query };
            [bool]$auto_update_stats_async = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType 'Scalar' -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   


            # Modify is_auto_update_stats_async_on
            if($auto_update_stats_async)
            {
                $query = 'USE master; ALTER DATABASE [{0}] SET AUTO_UPDATE_STATISTICS_ASYNC OFF WITH NO_WAIT;' -f $database_name;
                if ($user_interactive) {Write-Host -ForegroundColor Green $query };
                $ds = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
            }

            # Kill all connections for the given database
            $query = 'USE master; SELECT spid FROM sys.sysprocesses WHERE DB_NAME(dbid) = ''{0}'' /* AND spid > 50 */ ;' -f $database_name;
            if ($user_interactive) {Write-Host -ForegroundColor Green $query };
            $ds = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType $command_type -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
            foreach ($Row in $ds.Tables[0].Rows)        
            {    
                [string]$spid = $Row.Item('spid');
                $query = 'KILL ' + $spid + ';';
                $ds = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
            }
   
            # Single user
            $query = 'USE [{0}]; ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' -f $database_name;
            if ($user_interactive) {Write-Host -ForegroundColor Green $query };
            $ds = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   

            # Detach database
            $query = 'USE master; EXEC sp_detach_db ''{0}'', ''true'';' -f $database_name;
            if ($user_interactive) {Write-Host -ForegroundColor Green $query };
            $ds = Exec-Sql -Server $source_server -Database $database -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
            #>

    
                    # Recover the database to allow access
                    if($RecoverDatabase)
                    {
                        $query = 'RESTORE DATABASE [{0}] WITH RECOVERY;' -f $database_name;        
                        Write-Message -Text $query -ForegroundColor Yellow;
                        $ds = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
            
                        # Read-Write.
                        # If the databse was at the read-only state when we took the backup that state is retained at the target server so we set it back to read-write        
                        if($is_read_only)
                        {
                            $query = 'ALTER DATABASE [{0}] SET READ_WRITE WITH ROLLBACK IMMEDIATE;' -f $database_name;            
                            Write-Message -Text $query -ForegroundColor Yellow;
                            $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                        }
    
                        #region <target server database properties>
                        # Set trustworthy.
                        if($is_trustworthy_on)
                        {
                            $query = 'ALTER DATABASE [{0}] SET TRUSTWORTHY ON;' -f $database_name;            
                            Write-Message -Text $query -ForegroundColor Yellow;
                            $val = Exec-Sql -Server $target_server -Database $database -CommandText $query -CommandType NonQuery -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
                        }

                        # Set broker.
                        if($is_broker_enabled)
                        {
                            $query = 'ALTER DATABASE [{0}] SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;' -f $database_name;            
                            Write-Message -Text $query -ForegroundColor Yellow;
                            $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                        }
                 

                        # Change db_owner.
                        $query = 'ALTER AUTHORIZATION ON DATABASE::[{0}] TO [{1}];' -f $database_name, $db_owner;        
                        Write-Message -Text $query -ForegroundColor Yellow;
                        $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                        #endregion        

                        # Rename the db
                        #$query = 'USE master; EXEC sp_renamedb ''{0}'', ''{1}'';' -f $database, $database;                
                        #Exec-Sql -Server $source_server -CommandText $query -CommandType NonQuery -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
                    }


                } # $IncludeDatabase
            }
            catch [Exception]
            {    
                Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;
            }
        } # foreach
    } # try

    catch [Exception]
    {    
        Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;
    }

    finally 
    {   
        # Enable ddl server triggers.
        foreach ($Row in $ds_server_triggers.Tables[0].Rows)        
        {
            [string]$trigger_name = $Row.Item('name');

            $query = 'ENABLE TRIGGER [{0}] ON ALL SERVER;' -f $trigger_name;        
            Write-Message -Text $query -ForegroundColor Yellow;
            $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;

            <#
            $query = 'RESTORE DATABASE [{0}] WITH RECOVERY;' -f $database_name;        
            Write-Message -Text $query -ForegroundColor Yellow;
            $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
           #>
        }
    }
}


function Create-AvailabilityGroup
{
[CmdletBinding()]
[Alias()]  
Param
(     
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$SourceServer,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$TargetServer,
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,          
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials, 
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]         
        [string]$ApplicationName = 'FSX',        

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=15)]
        [bool]$SkipTargetDatabaseIfExists = $true,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=16)]
        [bool]$DropTargetDatabaseIfExists = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=18)]
        [System.Object]$IncludeDatabase,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=19)]
        [System.Object]$ExcludeDatabase                
    )


        [bool]$user_interactive = [Environment]::UserInteractive;

    try
    {
        # Get the list of databases tpo process from the sourve server.                 
        [string]$query = 
        'SELECT name AS database_name
        FROM sys.databases d WHERE d.database_id > 4 AND d.source_database_id IS NULL AND d.is_distributor = 0 AND d.is_published = 0 
        AND d.is_read_only = 0 AND d.state_desc = N''ONLINE'' 
        AND replica_id IS NULL        
        ORDER BY database_name;';
       
        
        $ds_databases = Exec-Sql -Server $SourceServer -CommandText $query -CommandType DataSet -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
        foreach ($Row in $ds_databases.Tables[0].Rows)        
        {
            $database_name = $Row.Item('database_name');
            Write-Message -Text $database_name -ForegroundColor Yellow;

            # Skip these iteration            
            if ($ExcludeDatabase -contains $database_name ) { continue; }


            if ($IncludeDatabase -contains $database_name -or $IncludeDatabase -eq $null) 
            {	
                # Check if the database exists
	            $query = 'IF EXISTS(SELECT * FROM sys.databases WHERE name = ''{0}'') SELECT 1 AS bit ELSE SELECT 0 AS bit;' -f $database_name;        
                Write-Message -Text $query -ForegroundColor Yellow;
                [bool]$database_exists = Exec-Sql -Server $TargetServer -CommandText $query -CommandType Scalar -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
        
                if($database_exists)
                {
                    if ($DropTargetDatabaseIfExists)
                    {
                        # Drop the target database if exists. 
                        $query = 'DROP DATABASE [{0}];' -f $database_name;                
                        Write-Message -Text $query -ForegroundColor Yellow;
                        $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType 'NonQuery' -IntegratedSecurity $IntegratedSecurity -Credentials $Credentials -ApplicationName $ApplicationName;
                    }
                    else
                    {
                        # Skip the database if exists. 
                        # Do not process this database
                        if ($SkipTargetDatabaseIfExists) 
                        {
                            $text = 'Skipping database {0}.' -f $database_name;                    
                            Write-Message -Text $text -ForegroundColor Yellow;
                            Continue; 
                        }
                    }
                }
                
                $ag_name = 'AG_{0}' -f $database_name;                

                $query = 
                'CREATE AVAILABILITY GROUP [{0}] WITH (AUTOMATED_BACKUP_PREFERENCE = none, BASIC, DB_FAILOVER = OFF, DTC_SUPPORT = NONE)
                FOR DATABASE [{1}] REPLICA ON
                N''{2}'' WITH (ENDPOINT_URL = N''TCP://Prod-SQL-STD-N1.winnersinc-uk.local:5022'', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
                , SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)),
                N''{3}'' WITH (ENDPOINT_URL = N''TCP://Prod-SQL-STD-N2.winnersinc-uk.local:5022'', FAILOVER_MODE = AUTOMATIC, AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
                , SEEDING_MODE = AUTOMATIC, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO));' -f $ag_name, $database_name, $SourceServer, $TargetServer;
                Write-Message -Text $query -ForegroundColor Green;
                $val = Exec-Sql -Server $SourceServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;  
                                
                $query = 
                'ALTER AVAILABILITY GROUP [{0}] JOIN; 
                 ALTER AVAILABILITY GROUP [{0}] GRANT CREATE ANY DATABASE;' -f $ag_name;
                Write-Message -Text $query -ForegroundColor Yellow;
                $val = Exec-Sql -Server $TargetServer -CommandText $query -CommandType NonQuery -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;  
                          

            #} # $IncludeDatabase
        } # foreach
    } # try

    }
    catch [Exception]
    {    
        Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;
    }  
  
}
