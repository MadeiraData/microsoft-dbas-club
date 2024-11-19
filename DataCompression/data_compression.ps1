<#
.SYNOPSIS
    This script automates the process of applying data compression to indexes in sql server.

.DESCRIPTION
    The scripts goes over all databases on the sql serevr instance and processes all indexes that were not 
    built using the data_compression index option.

    Key Features:
    Supported indexes types: 1 = Clustered rowstore (B-tree), 2 = Nonclustered rowstore (B-tree).
    Supports Filtered indexes.
    Supports online index rebuild based on the sql server instance edition.
    Flip/Switch Primary Key keys order. This is a very specific rare requirement.

    Use cases:
    Deploy a policy where all indexes are required to be compressed.
    Move objets to a new/different file group.


.PARAMETER 
    [string]$Server
    The sql server to process. If no value is passed the local computer name will be used.

.PARAMETER 
    [switch]$WindowsAuthentication
    Use $WindowsAuthentication in order to connect to sql server using the current identity.

.PARAMETER 
    [string]$SqlUser
    The sql login that will be used to connect to sql server.
    If $WindowsAuthentication is passed $SqlUser is disregarded.


.PARAMETER 
    [bool;]$replace_filegroup
    Optionaly rebuild the index on a new file group.

.PARAMETER 
    [bool]$switch_pk_keys_order
    Optionaly flip/switch the order of the keys in the Primary Keys index.
    This was originally added for a very specific case.

.PARAMETER 
    [int]$max_num_pk_keys
    $max_num_pk_keys only takes effect if the pramter $switch_pk_keys_order is set True.
    $max_num_pk_keys limmits the number of keys supported by the script. Current limmit is a Primary Key index with 4 keys.

.PARAMETER 
    [bool]$drop_fks 
    if $drop_fks is true the script drops refferencing FKs, that is an FK whos columns refference index keys of an index we process.
    FKs that are dropped are recreated after the index has been processed.
    When set false refferencing FKs will not be dropped resulting in some of the indexes rebuild to fail due to the 
    refferncing FK preventing to drop the index before creating it with the data compression option.

.PARAMETER 
    [string[]]$IncludeDatabase
    Specify spcefic an explicit databases list to process in the form of: 'db1','db2', 'db3'

.PARAMETER 
    [string[]]$ExcludeDatabase
    Specify spcefic an explicit databases list to exclude in the form of: 'db1','db2', 'db3'

    

.EXAMPLE    
    Work on the local instance using WindowsAuthentication.
    .\data_compression.ps1;
    .\data_compression.ps1 -Server $env:COMPUTERNAME; 
    .\data_compression.ps1 -Server $env:COMPUTERNAME -WindowsAuthentication;

    Work on the local instance using SQl Authentication while processing 2 specific databases only.
    .\data_compression.ps1 -IncludeDatabase 'DBA','CloudMonitoring' -SqlUser yaniv;

    Work on remote instance using WindowsAuthentication
    .\data_compression.ps1 -Server server1; 
    .\data_compression.ps1 -Server server1 -WindowsAuthentication;


.NOTES
    Author: Yaniv Etrogi - 20220502
    License: MIT
    Version: 2.0

    Please note the bellow for cases where the authentication type is sql authentication ($WindowsAuthentication is not passed).
    The script creates 2 files based on the user input in the working directory (the folder where the Powershell script is located):
    1. sql_user.txt
    2. sql_password.txt

    sql_user.txt is plain text file containing the sql user name.
    sql_password.txt is an encrypted text file containg the sql user password.

    When the 2 files exists you can simply execute the script with out parameters for credentials, just like this:  .\data_compression.ps1
    This allows to automate the script execution.     

    Note that the preserved password on disk matches a specific sql login.
    If needs to be used with another sql login simply delete the 2 files and the script execution will prompt you for credentials to be enetered.    

#>

