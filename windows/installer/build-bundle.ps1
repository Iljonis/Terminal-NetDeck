# Genera Terminal-NetDeck-X.Y.Z-Setup.exe (NetDeckBundle.wxs): el instalador de un paso, con el .msi dentro.
# Prerequisitos: el .msi ya compilado (build-msi.ps1 o el CI) y wix 4.0.6 (dotnet tool install --global wix --version 4.0.6).
# La extension WixToolset.Bal.wixext 4.0.6 se anade sola si falta. Windows App Runtime y OpenSSH ya van dentro del .msi
# (incluir-dependencias.ps1): el Setup.exe no instala nada mas.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/build-bundle.ps1 -Msi <ruta del .msi>
#        [-Out <ruta del Setup.exe>] [-Version 1.1.1]
param(
    [Parameter(Mandatory = $true)][string]$Msi,
    [string]$Out = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller\Terminal-NetDeck-Setup.exe'),
    [string]$Version = '1.1.1'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

if (!(Test-Path -LiteralPath $Msi)) { throw "Falta el .msi: $Msi (compilalo antes con build-msi.ps1)." }

# (sin el operador ?. : es de PowerShell 7 y el uso de arriba es con powershell.exe 5.1)
$comandoWix = Get-Command wix -ErrorAction SilentlyContinue
$wix = if ($comandoWix) { $comandoWix.Source } else { $null }
if (!$wix) {
    $userWix = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
    if (Test-Path $userWix) { $wix = $userWix }
    else { throw 'wix no esta en PATH. Instala: dotnet tool install --global wix --version 4.0.6' }
}

# La extension de la interfaz estandar de Burn (global: la misma que usa el CI)
$extensiones = & $wix extension list -g 2>&1 | Out-String
if ($extensiones -notmatch 'WixToolset\.Bal\.wixext 4\.0\.6') {
    & $wix extension add -g WixToolset.Bal.wixext/4.0.6
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo anadir WixToolset.Bal.wixext 4.0.6' }
}

New-Item -ItemType Directory -Force (Split-Path $Out -Parent) | Out-Null
Write-Host "Generando $Out ..."
& $wix build `
    (Join-Path $repo 'windows/installer/NetDeckBundle.wxs') `
    -ext WixToolset.Bal.wixext `
    -arch x64 `
    -d "Version=$Version" `
    -d "Msi=$((Resolve-Path -LiteralPath $Msi).Path)" `
    -d "Assets=$(Join-Path $repo 'windows\Desktop\Assets')" `
    -o $Out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$f = Get-Item $Out
Write-Host "Setup OK: $Out ($([math]::Round($f.Length/1MB,1)) MB)"
