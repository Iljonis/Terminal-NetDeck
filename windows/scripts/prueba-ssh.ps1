# windows\scripts\prueba-ssh.ps1 - paso P1: qué hace el OpenSSH de Windows de lo que NetDeck necesita.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/prueba-ssh.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/prueba-ssh.ps1 -Destino tu.usuario@192.0.2.10 [-Salto tu.usuario@192.0.2.1]
# Sin -Destino sólo usa archivos temporales. Con -Destino (una cuenta de laboratorio que entre por clave o agente, sin
# contraseña) prueba también ControlMaster, -J y el subsistema sftp.
# No toca tu ~/.ssh. Para probar «Include ~/…» crea un archivo temporal en tu carpeta de usuario y lo borra al acabar.
# La salida es una tabla en Markdown sin tu usuario, tus rutas ni el destino: se puede copiar a
# windows/resultados/ssh-windows.md.

param([string]$Destino = '', [string]$Salto = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'comun.ps1')
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) { Write-Host "✗ No está el ssh de Windows en System32\OpenSSH" -ForegroundColor Red; exit 1 }
$id = [guid]::NewGuid().ToString('N').Substring(0, 8)
$tmp = Join-Path $env:TEMP "netdeck-prueba-$id"
$enCasa = Join-Path $env:USERPROFILE "netdeck-prueba-$id.conf"
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fila($funcion, $ok, $nota) {
    $c = if ($ok -eq 'sí') { 'Green' } elseif ($ok -eq 'no') { 'Red' } else { 'Yellow' }
    $n = (Limpiar ([string]$nota) @($Destino, $Salto)) -replace '\|', '/'
    Write-Host ("| {0} | {1} | {2} |" -f $funcion, $ok, $n) -ForegroundColor $c
}
# ¿ssh -G lee core-01 del archivo incluido? (lo que hace SessionFile para validar el archivo de sesiones)
function LeeCore01([string]$config) {
    $g = Salida $ssh @('-G', '-F', $config, 'core-01')
    $ok = ($g -match 'hostname 192\.0\.2\.10') -and ($g -match 'user tu\.usuario') -and ($g -match 'port 2222')
    return @{ ok = $ok; texto = $g }
}
function PrimerasPalabras([string]$t) { if ($t.Length -gt 160) { return $t.Substring(0, 160) + '…' } else { return $t } }

