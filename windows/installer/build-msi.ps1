# Genera NetDeckWindows.msi a partir de los archivos preparados por preparar-instalador.ps1.
# Prerequisito: dotnet tool install --global wix  (requiere .NET SDK 8+)
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/build-msi.ps1
param(
    [string]$SourceDir = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller\release'),
    [string]$Out      = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller\NetDeckWindows.msi'),
    [string]$Version  = '0.9.0'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$archivos = Join-Path (Split-Path $SourceDir -Parent) 'archivos.wxs'

if (!(Test-Path $SourceDir)) { throw "Falta SourceDir: $SourceDir — ejecuta preparar-instalador.ps1 -Configuracion release primero." }
if (!(Test-Path $archivos))  { throw "Falta archivos.wxs: $archivos — ejecuta preparar-instalador.ps1 primero." }

$wix = (Get-Command wix -ErrorAction SilentlyContinue)?.Source
if (!$wix) {
    $userWix = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
    if (Test-Path $userWix) { $wix = $userWix }
    else { throw 'wix no esta en PATH. Instala: dotnet tool install --global wix' }
}

Write-Host "Generando $Out ..."
& $wix build `
    (Join-Path $repo 'windows/installer/NetDeckWindows.wxs') `
    $archivos `
    -arch x64 `
    -d "SourceDir=$SourceDir" `
    -d "Version=$Version" `
    -o $Out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$f = Get-Item $Out
Write-Host "MSI OK: $Out ($([math]::Round($f.Length/1MB,1)) MB)"
