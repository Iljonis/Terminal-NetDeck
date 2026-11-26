# Genera Terminal-NetDeck-X.Y.Z-Setup.exe (NetDeckBundle.wxs): el instalador de un paso, con Windows App Runtime 1.5 dentro.
# Prerequisitos: el .msi ya compilado (build-msi.ps1 o el CI) y wix 4.0.6 (dotnet tool install --global wix --version 4.0.6).
# La extension WixToolset.Bal.wixext 4.0.6 se anade sola si falta.
#
# El redistribuible de Microsoft se baja de la URL fija de windows-app-runtime.json (o se usa -Runtime con uno ya bajado) y
# se comprueban su sha256 y su firma Authenticode (firmante de ese .json) ANTES de meterlo en el .exe: va a ejecutarse con
# permisos de administrador en el equipo de quien instale.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/build-bundle.ps1 -Msi <ruta del .msi>
#        [-Out <ruta del Setup.exe>] [-Version 1.1.0] [-Runtime <WindowsAppRuntimeInstall-x64.exe ya bajado>]
param(
    [Parameter(Mandatory = $true)][string]$Msi,
    [string]$Out = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller\Terminal-NetDeck-Setup.exe'),
    [string]$Version = '1.1.0',
    [string]$Runtime = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fijado = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'windows-app-runtime.json') | ConvertFrom-Json

if (!(Test-Path -LiteralPath $Msi)) { throw "Falta el .msi: $Msi (compilalo antes con build-msi.ps1)." }

# (sin el operador ?. : es de PowerShell 7 y el uso de arriba es con powershell.exe 5.1)
$comandoWix = Get-Command wix -ErrorAction SilentlyContinue
$wix = if ($comandoWix) { $comandoWix.Source } else { $null }
if (!$wix) {
    $userWix = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
    if (Test-Path $userWix) { $wix = $userWix }
    else { throw 'wix no esta en PATH. Instala: dotnet tool install --global wix --version 4.0.6' }
}

# El redistribuible: bajado aqui (a una carpeta propia y vacia) o el que se pasa con -Runtime; en los dos casos, comprobado.
if (!$Runtime) {
    $carpeta = Join-Path $env:TEMP ('netdeck-runtime-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $carpeta | Out-Null
    $Runtime = Join-Path $carpeta 'WindowsAppRuntimeInstall-x64.exe'
    Write-Host "Bajando $($fijado.url) ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'          # (con la barra de progreso, Invoke-WebRequest de 5.1 va muchisimo mas lento)
    Invoke-WebRequest -UseBasicParsing -Uri $fijado.url -OutFile $Runtime
}
if (!(Test-Path -LiteralPath $Runtime)) { throw "Falta el redistribuible: $Runtime" }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Runtime).Hash.ToLower()
if ($hash -ne $fijado.sha256) { throw "El sha256 del redistribuible ($hash) no es el de windows-app-runtime.json ($($fijado.sha256))." }
$firma = Get-AuthenticodeSignature -LiteralPath $Runtime
if ($firma.Status -ne 'Valid') { throw "La firma del redistribuible no es valida: $($firma.Status)" }
if ($firma.SignerCertificate.Subject -ne $fijado.firmante) { throw "El redistribuible lo firma '$($firma.SignerCertificate.Subject)', no '$($fijado.firmante)'." }
Write-Host "Redistribuible comprobado: sha256 $hash, firmado por $($firma.SignerCertificate.Subject)"

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
    -d "RuntimeInstaller=$((Resolve-Path -LiteralPath $Runtime).Path)" `
    -d "Assets=$(Join-Path $repo 'windows\Desktop\Assets')" `
    -o $Out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$f = Get-Item $Out
Write-Host "Setup OK: $Out ($([math]::Round($f.Length/1MB,1)) MB)"
