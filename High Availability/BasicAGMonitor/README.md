The goal of the bellow 2 Powershell scripts is to assure that all AGs (Availability Grupes) are hosted on the Primary Replica.
This is required for sql server standard edition where you can have multiple groups and while a cross database dpendency exists enforcing you to have all databases hosted on the same replica.

The scripts are intended to be used for monitoring purposes.

The 2 scripts provide the same functionality and differs by the fact that 1 script processes the task(s) single threaded while the other script processes the task(s) multi threaded.
Use the multi threaded version in cases where there are many AGs to reduce the overall failover time.

monitor_ag_owner_node.ps1		   - Multi Threaded

monitor_ag_owner_node_v2.ps1	- Single Threaded


The script is intended for sql server std. edition that has the following setup:
1. Basic Availability Groups with multiple groups 
2. A single vnn/listener
3. There is a cross database dependency.

When the above conditione are true there is a requirement to have all AGs located on the same replica.
The script implements the following logic:
1. Detects the replica that owns the vnn/listener and reffers to this replica as the Primary Replica.
2. Looks for any AG that is hosted on a Secondary Replica and initiates a failover for the given AG.