Param
    (   
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=0)] 
        [string]$Server = $env:COMPUTERNAME,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=1)]
        [switch]$WindowsAuthentication,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=2)] 
        [string]$SqlUser,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)] 
        [bool]$ReplaceFilegroup = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)] 
        [bool]$SwitchPkKeysOrder = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=5)]
        [int]$MaxNumberOfPkKeys = 2,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=6)]
        [bool]$DropFks = $false,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=7)]
        [string[]]$IncludeDatabase,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=8)]
        [string[]]$ExcludeDatabase
    )



#region <functions>
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
        [switch]$LogToFile,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false,  Position=4)]
        [string]$LogFileName
    )
    Begin
    {
        try
        {
            [bool]$user_interactive = [Environment]::UserInteractive;

            # If this is not a user session and we do not log to file exit here.
            if(-not $user_interactive -and -not $LogToFile ) 
            {
                return; 
            }

            [string]$dt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss');
            [string]$message = '{0} - {1}:  {2}' -f $dt, $Severity, $Text; 
            

            if ($user_interactive) 
            {
                if($Severity -eq 'Error')
                {
                    Write-Host -ForegroundColor Red $message; 
                }
                else
                {
                    Write-Host -ForegroundColor $ForegroundColor $message; 
                }
            };

            
            if ($LogToFile) 
            {                
                #[string]$log_file_full_name = '{0}\{1}' -f $PSScriptRoot, $LogFileName;                                
                
                if (Test-Path -Path $LogFileName)
                {
                    $isWritten = $false;
                    do
                    {
                        try
                        {
                            Add-Content -Path $LogFileName -Value $message #-ErrorAction Continue;
                            $isWritten = $true;
                        }
                        catch{ }
                    } until ( $isWritten )
                }
                else
                {
                    Set-Content -Path $LogFileName -Value $message;
                }
            }        
        }
        catch
        {       
            Write-Message -Severity Error -Text $($_.Exception.Message) -LogFileName $log_file_full_name;
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
        $val = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType Scalar -IntegratedSecurity $true -Credentials $credentials;     
   DataSet            
        $ds = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType DateSet -IntegratedSecurity $true -Credentials $credentials;     

#>
function Exec-Sql
{
    [CmdletBinding()]
    [Alias()]    
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
        [int32]$CommandTimeOut = 30,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [string]$ApplicationIntent        
    )

    Begin
    {
        $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";

        try
        {
            if ($IntegratedSecurity)
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            }
            else
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString, $Credentials);
                #$SqlConnection.Credential = $Credentials;
            }

            $SqlCommand = New-Object System.Data.SqlClient.SqlCommand;            
            $SqlCommand.Connection = $SqlConnection;
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



<#
.Synopsis
   Test sql connection
.DESCRIPTION
   Tests a connection to an instance of sql server.
.EXAMPLE
   Test-SqlConnection -Server $Server -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials;    
#>
function Test-SqlConnection
{
    [CmdletBinding()]
    [Alias()]
    [OutputType('boolean')]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server = $env:COMPUTERNAME,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database = 'master',

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [bool]$IntegratedSecurity,  

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=3)]
        [System.Data.SqlClient.SqlCredential]$Credentials,     

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=4)]
        [string]$ApplicationName        
    )

    Begin
    {
        $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";
        [bool]$rc = $false;

        #$ErrorActionPreference = SilentlyContinue;
        #$ErrorActionPreference = 'Stop'
    }

    Process
    {
        try
        {            
            if ($IntegratedSecurity)
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            }
            else
            {
                $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString, $Credentials);
            }
            
            $SqlCommand = New-Object System.Data.SqlClient.SqlCommand;
            $SqlCommand.Connection = $SqlConnection;            
            
            # Here is where we actually test the connection.
            $SqlConnection.Open();                       
            $rc = $true;
        }
        catch
        {   
            $rc = $false;                     
            Write-Message -Severity Error -Text $($_.Exception.Message) -LogFileName $log_file_full_name;
            
        }
        finally
        {            
            if ($SqlConnection.State -eq 'Open') { $SqlConnection.Close(); }
        }
       
        return $rc;
    }
}


#endregion


