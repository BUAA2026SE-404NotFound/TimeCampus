param(
    [int]$Port = 8080,
    [switch]$WithQdrant,
    [string]$McpToken = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root "TimeCampus-Backend"

function Import-SelectedDotEnv {
    param(
        [string]$Path,
        [string[]]$Names
    )

    if (-not (Test-Path $Path)) {
        return
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or $line -notmatch "^([^=]+)=(.*)$") {
            return
        }
        $name = $matches[1].Trim()
        if ($Names -notcontains $name) {
            return
        }
        $value = $matches[2].Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

Import-SelectedDotEnv -Path (Join-Path $root ".env") -Names @(
    "TENCENT_MAP_KEY",
    "TENCENT_MAP_SK",
    "DEEPSEEK_API_KEY",
    "ZHIPU_API_KEY"
)

$env:SERVER_PORT = "$Port"
$env:CAP_ENABLED = "false"
$env:TIMECAMPUS_MCP_ENABLED = "true"

if ($McpToken) {
    $env:TIMECAMPUS_MCP_AUTH_REQUIRED = "true"
    $env:TIMECAMPUS_MCP_TOKEN = $McpToken
} else {
    $env:TIMECAMPUS_MCP_AUTH_REQUIRED = "false"
}

if ($WithQdrant) {
    $env:SPRING_AI_VECTORSTORE_TYPE = "qdrant"
    $env:TIMECAMPUS_RAG_VECTOR_ENABLED = "true"
} else {
    $env:SPRING_AI_VECTORSTORE_TYPE = "none"
    $env:TIMECAMPUS_RAG_VECTOR_ENABLED = "false"
}

Write-Host "Starting TimeCampus backend + MCP on http://127.0.0.1:$Port"
Write-Host "MCP endpoint: http://127.0.0.1:$Port/mcp"
Write-Host "Qdrant vector store: $(if ($WithQdrant) { 'enabled' } else { 'disabled, lexical RAG fallback only' })"

Push-Location $backend
try {
    mvn -q -pl timecampus-server -am spring-boot:run
} finally {
    Pop-Location
}
