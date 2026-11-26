# Compila la interfaz WinUI 3 de P8. -Demo abre la ventana con un perfil temporal. -Configuration release es el build del instalador
# (la carpeta de salida pasa a ser Release-windows-x86_64: windows/installer/preparar-instalador.ps1 -Configuracion release).
param([switch]$Demo, [string]$Scratch = (Join-Path $env:LOCALAPPDATA 'NetDeckDesktopBuild'), [ValidateSet('debug', 'release')][string]$Configuration = 'debug')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$package = Join-Path $repo 'windows/Desktop'
$swift = (Get-Command swift.exe -CommandType Application -TotalCount 1).Source
$swiftRoot = Join-Path $env:LOCALAPPDATA 'Programs/Swift'
$runtimeBin = Join-Path $swiftRoot 'Runtimes/6.4.2/usr/bin'
$manifestBin = Join-Path (Split-Path (Split-Path $swift)) 'lib/swift/pm/ManifestAPI'
$env:PATH = "$runtimeBin;$manifestBin;$env:PATH"
if (!$env:SDKROOT) {
    $env:SDKROOT = Join-Path $swiftRoot 'Platforms/6.4.2/Windows.platform/Developer/SDKs/Windows.sdk'
}

# El terminfo necesita LF. Pasar los metadatos evita que el plugin invoque Git via Foundation.Process.
$gitConfigIndex = [int]$env:GIT_CONFIG_COUNT
$env:GIT_CONFIG_COUNT = [string]($gitConfigIndex + 1)
Set-Item "env:GIT_CONFIG_KEY_$gitConfigIndex" 'core.autocrlf'
Set-Item "env:GIT_CONFIG_VALUE_$gitConfigIndex" 'false'
$lock = Get-Content -LiteralPath (Join-Path $package 'Package.resolved') -Raw | ConvertFrom-Json
$pin = $lock.pins | Where-Object identity -eq 'swiftterm'
$env:SWIFTTERM_BUILD_BRANCH = 'release'
$env:SWIFTTERM_BUILD_TAG = $pin.state.version
$env:SWIFTTERM_BUILD_COMMIT = $pin.state.revision
$env:SWIFTTERM_BUILD_DIRTY = 'false'

# El icono del .exe (logo de NetDeck): NetDeck.rc -> NetDeck.res, que Package.swift enlaza si existe. Si falta llvm-rc el
# build sigue, sin icono.
$rc = Join-Path (Split-Path $swift) 'llvm-rc.exe'
if (Test-Path $rc) {
    Push-Location $package
    try {
        & $rc /FO (Join-Path $package 'NetDeck.res') (Join-Path $package 'NetDeck.rc')
        if ($LASTEXITCODE -ne 0) { Write-Warning "llvm-rc falló (código $LASTEXITCODE): el .exe saldrá sin icono."; Remove-Item (Join-Path $package 'NetDeck.res') -ErrorAction SilentlyContinue }
    } finally { Pop-Location }
} else {
    Write-Warning 'No está llvm-rc: el .exe saldrá sin icono.'
}

$build = @('--package-path', $package, '--scratch-path', $scratch, '--force-resolved-versions', '-c', $Configuration, '-Xcc', '-DOPENSSL_NO_ASM', '-Xcc', '-D_CRT_SECURE_NO_WARNINGS')
# En Windows sin Developer Mode SwiftPM sale con código 1 al fallar el symlink "debug",
# aunque el build sea correcto. Verificamos el exe en lugar del código de salida.
$configFolder = if ($Configuration -eq 'release') { 'Release' } else { 'Debug' }
$products = Join-Path $Scratch "out\Products\$configFolder-windows-x86_64"
# Con 'Stop', la primera línea de stderr (con la salida redirigida) cortaba swift con -1 y se seguía con el exe viejo.
$ErrorActionPreference = 'Continue'
$completo = $false
& $swift build @build 2>&1 | ForEach-Object { $linea = "$_"; if ($linea -match '^Build complete!') { $completo = $true }; $linea }
$codigo = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($codigo -ne 0) {
    if (!$completo -or !(Test-Path (Join-Path $products 'NetDeckWindows.exe'))) {
        Write-Error "swift build falló (código $codigo)."
        exit 1
    }
    Write-Warning "swift build salió con código $codigo (symlink); el build terminó, continuamos."
}

try { & $swift build @build --show-bin-path | Out-Null } catch {}
# --show-bin-path devuelve la ruta como última línea (puede haber avisos antes)
# La ruta ya está en $products desde arriba; si el output fue un array lo ignoramos.
# SwiftPM crea .bundle, pero WinAppSDK 0.1.2 busca el bootstrapper en .resources.
$bundle = 'swift-windowsappsdk_CWinAppSDK'
$resources = Join-Path $products "$bundle.resources"
New-Item -ItemType Directory -Force $resources | Out-Null
$bootstrap = (Get-ChildItem -LiteralPath (Join-Path $products "$bundle.bundle") -Recurse -Filter 'Microsoft.WindowsAppRuntime.Bootstrap.dll' |
    Select-Object -First 1 -ExpandProperty FullName)
if (!$bootstrap -or !(Test-Path $bootstrap)) { throw 'Falta el bootstrapper de Windows App SDK.' }
Copy-Item -LiteralPath $bootstrap -Destination $resources -Force
foreach ($assets in @('Temas', 'Resaltado', 'windows/Desktop/Fonts', 'windows/Desktop/Assets')) {
    Copy-Item -LiteralPath (Join-Path $repo $assets) -Destination $products -Recurse -Force
}
$app = Join-Path $products 'NetDeckWindows.exe'
Write-Host $app

# NETDECK_BUILD_ONLY=1 compila y prepara la demo sin abrir la ventana.
if ($Demo -and $env:NETDECK_BUILD_ONLY -ne '1') {
    $profile = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("netdeck-desktop-" + [guid]::NewGuid().ToString('N')))
    $env:NETDECK_HOME = $profile.FullName
    $env:NETDECK_DESKTOP_DEMO = '1'
    # Start-Process lanza el exe desligado del script: el PowerShell cierra sin arrastrar la app.
    Start-Process -FilePath $app -WorkingDirectory $products
    exit 0
}
