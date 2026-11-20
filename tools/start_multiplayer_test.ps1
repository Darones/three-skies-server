param(
    [Parameter(Mandatory = $true)]
    [string]$Exe,
    [string]$SecondProfile = "$env:TEMP\ThreeSkiesPlayer2"
)

# Launch two clients with separate user:// profiles (different nicknames and
# player ids). Use the same matching PCK that ships with your EXE.
if (-not (Test-Path -LiteralPath $Exe)) {
    throw "EXE not found: $Exe"
}

$workDir = Split-Path -Parent (Resolve-Path -LiteralPath $Exe)
Start-Process -FilePath $Exe -WorkingDirectory $workDir

Start-Sleep -Seconds 8

New-Item -ItemType Directory -Force -Path $SecondProfile | Out-Null
$oldAppData = $env:APPDATA
try {
    $env:APPDATA = $SecondProfile
    Start-Process -FilePath $Exe -WorkingDirectory $workDir
} finally {
    $env:APPDATA = $oldAppData
}

Write-Host ""
Write-Host "Two clients launched."
Write-Host "In both: choose a hero and press PLAY within 30 seconds."
Write-Host "The first player starts the 30s countdown; bots fill the empty slots."
Write-Host "Second profile: $SecondProfile"
