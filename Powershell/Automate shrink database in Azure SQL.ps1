<#
.SYNOPSIS
##############################################################################################################
# This script is used to shrink the database files for a SQL Server database.
.DESCRIPTION
##############################################################################################################
# This script is used to shrink the database files for a SQL Server database.
# The script will shrink the data files for the specified database to the target free space.
# The script will shrink the data files in chunks of 128 MB until the target free space is reached and increase the chunk size by 64 MB after 2 successful runs.
# The script will reduce the chunk size by 10% if the shrink operation exceeds the MaxRunTimeMinutes value.
# The script will calculate the target free space by adding 30% buffer to the used space.
.PARAMETER ServerName
Parameter description of the server name
.PARAMETER DatabaseName
Parameter description of the database name
.PARAMETER Username
Parameter description of the username
.PARAMETER Password
Parameter description of the password
.PARAMETER TargetFreeMB
Parameter description
.PARAMETER InitialShrinkIncrementMB
Parameter description Initial shrink increment in MB
.PARAMETER ShrinkIncrementInMB
Parameter description subsequent shrink increment in MB
.PARAMETER SuccessfulRunCount
Parameter description the number of successful runs before increasing the shrink increment
.PARAMETER MaxRunTimeMinutes
Parameter description the maximum run time in minutes for the shrink operation
.EXAMPLE
An example of how to use this function
Shrink-SqlDatabase -ServerName "ServerName" -DatabaseName "DatabaseName" -Username "Username" -Password "Password"
An example of how to store the output in text file.

Shrink-SqlDatabase -ServerName 'localhost' -DatabaseName 'WideWorldImporters' -Username 'userid' -Password 'password' 

>> c:\temp\shrink.log

