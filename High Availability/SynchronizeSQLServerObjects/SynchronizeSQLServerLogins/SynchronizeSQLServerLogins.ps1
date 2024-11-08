<#
    20231016 - Yaniv Etrogi

    Script sql server Logins that were added/changed in the last xx minutes.
    If the variable $execute_script_file is true execute the generated script on all Secondary replica(s).


#>

 Set-Location 'C:\';

# Edit here.
[bool]$execute_script_file = $true;
#[string]$destination_server = 'SQL-ENT-Prod-N1';
[string]$database = 'master';

#The number of minutes to check back in order to find if a object was addedd\changed.
$hours = 1;


try
{
    #region <variabes>  
    [bool]$user_interactive = [Environment]::UserInteractive;

    [string]$helpers_file_path = Split-Path -Parent $PSScriptRoot;
    [string]$helpers_file_full_name = Join-Path $helpers_file_path 'helpers.ps1';
    . $helpers_file_full_name;



    
    Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=16.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91";
    $smo_server = New-Object Microsoft.SqlServer.Management.Smo.Server($env:COMPUTERNAME);    
        
    [string]$server = $env:COMPUTERNAME;
    [string]$application_name = $MyInvocation.MyCommand.Name.Split(".")[0];
    [string]$new_line = [Environment]::NewLine;    
    [string]$timestamp = (Get-Date).ToString('yyyy-MM-ddTHHmmss');
      
    # Log file
    [string]$log_file = '{0}.{1}' -f $application_name, 'log' ;     
    [string]$log_folder = '{0}\{1}' -f $PSScriptRoot, 'Logs' ;
    [string]$log_file_full_name = '{0}\{1}\{2}' -f $PSScriptRoot, 'Logs', $log_file;
    if (-not (Test-Path -Path $log_folder)) {New-Item -ItemType Directory $log_folder; }        

    # Script file
    $objet_type = 'Logins';
    $folder = '{0}ChangesScripts' -f $objet_type;
    $script_file = '{0}_{1}_{2}.{3}' -f $server, $objet_type, $timestamp, 'sql';
    $script_folder = '{0}\{1}' -f $PSScriptRoot, $folder;
    $script_file_full_name = '{0}\{1}\{2}' -f $PSScriptRoot, $folder, $script_file;
    if (-not (Test-Path -Path $script_folder)) {New-Item -ItemType Directory $script_folder; }        
    #endregion        
            
    
    #region <VNN>    
    # Get the Primary Replica based on the node that ownes the VNN.
    $vnn_obj = Get-ClusterResource | Select-Object Name, OwnerNode, OwnerGroup, ResourceType, State | Where-Object {$_.ResourceType -eq "IP Address" -and $_.OwnerGroup -ne "Cluster Group" -and $_.State -eq "online";}
    $text = '{0} - The VNN is owned by {0}.' -f $vnn_obj.OwnerNode.Name ;
    #if($user_interactive) {Write-Host $text; }
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;

    
    # If this server is not the Primary Replica we exit here.
    # This is to enforce the script to be executed on a Primary Replica only.
    if ($smo_server.Name -ne $vnn_obj.OwnerNode.Name[0])
    {    
        $text = 'This is not a Primary Replica. Terminating.';
        #if($user_interactive) {Write-Host $text; }
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Yellow;
        return;
    }
    #endregion
       

    #region <get-objects> 
    # Check if any object was added/changed in the past xx hours.        
    [string]$dt = (Get-Date).AddHours(-$hours).ToString('yyyyMMdd HH:mm'); 
    $text = '{0} - Check if any objects were added/changed in the last {1} hours.' -f $server, $hours  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;
    
                        

    # Get the object that were added/changed in the past xx hours.    
    $text = '{0} - Get the objects were added/changed in the last {1} hours.' -f $server, $hours  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;    
    $query = 'SELECT name, type_desc FROM sys.server_principals WHERE (create_date > DATEADD(HOUR, -{0}, CURRENT_TIMESTAMP) OR modify_date > DATEADD(HOUR, -{0}, CURRENT_TIMESTAMP));' -f $hours;
    $ds = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType DataSet -IntegratedSecurity $true -ApplicationName $application_name;

    if ($ds.tables[0].Rows.Count -gt 0)
    {
        [Microsoft.SqlServer.Management.Smo.SimpleObjectCollectionBase]$objects = $smo_server.Logins;     
    }    

     # If there no object added/changed we exit here.
    if ($ds.tables[0].Rows.Count -eq 0) 
    {
        $text = '{0} - No objects were added/changed in the past {1} hours. Terminating.' -f $server, $hours;
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
    $scripting_options.ScriptSchema = $true;
    $scripting_options.LoginSid = $true;
    #endregion
        

    #region <script>      
    
    [int]$counter = 1;
    [string]$dummy_line_to_be_replaced = ' /* This line will be replaced at the end of the script with the number of objects that were scripted. */';
    Add-Content -Path $script_file_full_name -Value $dummy_line_to_be_replaced;
           

    # Loop through each object and script it.      
    foreach ($obj in $objects)          
    {
        #Write-Host $counter -ForegroundColor Yellow

        # If the current object is not part of the DataSet we skip this object as we only handle objects that werea added/changed.
        if (-not $ds.tables[0].Rows.name.Contains($obj.Name) )
        {
            continue; 
        }        


        $script = $obj.Script($scripting_options);        
        
        if ($obj.LoginType -eq 'SqlLogin')
        {            
            # Get the hashed password.
            $query = 'SELECT sys.fn_varbintohexstr(CONVERT(VARBINARY(MAX), LOGINPROPERTY(N''{0}'', N''passwordhash''))) FROM sys.server_principals WHERE name = N''{0}'';' -f $obj.Name;                    
            $hashed_password = Exec-Sql -Server $server -Database $database -CommandText $query -CommandType Scalar -IntegratedSecurity $true -ApplicationName $application_name;
                    
            # Replace the random password with the hashed password.
            $replacement_string = 'PASSWORD={0} HASHED ' -f $hashed_password;
            $script = $script -replace 'PASSWORD=N(.*)''.*?''', $replacement_string;
        }

        [string]$text = '/* {0} */ {1}' -f $counter, $new_line;   
        $text += 'IF EXISTS (SELECT * FROM sys.server_principals WHERE name = N''{0}'') DROP LOGIN [{0}];' -f $obj.Name, $new_line;        
       
        Add-Content -Path $script_file_full_name -Value $text;
        Add-Content -Path $script_file_full_name -Value "GO";
        
        $text = '';
        foreach($s in $script)
        {
            if (-not $s.StartsWith('ALTER LOGIN')) # Prevent the DISABLE login command.
            {                
                $text += $s;                
                $text += $new_line;
            }
        }

        Add-Content -Path $script_file_full_name -Value $text;
        Add-Content -Path $script_file_full_name -Value "GO";
        Add-Content -Path $script_file_full_name -Value $new_line;   
        #Add-Content -Path $script_file_full_name -Value $new_line;   
        
        $counter ++;          
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
    

    # Execute the generated script against each Secondary Replica.
    $nodes = Get-ClusterNode | where State -eq Up | select name;

    foreach ($node in $nodes)
    {
        # If this node is the Primary Replica skip this iteration as we copy one way from the Primary Replica to Secondary Replica(s).
        if ($node.Name -eq $smo_server.Name )
        {        
            $text = '{0} - Skipping this node since it is the Primary Replica.' -f $node.Name;            
            Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;
            continue;
        }


        $text = '{0} - Processing...' -f $node.Name;        
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;    

        #region <execute>    
        if ($execute_script_file)
        {
            # Execute the splited jobs script against Secondary Replica(s).
            for($i=0; $i -lt $script_file_splited.Count -1; $i++)
            {
                $text = '{0} - Executing command number: {1}' -f $node.Name, $i;
                Write-Message -Text $text -LogToConsole -LogFileName $log_file_full_name;
                try
                {
                    #$script_file_splited[$i]
                    #Write-Host -ForegroundColor Yellow '---------------------------------------------------------'
                    $rc = Exec-Sql -Server $node.Name -Database $database -CommandText $script_file_splited[$i] -CommandType NonQuery -IntegratedSecurity $true -ApplicationName $application_name;                                                           
                }
                catch [Exception]
                {                    
                    Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;
                    if($sql_connection.State -eq 'Open') {$sql_connection.Close(); }
                }
            }          
                    
            if($sql_connection.State -eq 'Open') {$sql_connection.Dispose(); }

            $text = '{0} - Processing completed.' -f $node.Name;        
            Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;        
        }  
        #endregion 
    }    
}
catch [Exception]
{    
    Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;    
    if($sql_connection.State -eq 'Open') {$sql_connection.Dispose(); }
} 





