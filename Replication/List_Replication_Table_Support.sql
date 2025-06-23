/*
    List tables in selected databases and check if they are supported for replication.
    A table is considered supported if it has a primary key and does not contain
    data types typically unsupported by replication (text, ntext, image, xml,
    hierarchyid, geography, geometry, filestream).

    Optional parameters:
        @DatabaseNamePattern - LIKE pattern for database names (NULL for all databases)
        @TableNamePattern    - LIKE pattern for table names (NULL for all tables)

    Example:
        DECLARE @DatabaseNamePattern sysname = 'AdventureWorks%';
        DECLARE @TableNamePattern sysname = 'Dim%';
        -- Run the script after setting the parameters above.
*/

DECLARE @DatabaseNamePattern sysname = NULL; -- NULL for all databases
DECLARE @TableNamePattern  sysname = NULL;   -- NULL for all tables

IF OBJECT_ID('tempdb..#ReplicationSupport') IS NOT NULL
    DROP TABLE #ReplicationSupport;

CREATE TABLE #ReplicationSupport (
    DatabaseName sysname,
    SchemaName   sysname,
    TableName    sysname,
    ReplicationSupported bit,
    Details NVARCHAR(300)
);

DECLARE @db sysname;
DECLARE db_cursor CURSOR LOCAL STATIC FORWARD_ONLY READ_ONLY FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4 -- skip system databases
      AND state_desc = 'ONLINE'
      AND HAS_DBACCESS([name]) = 1
      AND (@DatabaseNamePattern IS NULL OR name LIKE @DatabaseNamePattern);

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #ReplicationSupport (DatabaseName, SchemaName, TableName, ReplicationSupported, Details)
    SELECT
        DB_NAME(),
        s.name,
        t.name,
        CASE
            WHEN OBJECTPROPERTY(t.object_id, ''TableHasPrimaryKey'') = 0 THEN 0
            WHEN EXISTS (
                SELECT 1
                FROM sys.columns c
                JOIN sys.types st ON c.user_type_id = st.user_type_id
                WHERE c.object_id = t.object_id
                  AND (
                        st.name IN (''text'', ''ntext'', ''image'', ''xml'', ''hierarchyid'', ''geography'', ''geometry'')
                        OR c.is_filestream = 1
                      )
            ) THEN 0
            ELSE 1
        END AS ReplicationSupported,
        CASE
            WHEN OBJECTPROPERTY(t.object_id, ''TableHasPrimaryKey'') = 0 THEN ''Missing primary key''
            WHEN EXISTS (
                SELECT 1
                FROM sys.columns c
                JOIN sys.types st ON c.user_type_id = st.user_type_id
                WHERE c.object_id = t.object_id
                  AND (
                        st.name IN (''text'', ''ntext'', ''image'', ''xml'', ''hierarchyid'', ''geography'', ''geometry'')
                        OR c.is_filestream = 1
                      )
            ) THEN ''Contains unsupported datatypes''
            ELSE ''Supported''
        END AS Details
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.is_ms_shipped = 0
      AND (@TableNamePattern IS NULL OR t.name LIKE @TableNamePattern);';

    EXEC sp_executesql @sql, N'@TableNamePattern sysname', @TableNamePattern = @TableNamePattern;
    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT * FROM #ReplicationSupport
ORDER BY DatabaseName, SchemaName, TableName;

DROP TABLE #ReplicationSupport;
