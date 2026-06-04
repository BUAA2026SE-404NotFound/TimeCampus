param(
    [switch]$IncludeContainers,
    [switch]$NoRebootPrompt
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        if ($IncludeContainers) { $argsList += "-IncludeContainers" }
        if ($NoRebootPrompt) { $argsList += "-NoRebootPrompt" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argsList
        exit
    }
}

Assert-Administrator

$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "Microsoft-Hyper-V-All"
)
if ($IncludeContainers) {
    $features += "Containers"
}

foreach ($feature in $features) {
    Write-Host "Enabling $feature ..."
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
    } catch {
        Write-Warning "Failed to enable ${feature}: $($_.Exception.Message)"
    }
}

Write-Host "Enabling hypervisor launch at boot ..."
bcdedit /set hypervisorlaunchtype auto | Out-Null

Write-Host "Hyper-V/WSL features were enabled. A Windows restart is required."
if (-not $NoRebootPrompt) {
    $answer = Read-Host "Restart now? (y/N)"
    if ($answer -match "^(y|yes)$") {
        Restart-Computer
    }
}
