# windows\scripts\prueba-askpass.ps1 - paso P1: ¿el ssh de Windows llama al askpass como hace el de macOS?
# NetDeck pasa la contraseña de las sesiones con SSH_ASKPASS = su propio ejecutable y SSH_ASKPASS_REQUIRE=force.
# Este script compila un askpass de prueba (askpass-registro.swift), lanza ssh contra -Destino con la autenticación por
# contraseña y mira si el askpass ha sido llamado. Contesta una contraseña FALSA: el acceso tiene que fallar.
# Usa un equipo de laboratorio: un intento fallido puede contar para el bloqueo de la cuenta.
#   powershell -ExecutionPolicy Bypass -File windows\scripts\prueba-askpass.ps1 -Destino tu.usuario@192.0.2.10
# No toca tu ~/.ssh (known_hosts y config van a una carpeta temporal).

param([Parameter(Mandatory = $true)][string]$Destino)

$ErrorActionPreference = 'Continue'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) { Write-Host "✗ No está $ssh" -ForegroundColor Red; exit 1 }
if (-not (Get-Command swiftc -ErrorAction SilentlyContinue)) { Write-Host "✗ Hace falta swiftc (paso P0)" -ForegroundColor Red; exit 1 }

$tmp = Join-Path $env:TEMP ("netdeck-askpass-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$exe = Join-Path $tmp 'askpass-registro.exe'
& swiftc -O -o $exe (Join-Path $PSScriptRoot 'askpass-registro.swift')
if (-not (Test-Path $exe)) { Write-Host "✗ No compila el askpass de prueba" -ForegroundColor Red; exit 1 }

$log = Join-Path $tmp 'askpass.log'
$vacio = Join-Path $tmp 'config'
Set-Content -Path $vacio -Encoding ascii -Value ''
$base = @('-F', $vacio, '-o', "UserKnownHostsFile=$(Join-Path $tmp 'known_hosts')", '-o', 'StrictHostKeyChecking=accept-new',
          '-o', 'BatchMode=no', '-o', 'ConnectTimeout=8', '-o', 'NumberOfPasswordPrompts=1',
          '-o', 'PreferredAuthentications=keyboard-interactive,password', '-o', 'PubkeyAuthentication=no')

function Prueba($nombre, [scriptblock]$lanzar) {
    Remove-Item $log -ErrorAction SilentlyContinue
    $env:SSH_ASKPASS = $exe
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:NETDECK_PRUEBA_LOG = $log
    $env:DISPLAY = 'netdeck:0'      # (algunas versiones antiguas sólo usan el askpass si hay DISPLAY)
    & $lanzar
    Remove-Item Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:NETDECK_PRUEBA_LOG, Env:DISPLAY -ErrorAction SilentlyContinue
    if (Test-Path $log) {
        Write-Host "  ✓ $nombre`: ssh ha llamado al askpass" -ForegroundColor Green
        Get-Content $log | ForEach-Object { Write-Host "      $_" }
    } else {
        Write-Host "  ✗ $nombre`: ssh NO ha llamado al askpass" -ForegroundColor Red
    }
}

Write-Host "Askpass con la consola de PowerShell (como una pestaña con terminal):" -ForegroundColor Cyan
Prueba 'con consola' { & $ssh @base -- $Destino exit 2>&1 | ForEach-Object { Write-Host "      ssh: $_" } }

Write-Host "Askpass sin consola, con la entrada y la salida redirigidas (como el explorador SFTP y los túneles):" -ForegroundColor Cyan
Prueba 'sin consola' {
    $entrada = Join-Path $tmp 'entrada'; Set-Content -Path $entrada -Value ''
    # (Start-Process junta los argumentos sin comillas: las rutas con espacios van entre comillas a mano)
    $argumentos = (($base + @('--', $Destino, 'exit')) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath $ssh -ArgumentList $argumentos -NoNewWindow -Wait -PassThru `
        -RedirectStandardInput $entrada -RedirectStandardOutput (Join-Path $tmp 'out') -RedirectStandardError (Join-Path $tmp 'err')
    Get-Content (Join-Path $tmp 'err') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      ssh: $_" }
}

Remove-Item -Recurse -Force $tmp
Write-Host ""
Write-Host "Apunta el resultado (sin el destino) en windows\resultados\ssh-windows.md." -ForegroundColor Cyan
Write-Host "Falta la prueba dentro de Windows Terminal (ConPTY): ver el paso P1 de windows\PLAN.md." -ForegroundColor Cyan
