<#
    20191022 - Yaniv Etrogi
    The script monitors to assure all AGs are hosted on the Primary Replica (single-thred).


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
    

    foreach($ag in $ags_obj)
    {
        $objarr_str = New-Object System.Collections.Generic.Dictionary"[String, String]";

        if ($ag.OwnerNode.Name -ne $vnn_obj.OwnerNode.Name)
        {
            #if ($user_interactive) {Write-Host $ag.OwnerNode.Name $ag.Name -ForegroundColor Yellow}; 

            [string]$query = 'ALTER AVAILABILITY GROUP [{0}] FAILOVER;' -f $ag.Name;
            if ($user_interactive) {Write-Host $query -ForegroundColor Yellow}; 
            
            try
            {
                # Execute the failover command on the secondary.
                [string]$server = $vnn_obj.OwnerNode.Name;
                Exec-Sql -Server $server -Database $database -CommandText $query -CommandType $command_type -IntegratedSecurity $windows_authentication -Credentials $credentials -ApplicationName $application_name;   
            }
            catch [Exception] 
            {        
                $exception = $_.Exception;
                if ($user_interactive) {Write-Host -ForegroundColor Red $exception};         
            
                $subject = $server + ': Exception at ' + $collector_name;
                $body = $exception;                   
                if ($send_mail ) {$smtp_client.Send($from, $to, $subject, $body);} 
            }  
        }
    }
}
catch [Exception] 
{        
    $exception = $_.Exception;
    if ($user_interactive) {Write-Host -ForegroundColor Red $exception};                     
}    