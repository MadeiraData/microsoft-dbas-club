SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT 
    Msg = CONCAT(N'Job "', j.name, N'" step ', s.step_id, N' ("', s.step_name,N'") ',
    , CARE WHEN s.retry_attempts > 0 THEN N'has retries enabled but ' ELSE N'' END
    , CASE WHEN (s.flags & 2) = 0 THEN N'Append is disabled (which may cause loss of info) ' ELSE N'Append is enabled ' END
    , CASE WHEN
                s.output_file_name NOT LIKE '%(TIME)%'
            AND s.output_file_name NOT LIKE '%(STRTTM)%'
            AND s.output_file_name NOT LIKE '%(STRTDT)%'
            AND s.output_file_name NOT LIKE '%(DATE)%'
        THEN
            N'with no time-based tokens contained in the output file path'
            + CASE WHEN (s.flags & 2) > 0 THEN N' (which may cause the file to grow out of control) ' ELSE N' (which are needed when append is enabled) ' END
        ELSE N'' END
    , N' for the output file path: ', s.output_file_name)
    , s.step_id
    , RemediationCommand = N'-- REVIEW BEFORE EXECUTION:
    EXEC msdb.dbo.sp_update_jobstep 
        @job_name = N' + QUOTENAME(j.name, '''') + ', 
        @step_id = ' + CAST(s.step_id AS NVARCHAR(MAX)) + ', 
        @output_file_name = N''' + 
        CASE 
            WHEN     s.output_file_name NOT LIKE '%(TIME)%'
                 AND s.output_file_name NOT LIKE '%(STRTTM)%'
                 AND s.output_file_name NOT LIKE '%(STRTDT)%'
                 AND s.output_file_name NOT LIKE '%(DATE)%'
            THEN
                -- Insert tokens before .txt (case-insensitive)
                CASE 
                    WHEN LOWER(s.output_file_name) LIKE N'%.txt'
                    THEN LEFT(s.output_file_name, LEN(s.output_file_name) - 4) + '_$(ESCAPE_SQUOTE(DATE))_$(ESCAPE_SQUOTE(TIME)).txt'
                    ELSE s.output_file_name + '_$(ESCAPE_SQUOTE(DATE))_$(ESCAPE_SQUOTE(TIME))'
                END
            ELSE
                s.output_file_name
        END + ''', 
        @flags = ' + CAST(s.flags | 2 AS NVARCHAR(MAX))
FROM 
    msdb.dbo.sysjobs AS j
INNER JOIN 
    msdb.dbo.sysjobsteps AS s ON j.job_id = s.job_id
WHERE 
    j.[enabled] = 1
    AND s.output_file_name IS NOT NULL
    AND LTRIM(RTRIM(s.output_file_name)) <> ''
    AND (
            (s.retry_attempts > 0 AND (s.flags & 2) = 0)  -- Retry is enabled but Append to output file is disabled
            OR
            (
                (s.flags & 2) > 0 -- Append enabled
            AND s.output_file_name NOT LIKE '%(TIME)%'
            AND s.output_file_name NOT LIKE '%(STRTTM)%'
            AND s.output_file_name NOT LIKE '%(STRTDT)%'
            AND s.output_file_name NOT LIKE '%(DATE)%'
            )
        )
ORDER BY 
    j.name, s.step_id;
