-- more info:
-- https://aka.ms/sqldbtipswiki#tip_id-1000
-- https://aka.ms/sqldbtipswiki#tip_id-1010
-- https://aka.ms/sqldbtipswiki#tip_id-1020
-- https://techcommunity.microsoft.com/blog/azuresqlblog/changing-default-maxdop-in-azure-sql-database-and-azure-sql-managed-instance/1538528

DECLARE @PrimaryMaxDop int, @SecondaryMaxDop int, @CpuCount int, @EffectiveMaxDOP int, @SchedulersCount int, @RecommendedMaxDOP int
select @CpuCount = cpu_count, @SchedulersCount = scheduler_count from sys.dm_os_sys_info

SELECT @PrimaryMaxDop = c.value,
       @SecondaryMaxDop = c.value_for_secondary,
	   @CpuCount = g.cpu_limit
FROM sys.database_scoped_configurations AS c
CROSS JOIN sys.dm_user_db_resource_governance AS g
WHERE 
      CAST(SERVERPROPERTY('EngineEdition') AS int) = 5
      AND
      c.name = N'MAXDOP'
      AND
      g.database_id = DB_ID()


SET @EffectiveMaxDOP = @PrimaryMaxDop

IF @EffectiveMaxDOP = 0
      SET @EffectiveMaxDOP = @SchedulersCount;

IF @CpuCount < @EffectiveMaxDOP
      SET @RecommendedMaxDOP = @CpuCount;
ELSE IF @EffectiveMaxDOP > 8 AND @CpuCount >= 8
      SET @RecommendedMaxDOP = 8
ELSE
      SET @RecommendedMaxDOP = @EffectiveMaxDOP

RAISERROR(N'Current MaxDOP: %d',0,1, @CurrentMaxDop)
RAISERROR(N'Effective MaxDOP: %d',0,1, @EffectiveMaxDOP)
RAISERROR(N'Cpu Count: %d',0,1, @CpuCount)

IF @RecommendedMaxDOP = @PrimaryMaxDop AND ISNULL(@SecondaryMaxDop,@RecommendedMaxDOP) = @RecommendedMaxDOP
      PRINT N'Nothing to change.'

SELECT CONCAT(
             'MAXDOP not in recomended range (primary: ', CAST(@PrimaryMaxDop AS varchar(2)),
             ', secondary: ', ISNULL(CAST(@SecondaryMaxDop AS varchar(4)), 'NULL'), ')'
             )
       AS details
    , CONCAT(N'ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = ' + CONVERT(nvarchar(4000), @RecommendedMaxDOP), ';'
	 , ISNULL(CHAR(13) + CHAR(10) + N'ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET MAXDOP = ' + CONVERT(nvarchar(4000), @RecommendedMaxDOP), N''))
WHERE (@PrimaryMaxDop NOT BETWEEN 1 AND 8)
   OR
   (@SecondaryMaxDop IS NOT NULL AND @SecondaryMaxDop NOT BETWEEN 1 AND 8)
   OR
   (@PrimaryMaxDop > @CpuCount)
   OR
   (@SecondaryMaxDop > @CpuCount)
;
