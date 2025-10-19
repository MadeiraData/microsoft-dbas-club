/*========================================================================================================================

Description:	Display all the objects referenced by another object
				For example, display all the objects (tables, views, etc.) referenced by a specific view
Scope:			Database
Author:			Guy Glantser
Created:		26/04/2022
Last Updated:	26/04/2022
Notes:			

=========================================================================================================================*/

SELECT
    ReferencedServerName	= Dependencies.referenced_server_name ,
	ReferencedDatabaseName	= Dependencies.referenced_database_name ,
	ReferencedSchemaName	= Dependencies.referenced_schema_name ,
	ReferencedObjectName	= Dependencies.referenced_entity_name
FROM
	sys.sql_expression_dependencies AS Dependencies
WHERE
	Dependencies.referencing_id = OBJECT_ID (N'YourObject')
AND
	Dependencies.referencing_class = 1	-- Object or column
ORDER BY
    ReferencedServerName	ASC ,
	ReferencedDatabaseName	ASC ,
	ReferencedSchemaName	ASC ,
	ReferencedObjectName	ASC;
GO

-- Get all dependencies

SELECT
    ReferencedObject	= ISNULL(QUOTENAME(Dependencies.referenced_server_name) + '.', '') + ISNULL(QUOTENAME(Dependencies.referenced_database_name) + '.', '') + ISNULL(QUOTENAME(Dependencies.referenced_schema_name) + '.','') + QUOTENAME(Dependencies.referenced_entity_name) ,
	ReferencingObject = QUOTENAME(DB_NAME()) + '.' + QUOTENAME(OBJECT_SCHEMA_NAME(Dependencies.referencing_id)) + '.' + QUOTENAME(OBJECT_NAME(Dependencies.referencing_id)) ,
	ReferencingClass = Dependencies.referencing_class_desc
FROM
	sys.sql_expression_dependencies AS Dependencies
WHERE
	Dependencies.referenced_entity_name NOT IN ('sysdiagrams','dtproperties')
ORDER BY
    ReferencedObject	ASC ,
	ReferencingObject	ASC;
GO