# windows\scripts\comun.ps1 - funciones comunes de los scripts de prueba (se cargan con «. $PSScriptRoot\comun.ps1»).

# Salida en UTF-8 aunque la lea otro programa (un agente, una tubería): si no, ✓ ✗ y los acentos salen como «?».
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

# Quita de un texto lo que te identifica: tu carpeta de usuario, tu nombre de usuario y los destinos que se pasen.
function Limpiar([string]$texto, [string[]]$destinos = @()) {
    if (-not $texto) { return '' }
    $t = $texto
    if ($env:USERPROFILE) { $t = $t -replace [regex]::Escape($env:USERPROFILE), 'C:\Users\<usuario>' }
    foreach ($d in $destinos) { if ($d) { $t = $t -replace [regex]::Escape($d), '<destino>' } }
    if ($env:USERNAME -and $env:USERNAME.Length -ge 3) { $t = $t -replace [regex]::Escape($env:USERNAME), '<usuario>' }
    if ($env:COMPUTERNAME) { $t = $t -replace [regex]::Escape($env:COMPUTERNAME), '<equipo>' }
    return $t
}

# Ejecuta un programa y devuelve su salida (stdout y stderr) en una línea. En Windows PowerShell 5.1, «2>&1» convierte
# cada línea de stderr en un registro de error de varias líneas (con la ruta del script); «"$_"» se queda sólo con el texto.
function Salida([string]$exe, [string[]]$argumentos) {
    $lineas = & $exe @argumentos 2>&1 | ForEach-Object { "$_" }
    return (($lineas -join ' ') -replace '\s+', ' ').Trim()
}
