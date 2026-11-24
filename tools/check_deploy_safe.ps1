# Refuse to deploy while a live match is running.
# Usage: powershell -ExecutionPolicy Bypass -File tools/check_deploy_safe.ps1
$ErrorActionPreference = "Stop"
$healthUrl = "https://three-skies-server.relaxdev.ru/health"
$statsUrl = "https://three-skies-server.relaxdev.ru/stats/data?token=239837"

try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 10
} catch {
    Write-Output "BLOCKED health request failed: $($_.Exception.Message)"
    exit 2
}

$live = 0
if ($null -ne $health.live_matches) {
    $live = [int]$health.live_matches
}
if ($live -gt 0) {
    Write-Output "BLOCKED live_matches=$live; wait for the match to finish"
    exit 1
}

try {
    $stats = Invoke-RestMethod -Uri $statsUrl -TimeoutSec 10
    $online = [int]$stats.online_now
    if ($online -gt 0) {
        Write-Output "WARN online_now=$online (no live match detected); deploy is allowed but players are online"
    } else {
        Write-Output "OK live_matches=0 online_now=0"
    }
} catch {
    Write-Output "OK live_matches=0 (stats unavailable)"
}
exit 0
