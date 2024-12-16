SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

;WITH RingBufferConnectivity AS
(
	SELECT
		records.record.value('(/Record/ConnectivityTraceRecord/RecordTime)[1]', 'datetime')										AS [RecordTime],			
		records.record.value('(/Record/ConnectivityTraceRecord/RecordType)[1]', 'varchar(max)')									AS [RecordType],
		records.record.value('(/Record/ConnectivityTraceRecord/RemoteHost)[1]', 'varchar(max)')									AS [RemoteHost],
		records.record.value('(/Record/ConnectivityTraceRecord/RemotePort)[1]', 'varchar(max)')									AS [RemotePort],
		records.record.value('(/Record/ConnectivityTraceRecord/LocalHost)[1]', 'varchar(max)')									AS [LocalHost],
		records.record.value('(/Record/ConnectivityTraceRecord/LocalPort)[1]', 'int')											AS [LocalPort],
		records.record.value('(/Record/ConnectivityTraceRecord/SniConsumerError)[1]', 'int')									AS [Error],
		records.record.value('(/Record/ConnectivityTraceRecord/Spid)[1]', 'int')												AS [Spid],
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/SessionIsKilled)[1]', 'int')					AS SessionIsKilled,			
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/PhysicalConnectionIsKilled)[1]', 'int')		AS PhysicalConnectionIsKilled,
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/DisconnectDueToReadError)[1]', 'int')			AS DisconnectDueToReadError,
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/NetworkErrorFoundInInputStream)[1]', 'int')	AS NetworkErrorFoundInInputStream,
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/ErrorFoundBeforeLogin)[1]', 'int')			AS ErrorFoundBeforeLogin,
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/RoutingCompleted)[1]', 'int')					AS RoutingCompleted,
		records.record.value('(/Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalDisconnect)[1]', 'int')					AS NormalDisconnect,
		records.record.value('(/Record/ConnectivityTraceRecord/SniConnectionId)[1]', 'uniqueidentifier')						AS SniConnectionId,
		records.record.value('(/Record/ConnectivityTraceRecord/ClientConnectionId)[1]', 'uniqueidentifier')						AS ClientConnectionId
	FROM
		(
			SELECT CAST(record as xml) AS record_data
			FROM sys.dm_os_ring_buffers
			WHERE ring_buffer_type= 'RING_BUFFER_CONNECTIVITY'
		) TabA
	CROSS APPLY record_data.nodes('//Record') AS records (record)
)
SELECT
	RBC.[RecordTime],
	RBC.[RecordType],
	RBC.[Error],
	M.[Severity],
	M.[text]							AS [ErrorText],	
	RBC.[RemoteHost],
	RBC.[RemotePort],		
	RBC.[LocalHost],
	RBC.[LocalPort],
	RBC.[Spid],
	RBC.[SessionIsKilled],
	RBC.[PhysicalConnectionIsKilled],
	RBC.[DisconnectDueToReadError],
	RBC.[NetworkErrorFoundInInputStream],
	RBC.[ErrorFoundBeforeLogin],
	RBC.[RoutingCompleted],
	RBC.[NormalDisconnect],
	RBC.[SniConnectionId],
	RBC.[ClientConnectionId],
	COUNT(*)
FROM 
	RingBufferConnectivity AS RBC
	LEFT JOIN sys.messages AS M ON RBC.[Error] = M.[message_id]
	INNER JOIN sys.syslanguages AS L ON M.[language_id] = L.[lcid] AND L.[name] = @@LANGUAGE
WHERE
	RBC.RecordType='Error'
	AND RBC.RecordTime > DATEADD(MINUTE,-10,GETUTCDATE())
	AND RemoteHost <> (SELECT client_net_address FROM sys.dm_exec_connections WHERE session_id = @@SPID)
	AND RBC.[Error] = 40615 -- is blocked by Azure FW
GROUP BY 
	RBC.[RecordTime],
	RBC.[RecordType],
	RBC.[Error],
	M.[Severity],
	M.[text],
	RBC.[RemoteHost],
	RBC.[RemotePort],		
	RBC.[LocalHost],
	RBC.[LocalPort],
	RBC.[Spid],
	RBC.[SessionIsKilled],
	RBC.[PhysicalConnectionIsKilled],
	RBC.[DisconnectDueToReadError],
	RBC.[NetworkErrorFoundInInputStream],
	RBC.[ErrorFoundBeforeLogin],
	RBC.[RoutingCompleted],
	RBC.[NormalDisconnect],
	RBC.[SniConnectionId],
	RBC.[ClientConnectionId]
ORDER BY
	RBC.[RecordTime] DESC


