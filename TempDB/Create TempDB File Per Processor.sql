/*
Script to Create A TempDB File Per Processor

Author: David-Levy, 2010-04-09

Source:
https://www.sqlservercentral.com/blogs/script-to-create-a-tempdb-file-per-processor
*/
USE [master]
GO
DECLARE @cpu_count      int,
        @file_count     int,
        @logical_name   sysname,
        @file_name      nvarchar(520),
        @physical_name  nvarchar(520),
        @size           int,
        @max_size       int,
        @growth         int,
        @alter_command  nvarchar(max)

SELECT  @physical_name = physical_name,
        @size = size / 128,
        @max_size = max_size / 128,
        @growth = growth / 128
FROM    tempdb.sys.database_files
WHERE   name = 'tempdev'

SELECT  @file_count = COUNT(*)
FROM    tempdb.sys.database_files
WHERE   type_desc = 'ROWS'

SELECT  @cpu_count = cpu_count
FROM    sys.dm_os_sys_info

WHILE @file_count < @cpu_count -- Add * 0.25 here to add 1 file for every 4 cpus, * .5 for every 2 etc.
BEGIN

    SET  @logical_name = 'tempdev' + CAST(@file_count AS nvarchar)

    SET  @file_name = REPLACE(@physical_name, 'tempdb.mdf', @logical_name + '.ndf')

    SET  @alter_command = 'ALTER DATABASE [tempdb] ADD FILE ( NAME =N''' + @logical_name + ''', FILENAME =N''' +  @file_name + ''', SIZE = ' + CAST(@size AS nvarchar) + 'MB, MAXSIZE = ' + CAST(@max_size AS nvarchar) + 'MB, FILEGROWTH = ' + CAST(@growth AS nvarchar) + 'MB )'

    PRINT   @alter_command

    EXEC    sp_executesql @alter_command

    SET  @file_count = @file_count + 1

END
