# windows\scripts\prueba-ssh.ps1 - paso P1: qué hace el OpenSSH de Windows de lo que NetDeck necesita.
# No toca tu ~/.ssh: todo va en una carpeta temporal que se borra al final.
#   powershell -ExecutionPolicy Bypass -File windows\scripts\prueba-ssh.ps1
#   powershell -ExecutionPolicy Bypass -File windows\scripts\prueba-ssh.ps1 -Destino tu.usuario@192.0.2.10
# Con -Destino (un equipo de laboratorio al que entres con clave o agente, sin contraseña) prueba también
# ControlMaster y el subsistema sftp. La salida no lleva tus datos salvo el destino que pases: no lo copies a resultados.

param([string]$Destino = '')

$ErrorActionPreference = 'Continue'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path $ssh)) { Write-Host "✗ No está $ssh" -ForegroundColor Red; exit 1 }
$tmp = Join-Path $env:TEMP ("netdeck-prueba-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fila($funcion, $ok, $nota) {
    $c = if ($ok -eq 'sí') { 'Green' } elseif ($ok -eq 'no') { 'Red' } else { 'Yellow' }
    Write-Host ("| {0} | {1} | {2} |" -f $funcion, $ok, $nota) -ForegroundColor $c
}

Write-Host "| Función | Funciona | Notas |"
Write-Host "|---|---|---|"
Fila 'Versión' '·' ((& $ssh -V 2>&1) | Out-String).Trim()

# 1. ssh -G con Include (lo que hace SessionFile para validar el archivo de sesiones)
$incluido = Join-Path $tmp 'sesiones'
$config = Join-Path $tmp 'config'
Set-Content -Path $incluido -Encoding ascii -Value @("Host core-01", "    HostName 192.0.2.10", "    User tu.usuario", "    Port 2222")
Set-Content -Path $config -Encoding ascii -Value @("Include `"$incluido`"")
$g = (& $ssh -G -F $config core-01 2>&1) | Out-String
$ok = ($g -match '(?m)^hostname 192\.0\.2\.10') -and ($g -match '(?m)^user tu\.usuario') -and ($g -match '(?m)^port 2222')
if ($ok) { Fila 'ssh -G con Include' 'sí' 'lee HostName, User y Port del archivo incluido' }
else { Fila 'ssh -G con Include' 'no' (($g -split "`n" | Select-Object -First 2) -join ' ') }

# 2. ¿Rechaza un Include con la ruta entre comillas y espacios? (la carpeta de la app puede tener espacios)
$conEspacio = Join-Path $tmp 'con espacio'
New-Item -ItemType Directory -Path $conEspacio | Out-Null
Copy-Item $incluido (Join-Path $conEspacio 'sesiones')
Set-Content -Path $config -Encoding ascii -Value @("Include `"$(Join-Path $conEspacio 'sesiones')`"")
$g2 = (& $ssh -G -F $config core-01 2>&1) | Out-String
if ($g2 -match '(?m)^hostname 192\.0\.2\.10') { Fila 'Include con espacios' 'sí' '' } else { Fila 'Include con espacios' 'no' 'hay que evitar espacios en la ruta de la app' }

# 3. Opciones que NetDeck pone siempre: ¿las acepta?
$opts = @('-T', '-x', '-a', '-o', 'ClearAllForwardings=yes', '-o', 'PermitLocalCommand=no', '-o', 'RequestTTY=no', '-o', 'BatchMode=no', '-o', 'RemoteCommand=none')
$g3 = (& $ssh -G -F $config @opts core-01 2>&1) | Out-String
if ($g3 -match '(?m)^hostname ') { Fila 'Opciones fijas de NetDeck' 'sí' '' } else { Fila 'Opciones fijas de NetDeck' 'no' (($g3 -split "`n" | Select-Object -First 2) -join ' ') }

# 4. Programas
$sftp = Join-Path $env:SystemRoot 'System32\OpenSSH\sftp.exe'
if (Test-Path $sftp) { Fila 'sftp.exe' 'sí' '' } else { Fila 'sftp.exe' 'no' '' }
if (Get-Command telnet -ErrorAction SilentlyContinue) { Fila 'telnet' 'sí' '' } else { Fila 'telnet' 'no' 'característica opcional' }

# 5. Permisos de ~/.ssh: ¿alguien más que tú, SYSTEM y Administradores? (sólo se cuentan, no se enseñan nombres)
$dirSsh = Join-Path $env:USERPROFILE '.ssh'
if (Test-Path $dirSsh) {
    $yo = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $permitidos = @($yo, 'S-1-5-18', 'S-1-5-32-544')
    $extra = 0
    foreach ($a in (Get-Acl $dirSsh).Access) {
        try { $sid = $a.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $sid = '?' }
        if ($permitidos -notcontains $sid) { $extra++ }
    }
    if ($extra -eq 0) { Fila 'ACL de ~/.ssh' 'sí' 'sólo tú, SYSTEM y Administradores' } else { Fila 'ACL de ~/.ssh' '·' "$extra entrada(s) de otros: ssh puede quejarse de los permisos" }
} else { Fila 'ACL de ~/.ssh' '·' 'no hay ~/.ssh' }

# 6. Con destino: ControlMaster y subsistema sftp
if ($Destino) {
    $cp = Join-Path $tmp 'cm-%C'
    $cm = (& $ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=yes -o "ControlPath=$cp" -o ControlPersist=10 -- $Destino exit 2>&1) | Out-String
    $chk = (& $ssh -o "ControlPath=$cp" -O check -- $Destino 2>&1) | Out-String
    if ($chk -match 'Master running') { Fila 'ControlMaster' 'sí' '' } else { Fila 'ControlMaster' 'no' ((($cm + ' ' + $chk) -replace "\s+", ' ').Trim()) }
    & $ssh -o "ControlPath=$cp" -O exit -- $Destino 2>$null | Out-Null

    # Subsistema sftp: un paquete SSH_FXP_INIT (versión 3) y se espera SSH_FXP_VERSION (tipo 2)
    $init = [byte[]](0, 0, 0, 5, 1, 0, 0, 0, 3)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ssh
    $psi.Arguments = "-T -x -a -o BatchMode=yes -o ConnectTimeout=8 -s -- $Destino sftp"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.BaseStream.Write($init, 0, $init.Length); $p.StandardInput.BaseStream.Flush()
    $buf = New-Object byte[] 5
    $t = $p.StandardOutput.BaseStream.ReadAsync($buf, 0, 5)
    if ($t.Wait(10000) -and $t.Result -eq 5 -and $buf[4] -eq 2) { Fila 'ssh -s sftp' 'sí' 'responde SSH_FXP_VERSION' }
    else { Fila 'ssh -s sftp' 'no' (($p.StandardError.ReadToEnd() -replace "\s+", ' ').Trim()) }
    try { $p.Kill() } catch {}
} else {
    Fila 'ControlMaster' '·' 'sin -Destino no se prueba'
    Fila 'ssh -s sftp' '·' 'sin -Destino no se prueba'
}

Remove-Item -Recurse -Force $tmp
Write-Host ""
Write-Host "Para el askpass: windows\scripts\prueba-askpass.ps1 -Destino ..." -ForegroundColor Cyan
