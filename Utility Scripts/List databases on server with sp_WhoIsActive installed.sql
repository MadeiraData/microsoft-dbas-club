SELECT name, 
       CASE 
           WHEN OBJECT_ID(QUOTENAME(name) + '.dbo.sp_WhoIsActive') IS NOT NULL 
           THEN 'Exists'
           ELSE 'Doesn''t Exist'
       END AS 'Exist/Doesn''t Exist'
FROM sys.databases
WHERE state = 0
AND HAS_DBACCESS([name]) = 1
;
GO