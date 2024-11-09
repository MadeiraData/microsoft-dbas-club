**General**

The 2 scripts _SynchronizeSQLServerJobs_ + _SynchronizeSQLServerLogins_ can be used to sync objects from an Alwayson Primary replica to an Alwayson Senodary replica(s).
The sync is done always one way from the current Primary replica to Secondary replica(s).

The script first generates the differences it detects (if there were any) and then generates a script. Only then the generated script gets executed against each secondary replica.

**Parameters**

[bool]$execute_script_file - Defines if we execute the generated script.

[bool]$drop_job - Defines if we drop an existing object with an identical name at the target.

[int]$hours - Defines the number of hours to check back in order to find if an object has been addedd\changed.


**Usage**

Schedule from an sql server agent job (or any other scheduler) using a job step type of cmd exec and provide the full path to the Powershell script file.
Note that there should be a coralation beteen the $hours paramter and the job schedule. For example if the parameter $hours is set to 1 then you should schedule the job to run every 1 hour.

**Known issues**

The line in the Powershell script that loads the **smo** assembly may need to be edited based on the sql server instance version where it is exeuted.
The bellow example works on sql server 2016. For example on sql server 2022 the **13** would need to be replaced with **16**.
_Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=**13.0.0.0**, Culture=neutral, PublicKeyToken=89845dcd8080cc91";_


**Troubleshooting**

Check the log file located under the LOg folder and address the logged exception.

**Background**

The 4 scripts were originally created to sync objects from a Transactional Replication publisher to a Transactional Replication subscriber.
This is why we also have the 2 files SynchronizeSQLServerRoutines + SynchronizeSQLServerTables.
