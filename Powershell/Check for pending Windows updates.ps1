try {
    # Try to create the Windows Update COM object
    $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
    $searcher = $session.CreateUpdateSearcher()

    # Only need to know if ANY updates are pending (not installed & not hidden)
    Write-Output "Searching..."
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and IsAssigned=1")

    if ($result.Updates.Count -gt 0) {
        Write-Output "YES. $($result.Updates.Count) pending update(s) found."
    } else {
        Write-Output "NO"
    }
}
catch {
    # Covers: COM not allowed, insufficient permissions, group policy blocks updates, etc.
    Write-Output "ERROR: $($_.Exception.Message)"
}
