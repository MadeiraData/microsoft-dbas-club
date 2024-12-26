/*
 	Created: Vitaly Bruk / MadeiraData
	Date:	2024-12-26
	
	Description:
		This is an example script for creating an EXTERNAL TABLE with various file formats.

		This script is an example of the usage of various file formats such as Parquet, DELTA, CSV, JSON, ORC, and more. See the references.
		The same is about Data Source Type and Data Compression.

    Prerequisites:
        SQL Server Setup:
            Ensure you have SQL Server 2016 or later, Azure SQL Database, or Azure SQL Managed Instance.
        
        PolyBase Installation:
            Install the PolyBase feature on your SQL Server instance. 
			PolyBase allows you to query data stored outside of SQL Server.

    References:
        1. Virtualize Parquet File with PolyBase:						https://learn.microsoft.com/en-us/sql/relational-databases/polybase/polybase-virtualize-parquet-file
        2. a. CREATE EXTERNAL TABLE (Transact-SQL):						https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-table-transact-sql
        2. b. CREATE EXTERNAL TABLE AS SELECT (CETAS) (Transact-SQL):	https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-table-as-select-transact-sql
        3. Use External Tables with Synapse SQL:						https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tables-external-tables
        4. CREATE EXTERNAL FILE FORMAT (Transact-SQL):					https://learn.microsoft.com/en-us/sql/t-sql/statements/create-external-file-format-transact-sql

*/

DECLARE 
	@WhatIf							BIT				= 1,															-- Set to 1 to print the script, 0 to execute

	@DataSourceType					NVARCHAR(50)	= 'HADOOP',														-- Choose the type of external data source (e.g., HADOOP, RDBMS)
	@FileFormatType					NVARCHAR(50)	= 'PARQUET',													-- Choose the file format type: PARQUET, DELTA, CSV, JSON, ORC
	@DataCompression				NVARCHAR(50)	= 'org.apache.hadoop.io.compress.SnappyCodec',					-- Set NULL or Specify the compression codec (e.g., org.apache.hadoop.io.compress.SnappyCodec)
	-- NULL
	@StorageAccountName				NVARCHAR(100)	= 'your_storage_account_name',									-- Specify name of your Azure Storage account
	@StorageAccountKey				NVARCHAR(100)	= 'your_storage_account_key',									-- Specify access key for your Azure Storage account
	@ContainerName					NVARCHAR(100)	= 'your_container_name',										-- Specify name of the container within your Azure Storage account where your files are stored
	@FolderPath						NVARCHAR(100)	= 'your_folder_or_file_path/',									-- Specify path within the container where your files are located. This should end with a "/"

	@CredentialName					NVARCHAR(100)	= 'ExternalCredential',											-- Specify name of the database scoped credential used to access the Azure Storage account
	@DataSourceName					NVARCHAR(100)	= 'ExternalDataSource',											-- Specify name of the external data source that points to the Azure Storage location
	@FileFormatName					NVARCHAR(100)	= 'FileFormat',													-- Specify name of the external file format used to define the format of the files (e.g., Parquet, CSV).
	@MasterKeyPassword				NVARCHAR(100)	= 'YourStrongPasswordHere',										-- Specify password used to create the master key for encryption in your SQL Server, Azure SQL Database/Managed Instance
	
	@ExternalTableType				NVARCHAR(50)	= 'CREATE',														-- Choose the type of external table creation: CREATE or SELECT
	@ExternalTableName				NVARCHAR(100)	= 'ExternalTable',												-- Choose the type of external table
	@SourceTableName				NVARCHAR(100)	= 'SourceTable',												-- Specify NULL if @ExternalTableType = CREATE, else - specify source table name
	@ColumnList						NVARCHAR(MAX)	= 'Column1 INT, Column2 NVARCHAR(100), Column3 DATETIME',		-- Specify columns with data types, sepated by comma if @ExternalTableType = CREATE, else - specify NULL
	@SelectColumnList				NVARCHAR(MAX)	= 'Column1, Column2, Column3',									-- Specify columns without data types, separated by comma or "*" if @ExternalTableType = SELECT, else - specify NULL


	/***************************** Script start *****************************/

	@SQL							NVARCHAR(MAX);

