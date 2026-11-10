# windows\scripts\prueba-askpass.ps1 - paso P1: ¿el ssh de Windows llama al askpass como hace el de macOS?
# NetDeck pasa la contraseña de las sesiones con SSH_ASKPASS = un ejecutable suyo y SSH_ASKPASS_REQUIRE=force.
# Este script compila un askpass de prueba (askpass-registro.swift), lanza ssh contra -Destino pidiendo contraseña y mira
# si el askpass ha sido llamado. Contesta una contraseña FALSA: el acceso tiene que fallar. Usa una cuenta de
# laboratorio: un intento fallido puede contar para el bloqueo de la cuenta.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/prueba-askpass.ps1 -Destino tu.usuario@192.0.2.10 [-Conservar]
# -Conservar deja el askpass compilado e imprime las órdenes para repetir la prueba en Windows Terminal (ConPTY) y por -J.
# No toca tu ~/.ssh (known_hosts y config van a una carpeta temporal). La salida no lleva tu usuario ni el destino.

param([Parameter(Mandatory = $true)][string]$Destino, [switch]$Conservar)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'comun.ps1')
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) { Write-Host "✗ No está el ssh de Windows en System32\OpenSSH" -ForegroundColor Red; exit 1 }
if (-not (Get-Command swiftc -ErrorAction SilentlyContinue)) { Write-Host "✗ Hace falta swiftc (paso P0)" -ForegroundColor Red; exit 1 }

$tmp = Join-Path $env:TEMP ("netdeck-askpass-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$llamados = 0
try {
    $exe = Join-Path $tmp 'askpass-registro.exe'
    & swiftc -O -o $exe (Join-Path $PSScriptRoot 'askpass-registro.swift') 2>&1 | ForEach-Object { Write-Host ("  swiftc: " + (Limpiar "$_")) }
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
        try { $codigo = & $lanzar }
        finally { Remove-Item Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:NETDECK_PRUEBA_LOG, Env:DISPLAY -ErrorAction SilentlyContinue }
        if (Test-Path $log) {
            $script:llamados++
            Write-Host "  ✓ $nombre`: ssh ha llamado al askpass (ssh salió con $codigo)" -ForegroundColor Green
            Get-Content $log | ForEach-Object { Write-Host ("      " + (Limpiar $_ @($Destino))) }
        } else {
            Write-Host "  ✗ $nombre`: ssh NO ha llamado al askpass (ssh salió con $codigo)" -ForegroundColor Red
        }
    }

    Write-Host "Con la consola de PowerShell:" -ForegroundColor Cyan
    Prueba 'con consola' {
        & $ssh @base -- $Destino exit 2>&1 | ForEach-Object { Write-Host ("      ssh: " + (Limpiar "$_" @($Destino))) }
        $LASTEXITCODE
    }

    Write-Host "Sin consola (proceso sin ventana y con la entrada y la salida redirigidas, como lo lanzaría una app):" -ForegroundColor Cyan
    Prueba 'sin consola' {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ssh
        $psi.Arguments = ((($base + @('--', $Destino, 'exit')) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        foreach ($k in 'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE', 'NETDECK_PRUEBA_LOG', 'DISPLAY') { $psi.EnvironmentVariables[$k] = [Environment]::GetEnvironmentVariable($k) }
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch {} ; $null = $p.WaitForExit(3000) }
        if ($err.Wait(2000)) { ($err.Result -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { Write-Host ("      ssh: " + (Limpiar $_.Trim() @($Destino))) } }
        if ($p.HasExited) { $p.ExitCode } else { 'sin acabar' }
    }

    Write-Host ""
    Write-Host "Apunta el resultado en windows/resultados/ssh-windows.md (la salida ya va sin tu usuario ni el destino)." -ForegroundColor Cyan
    if ($Conservar) {
        Write-Host ""
        Write-Host "Askpass conservado. Para la prueba en Windows Terminal (ConPTY), abre una pestaña de PowerShell y pega" -ForegroundColor Cyan
        Write-Host "(estas órdenes llevan rutas tuyas: no las copies a resultados):" -ForegroundColor Cyan
        Write-Host "  `$env:SSH_ASKPASS = '$exe'; `$env:SSH_ASKPASS_REQUIRE = 'force'; `$env:NETDECK_PRUEBA_LOG = '$log'"
        Write-Host "  & '$ssh' -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no <destino> exit"
        Write-Host "  Get-Content '$log'"
        Write-Host "Y por un salto: añade «-J <bastion>» a la orden de ssh. Al acabar, borra la carpeta:" -ForegroundColor Cyan
        Write-Host "  Remove-Item -Recurse -Force '$tmp'"
    }
} finally {
    if (-not $Conservar) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}
if ($llamados -eq 2) { exit 0 } else { exit 1 }
