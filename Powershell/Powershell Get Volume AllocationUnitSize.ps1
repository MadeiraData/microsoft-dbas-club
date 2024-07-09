<#
.SYNOPSIS
Get the allocation unit size of every disk volume.
If you have a SQL Server, ensure the block size is 64 KB for the database and log files.

.LINK
https://serverfault.com/a/904263
https://www.alitajran.com/get-allocation-unit-size-powershell/
#>
Get-CimInstance -ClassName Win32_Volume | Select-Object Name, FileSystem, Label, BlockSize | Sort-Object Name | Format-Table -AutoSize

Get-Volume | Select-Object DriveLetter, FileSystemLabel, AllocationUnitSize | Sort-Object DriveLetter | Get-Unique -AsString
