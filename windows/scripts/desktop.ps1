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

$build = @('--package-path', $package, '--scratch-path', $scratch, '--force-resolved-versions', '-c', $Configuration, '-Xcc', '-DOPENSSL_NO_ASM')
& $swift build @build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$products = & $swift build @build --show-bin-path
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# SwiftPM crea .bundle, pero WinAppSDK 0.1.2 busca el bootstrapper en .resources.
$bundle = 'swift-windowsappsdk_CWinAppSDK'
$resources = Join-Path $products "$bundle.resources"
New-Item -ItemType Directory -Force $resources | Out-Null
$bootstrap = (Get-ChildItem -LiteralPath (Join-Path $products "$bundle.bundle") -Recurse -Filter 'Microsoft.WindowsAppRuntime.Bootstrap.dll' |
    Select-Object -First 1 -ExpandProperty FullName)
if (!$bootstrap -or !(Test-Path $bootstrap)) { throw 'Falta el bootstrapper de Windows App SDK.' }
Copy-Item -LiteralPath $bootstrap -Destination $resources -Force
foreach ($assets in @('Temas', 'Resaltado')) {
    Copy-Item -LiteralPath (Join-Path $repo $assets) -Destination $products -Recurse -Force
}
$app = Join-Path $products 'NetDeckWindows.exe'
Write-Host $app

if ($Demo) {
    $profile = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("netdeck-desktop-" + [guid]::NewGuid().ToString('N')))
    $env:NETDECK_HOME = $profile.FullName
    $env:NETDECK_DESKTOP_DEMO = '1'
    Push-Location $products
    try { & $app } finally { Pop-Location }
    exit $LASTEXITCODE
}
