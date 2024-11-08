<#
    20220525 Yaniv Etrogi
    Get the count of files in a folder including subfolders for the specific file extentions provided
    

#>
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
    #[OutputType([int])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [string]$CommandText,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=3)]
        [string]$CommandType,       

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=4)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [System.Data.SqlClient.SqlCredential]$Credentials,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)]
        [int32]$CommandTimeOut = 30,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationName = "CloudMonitoring",
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [string]$ApplicationIntent        
    )

    Begin
    {
        $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";
        
        if($CommandType -notin ('NonQuery' ,'Scalar' ,'DataSet') )
        {
            throw 'The ''$CommandType'' parameter contains an invalid value Valid values are: ''NonQuery'' ,''Scalar'' ,''DataSet''';
        }

        try
        {
            if ($windows_authentication)
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            }
            else
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString, $Credentials);
                $SqlConnection.Credential = $Credentials;
            }

            
            $SqlCommand = $sqlConnection.CreateCommand();
            $SqlConnection.Open(); 
            $SqlCommand.CommandText = $CommandText;                      
                  
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


#region <Insert-Sql>
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