#region <sql credentials>
if (-not $WindowsAuthentication )
{    
    [string]$sql_user_full_name = Join-Path $PSScriptRoot 'sql_user.txt';
    [string]$sql_password_full_name = Join-Path $PSScriptRoot 'sql_password.txt';
        
    # If we pass an argument executing the script taht argument takes effect.
    if ($MyInvocation.BoundParameters.ContainsKey('SqlUser'))
    {
        $SqlUser = $($MyInvocation.BoundParameters['SqlUser']);
    }
    else
    {
        if (-not (Test-Path $sql_user_full_name))
        {
            Write-Host -ForegroundColor White 'When not using WindowsAuthentication the $SqlUser paramter must be suppied for the very first run.';
            Write-Host 'Please type your sql login and hit the Enter key.';
            [string]$SqlUser = Read-Host;
            Set-Content -Path $sql_user_full_name -Value $SqlUser;
        }
    }

    # If there is no password file generate the sql password as an encrypted secure string and save to file.
    if (-not (Test-Path $sql_password_full_name))
    {        
        Write-Host 'Please type your password and hit the Enter key.'
        $secure_string = Read-Host -AsSecureString;
        $encrypted = ConvertFrom-SecureString -SecureString $secure_string;        
        $encrypted | Set-Content -Path $sql_password_full_name;
    }  

    # Create an SqlCredential object to be used for sql authetication 
    # If the script execution does not have a value for $SqlUser then we read it from disk.
    if (-not $MyInvocation.BoundParameters.ContainsKey('SqlUser'))
    {
        $SqlUser = Get-Content -Path $sql_user_full_name;
    }
    [securestring]$password = Get-Content $sql_password_full_name | ConvertTo-SecureString;
    [pscredential]$pscredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SqlUser, $password;
    $pscredential.Password.MakeReadOnly();
    [System.Data.SqlClient.SqlCredential]$Credentials = New-Object System.Data.SqlClient.SqlCredential($pscredential.username, $pscredential.password);        
}




# Test database connection before we go on.
Write-Message -Severity Info -Text 'Testing sql server instance connection...' -LogFileName $log_file_full_name -ForegroundColor Cyan;
try
{
    [bool]$sql_connection_status = Test-SqlConnection -Server $Server -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials;
}
catch {}
if ($sql_connection_status)
{
    Write-Message -Severity Info -Text 'Testing sql server instance success.' -LogFileName $log_file_full_name -ForegroundColor Cyan;
}
else
{
    Write-Message -Severity Warn -Text 'Testing database connection failed. Terminating.' -LogFileName $log_file_full_name -ForegroundColor Cyan;
    Remove-Item $sql_password_full_name;
    return;
}

#endregion



[bool]$user_interactive = [Environment]::UserInteractive;
[string]$new_line = [Environment]::NewLine;
[string]$application_name = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name);

# Log file.
[string]$log_file = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name);
$log_file += '.log';
$log_file_full_name = join-path $PSScriptRoot $log_file;



# Input validation.
if ($IncludeDatabase -and $ExcludeDatabase)
{        
    Write-Message -Text 'You cannot select both paramteres: IncludeDatabase and ExcludeDatabase.' -ForegroundColor Cyan;
    return;
}



