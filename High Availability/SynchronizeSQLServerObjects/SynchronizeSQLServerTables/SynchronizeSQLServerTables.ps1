<#
    20231016 - Yaniv Etrogi
    Script sql server objects that were changed in the last xx minutes.

#>

 Set-Location 'c:\';

# Edit here.
[bool]$execute_script_file = $true;
[string]$destination_server = $env:COMPUTERNAME;
[string]$database = '';

#The number of minutes to check back in order to find if a object was addedd\changed.
$minutes = 30;


try
{
    #region <variabes>  
    [bool]$user_interactive = [Environment]::UserInteractive;

    [string]$helpers_file_path = Split-Path -Parent $PSScriptRoot;
    [string]$helpers_file_full_name = Join-Path $helpers_file_path 'helpers.ps1';
    . $helpers_file_full_name;
    
    $new_line = [Environment]::NewLine;    
    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHHmmss');        

    Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=15.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91";
    $smo_server = New-Object Microsoft.SqlServer.Management.Smo.Server($env:COMPUTERNAME);    
            
    [string]$server = $env:COMPUTERNAME;
    [string]$application_name = $MyInvocation.MyCommand.Name.Split(".")[0];  
    
    # Log file
    [string]$log_file = '{0}.{1}' -f $application_name, 'log' ;     
    [string]$log_folder = '{0}\{1}' -f $PSScriptRoot, 'Logs' ;
    [string]$log_file_full_name = '{0}\{1}\{2}' -f $PSScriptRoot, 'Logs', $log_file;
    if (-not (Test-Path -Path $log_folder)) {New-Item -ItemType Directory $log_folder; }        

    # Script file
    $script_file = '{0}_{1}_{2}.{3}' -f $server, 'tables', $timestamp, 'sql';
    $script_folder = '{0}\{1}' -f $PSScriptRoot, 'TablesChangesScripts';
    $script_file_full_name = '{0}\{1}\{2}' -f $PSScriptRoot, 'TablesChangesScripts', $script_file;
    if (-not (Test-Path -Path $script_folder)) {New-Item -ItemType Directory $script_folder; }

    #endregion        
    

       
    #region <get-objects> 

    # For tables that were changed we script the alter table command.
    # For tables that were added we script the create command.
    # For views that were added/changed we script the create command.

    # Get the tables that were changed in the past xx hours.    
    $dt = (Get-Date).AddMinutes(-$minutes);       
    $text = '{0} - Get the tables were changed in the last {1} minutes.' -f $server, $minutes  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;    
    $query = 'SELECT DatabaseName,SchemaName,ObjectName,Command FROM master.dbo.DDLAuditLog WHERE DatabaseName IN (''{1}'') AND EventType IN (''ALTER_TABLE'', ''DROP_TABLE'') AND InsertTime > DATEADD(MINUTE, -{0}, CURRENT_TIMESTAMP);' -f $minutes, $database;
    $ds_tables_altered = Exec-Sql -Server $server -Database 'master' -CommandText $query -CommandType DataSet -IntegratedSecurity $true -ApplicationName $application_name;
    
        
    # Get the tables that were added the past xx hours.         
    $text = '{0} - Get the tables were added in the last {1} minutes.' -f $server, $minutes  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;    
    $query = 'SELECT name, type_desc FROM sys.objects WHERE type_desc IN (''USER_TABLE'') AND create_date > DATEADD(MINUTE, -{0}, CURRENT_TIMESTAMP);' -f $minutes;
    $ds_tables = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType DataSet -IntegratedSecurity $true -ApplicationName $application_name;
        
    if ($ds_tables.tables[0].Rows.Count -gt 0)
    {
        [Microsoft.SqlServer.Management.Smo.SchemaCollectionBase]$tables = $smo_server.Databases[$database].Tables;        
    }    

    # Get the views that were add/changed in the past xx hours.    
    $text = '{0} - Get the views were added/changed in the last {1} minutes.' -f $server, $minutes  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;    
    $query = 'SELECT name, type_desc FROM sys.objects WHERE type_desc IN (''VIEW'') AND (create_date > DATEADD(MINUTE, -{0}, CURRENT_TIMESTAMP) OR modify_date > DATEADD(MINUTE, -{0}, CURRENT_TIMESTAMP));' -f $minutes;
    $ds_views = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType DataSet -IntegratedSecurity $true -ApplicationName $application_name;

    if ($ds_views.tables[0].Rows.Count -gt 0)
    {
        [Microsoft.SqlServer.Management.Smo.SchemaCollectionBase]$views = $smo_server.Databases[$database].Views;        
    }    


    # If there no object added/changed we exit here.
    if ($ds_tables.tables[0].Rows.Count -eq 0 -and $ds_views.tables[0].Rows.Count -eq 0 -and $ds_tables_altered.tables[0].Rows.Count -eq 0) 
    {
        $text = '{0} - No objects were added/changed in the past {1} minutes. Terminating.' -f $server, $minutes;
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;
        return; 
    } 
    #endregion   
    
    
    

    #region <scripting options>    
    $scripting_options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions;
    $scripting_options.ScriptDrops = $false;
    $scripting_options.IncludeHeaders = $false;
    $scripting_options.AppendToFile = $true;
    $scripting_options.IncludeIfNotExists = $false
    $scripting_options.AnsiFile = $true;
    $scripting_options.AllowSystemObjects = $false;
    $scripting_options.ScriptForCreateDrop = $false
    $scripting_options.ScriptSchema = $true;
    #endregion

    #region <script>      
    
    [int]$counter = 1;
    [string]$dummy_line_to_be_replaced = ' /* This line will be replaced at the end of the script with the number of objects that were scripted. */';
    Add-Content -Path $script_file_full_name -Value $dummy_line_to_be_replaced;
           

    # Tables
    # New tables only
    if ($ds_tables.tables[0].Rows.Count -gt 0)
    {
        foreach ($obj in $tables)          
        {
            # If the current object is a system object we skip it.
            if($obj.IsSystemObject)
            {
                continue; 
            } 

            # If the current object is not part of the DataSet we skip this object as we only handle objects that werea added/changed.
            if (-not $ds_tables.tables[0].Rows.name.Contains($obj.Name) )
            {
                continue; 
            }                   


            [string]$text = '/* {0} */' -f $counter;   
            #$text += 'IF EXISTS (SELECT * FROM sys.objects WHERE name = N''{1}'' AND SCHEMA_NAME(schema_id) = ''{0}'') DROP TABLE {0}.{1};' -f $obj.Schema, $obj.Name, $new_line;        
       
            Add-Content -Path $script_file_full_name -Value $text;
            Add-Content -Path $script_file_full_name -Value "GO";

            $script = $obj.Script($scripting_options);
        
            foreach($s in $script)
            {            
                if (-not $s.StartsWith('SET'))
                {
                    $text = $s;
                }
            }

            Add-Content -Path $script_file_full_name -Value $text;
            Add-Content -Path $script_file_full_name -Value "GO";
            Add-Content -Path $script_file_full_name -Value $new_line;               
        
            $counter ++;          
        }
    }  


    # Tables
    # Changed tables only
    foreach ($row in $ds_tables_altered.tables[0].Rows)
    {
        [string]$text = '/* {0} */' -f $counter;   
        #$text += 'IF EXISTS (SELECT * FROM sys.objects WHERE name = N''{0}'') DROP TABLE {0};' -f $obj.Name, $new_line;        
       
        Add-Content -Path $script_file_full_name -Value $text;
        Add-Content -Path $script_file_full_name -Value "GO";

        #$command = $Row.Item('command');
        $text = $row.Item('command');       

        Add-Content -Path $script_file_full_name -Value $text;
        Add-Content -Path $script_file_full_name -Value "GO";
        Add-Content -Path $script_file_full_name -Value $new_line;           
        
        $counter ++;                  
    }  


    # Views
    # New views and chaned views
    [int]$i = 0;
    if ($ds_views.tables[0].Rows.Count -gt 0)
    {        
        foreach ($obj in $views)          
        {
            # If the current object is a system object we skip it 
            if($obj.IsSystemObject)
            {
                continue; 
            }           

            # If the current object is not part of the DataSet we skip this object as we only handle objects that werea added/changed.
            if (-not $ds_views.tables[0].Rows.name.Contains($obj.Name) )
            {
                continue; 
            }                   

            [string]$text = '/* {0} */{1}' -f $counter, $new_line;   
            $text += 'IF EXISTS (SELECT * FROM sys.objects WHERE name = N''{1}'' AND SCHEMA_NAME(schema_id) = ''{0}'') DROP VIEW {0}.{1};' -f $obj.Schema, $obj.Name, $new_line;        
       
            Add-Content -Path $script_file_full_name -Value $text;
            Add-Content -Path $script_file_full_name -Value "GO";

            $script = $obj.Script($scripting_options);
        
            foreach($s in $script)
            {            
                if (-not $s.StartsWith('SET'))
                {
                    $text = $s;
                }
            }

            Add-Content -Path $script_file_full_name -Value $text;
            Add-Content -Path $script_file_full_name -Value "GO";
            Add-Content -Path $script_file_full_name -Value $new_line;               
        
            $counter ++;     
            $i++ 
        }                   
    }  

   

    $number_of_objects_scripted = $counter-1
    $text = '{0} - The number of objects scripted: {1}.' -f $server, $number_of_objects_scripted ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green ;
            

    # Replace the dummy line at the top of the file.
    [string]$replace = '/* {1} {2} {1} Scripted by {0} {1}' -f $application_name, $new_line, $timestamp;
    $replace += ' The number of objects scripted: {0} {1}*/ {1}{1} ' -f $number_of_objects_scripted, $new_line;    
    $content = Get-Content -Path $script_file_full_name -Raw;  
    $content.Replace($dummy_line_to_be_replaced, $replace) | Set-Content -Path $script_file_full_name;
    #endregion <jobs>     
     
    

    #region <script content> 
    $script_file_content = Get-Content $script_file_full_name -Raw;
    
    # Break the script file content into commands based on the GO batch separator.    
    $script_file_splited = [regex]::Split($script_file_content, "\bGO\b");   
    #$script_file_splited = [regex]::Split($script_file_content, '(?smi)^[\s]*GO[\s]*$');       
    #endregion 
    


     #region <execute>    
    if ($execute_script_file)
    {
        $text = '{0} - Processing...' -f $destination_server;        
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Yellow;  
        #[string]$connection_string = 'Data Source={0}; Integrated Security=SSPI; Initial Catalog=msdb; Application Name={1}' -f $destination_server, $application_name;
            

        # Execute the splited jobs script against Secondary Replica(s).
        for($i=0; $i -lt $script_file_splited.Count -1; $i++)
        {
            $text = 'Executing command number: {0}' -f $i
            Write-Message -Text $text -LogToConsole -LogFileName $log_file_full_name;
            try
            {
                #$text = $script_file_splited[$i];
                #Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;    
                $rc = Exec-Sql -Server $destination_server -Database $database -CommandText $script_file_splited[$i] -CommandType NonQuery -IntegratedSecurity $true -ApplicationName $application_name;                                                           
            }
            catch [Exception]
            {                 
                $text = '{0} - {1}' -f $destination_server, $_.Exception.Message;
                Write-Message -Severity Error -Text $text -ForegroundColor Red -LogToFile $log_file_full_name ;
                if($sql_connection.State -eq 'Open') {$sql_connection.Close(); }
            }
        }          
                    
        if($sql_connection.State -eq 'Open') {$sql_connection.Dispose(); }

        $text = '{0} - Processing completed.' -f $destination_server;        
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;        
    }  
    #endregion 
    
}
catch [Exception]
{    
    Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;    
    if($sql_connection.State -eq 'Open') {$sql_connection.Dispose(); }
} 