-- Parameters Validation
IF @DataSourceType IS NULL OR LEN(@DataSourceType) = 0
BEGIN
    RAISERROR('DataSourceType cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @FileFormatType IS NULL OR LEN(@FileFormatType) = 0
BEGIN
    RAISERROR('FileFormatType cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @StorageAccountName IS NULL OR LEN(@StorageAccountName) = 0
BEGIN
    RAISERROR('StorageAccountName cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @StorageAccountKey IS NULL OR LEN(@StorageAccountKey) = 0
BEGIN
    RAISERROR('StorageAccountKey cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @ContainerName IS NULL OR LEN(@ContainerName) = 0
BEGIN
    RAISERROR('ContainerName cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @FolderPath IS NULL OR LEN(@FolderPath) = 0
BEGIN
    RAISERROR('FolderPath cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @CredentialName IS NULL OR LEN(@CredentialName) = 0
BEGIN
    RAISERROR('CredentialName cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @DataSourceName IS NULL OR LEN(@DataSourceName) = 0
BEGIN
    RAISERROR('DataSourceName cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @FileFormatName IS NULL OR LEN(@FileFormatName) = 0
BEGIN
    RAISERROR('FileFormatName cannot be NULL or empty.', 16, 1);
    RETURN;
END

IF @MasterKeyPassword IS NULL OR LEN(@MasterKeyPassword) = 0
BEGIN
    RAISERROR('MasterKeyPassword cannot be NULL or empty.', 16, 1);
    RETURN;
END

-- Check conditions based on @ExternalTableType
IF @ExternalTableType NOT IN ('CREATE', 'SELECT')
BEGIN
    RAISERROR('Invalid ExternalTableType. Must be either CREATE or SELECT', 16, 1);
    RETURN;
END

-- Check conditions based on @ExternalTableType
IF @ExternalTableType = 'CREATE'
BEGIN
    -- @SourceTableName can be NULL
    IF @ColumnList IS NULL
    BEGIN
        RAISERROR('ColumnList cannot be NULL when ExternalTableType is CREATE.', 16, 1);
        RETURN;
    END
END
ELSE
BEGIN
    -- @SourceTableName must not be NULL
    IF @SourceTableName IS NULL
    BEGIN
        RAISERROR('SourceTableName cannot be NULL when ExternalTableType is SELECT.', 16, 1);
        RETURN;
    END

    -- @SelectColumnList must not be NULL
    IF @SelectColumnList IS NULL
    BEGIN
        RAISERROR('SelectColumnList cannot be NULL when ExternalTableType is SELECT.', 16, 1);
        RETURN;
    END
END

-- Ensure @FolderPath ends with '/'
IF RIGHT(@FolderPath, 1) <> '/'
BEGIN
	SET @FolderPath = CONCAT(@FolderPath, '/');
END

SET @SQL = CONCAT(N'
BEGIN TRY
    -- Step 1: Create a MASTER KEY if it does not already exist
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE [name] = ''##MS_DatabaseMasterKey##'')
    BEGIN
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = ''' , @MasterKeyPassword , ''';
    END;

    -- Step 2: Create a DATABASE SCOPED CREDENTIAL to access the external storage
    IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE [name] = ''' , @CredentialName , ''')
    BEGIN
        CREATE DATABASE SCOPED CREDENTIAL ' , @CredentialName , '
        WITH IDENTITY = ''' , @StorageAccountName , ''',
        SECRET = ''' , @StorageAccountKey , ''';
    END;

    -- Step 3: Create an EXTERNAL DATA SOURCE to point to the storage location
    IF NOT EXISTS (SELECT 1 FROM sys.external_data_sources WHERE [name] = ''' , @DataSourceName , ''')
    BEGIN
        CREATE EXTERNAL DATA SOURCE ' , @DataSourceName , '
        WITH (
            TYPE = ' , @DataSourceType , ',
            LOCATION = ''https://' , @StorageAccountName , '.blob.core.windows.net/' , @ContainerName , ''',
            CREDENTIAL = ' , @CredentialName , '
        );
    END;

    -- Step 4: Create an EXTERNAL FILE FORMAT
    IF NOT EXISTS (SELECT 1 FROM sys.external_file_formats WHERE [name] = ''' , @FileFormatName , ''')
    BEGIN
        CREATE EXTERNAL FILE FORMAT ' , @FileFormatName , '
        WITH (
            FORMAT_TYPE = ' , @FileFormatType ,	'')

IF @DataCompression IS NOT NULL
BEGIN
	SET @SQL = CONCAT(@SQL , N',
            DATA_COMPRESSION = ''' , @DataCompression , '''')
END

	SET @SQL = CONCAT(@SQL , N'
		);	
    END;

    -- Step 5: Create the EXTERNAL TABLE
    IF NOT EXISTS (SELECT 1 FROM sys.external_tables WHERE [name] = ''' , @ExternalTableName , ''')
    BEGIN
	')

IF @ExternalTableType = 'CREATE'
BEGIN
	SET @SQL = CONCAT(@SQL , N'
        CREATE EXTERNAL TABLE ' , @ExternalTableName , ' (
            ' , @ColumnList , '
        )
        WITH (
            LOCATION = ''' , @FolderPath , ''',
            DATA_SOURCE = ' , @DataSourceName , ',
            FILE_FORMAT = ' , @FileFormatName , '
        );
	')
END
ELSE
BEGIN
	SET @SQL = CONCAT(@SQL , N'
        CREATE EXTERNAL TABLE ' , @ExternalTableName , '
        WITH (
            LOCATION = ''' , @FolderPath , ''',
            DATA_SOURCE = ' , @DataSourceName , ',
            FILE_FORMAT = ' , @FileFormatName , '
        )
        AS
        SELECT ' , @SelectColumnList , '
        FROM ' , @SourceTableName , ';
	')
END;

	SET @SQL = CONCAT(@SQL , N'    END;

    -- Query the EXTERNAL TABLE
    SELECT ' , @SelectColumnList , ' FROM ' , @ExternalTableName , ';

END TRY
BEGIN CATCH
    PRINT ''Error occurred: '' + ERROR_MESSAGE();
END CATCH;
');

IF @WhatIf = 1
BEGIN
    PRINT @Sql;
END
ELSE
BEGIN
    EXEC sp_executesql @Sql;
END;
