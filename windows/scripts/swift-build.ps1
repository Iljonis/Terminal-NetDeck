# windows/scripts/swift-build.ps1 — lanza swift build con el PATH y SDKROOT correctos en este PC.
# Uso (desde la raíz del repositorio):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/swift-build.ps1 [argumentos de swift build]
# Ejemplo:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/swift-build.ps1 --target NetDeckCore
#
# Problemas conocidos de SPM en Windows (2026-11-10, Swift 6.4.2):
#   - SPM no crea .build/plugins/cache/ ni .build/plugins/outputs/ antes del primer build.
#     Este script los crea automáticamente.
#   - Las DLLs del runtime (swiftCore.dll, swift_Concurrency.dll…) están en Runtimes/, no en Toolchains/bin.
#   - git de DevKitPro (MSYS2) no resuelve bien los tags de SPM: Git for Windows debe ir antes en el PATH.

$ErrorActionPreference = 'Stop'

# Rutas de la instalación de Swift 6.4.2 en Windows (winget install Swift.Toolchain)
$base    = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$toolBin = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\bin'
$rtBin   = Join-Path $base 'Runtimes\6.4.2\usr\bin'
$mapi    = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\lib\swift\pm\ManifestAPI'
$sdk     = Join-Path $base 'Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk'
$gitWin  = 'C:\Program Files\Git\bin'

foreach ($dir in @($toolBin, $rtBin, $mapi, $sdk)) {
    if (-not (Test-Path $dir)) { Write-Error "No existe: $dir — ¿está instalado Swift 6.4.2?"; exit 1 }
}

$env:PATH    = "$gitWin;$toolBin;$rtBin;$mapi;" + $env:PATH
$env:SDKROOT = $sdk

# SPM no crea estos directorios en Windows antes del primer build
New-Item -ItemType Directory -Force '.build\plugins\cache'   | Out-Null
New-Item -ItemType Directory -Force '.build\plugins\outputs' | Out-Null

$swift = Join-Path $toolBin 'swift.exe'
& $swift build @args
exit $LASTEXITCODE
