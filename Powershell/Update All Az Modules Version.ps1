# Specify which Az modules to save. The rest will be uninstalled
$modulesToSave = @("Az.Sql","Az.Account","Az.Accounts","Az.Compute","Az.Resources","Az.ManagementPartner")

Get-Module -Name Az.* -ListAvailable | ForEach-Object {
    $moduleName = $_.Name
    $currentVersion = [Version]$_.Version

    Write-Host "Current version $moduleName [$currentVersion]"

    # Get latest version from gallery
    $latestVersion = [Version](Find-Module -Name $moduleName).Version
    
    if ($moduleName -notin $modulesToSave) {

        # Uninstall outdated version
        Write-Host "Uninstalling $moduleName [$currentVersion]"
        Uninstall-Module -Name $moduleName -RequiredVersion $currentVersion -Force

    } elseif ($latestVersion -gt $currentVersion) {
    # Only proceed if latest version in gallery is greater than your current version
        Write-Host "Found latest version $modulename [$latestVersion] from $($latestVersion.Repository)"

        # Check if latest version is already installed before updating
        $latestVersionModule = Get-InstalledModule -Name $moduleName -RequiredVersion $latestVersion -ErrorAction SilentlyContinue
        if ($null -eq $latestVersionModule) {
            Write-Host "Updating $moduleName Module from [$currentVersion] to [$latestVersion]"
            Update-Module -Name $moduleName -RequiredVersion $latestVersion -Force
        }
        else {
            Write-Host "No update needed, $modulename [$latestVersion] already exists"
        }

        # Uninstall outdated version
        Write-Host "Uninstalling $moduleName [$currentVersion]"
        Uninstall-Module -Name $moduleName -RequiredVersion $currentVersion -Force
    }

    # Otherwise we already have most up to date version
    else {
        Write-Host "$moduleName already up to date"
    }
}