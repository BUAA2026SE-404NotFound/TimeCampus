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

Write-Host "Stopping WSL instances if wsl.exe is available ..."
try {
    wsl --shutdown
} catch {
    Write-Warning "wsl --shutdown failed or WSL is unavailable: $($_.Exception.Message)"
}

$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "Microsoft-Hyper-V-All"
)
if ($IncludeContainers) {
    $features += "Containers"
}

foreach ($feature in $features) {
    Write-Host "Disabling $feature ..."
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
    } catch {
        Write-Warning "Failed to disable ${feature}: $($_.Exception.Message)"
    }
}

Write-Host "Disabling hypervisor launch at boot ..."
bcdedit /set hypervisorlaunchtype off | Out-Null

Write-Host "Hyper-V/WSL features were disabled. Existing WSL distributions are not deleted. A Windows restart is required."
if (-not $NoRebootPrompt) {
    $answer = Read-Host "Restart now? (y/N)"
    if ($answer -match "^(y|yes)$") {
        Restart-Computer
    }
}
