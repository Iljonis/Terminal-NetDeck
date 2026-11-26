# windows\scripts\comprobar-entorno.ps1 - comprueba que el PC con Windows tiene lo que pide el paso P0 del plan.
# Sólo lee: no instala ni cambia nada. Uso, desde la raíz del repositorio (PowerShell o Git Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/comprobar-entorno.ps1
# Sale con el número de fallos (0 = todo bien). La salida no lleva tu usuario ni tus rutas: se puede copiar a
# windows/resultados/entorno.md.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'comun.ps1')
$fallos = 0
function Bien($t)  { Write-Host ("  ✓ " + (Limpiar $t)) -ForegroundColor Green }
function Mal($t)   { Write-Host ("  ✗ " + (Limpiar $t)) -ForegroundColor Red; $script:fallos++ }
function Nota($t)  { Write-Host ("  · " + (Limpiar $t)) -ForegroundColor Yellow }
function Titulo($t){ Write-Host ""; Write-Host $t -ForegroundColor Cyan }

Titulo "Sistema"
$so = Get-CimInstance Win32_OperatingSystem
$build = [int]$so.BuildNumber
if ($build -ge 22000) { Bien "Windows 11 (compilación $build)" } else { Mal "Hace falta Windows 11 (esta es la compilación $build)" }
Bien "Arquitectura: $env:PROCESSOR_ARCHITECTURE"
$dev = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
if ($dev -and $dev.AllowDevelopmentWithoutDevLicense -eq 1) { Bien "Modo de desarrollador activado" }
else { Nota "Modo de desarrollador apagado (no es obligatorio; ayuda con los enlaces simbólicos de algunos paquetes)" }

Titulo "Herramientas"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Bien (Salida 'git' @('--version')) } else { Mal "No está Git (winget install --id Git.Git -e)" }
$bashes = @((Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
if ($bashes | Where-Object { Test-Path $_ }) { Bien "Git Bash (para bash tools/privacidad.sh)" } else { Mal "No está Git Bash: hace falta para bash tools/privacidad.sh" }

$swift = Get-Command swift -ErrorAction SilentlyContinue
if ($swift) {
    $v = Salida 'swift' @('--version')
    if ($v -match 'version (\d+)\.(\d+)') {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -gt 6 -or ($maj -eq 6 -and $min -ge 2)) { Bien "Swift $maj.$min" } else { Mal "Swift $maj.$min: el Package.swift pide 6.2 o posterior" }
    } else { Nota "Swift instalado, versión sin reconocer: $v" }
} else { Mal "No está Swift (guía: https://www.swift.org/install/windows/)" }

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vc = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property displayName 2>$null
    if (-not $vc) { $vc = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property displayName 2>$null }
    if ($vc) { Bien "Visual Studio con herramientas de C++: $vc" } else { Mal "Visual Studio sin «Desarrollo para el escritorio con C++»" }
} else { Mal "No está Visual Studio / Build Tools (lo pide el toolchain de Swift)" }
$kits = @('HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots') |
    ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Where-Object { $_.KitsRoot10 }
if ($kits) { Bien "SDK de Windows 10/11" } else { Mal "No está el SDK de Windows" }

if (Get-Command claude -ErrorAction SilentlyContinue) { Bien "Claude Code" } else { Nota "No se encuentra «claude» en el PATH" }

Titulo "OpenSSH de Windows (el que usaría NetDeck)"
$dir = Join-Path $env:SystemRoot 'System32\OpenSSH'
foreach ($p in 'ssh.exe', 'sftp.exe', 'ssh-keygen.exe') {
    if (Test-Path (Join-Path $dir $p)) { Bien "$p" } else { Mal "No está $p en System32\OpenSSH (Configuración → Sistema → Características opcionales → Cliente OpenSSH)" }
}
$ssh = Join-Path $dir 'ssh.exe'
if (Test-Path $ssh) { Bien ("Versión: " + (Salida $ssh @('-V'))) }
$enPath = Get-Command ssh -ErrorAction SilentlyContinue
if ($enPath -and $enPath.Source -ne $ssh) { Nota "El «ssh» del PATH no es el de Windows (es otro: Git, MSYS…). NetDeck usaría el de System32." }
if (Test-Path (Join-Path $env:SystemRoot 'System32\telnet.exe')) { Bien "Cliente Telnet" } else { Nota "Sin cliente Telnet (característica opcional de Windows; sólo para las pestañas telnet)" }

Titulo "Repositorio"
if ($git) {
    $raiz = (& git rev-parse --show-toplevel 2>$null)
    if ($raiz) {
        $rama = (& git branch --show-current 2>$null)
        if ($rama -like 'propuesta/windows*' -or $rama -like 'windows/*') { Bien "Rama: $rama" } else { Nota "Rama: $rama (el trabajo de Windows va en propuesta/windows o windows/…)" }
        $crlf = (& git config core.autocrlf 2>$null)
        if ($crlf -eq 'false') { Bien "core.autocrlf = false" } else { Mal "core.autocrlf no es false: git config core.autocrlf false" }
        $cambiados = @(& git status --porcelain 2>$null).Count
        if ($cambiados -gt 50) { Nota "git status enseña $cambiados archivos cambiados: ¿fin de línea CRLF? (ver windows/CLAUDE.md)" }
        if (Test-Path (Join-Path $raiz '.claude\skills\terminal-netdeck-patterns')) { Bien "Skills del proyecto copiadas a .claude\skills" }
        else { Nota "Skills sin copiar (paso P0 de windows/PLAN.md)" }
    } else { Nota "No estás dentro del repositorio" }
}

Write-Host ""
if ($fallos -eq 0) { Write-Host "Todo listo." -ForegroundColor Green } else { Write-Host "$fallos cosa(s) por arreglar." -ForegroundColor Red }
exit $fallos