.LINK
https://techcommunity.microsoft.com/t5/azure-database-support-blog/automate-shrink-database-in-azure-sql/ba-p/4218097
#>
function Shrink-SqlDatabase{
    param (
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [int]$TargetFreeMB = 0,
        [int]$InitialShrinkIncrementMB = 128,
        [int]$ShrinkIncrementInMB = 64,
        [int]$SuccessfulRunCount = 2,
        [int]$MaxRunTimeMinutes = 15,
        [int]$Sleeptaskseconds = 15,
        [float]$BufferSpace = 0.2
    )

    function Open-ConnectionAsync {
        param (
            [string]$connectionString,
            [int]$maxAttempts
        )

        $attempts = 1
        while ($attempts -le $maxAttempts) {
            try {
                $connection = New-Object System.Data.SqlClient.SqlConnection
                $connection.ConnectionString = "$connectionString;MultipleActiveResultSets=True"
             #   $connection.ConnectionTimeout = 0
                $openTask = $connection.OpenAsync()
               Start-Sleep -Seconds 5
                if ( $openTask.IsFaulted) 
                {
                    $openTask.Wait()
                    }
                Start-Sleep -Milliseconds 30
                if ($openTask.IsCompleted) {
                    if (-not $openTask.IsFaulted -and -not $openTask.IsCanceled) {
                        Write-Host "$(Get-Date) - Connection established successfully."
                        return $connection
                    }
                }

            }
            catch {
                $attempts++
                $ConnectionerrorMessage = $openTask.Exception.InnerException.Message
                Write-Host "$(Get-Date) - Error establishing connection: $ConnectionerrorMessage Retrying in $backoffTime milliseconds..."
               break 
            }
        }
        Write-Host "$(Get-Date) - Maximum connection attempts reached. Could not establish connection. $ConnectionerrorMessage"
        return $null
    }

        function Resiliency-Check {
        param (
            [System.Data.SqlClient.SqlCommand]$command
        )

        if ($command -eq $null -or $command.Connection -eq $null) {
            Write-Host "$(Get-Date) - Command or connection object is null. Exiting..."
            write-host "CommandObject: $command Connection Object: $command.Connection"
            return $false
        }

        return $true
    }
    function Execute-QueryAsync {
        param (
            [System.Data.SqlClient.SqlConnection]$connection,
            [string]$query,
            [int]$queryNumber,
            [int]$maxAttempts
        )
    
        for ($i = 1; $i -le $maxAttempts; $i++) {
            $queryTimer = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $command = $connection.CreateCommand()
                $command.CommandText = $query
                Write-Host "$(Get-Date) - Attempt $i to execute Query $queryNumber..."
                ##Command timeout is set to 0 to avoid timeout issues
                $command.CommandTimeout = 0 
    
                $openTask = $command.ExecuteNonQueryAsync()
                Start-Sleep -Seconds 5
                if ( $openTask.IsFaulted) 
                {
                    $openTask.Wait()
                    }
                while (-not $openTask.IsCompleted) {
                    Start-Sleep -Seconds $Sleeptaskseconds #frequency to check the task status
                }
                    ##Validate command and connection object are still valid
                if (-not (Resiliency-Check -command $command)) {
                    write-host "ResiliencyCheck" $command
                    return
                }
    
                if (-not $openTask.IsFaulted -and -not $openTask.IsCanceled) {
                    $queryTimer.Stop()
                    Write-Host "$(Get-Date) - Query $queryNumber, attempt $($i) executed successfully. Execution time: $($queryTimer.Elapsed.ToString())"
                    return
                }
                else {
                    $openTask.Wait() # To throw the exception explicitly
                }
            }

            catch {
                $queryTimer.Stop()
                $errorMessage = $openTask.Exception.InnerException.Message
                Write-Host "$(Get-Date) - Error executing query $queryNumber, attempt $($i): $errorMessage. Execution time: $($queryTimer.Elapsed.ToString())"
               break 
            }
                   }
    }
    
    $exceptionOccurred = $false

    try {
        $Connection = Open-ConnectionAsync -connectionString "Server = $ServerName; Database = $DatabaseName; User ID = $Username; Password = $Password;" -maxAttempts 1 
        if ($Connection -eq $null) {
            Write-Host "Failed to establish a connection. Exiting..."
            return
        }
    
        $QueryFiles = "SELECT name, size/128 AS AllocatedMB, FILEPROPERTY(name, 'SpaceUsed')/128.0 AS UsedMB FROM sys.database_files WHERE type_desc = 'ROWS';"
        $CommandFiles = $Connection.CreateCommand()
        $CommandFiles.CommandText = $QueryFiles
        $Files = $CommandFiles.ExecuteReader()
    
        while ($Files.Read() -and -not $exceptionOccurred) {
            $DBFileName = $Files["name"]
            $AllocatedMB = $Files["AllocatedMB"]
            $UsedMB = $Files["UsedMB"]
            $TargetFreeMB = ($UsedMB + ($UsedMB * $BufferSpace))

            Write-Output "AllocatedMB: $AllocatedMB"
            Write-Output "UsedMB: $UsedMB"
            Write-Output "TargetFreeMB: $TargetFreeMB"
    
            if ($AllocatedMB -gt $TargetFreeMB) {
                $Files.Close()
                $successfulRuns = 0
    
                while ($AllocatedMB -gt $TargetFreeMB -and -not $exceptionOccurred) {
                    
                    $SizeReduced = 0
                    $NewTargetSizeMB = [math]::Max($AllocatedMB - $InitialShrinkIncrementMB, $TargetFreeMB)

                    # Calculate the percentage of free space left
                    $PercentFreeSpaceLeft = ($AllocatedMB - $TargetFreeMB) / $AllocatedMB * 100
                    Write-Output ("Percent Free Space Left: {0:N2}%" -f $PercentFreeSpaceLeft)
    
                    try {
                        $shrinkStartTime = Get-Date
                        Write-Output "ShrinkStartTime: $shrinkStartTime"
                        # Construct the DBCC SHRINKFILE command with the new target size
                       $QueryShrink = "DBCC SHRINKFILE ('$DBFileName', $NewTargetSizeMB) WITH NO_INFOMSGS;"
                       # $QueryShrink = "EXEC dbo.SampleLongRunningProcedure"
                        
                        Execute-QueryAsync -connection $Connection -query $QueryShrink -queryNumber 1 -maxAttempts 1
                        $elapsedTime = (Get-Date) - $shrinkStartTime
                        $elapsedMinutes = $elapsedTime.TotalMinutes
                        Write-Output "Elapsed Time in Minutes: $elapsedMinutes"

                        # Calculate the percentage left to reach the target free space after each run
                        # $PercentageLeft = ($AllocatedMB - $TargetFreeMB) / $AllocatedMB * 100
                        # Write-Host "Percentage left to reach target free space: $PercentageLeft%" 

    
                        if ($elapsedMinutes -gt $MaxRunTimeMinutes) {
                            Write-Output "Max duration exceeded. Reducing InitialShrinkIncrementMB by 10%."
                            $InitialShrinkIncrementMB = [math]::Max(1, [math]::Round($InitialShrinkIncrementMB * 0.9))
                            $SizeReduced++
                            Write-Output "Reducing InitialShrinkIncrementMB by 10%: $InitialShrinkIncrementMB"
                        }
                    }

                    catch {
                        $exceptionOccurred = $true
                        Write-Output "Error during shrink: $_"
                        break  # Exit the while loop on exception
                    }
    
                    $QuerySize = "SELECT size/128 FROM sys.database_files WHERE name = '$DBFileName';"
                    $CommandSize = $Connection.CreateCommand()
                    $CommandSize.CommandText = $QuerySize
                    $AllocatedMB = $CommandSize.ExecuteScalar()
    
                    $QueryUsed = "SELECT FILEPROPERTY('$DBFileName', 'SpaceUsed')/128.0;"
                    $CommandUsed = $Connection.CreateCommand()
                    $CommandUsed.CommandText = $QueryUsed
                    $UsedMB = $CommandUsed.ExecuteScalar()
    
                    Write-Output "NewTargetSizeMB: $NewTargetSizeMB"
                    $successfulRuns++
                    Write-Output "Successful Run #$successfulRuns"
                    $shrinkEndTime = Get-Date
                    Write-Output "shrinkEndTime: $shrinkEndTime"
                    $shrinkTotalTime = $shrinkEndTime - $shrinkStartTime
                    Write-Output "shrinkTotalTime: $shrinkTotalTime"
    
                    if ($successfulRuns -eq $SuccessfulRunCount -and $SizeReduced -eq 0) {
                        $InitialShrinkIncrementMB = [math]::Round($InitialShrinkIncrementMB + $ShrinkIncrementInMB)
                        Write-Output "Increasing InitialShrinkIncrementMB by $ShrinkIncrementInMB : $InitialShrinkIncrementMB"
                        $successfulRuns = 0  # Reset the successful runs counter
                    }
    
                    if ($AllocatedMB -le $TargetFreeMB) {
                        break  # Exit the while loop if the target size is reached
                    }
                }
    
                $Files = $CommandFiles.ExecuteReader()
            }
        }
    }

    catch {
        # Handle the exception at the higher level
        $exceptionOccurred = $true
        Write-Host "Exception occurred: $_"
    }
    finally {
        # Close the connection
        if ($Connection -ne $null) {
            $Connection.Close()
        }
    }    
}