try {
    Write-Host "| Función | Funciona | Notas |"
    Write-Host "|---|---|---|"
    Fila 'Versión' '·' (Salida $ssh @('-V'))

    $sesiones = @("Host core-01", "    HostName 192.0.2.10", "    User tu.usuario", "    Port 2222")
    $incluido = Join-Path $tmp 'sesiones'
    $config = Join-Path $tmp 'config'
    Set-Content -Path $incluido -Encoding ascii -Value $sesiones

    # 1. Include con ruta absoluta
    Set-Content -Path $config -Encoding ascii -Value @("Include `"$incluido`"")
    $r = LeeCore01 $config
    if ($r.ok) { Fila 'Include absoluto (C:\…)' 'sí' '' } else { Fila 'Include absoluto (C:\…)' 'no' (PrimerasPalabras $r.texto) }

    # 2. Include con ~/ (la forma que escribe NetDeck: «Include ~/.config/netdeck/ssh_config»)
    Set-Content -Path $enCasa -Encoding ascii -Value $sesiones
    Set-Content -Path $config -Encoding ascii -Value @("Include ~/netdeck-prueba-$id.conf")
    $r = LeeCore01 $config
    if ($r.ok) { Fila 'Include con ~/' 'sí' '' } else { Fila 'Include con ~/' 'no' (PrimerasPalabras $r.texto) }

    # 3. Include relativo (OpenSSH los toma relativos a ~/.ssh): «../archivo» apunta a la carpeta de usuario
    Set-Content -Path $config -Encoding ascii -Value @("Include ../netdeck-prueba-$id.conf")
    $r = LeeCore01 $config
    if ($r.ok) { Fila 'Include relativo (a ~/.ssh)' 'sí' '' } else { Fila 'Include relativo (a ~/.ssh)' 'no' (PrimerasPalabras $r.texto) }

    # 4. Include con espacios en la ruta (la carpeta de la app podría tenerlos)
    $conEspacio = Join-Path $tmp 'con espacio'
    New-Item -ItemType Directory -Path $conEspacio | Out-Null
    Copy-Item $incluido (Join-Path $conEspacio 'sesiones')
    Set-Content -Path $config -Encoding ascii -Value @("Include `"$(Join-Path $conEspacio 'sesiones')`"")
    $r = LeeCore01 $config
    if ($r.ok) { Fila 'Include con espacios' 'sí' '' } else { Fila 'Include con espacios' 'no' (PrimerasPalabras $r.texto) }

    # 5. Opciones que NetDeck pone siempre al explorador SFTP
    Set-Content -Path $config -Encoding ascii -Value @("Include `"$incluido`"")
    $g = Salida $ssh @('-G', '-F', $config, '-T', '-x', '-a', '-o', 'ClearAllForwardings=yes', '-o', 'PermitLocalCommand=no',
                       '-o', 'RequestTTY=no', '-o', 'BatchMode=no', '-o', 'RemoteCommand=none', 'core-01')
    if ($g -match 'hostname 192\.0\.2\.10') { Fila 'Opciones fijas de NetDeck' 'sí' '' } else { Fila 'Opciones fijas de NetDeck' 'no' (PrimerasPalabras $g) }

    # 6. Permisos: con la ACL abierta a «Usuarios» (S-1-5-32-545), ¿ssh se niega a leer el config o el incluido?
    $abiertoConfig = Join-Path $tmp 'config-abierto'
    Copy-Item $config $abiertoConfig
    & icacls $abiertoConfig /grant '*S-1-5-32-545:(R)' | Out-Null
    $r = LeeCore01 $abiertoConfig
    if ($r.ok) { Fila 'Config con ACL abierta' '·' 'ssh lo lee igual (no comprueba permisos del config)' }
    else { Fila 'Config con ACL abierta' 'no' ('ssh lo rechaza: ' + (PrimerasPalabras $r.texto)) }
    & icacls $incluido /grant '*S-1-5-32-545:(R)' | Out-Null
    $r = LeeCore01 $config
    if ($r.ok) { Fila 'Incluido con ACL abierta' '·' 'ssh lo lee igual' }
    else { Fila 'Incluido con ACL abierta' 'no' ('ssh lo rechaza: ' + (PrimerasPalabras $r.texto)) }

    # 7. Programas
    if (Test-Path (Join-Path $env:SystemRoot 'System32\OpenSSH\sftp.exe')) { Fila 'sftp.exe' 'sí' '' } else { Fila 'sftp.exe' 'no' '' }
    if (Test-Path (Join-Path $env:SystemRoot 'System32\telnet.exe')) { Fila 'telnet.exe' 'sí' 'probarlo a mano en Windows Terminal (P1)' } else { Fila 'telnet.exe' 'no' 'característica opcional' }

    # 8. Con destino: ControlMaster, -J y subsistema sftp
    if ($Destino) {
        $cp = Join-Path $tmp 'cm-%C'
        $cm = Salida $ssh @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'ControlMaster=yes', '-o', "ControlPath=$cp",
                            '-o', 'ControlPersist=10', '--', $Destino, 'exit')
        $chk = Salida $ssh @('-o', "ControlPath=$cp", '-O', 'check', '--', $Destino)
        if ($chk -match 'Master running') { Fila 'ControlMaster' 'sí' '' } else { Fila 'ControlMaster' 'no' (PrimerasPalabras "$cm $chk") }
        Salida $ssh @('-o', "ControlPath=$cp", '-O', 'exit', '--', $Destino) | Out-Null

        if ($Salto) {
            & $ssh -o BatchMode=yes -o ConnectTimeout=8 -J $Salto -- $Destino exit 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Fila 'Salto con -J' 'sí' '' } else { Fila 'Salto con -J' 'no' "código $LASTEXITCODE" }
        } else { Fila 'Salto con -J' '·' 'sin -Salto no se prueba' }

        # Subsistema sftp: un SSH_FXP_INIT (versión 3) y se espera SSH_FXP_VERSION (tipo 2) en el quinto byte
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ssh
        $psi.Arguments = "-T -x -a -o BatchMode=yes -o ConnectTimeout=8 -s -- $Destino sftp"
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $errTarea = $p.StandardError.ReadToEndAsync()
        $init = [byte[]](0, 0, 0, 5, 1, 0, 0, 0, 3)
        $p.StandardInput.BaseStream.Write($init, 0, $init.Length); $p.StandardInput.BaseStream.Flush()
        $buf = New-Object byte[] 5
        $leidos = 0
        $limite = (Get-Date).AddSeconds(12)
        while ($leidos -lt 5 -and (Get-Date) -lt $limite) {
            $t = $p.StandardOutput.BaseStream.ReadAsync($buf, $leidos, 5 - $leidos)
            if (-not $t.Wait(([int]($limite - (Get-Date)).TotalMilliseconds) + 1)) { break }
            if ($t.Result -le 0) { break }
            $leidos += $t.Result
        }
        if (-not $p.HasExited) { try { $p.Kill() } catch {} }
        $null = $p.WaitForExit(3000)
        if ($leidos -eq 5 -and $buf[4] -eq 2) { Fila 'ssh -s sftp' 'sí' 'responde SSH_FXP_VERSION' }
        else {
            $err = if ($errTarea.Wait(2000)) { $errTarea.Result } else { '' }
            Fila 'ssh -s sftp' 'no' (PrimerasPalabras ((($err -replace '\s+', ' ').Trim()) + " (leídos $leidos bytes)"))
        }
    } else {
        Fila 'ControlMaster' '·' 'sin -Destino no se prueba'
        Fila 'Salto con -J' '·' 'sin -Destino no se prueba'
        Fila 'ssh -s sftp' '·' 'sin -Destino no se prueba'
    }
} finally {
    Remove-Item -Force $enCasa -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "Para el askpass: windows/scripts/prueba-askpass.ps1 -Destino … -Conservar" -ForegroundColor Cyan
