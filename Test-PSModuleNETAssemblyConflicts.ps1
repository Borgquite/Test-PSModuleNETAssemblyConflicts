# https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/resolving-dependency-conflicts?view=powershell-7.5#differences-in-net-framework-vs-net-core
    # 'For PowerShell, this means that the following factors can affect an assembly load conflict:
        # Which module was loaded first?
        # Was the code path that uses the dependency library run?
        # Does PowerShell load a conflicting dependency at startup or only under certain code paths?'
# https://devblogs.microsoft.com/powershell/resolving-powershell-module-assembly-dependency-conflicts/

# [System.AppDomain]::CurrentDomain.GetAssemblies() | Sort-Object Location | Select-Object FullName, Location

$ModulesCheckCommandsForAssemblyClashes = @{
    'Az.Accounts' = {Connect-AzAccount -Credential (New-Object System.Management.Automation.PSCredential ("username@contoso.com", (New-Object System.Security.SecureString)))}
    'Microsoft.Graph.Authentication' = {Connect-MgGraph -AccessToken (ConvertTo-SecureString -String "accesstoken" -AsPlainText -Force)}
    'ExchangeOnlineManagement' = {Connect-ExchangeOnline -Credential (New-Object System.Management.Automation.PSCredential ("username@contoso.com", (New-Object System.Security.SecureString))) -DisableWAM}
    'PnP.PowerShell' = {Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Credentials (New-Object System.Management.Automation.PSCredential ("username@contoso.com", (New-Object System.Security.SecureString)))}
}

$AssembliesLoaded = [System.Collections.Generic.List[psobject]]::new()

# Go through each module and import into the PowerShell job system; once imported, get the assemblies that are loaded, and store in a hashtable
foreach ($ModuleToCheck in $ModulesCheckCommandsForAssemblyClashes.GetEnumerator()) {
    Write-Verbose "Checking $($ModuleToCheck.Key) with $($ModuleToCheck.Value)..." -Verbose
    $ModuleResults = Start-Job { Import-Module $using:ModuleToCheck.Key; try {Invoke-Expression $using:ModuleToCheck.Value} catch {}; [System.AppDomain]::CurrentDomain.GetAssemblies() } | Receive-Job -Wait
    foreach ($ModuleResult in $ModuleResults) {
        $AssembliesLoaded.Add(@{$ModuleToCheck.Key = $ModuleResult})
    }
}

# Get all the objects grouped by modules that they share
$SharedModuleAssemblies = ($AssembliesLoaded | Group-Object {$_.Values.ManifestModule} -AsHashTable -AsString).GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

# Want all the modules where the count in the second group may not equal the count in the first group (i.e. not all the same)
$ConflictingModuleAssemblies = $SharedModuleAssemblies | Select-Object -PipelineVariable SharedModuleAssembly | ForEach-Object { ($SharedModuleAssembly.Value | Group-Object { $_.Values.FullName } -AsHashTable -AsString).GetEnumerator() | Where-Object { $_.Value.Count -lt $SharedModuleAssembly.Value.Count } }

# List out all of the uniquely conflicting assemblies with each module's path
$ConflictingModuleAssemblies.Value.Values | Sort-Object FullName, Location -Descending | Select-Object -Unique -Property FullName, Location