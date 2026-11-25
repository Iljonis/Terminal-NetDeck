# windows/scripts/swift-build.ps1 — lanza swift build con el PATH y SDKROOT correctos en este PC.
# Uso (desde la raiz del repositorio):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/swift-build.ps1 [argumentos de swift build]
# Ejemplo:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/swift-build.ps1 --target NetDeckCore
#
# Problemas conocidos de SPM en Windows (2026-11-10, Swift 6.4.2):
#   - SPM no crea .build/plugins/cache/ ni .build/plugins/outputs/ antes del primer build.
#   - Las DLLs del runtime estan en Runtimes/, no en Toolchains/bin.
#   - git de DevKitPro (MSYS2) no resuelve bien los tags de SPM: Git for Windows debe ir antes en el PATH.
#   - Windows Defender "Controlled Folder Access" bloquea a llvm-lib.exe en Documents/: se usa
#     --scratch-path en AppData\Local\NetDeckBuild (fuera de las carpetas protegidas).
#   - SPM no puede crear el symlink .build/debug en Windows sin Developer Mode (warning inofensivo).

$ErrorActionPreference = 'Continue'

$base    = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$toolBin = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\bin'
$rtBin   = Join-Path $base 'Runtimes\6.4.2\usr\bin'
$mapi    = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\lib\swift\pm\ManifestAPI'
$sdk     = Join-Path $base 'Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk'
$gitWin  = 'C:\Program Files\Git\bin'

foreach ($dir in @($toolBin, $rtBin, $mapi, $sdk)) {
    if (-not (Test-Path $dir)) { Write-Error "No existe: $dir (instalar Swift 6.4.2?)"; exit 1 }
}

$env:PATH    = "$gitWin;$toolBin;$rtBin;$mapi;" + $env:PATH
$env:SDKROOT = $sdk

# SPM no crea estos directorios en Windows antes del primer build
New-Item -ItemType Directory -Force '.build\plugins\cache'   | Out-Null
New-Item -ItemType Directory -Force '.build\plugins\outputs' | Out-Null

# Ruta de build fuera de Documents para evitar el bloqueo de Windows Defender Controlled Folder Access
# en llvm-lib.exe (que no puede crear .lib en carpetas protegidas del usuario).
$scratchPath = Join-Path $env:LOCALAPPDATA 'NetDeckBuild'
New-Item -ItemType Directory -Force $scratchPath | Out-Null

$swift = Join-Path $toolBin 'swift.exe'
# -DOPENSSL_NO_ASM: BoringSSL necesita NASM para ASM en Windows; con este flag usa C puro.
& $swift build --scratch-path $scratchPath -Xcc -DOPENSSL_NO_ASM @args
exit $LASTEXITCODE