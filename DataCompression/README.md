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
