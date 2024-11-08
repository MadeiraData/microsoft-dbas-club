<#
    20210110 - Yaniv Etrogi
    The script monitors to assure all AGs are hosted on the Primary Replica (multi-thred).


    The script is intended for sql server std. edition that has the following setup:
    1. Basic Availability Groups with multiple groups 
    2. A single vnn/listener
    3. There is a cross database dependency.

    When the above conditione are true there is a requirement to have all AGs located on the same replica.
    The script implements the following logic:
    1. Detects the replica that owns the vnn/listener and reffers to this replica as the Primary Replica.
    2. Looks for any AG that is hosted on a Secondary Replica and initiates a failover for the given AG.

#>



#region <variables>
[bool]$user_interactive = [Environment]::UserInteractive;

#region <files>
[string]$helpers_file_full_name = Join-Path $PSScriptRoot 'helpers.ps1';
. $helpers_file_full_name;
#endregion


#region <database>
[string]$command_type = "NonQuery";
[string]$database = 'master';
[string]$sql_user = '';
[bool]$windows_authentication = $true;
[string]$application_name = 'AGMonitor'

if (-not $windows_authentication)
{
    [string]$sql_password_full_name = Join-Path $PSScriptRoot 'sql_password.txt';
    $password = Get-Content $sql_password_full_name | ConvertTo-SecureString;
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sql_user, $password;
    $cred.Password.MakeReadOnly();
    $credentials = New-Object System.Data.SqlClient.SqlCredential($cred.username, $cred.password);
}
#endregion

#endregion <variables>


try
{       
    # Get the vnv/listener in order to determin the active node that should host all the availability grroups.
    $vnn_obj = Get-ClusterResource | Select-Object Name, OwnerNode, OwnerGroup, ResourceType, State | Where-Object {$_.ResourceType -eq "IP Address" -and $_.OwnerGroup -ne "Cluster Group" -and $_.State -eq "online";}
    if ($user_interactive) {Write-Host 'The VNN is owned by' $vnn_obj.OwnerNode.Name -ForegroundColor Green}; 

    # Get the availability grroups
    $ags_obj = Get-ClusterResource | Select-Object Name, OwnerNode, OwnerGroup, ResourceType, State | Where-Object {$_.ResourceType -eq "SQL Server Availability Group";}
    
    $dictionary = New-Object System.Collections.Generic.Dictionary"[int, String]";
    $counter = 1;

    foreach($ag in $ags_obj)
    {            
        if ($ag.OwnerNode.Name -ne $vnn_obj.OwnerNode.Name)        
        {
            [string]$query = 'ALTER AVAILABILITY GROUP [{0}] FAILOVER;' -f $ag.Name;
            if ($user_interactive) {Write-Host $query -ForegroundColor Yellow}; 

            $dictionary.Add($counter, $query);
            [string]$server = $vnn_obj.OwnerNode.Name;
                        
            $counter++;
        }
    }


    # If there are no AGs that need to be failed over we exit here.
    if ($dictionary.Count -lt 1) 
    {
        if ($user_interactive) {Write-Host 'There are no AGs to failover. Terminating.' -ForegroundColor Green};    
        return;
    }


    foreach ($key in $dictionary.Keys)
    {
       if ($user_interactive) {Write-Host "$key  $($dictionary[$key])" }; 
       
       [string]$query = $dictionary[$key] 
       [string]$val = $key;

        $script_block = 
        {
            param
            (               
               $server                       
              ,$query 
            )         
               
           try
           {
               $ConnectionString = "Server=$Server; Database=master; Integrated Security=true; Application Name=AGMonitor;";

               $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);            
               $SqlCommand = $sqlConnection.CreateCommand();
               $SqlConnection.Open(); 
               $SqlCommand.CommandText = $query;       
               $sqlCommand.ExecuteNonQuery();  
           }
           catch [Exception] 
           {        
                Throw;     
           }    
        }  
              
        
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 30);
        $RunspacePool.Open();

        
        $Jobs = @();

           $PowerShell = [powershell]::Create();
           $PowerShell.RunspacePool = $RunspacePool;
           $PowerShell.AddScript($script_block).AddParameter("server",$server).AddParameter("query",$query);
           $Jobs += $PowerShell.BeginInvoke();  
    }

    while ($Jobs.IsCompleted -contains $false)
    {        
        Start-Sleep -Milliseconds 100;       
    }
    $RunspacePool.Close();
    $RunspacePool.Dispose(); 


}
catch [Exception] 
{        
    $exception = $_.Exception;
    if ($user_interactive) {Write-Host -ForegroundColor Red $exception};         
}    

#finally
#{
#    $dictionary = $null
#}
