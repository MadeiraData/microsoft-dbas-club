SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT 
    CONCAT(N'Job "', j.name, N'" step ', s.step_id, N' ("', s.step_name,N'") has retries enabled but '
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
FROM 
    msdb.dbo.sysjobs AS j
INNER JOIN 
    msdb.dbo.sysjobsteps AS s ON j.job_id = s.job_id
WHERE 
    j.[enabled] = 1
    AND s.retry_attempts > 0
    AND s.output_file_name IS NOT NULL
    AND LTRIM(RTRIM(s.output_file_name)) <> ''
    AND (
            (s.flags & 2) = 0  -- Append to output file is disabled
            OR
            (
                s.output_file_name NOT LIKE '%(TIME)%'
            AND s.output_file_name NOT LIKE '%(STRTTM)%'
            AND s.output_file_name NOT LIKE '%(STRTDT)%'
            AND s.output_file_name NOT LIKE '%(DATE)%'
            )
        )
ORDER BY 
    j.name, s.step_id;
