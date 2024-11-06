<#
    20231016 - Yaniv Etrogi

    Script sql server agent jobs that were added/changed on a primary replica 
    If the variable $execute_script_file is true execute the generated script on all Secondary replica(s).

#>

# Edit here.
[bool]$execute_script_file = $false;
[bool]$drop_job = $true;

#The number of hours to chack back in order to find if a job was addedd\changed.
$hours = 1;


try
{
    #region <variabes>  
    [bool]$user_interactive = [Environment]::UserInteractive;   
        
    # Get the helper file located one folder bellow.
    
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
    $objet_type = 'Jobs';
    $folder = '{0}ChangesScripts' -f $objet_type;
    $script_file = '{0}_{1}_{2}.{3}' -f $server, $objet_type, $timestamp, 'sql';
    $script_folder = '{0}\{1}' -f $PSScriptRoot, $folder;
    $script_file_full_name = '{0}\{1}\{2}' -f $PSScriptRoot, $folder, $script_file;
    if (-not (Test-Path -Path $script_folder)) {New-Item -ItemType Directory $script_folder; }
    #endregion        

    
   # $text = '' -f
   # Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;    
    
    #region <VNN>    
    # Get the Primary Replica based on the node that ownes the VNN.
    $vnn_obj = Get-ClusterResource | Select-Object Name, OwnerNode, OwnerGroup, ResourceType, State | Where-Object {$_.ResourceType -eq "IP Address" -and $_.OwnerGroup -ne "Cluster Group" -and $_.State -eq "online";}
    $text = '{0} - The VNN is owned by {0}.' -f $vnn_obj.OwnerNode.Name ;
    #if($user_interactive) {Write-Host $text; }
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;

    
    # If this server is not the Primary Replica we exit here.
    # This is to enforce the script to be executed on a Primary Replica only.
    if ($smo_server.Name -ne $vnn_obj.OwnerNode.Name)
    {    
        $text = '{0} - This is not a Primary Replica. Terminating.' -f $smo_server.Name;
        #if($user_interactive) {Write-Host $text; }
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Yellow;
        return;
    }
    #endregion
       
    
    #region <get-jobs> 
    # Check if any job was added/changed in the past xx hours.        
    [string]$dt = (Get-Date).AddHours(-$hours).ToString('yyyyMMdd HH:mm');    

    $text = '{0} - Check if any job was added/changed in the past {1} hours.' -f $smo_server.Name, $hours  ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;
    $query = 'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
            IF EXISTS 
            (
	            SELECT TOP (1) j.name 
	            FROM msdb.dbo.sysjobs j
	            LEFT JOIN msdb.dbo.sysjobschedules s on s.job_id = j.job_id
	            LEFT JOIN msdb.dbo.sysschedules ss on ss.schedule_id = s.schedule_id
	            WHERE (j.date_created > ''{0}'' OR j.date_modified > ''{0}'')
	            OR (ss.date_created > ''{0}'' OR ss.date_modified > ''{0}'')
            ) SELECT 1 as bit ELSE SELECT 0 as bit;' -f $dt;
    [bool]$bit = Exec-Sql -Server $smo_server.Name -Database msdb -CommandText $query -CommandType Scalar -IntegratedSecurity $true -ApplicationName $application_name;

    #return

    # If there no job added/changed we exit here.
    if (-not $bit) 
    {
        $text = '{0} - No jobs were added/changed. Terminating.' -f $smo_server.Name ;
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;
        return; 
    } 
        

    # Get the jobs that were added/changed in the past xx hours.    
    $text = '{0} - Get the jobs that were added/changed in the past {1} hours.' -f $smo_server.Name, $hours ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green;
    $query = 'SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
              SELECT j.name 
	          FROM msdb.dbo.sysjobs j
	          LEFT JOIN msdb.dbo.sysjobschedules s on s.job_id = j.job_id
	          LEFT JOIN msdb.dbo.sysschedules ss on ss.schedule_id = s.schedule_id
	          WHERE (j.date_created > ''{0}'' OR j.date_modified > ''{0}'')
	          OR (ss.date_created > ''{0}'' OR ss.date_modified > ''{0}'');' -f $dt;
    $ds = Exec-Sql -Server $smo_server.Name -Database msdb -CommandText $query -CommandType DataSet -IntegratedSecurity $true -ApplicationName $application_name;
    #endregion 
        

    #region <scripting options>    
    $scripting_options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions;
    $scripting_options.ScriptDrops = $false;
    $scripting_options.IncludeHeaders = $true;
    $scripting_options.AppendToFile = $true;
    $scripting_options.IncludeIfNotExists = $true
    $scripting_options.AnsiFile = $true;
    $scripting_options.AgentJobId = $true;    
    #endregion
    

    #region <script jobs> 
     
    # Loop through each job and script it.  
    $jobs = $smo_server.JobServer.Jobs;      
    [int]$counter = 1;

    [string]$dummy_line_to_be_replaced = ' /* This line will be replaced at the end of the script with the number of jobs that were scripted. */';
    Add-Content -Path $script_file_full_name -Value $dummy_line_to_be_replaced;

    foreach ($job in $jobs)     
    {
        # If the current job is not part of the DataSet we skip this job as we only handle jobs that werea added/changed.
        if (-not $ds.tables[0].Rows.name.Contains($job.Name) )
        {
            continue; 
        }


        $text = '/* {0} */ {1}' -f $counter, $new_line;   
        if ($drop_job)
        {
            $text += 'BEGIN TRANSACTION; {0}' -f $new_line;
            $text += 'IF EXISTS (SELECT name FROM msdb.dbo.sysjobs WHERE name = N''{0}'') EXEC msdb.dbo.sp_delete_job @job_name = N''{0}''; {1}' -f $job.Name, $new_line;            
        }     
        $text += 'IF NOT EXISTS (SELECT name FROM msdb.dbo.sysjobs WHERE name = N''{0}'') {1}BEGIN; {1}' -f $job.Name, $new_line;
        $script = $job.Script($scripting_options);
        $text += $script;
        $text += 'END; {0}' -f $new_line;
        if ($drop_job)
        {
            $text += 'IF (@@TRANCOUNT > 0) COMMIT TRANSACTION;';
        }        

        Add-Content -Path $script_file_full_name -Value $text;
        Add-Content -Path $script_file_full_name -Value "GO";
        Add-Content -Path $script_file_full_name -Value $new_line;   
        
        $counter ++;  
    }  

    $number_of_jobs_scripted = $counter -1
    $text = '{0} - The number of jobs sripted: {1}.' -f $smo_server.Name, $number_of_jobs_scripted ;
    Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name -ForegroundColor Green ;

    
    # Replace the dummy line at the top of the file.
    #[string]$replace = '/* {1}  Scripted by {0} {1}' -f $application_name, $new_line;
    [string]$replace = '/* {1} {2} {1} Scripted by {0} {1}' -f $application_name, $new_line, $timestamp;
    $replace += '  The number of jobs sripted: {0} {1}*/ {1}{1} ' -f $number_of_jobs_scripted, $new_line;    
    $content = Get-Content -Path $script_file_full_name -Raw;  
    $content.Replace($dummy_line_to_be_replaced, $replace) | Set-Content -Path $script_file_full_name;
    #endregion <jobs> 
    
     
    
    $script_file_content = Get-Content $script_file_full_name -Raw;
    
    # Break the script file content into commands based on the GO batch separator.    
    $script_file_splited = [regex]::Split($script_file_content, "\bGO\b");   
    #$script_file_splited = [regex]::Split($script_file_content, '(?smi)^[\s]*GO[\s]*$');    


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


        $text = '{0} - Processing.' -f $node.Name;        
        Write-Message -Text $text -LogToFile -LogToConsole -LogFileName $log_file_full_name;        


        if ($execute_script_file)
        {
            # Execute the splited jobs script against Secondary Replica(s).
            for($i=0; $i -lt $script_file_splited.Count; $i++)
            {
                $text = '{0} - Executing command number: {1}' -f $node.Name, $i;
                Write-Message -Text $text -LogToConsole -LogFileName $log_file_full_name;
                try
                {
                    $rc = Exec-Sql -Server $node.Name -Database msdb -CommandText $script_file_splited[$i] -CommandType NonQuery -IntegratedSecurity $true -ApplicationName $application_name;                                                           
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
    } #foreach ($node in $nodes)
}
catch [Exception]
{    
    Write-Message -Severity Error -Text $_.Exception.Message -ForegroundColor Red;    
    if($sql_connection.State -eq 'Open') {$sql_connection.Dispose(); }
} 