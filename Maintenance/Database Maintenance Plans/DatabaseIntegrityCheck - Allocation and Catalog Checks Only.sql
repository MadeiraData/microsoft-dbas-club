/*
DatabaseIntegrityCheck - Allocation and Catalog Checks Only
==========================================================================
Author: Eitan Blumin
Date: 2024-10-27
Description:
	Use this variant to run only the most basic integrity checks,
	object-level checks not included.
	
	Please remember to create an additional, separate job to perform CHECKTABLE
	to complete the coverage for all database objects.

Prerequisites:
	- Ola Hallengren's maintenance solution installed. This script must run within the context of the database where it was installed.
	- Ola Hallengren's maintenance solution can be downloaded for free from here: https://ola.hallengren.com
	- SQL Server version 2012 or newer.
*/
DECLARE @MaxEndTime datetime = DATEADD(HOUR, 2, GETDATE())
DECLARE @TimeLimitSeconds int;

SET @TimeLimitSeconds = DATEDIFF(second, GETDATE(), @MaxEndTime)

EXEC dbo.DatabaseIntegrityCheck
	@Databases = 'ALL_DATABASES',
	@CheckCommands = 'CHECKALLOC,CHECKCATALOG',
	--@PhysicalOnly = 'Y',
	@TimeLimit = @TimeLimitSeconds,
	@LogToTable= 'Y',
	@Execute = 'Y'