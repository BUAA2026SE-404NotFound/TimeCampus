param(
    [ValidateSet("deploy", "start", "stop", "status")]
    [string]$Action = "deploy",
    [string]$Distro = "Ubuntu",
    [string]$ServiceHost = "127.0.0.1",
    [int]$ServerPort = 8080,
    [string]$SpringProfiles = "dev,wsl",
    [string]$WslAppDir = "~/app",
    [int]$HealthTimeoutSeconds = 60,
    [switch]$SkipBuild,
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backend = Join-Path $root "TimeCampus-Backend"
$serverTarget = Join-Path $backend "timecampus-server\target"

function Invoke-Checked {
    param(
        [scriptblock]$Command,
        [string]$ErrorMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function ConvertTo-WslPath {
    param([string]$Path)

    $normalized = $Path -replace "\\", "/"
    $converted = & wsl.exe -d $Distro -- wslpath -a $normalized
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to convert path to WSL path: $Path"
    }
    return ($converted | Select-Object -Last 1).Trim()
}

function Get-BackendJar {
    if (-not (Test-Path $serverTarget)) {
        return $null
    }

    return Get-ChildItem $serverTarget -Filter "*.jar" |
        Where-Object { $_.Name -notlike "original-*" -and $_.Name -notlike "*sources*" -and $_.Name -notlike "*javadoc*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe was not found. Enable WSL before using this script."
}

Invoke-Checked -Command { & wsl.exe -d $Distro -- true } -ErrorMessage "WSL distro '$Distro' is not available."

$rootWsl = ConvertTo-WslPath $root

if ($Action -eq "deploy" -and -not $SkipBuild) {
    $mvn = Get-Command mvn -ErrorAction SilentlyContinue
    if ($mvn) {
        Write-Host "Building backend on Windows with Maven ..."
        Push-Location $backend
        try {
            Invoke-Checked -Command { & $mvn.Source -B -pl timecampus-server -am package -DskipTests } -ErrorMessage "Maven package failed."
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "Windows Maven was not found; building backend from WSL over the mounted repository ..."
        $backendWsl = ConvertTo-WslPath $backend
        $buildScript = "cd '$($backendWsl.Replace("'", "'\''"))' && mvn -B -pl timecampus-server -am package -DskipTests"
        Invoke-Checked -Command { & wsl.exe -d $Distro -- bash -lc $buildScript } -ErrorMessage "WSL Maven package failed."
    }
}

$jar = Get-BackendJar
if (($Action -eq "deploy") -and -not $jar) {
    throw "No backend jar found under $serverTarget. Run without -SkipBuild or build the backend first."
}

$jarWsl = if ($jar) { ConvertTo-WslPath $jar.FullName } else { "" }
$noStartValue = if ($NoStart) { "true" } else { "false" }

$bash = @'
set -Eeuo pipefail

ACTION="$1"
REPO_ROOT="$2"
JAR_PATH="$3"
APP_DIR_RAW="$4"
SPRING_PROFILES="$5"
SERVICE_HOST="$6"
SERVER_PORT="$7"
HEALTH_TIMEOUT="$8"
NO_START="$9"

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

APP_DIR="$(expand_path "$APP_DIR_RAW")"
PID_FILE="$APP_DIR/timecampus-backend.pid"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/backend.log"
CONFIG_DIR="$APP_DIR/config"
STORAGE_DIR="$APP_DIR/storage"
APP_JAR="$APP_DIR/app.jar"

mkdir -p "$APP_DIR" "$CONFIG_DIR" "$STORAGE_DIR" "$LOG_DIR" "$APP_DIR/backup"

check_port() {
  local name="$1"
  local host="$2"
  local port="$3"
  if timeout 1 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    echo "[ok] ${name} port ${host}:${port} is reachable from WSL"
  else
    echo "[warn] ${name} port ${host}:${port} is not reachable from WSL"
  fi
}

stop_app() {
  local stopped="false"
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "Stopping TimeCampus backend pid ${pid} ..."
      kill "$pid" >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do
        if ! kill -0 "$pid" >/dev/null 2>&1; then
          stopped="true"
          break
        fi
        sleep 0.5
      done
      if [ "$stopped" != "true" ] && kill -0 "$pid" >/dev/null 2>&1; then
        echo "Force stopping pid ${pid} ..."
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
    rm -f "$PID_FILE"
  fi

  local stray_pids
  stray_pids="$(pgrep -f "java .*${APP_JAR}" || true)"
  if [ -n "$stray_pids" ]; then
    echo "$stray_pids" | xargs -r kill >/dev/null 2>&1 || true
  fi
}

write_wsl_config() {
  local config_src="$REPO_ROOT/config"
  if [ ! -d "$config_src" ]; then
    echo "Missing local config directory: $config_src" >&2
    exit 1
  fi

  rm -f "$CONFIG_DIR"/application*.yaml "$CONFIG_DIR"/application*.yml
  shopt -s nullglob
  local copied=0
  for f in "$config_src"/application*.yaml "$config_src"/application*.yml; do
    cp "$f" "$CONFIG_DIR/"
    copied=$((copied + 1))
  done
  shopt -u nullglob

  if [ "$copied" -eq 0 ]; then
    echo "No application*.yaml files found in $config_src" >&2
    exit 1
  fi

  cat > "$CONFIG_DIR/application-wsl.yaml" <<YAML
server:
  address: 0.0.0.0
  port: \${SERVER_PORT:${SERVER_PORT}}

storage:
  local-root-dir: \${TIMECAMPUS_STORAGE_DIR:${STORAGE_DIR}}

spring:
  datasource:
    url: \${SPRING_DATASOURCE_URL:jdbc:mysql://${SERVICE_HOST}:3306/timetrack?useUnicode=true&characterEncoding=UTF-8&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true&useSSL=false}
  data:
    redis:
      host: \${REDIS_HOST:${SERVICE_HOST}}
      port: \${REDIS_PORT:6379}
  ai:
    vectorstore:
      qdrant:
        host: \${QDRANT_HOST:${SERVICE_HOST}}
        port: \${QDRANT_GRPC_PORT:6334}

timecampus:
  ai:
    ollama:
      embedding:
        base-url: \${OLLAMA_BASE_URL:http://${SERVICE_HOST}:11434}
YAML

  echo "Copied ${copied} config file(s) into $CONFIG_DIR"
  echo "Generated $CONFIG_DIR/application-wsl.yaml"
}

copy_jar() {
  if [ -z "$JAR_PATH" ] || [ ! -f "$JAR_PATH" ]; then
    echo "Backend jar was not found: $JAR_PATH" >&2
    exit 1
  fi
  cp "$JAR_PATH" "$APP_JAR"
  echo "Copied jar to $APP_JAR"
}

show_status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "TimeCampus backend is running: pid ${pid}"
      echo "Health: http://127.0.0.1:${SERVER_PORT}/api/v1/health"
      echo "Log: $LOG_FILE"
      return 0
    fi
  fi
  echo "TimeCampus backend is not running"
  return 1
}

start_app() {
  if [ ! -f "$APP_JAR" ]; then
    echo "Missing $APP_JAR. Run deploy first." >&2
    exit 1
  fi
  if ! command -v java >/dev/null 2>&1; then
    echo "java was not found in WSL." >&2
    exit 1
  fi

  check_port "MySQL" "$SERVICE_HOST" 3306
  check_port "Redis" "$SERVICE_HOST" 6379
  check_port "Qdrant gRPC" "$SERVICE_HOST" 6334
  check_port "Ollama" "$SERVICE_HOST" 11434

  stop_app

  echo "Starting TimeCampus backend on WSL port ${SERVER_PORT} with profiles ${SPRING_PROFILES} ..."
  (
    cd "$APP_DIR"
    export SPRING_PROFILES_ACTIVE="$SPRING_PROFILES"
    export SERVER_PORT="$SERVER_PORT"
    export TIMECAMPUS_STORAGE_DIR="$STORAGE_DIR"
    nohup java -jar "$APP_JAR" \
      --spring.config.additional-location="file:${CONFIG_DIR}/" \
      --server.address=0.0.0.0 \
      --server.port="$SERVER_PORT" \
      > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
  )

  local pid
  pid="$(cat "$PID_FILE")"
  local health_url="http://127.0.0.1:${SERVER_PORT}/api/v1/health"
  local deadline=$((SECONDS + HEALTH_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "Backend process exited during startup. Recent log:" >&2
      tail -n 100 "$LOG_FILE" >&2 || true
      exit 1
    fi
    local code
    code="$(curl -sS -o /tmp/timecampus-wsl-health.out -w "%{http_code}" "$health_url" 2>/dev/null || true)"
    if [ "$code" = "200" ]; then
      echo "Backend is healthy: $health_url"
      return 0
    fi
    sleep 2
  done

  echo "Backend did not become healthy within ${HEALTH_TIMEOUT}s. Recent log:" >&2
  tail -n 120 "$LOG_FILE" >&2 || true
  exit 1
}

case "$ACTION" in
  deploy)
    copy_jar
    write_wsl_config
    if [ "$NO_START" = "true" ]; then
      echo "Deployment files are ready under $APP_DIR; start was skipped."
    else
      start_app
    fi
    ;;
  start)
    start_app
    ;;
  stop)
    stop_app
    echo "TimeCampus backend stopped."
    ;;
  status)
    show_status || true
    ;;
esac
'@

$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("timecampus-wsl-deploy-{0}.sh" -f ([guid]::NewGuid()))
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempScript, $bash, $utf8NoBom)

try {
    $tempScriptWsl = ConvertTo-WslPath $tempScript
    Invoke-Checked -Command {
        & wsl.exe -d $Distro -- bash $tempScriptWsl `
            $Action `
            $rootWsl `
            $jarWsl `
            $WslAppDir `
            $SpringProfiles `
            $ServiceHost `
            "$ServerPort" `
            "$HealthTimeoutSeconds" `
            $noStartValue
    } -ErrorMessage "WSL backend deployment action '$Action' failed."
} finally {
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}
