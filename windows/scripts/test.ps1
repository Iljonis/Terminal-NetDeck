# windows\scripts\test.ps1 - los tests del núcleo en Windows, como ./test.sh en macOS: con un NETDECK_HOME temporal
# para que nada escriba en tu carpeta de usuario. Los argumentos van a swift test (por ejemplo --filter SessionTests).
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test.ps1 [--filter …]
# Sale con el código de swift test.

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$casa = Join-Path $env:TEMP ("netdeck-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $casa | Out-Null
$anterior = $env:NETDECK_HOME
$codigo = 1
try {
    $env:NETDECK_HOME = $casa
    Push-Location $raiz
    & swift test @args
    $codigo = $LASTEXITCODE
} finally {
    Pop-Location
    $env:NETDECK_HOME = $anterior
    Remove-Item -Recurse -Force $casa -ErrorAction SilentlyContinue
}
exit $codigo
