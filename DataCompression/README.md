SYNOPSIS
    This script automates the process of applying data compression to indexes in sql server.

DESCRIPTION
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


EXAMPLE    
    Work on the local instance using WindowsAuthentication.
    .\data_compression.ps1;
    .\data_compression.ps1 -Server $env:COMPUTERNAME; 
    .\data_compression.ps1 -Server $env:COMPUTERNAME -WindowsAuthentication;

    Work on the local instance using SQl Authentication while processing 2 specific databases only.
    .\data_compression.ps1 -IncludeDatabase 'DBA','CloudMonitoring' -SqlUser yaniv;

    Work on remote instance using WindowsAuthentication
    .\data_compression.ps1 -Server server1; 
    .\data_compression.ps1 -Server server1 -WindowsAuthentication;


NOTES
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
