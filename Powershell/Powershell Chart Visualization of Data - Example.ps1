<#
Visualizing SQL Server Results with PowerShell

Author:
Chad Callihan

Source:
https://callihandata.com/2024/05/27/visualizing-sql-server-results-with-powershell/
#>

# Load Windows Forms and drawing namespaces
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Load the Windows Forms Charting namespace
Add-Type -AssemblyName System.Windows.Forms.DataVisualization

# SQL Server connection details
$ServerInstance = "YourSqlServerInstance"
$Database = "YourDatabase"
$Query = @"
SELECT COUNT(*) AS 'Count', CAST(CreationDate AS date) AS 'Date'
FROM Users
WHERE CreationDate <= '2009-01-01'
GROUP BY CAST(CreationDate AS date)
ORDER BY COUNT(*) DESC
"@

# Create SQL connection
$Connection = New-Object System.Data.SqlClient.SqlConnection
$Connection.ConnectionString = "Server=$ServerInstance; Database=$Database; Integrated Security=True;"
$Connection.Open()

# Execute SQL query
$Command = $Connection.CreateCommand()
$Command.CommandText = $Query
$Result = $Command.ExecuteReader()

# Create a DataTable and load query results
$DataTable = New-Object System.Data.DataTable
$DataTable.Load($Result)

# Close the connection
$Connection.Close()

# Create a new Chart object
$Chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$Chart.Width = 800
$Chart.Height = 600

# Create a ChartArea to display the chart
$ChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
$Chart.ChartAreas.Add($ChartArea)

# Create a Series to hold the data
$Series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
$Series.Name = "UserCount"
$Series.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Column

# Add data to the Series
foreach ($Row in $DataTable.Rows) {
    $Series.Points.AddXY($Row["Date"].ToString("yyyy-MM-dd"), $Row["Count"])
}

# Add the Series to the Chart
$Chart.Series.Add($Series)

# Customize the X-axis labels
$ChartArea.AxisX.Interval = 1
$ChartArea.AxisX.IntervalType = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Days
$ChartArea.AxisX.LabelStyle.Format = "yyyy-MM-dd"
$ChartArea.AxisX.LabelStyle.Angle = -45

# Create a form to host the chart
$Form = New-Object Windows.Forms.Form
$Form.Text = "SQL Query Results"
$Form.Width = 850
$Form.Height = 650

# Add the chart to the form
$Chart.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$Form.Controls.Add($Chart)

# Show the form
[Windows.Forms.Application]::Run($Form)