try
{
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null;
    $scripter = New-Object ('Microsoft.SqlServer.Management.Smo.Scripter') $server;    
    $scripting_options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions;
    $edition = $scripter.Server.Edition;    
    $scripting_options.AnsiPadding = $false;


    # Get the list of databases.
    #region <databases>    
    Write-Message -Severity Info -Text 'Getting the list of databases.' -LogFileName $log_file_full_name;
    [string]$query = 
        'SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = N''ONLINE'' AND is_read_only = 0 AND DATABASEPROPERTYEX(name , N''Updateability'') = N''READ_WRITE''
         --AND name NOT LIKE ''%test%'' 
         --AND name NOT LIKE ''%old%'' 
         --AND name IN ('''') 
         ORDER BY name;';
    $ds_Databases = Exec-Sql -Server $server -Database 'master' -CommandText $query -CommandType DataSet -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials -ApplicationName $application_name;             
    #endregion

       

    # Loop over the databases   
    foreach($row in $ds_Databases.Tables[0].Rows)
    {        
        [string]$database = $row.Item('name');        
            
        # Skip this iteration.
        if ($ExcludeDatabase -contains $database ) { continue; }                
        
        # Process the explicit database list or all the databases.
        if ($IncludeDatabase -contains $database -or $IncludeDatabase -eq $null) 
        {            
            Write-Message -Severity Info -Text "Processing database $($database)" -LogToFile -LogFileName $log_file_full_name -ForegroundColor Yellow;

        
            # Get the indexes with no data compression to be processed.
            [string]$query = 
            'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;        
            SELECT --TOP 1
	            SCHEMA_NAME(t.schema_id) AS schema_name, t.name AS table_name, i.name AS index_name, i.is_primary_key, i.is_unique_constraint, i.index_id, i.index_id, au.used_pages/128 AS size_mb, i.is_unique
            FROM sys.indexes i
            INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
            INNER JOIN sys.tables t ON t.object_id = i.object_id
            INNER JOIN sys.allocation_units au ON au.container_id = p.partition_id
            INNER JOIN sys.filegroups g ON g.data_space_id = au.data_space_id 
            WHERE t.is_ms_shipped = 0 AND t.is_published = 0 AND t.is_replicated = 0 AND t.is_memory_optimized = 0 AND i.is_hypothetical = 0 AND i.name IS NOT NULL AND i.is_disabled = 0        
            AND p.data_compression_desc NOT LIKE N''PAGE''     
            AND au.type_desc = N''IN_ROW_DATA''
            AND i.type IN (1, 2)                    
            --AND t.name = ''''        
            --AND i.name = ''''            
            ORDER BY t.name;';        
            $ds = Exec-Sql -Server $Server -Database $database -CommandText $query -CommandType DataSet -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials -ApplicationName $application_name;     

            #$text = 'The number of indexes to process: {0}' -f $ds.Tables[0].Rows.Count;
            Write-Message -Severity Info -Text "The number of indexes to process: $($ds.Tables[0].Rows.Count)" -LogToFile -LogFileName $log_file_full_name -ForegroundColor Yellow;    

            try
            {
                # Loop over indexes
                [int]$counter = 1;
                foreach ($row in $ds.Tables[0].Rows)
                {
                    try
                    {
                        [string]$schema_name = $row.Item('schema_name');
                        [string]$table_name  = $row.Item('table_name');     
                        [string]$index_name  = $row.Item('index_name');        
                        [bool]$is_primary_key  = $row.Item('is_primary_key');       
                        [bool]$is_unique_constraint  = $row.Item('is_unique_constraint');  
                        [bool]$is_unique  = $row.Item('is_unique');                      
                        [int]$index_id = $row.Item('index_id');                           
                                                
                        Write-Message -Severity Info -Text "$($counter) | Processing database:$($database) | table:$($table_name) | index:$($index_name)" -LogToFile -LogFileName $log_file_full_name;                               
                           

                        # Script the create command.         
                        $db = $scripter.Server.Databases[$database];
                        $table = $db.Tables[$table_name, $schema_name]                
                        $index = $table.Indexes[$index_name];   
                        $columns = $index.IndexedColumns;     
                        
                        # Get FKs refferencing the index columns in order to drop the FKs prior to droping the index/unique constaraint.
                        if ($drop_fks)
                        {
                            foreach ($c in $columns)
                            {                       
                                [string]$fk_drop = $null;
                                [string]$fk_create = $null;                       
                
                                $refferecing_object = $table.Columns[$c.Name].EnumForeignKeys();
                                foreach ($obj in $refferecing_object)
                                {                             
                                    $refferncing_table = $obj.Table_Name;
                                    $refferncing_fk = $obj.Name;
                
                                    # Drop refferencing FK in order to be able to modify the index
                                    $scripting_options.DriForeignKeys = $true;  
                                    $scripting_options.ScriptDrops = $true;
                                    $fk_drop += $scripter.Server.Databases[$database].Tables[$refferncing_table, $schema_name].ForeignKeys[$refferncing_fk].Script($scripting_options);  
                                    $fk_drop += $new_line;                            
                
                                    # Create refferencing FK
                                    $scripting_options.ScriptDrops = $false;
                                    $fk_create += $scripter.Server.Databases[$database].Tables[$refferncing_table, $schema_name].ForeignKeys[$refferncing_fk].Script($scripting_options) + [System.Environment]::NewLine;  
                                    $fk_create += $new_line;
                                }                    
                            }   
                        }   


                        [bool]$is_clustered = $false;                        
                        if ($index.IndexType -eq [Microsoft.SqlServer.Management.Smo.IndexType]::ClusteredIndex) {$is_clustered = $true; }

                        #[bool]$is_clustered_columnstore = $false;                        
                        #if ($index.IndexType -eq [Microsoft.SqlServer.Management.Smo.IndexType]::ClusteredColumnStoreIndex) {$is_clustered_columnstore = $true; }


                        # Find if the table contains a blob column.
                        #if($is_clustered)
                        #{
                        #    $query = 
                        #    'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                        #    IF EXISTS
                        #    (
	                    #        SELECT 
		                #             SCHEMA_NAME(t.schema_id) [schema], t.name [table], c.column_id  , c.name [column] ,tp.name [type], c.max_length
	                    #        FROM sys.tables t
	                    #        INNER JOIN sys.columns c ON c.object_id = t.object_id
	                    #        INNER JOIN sys.types tp ON tp.user_type_id = c.user_type_id
	                    #        WHERE t.is_ms_shipped = 0 AND t.name LIKE ''{0}'' AND tp.name IN (''text'', ''ntext'', ''image'', ''xml'', ''binary'')
                        #    )
                        #    SELECT 1 AS bit ELSE SELECT 0 AS bit;' -f $table_name;
                        #    [bool]$blob = Exec-Sql -Server $Server -Database $database -CommandText $query -CommandType Scalar -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials -ApplicationName $application_name;     
                        #}



                        # Find if the table contains a blob column.
                       [bool]$has_blob = $false;
                       # foreach ($column in $table.Columns) 
                       # {
                       #     if ($column.DataType.MaximumLength -eq -1 -or
                       #         $column.DataType.Name -in @("text", "ntext", "image", "varbinary", "nvarchar", "varchar") -and $column.DataType.MaximumLength -eq -1) 
                       #         {
                       #             $has_blob = $true;
                       #             break;
                       #         }
                       # }


                       $lobs = @("text", "ntext", "image", "varbinary", "nvarchar", "varchar")
                       foreach ($column in $table.Columns) 
                       {
                        if ($column.DataType.Name -in $lobs -and ($column.DataType.MaximumLength -eq -1 -or $column.DataType.Name -in @("text", "ntext", "image")) ) 
                        {
                            $has_blob = $true;
                            break;                            
                        }

                        }
                        #<#
                        # Find if the table has a columnstore clustered index as it prevents online rebuild for all none clustered indexes.
                        [bool]$table_has_clustered_columnstore = $false;                        
                        foreach ($index in $table.Indexes) 
                        {
                            if ($index.IndexType -eq [Microsoft.SqlServer.Management.Smo.IndexType]::ClusteredColumnStoreIndex) 
                            {
                                $table_has_clustered_columnstore = $true;
                                #$is_clustered = $false;   
                            }
                        }
                        ##>

                        # Set ONLINE=ON based on the edition.
                        # Can only be rebuild offline regrdless of the edition.
                        $index.OnlineIndexOperation = $false;
                        if ($has_blob -and $is_clustered -or $table_has_clustered_columnstore)
                        {
                            $index.OnlineIndexOperation = $false;
                        }
                        # Can be rebuild online based on the edition.
                        else 
                        {                        
                            if ($edition -like '*Developer*' -or $edition -like '*Enterprise*' )
                            {
                                $index.OnlineIndexOperation = $true;
                            }
                        }
               

                        # Drop
                        $scripting_options.ScriptDrops = $true;                   
                        $idx_drop = $scripter.Server.Databases[$database].Tables[$table_name, $schema_name].Indexes[$index_name].Script($scripting_options);                                          
                        if($idx_drop.Count -eq 1) {$drop_command = $idx_drop[0];}
                        if($idx_drop.Count -eq 2) {$drop_command = $idx_drop[1];}                                                    

                        # Create
                        $scripting_options.ScriptDrops = $false;                                   
                        $idx_create = $scripter.Server.Databases[$database].Tables[$table_name, $schema_name].Indexes[$index_name].Script($scripting_options);                                          
                        if($idx_create.Count -eq 1) {$create_command = $idx_create[0];}
                        if($idx_create.Count -eq 2) {$create_command = $idx_create[1];}                    
                            
                        # Get the index columns bit.   
                         $index_columns = $null;
                        if (-not $is_clustered_columnstore)
                        {                             
                            [int]$columns_left_bracket = $create_command.IndexOf('(');
                            [int]$columns_right_bracket = $create_command.IndexOf(')');
                            [string]$index_columns = $create_command.Substring($columns_left_bracket, $columns_right_bracket-$columns_left_bracket +1 )
                        }


                        # Create the first part of the create index command.
                        $basic_syntax = $null;             
                    
                        #region<Switch PK keys>
                        # This is an option for PKs only allowing to switch/flip the order of the keys (limmited to 4 index keys).   
                        [int]$pk_keys_count = $index_columns.Split(',').Count;                                 
                        if ($switch_pk_keys_order -and $is_primary_key -and $pk_keys_count -gt 1 -and $pk_keys_count -le $max_num_pk_keys ) 
                        {                            
                            Write-Message -Severity Info -Text "Switching PK keys" -LogToFile -LogFileName $log_file_full_name -ForegroundColor Yellow;

                            [string]$basic_syntax = 'ALTER TABLE ';                
                            $basic_syntax += '[{0}].[{1}] ADD CONSTRAINT [{2}] PRIMARY KEY ' -f $schema_name, $table_name, $index_name;
                            if ($is_clustered) {$basic_syntax += 'CLUSTERED '; } else {$basic_syntax += 'NONCLUSTERED '}

                            $key1 = $index_columns.Split(',')[0];
                            $key1 = $key1.Replace('(', '').Trim();
                    
                            switch ($pk_keys_count )
                            {
                                2 
                                {
                                    # Get the keys.                            
                                    $key2 = $index_columns.Split(',')[1]; 

                                    # Remove the brackets.
                                    $key2 = $key2.Replace('(', '').Trim();
                                    $key2 = $key2.Replace(')', '').Trim();
                                                        
                                    # Add the keys while replacing the order                                
                                    $basic_syntax += '({0}, {1})' -f $key2, $key1;
                                    break;
                                }

                                3 
                                {                            
                                    $key2 = $index_columns.Split(',')[1]; 
                                    $key3 = $index_columns.Split(',')[2]; 
                            
                                    $key2 = $key2.Replace('(', '').Trim();
                                    $key2 = $key2.Replace(')', '').Trim();
                                    $key3 = $key3.Replace('(', '').Trim();
                                    $key3 = $key3.Replace(')', '').Trim();

                                    $basic_syntax += '({0}, {1}, {2})' -f $key3, $key2, $key1;    
                                    break;
                                }

                                4 
                                {                            
                                    $key2 = $index_columns.Split(',')[1]; 
                                    $key3 = $index_columns.Split(',')[2]; 
                                    $key4 = $index_columns.Split(',')[3]; 

                                    $key2 = $key2.Replace('(', '').Trim();
                                    $key2 = $key2.Replace(')', '').Trim();
                                    $key3 = $key3.Replace('(', '').Trim();
                                    $key3 = $key3.Replace(')', '').Trim();
                                    $key4 = $key4.Replace('(', '').Trim();
                                    $key4 = $key4.Replace(')', '').Trim();


                                    $basic_syntax += '({0}, {1}, {2}, {3})' -f $key4, $key3, $key2, $key1;    
                                    break;
                                }
                            }                   
                            [bool]$keys_switched_order = $true;     

                        } # if ($switch_pk_keys_order              
                
                        else
                        {                                 
                            [string]$basic_syntax = 'CREATE ';                
                            if ($is_unique_constraint -or $is_primary_key -or $is_unique) {$basic_syntax += 'UNIQUE '; }
                            if ($is_clustered ) {$basic_syntax += 'CLUSTERED ';} 
                            #if ($is_clustered_columnstore ) {$basic_syntax += 'CLUSTERED COLUMNSTORE ';} 
                            #if (-not $is_clustered -and-not $is_clustered_columnstore) {$basic_syntax += 'NONCLUSTERED '}
                            $basic_syntax += 'INDEX ';
                            $basic_syntax += '[{0}] ON [{1}].[{2}]{3}{4} ' -f $index_name, $schema_name, $table_name, $new_line, $index_columns;
                        }
                        #endregion
                
                        # Get the index options bit.
                         $index_options = $null;                                                   
                        [int]$with  = $create_command.IndexOf('WITH'); 
                        [int]$index_options_left_bracket = $create_command.IndexOf('(', $with); 
                        [int]$index_options_right_bracket = $create_command.LastIndexOf('ON');                  
                        [string]$index_options = $create_command.Substring($index_options_left_bracket+1, $index_options_right_bracket-$index_options_left_bracket-3);
                        
                        # Get the include columns list.
                        $include_columns = $null;                                                   
                        if ($create_command.Contains('INCLUDE'))
                        {
                            [int]$include  = $create_command.IndexOf('INCLUDE'); 
                            [int]$include_left_bracket = $create_command.IndexOf('(', $include ); 
                            [int]$include_right_bracket = $create_command.IndexOf(')', $include_left_bracket + 2);                  
                            [string]$include_columns = $create_command.Substring($include_left_bracket+1, $include_right_bracket-$include_left_bracket-1);
                            $include_columns = 'INCLUDE ({0})' -f $include_columns;
                        }
                        #return
                        # Get the filtered index bit.
                        $filter_predicate = $null;
                        if ($create_command.Contains('WHERE'))
                        {
                            [int]$where  = $create_command.IndexOf('WHERE'); 
                            [int]$where_left_bracket = $create_command.IndexOf('(', $where); 


                            # Find the last occurrence of ')' before 'WITH'
                            # Locate the position of 'WITH'.
                            $with_index = $create_command.IndexOf("WITH");

                            # Extract the string before 'WITH'.
                            $string_before_with = $create_command.Substring(0, $with_index);

                            # Step 3: Find the last occurrence of ')'
                            $where_right_bracket = $string_before_with.LastIndexOf(")");

                            #[int]$where_right_bracket = $lastParenIndex
                            #[int]$where_right_bracket = $create_command.LastIndexOf( ")", $create_command.Substring(0, $create_command.IndexOf('WITH')) )
                                        
                            
                            [string]$filter_predicate = $create_command.Substring($where_left_bracket+1, $where_right_bracket-$where_left_bracket-1);
                            $filter_predicate = 'WHERE ({0}) ' -f $filter_predicate;
                            #$filter_predicate += ')';
                        }                      
                
                        # Get the filegroup.                
                        if (-not $replace_filegroup)
                        {
                            $filegroup = $null;
                            [int]$on  = $create_command.LastIndexOf('ON'); 
                            [string]$filegroup = $create_command.Substring($on +2 , $create_command.Length - $on-2); 
                        }

                        # Add DROP_EXISTING
                        if(-not $index_options.Contains('DROP_EXISTING') -and -not $keys_switched_order ) # If we flipped the keys order then we perform a DROP..CREATE command.
                        {
                            $drop_existing = (', DROP_EXISTING = ON');   
                            $index_options += $drop_existing;             
                        }

                         # If DROP_EXISTING is set OFF replace it to ON.
                        if($index_options.Contains('DROP_EXISTING = OFF'))
                        {
                            $index_options = $index_options.Replace('DROP_EXISTING = OFF', 'DROP_EXISTING = ON');                
                        }                              

                        # Add DATA_COMPRESSION
                        if( -not $index_options.Contains('DATA_COMPRESSION'))
                        {                
                            $data_compression = ', DATA_COMPRESSION = PAGE';
                            $index_options += $data_compression;
                        }              
                        
                                
                        # Construct the create index command.
                        $create_command = '{0} {1} {5} {2} WITH ({3}) {5} ON {4}; {5} GO {5}' -f $basic_syntax, $include_columns, $filter_predicate, $index_options, $filegroup, $new_line ;                   
                
                        # Remove the GO batch separator.    
                        [string]$command = [regex]::Split($create_command, "\bGO\b");    
                                
                        [string]$begin_block = 'BEGIN TRY;{0}BEGIN TRANSACTION;{0}' -f $new_line;
                        [string]$end_block = 'COMMIT TRANSACTION;{0}END TRY{0}BEGIN CATCH; IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;' -f $new_line;

                        if($is_primary_key -and $keys_switched_order)
                        {
                            $command = '{0}{1}{2}{6} {3}{6}{4} {6}{5}' -f $begin_block, $fk_drop, $drop_command, $command.Trim(), $fk_create, $end_block, $new_line;
                        }
                
                        # Switching the order of the keys require to first drop the constraint so we create a DROP...CREATE command wrapped in a transaction block.
                        #if(-$is_primary_key -and $keys_switched_order)
                        #{
                        #    $command = 'BEGIN TRY;{2} BEGIN TRANSACTION;{2} {0};{2} {1}{2}COMMIT TRANSACTION;{2}END TRY{2}BEGIN CATCH; IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH;' -f $drop_command, $command.Trim(), $new_line;                  
                        #}
                 
                
                        $msg = '{1}-- {0}{1}{2}' -f $counter, $new_line, $command;                    
                        Write-Message -Severity Info -Text $msg -LogToFile -LogFileName $log_file_full_name -ForegroundColor Cyan;                         
                
                        try
                        {                                           
                            $val = Exec-Sql -Server $Server -Database $database -CommandText $command -CommandType NonQuery -IntegratedSecurity $WindowsAuthentication -Credentials $Credentials -ApplicationName $application_name;                                                         
                        }
                        catch 
                        {
                            [string]$exception = $_.Exception.Message;
                            #Write-Message -Severity Info -Text $msg -LogToFile -LogFileName $log_file_full_name -ForegroundColor Cyan;
                            Write-Message -Severity Error -Text $exception -LogToFile -LogFileName $log_file_full_name -ForegroundColor Red;                     
                        }
                
                        $counter +=1;     
                        $keys_switched_order = $false;     
                    }
                     catch [Exception] 
                    {        
                        $exception = $_.Exception.Message;
                        Write-Message -Severity Error -Text $exception -LogToFile -LogFileName $log_file_full_name -ForegroundColor Red;                 
                    }   
               
                } #$ds.Tables[0].Rows
            }
            catch [Exception] 
            {        
                $exception = $_.Exception.Message;
                $line_nmber = $_.InvocationInfo.ScriptLineNumber;
    
                Write-Message -Severity Error -Text "Execption at line number: $($line_nmber)" -LogToFile -LogFileName $log_file -ForegroundColor Red;                    
                Write-Message -Severity Error -Text $exception -LogToFile -LogFileName $log_file -ForegroundColor Red;      
            }    
        }
    } #foreach databases
}
catch [Exception] 
{        
    $exception = $_.Exception#.Message;    
    Write-Message -Severity Error -Text $exception -LogToFile -LogFileName $log_file -ForegroundColor Red;                    
} 

