# Pone el idioma neutro (0) en la columna Language de la tabla File del .msi recien compilado, en los archivos que la llevan.
#
# Por que: WiX copia ahi el idioma del recurso de version de cada archivo, y algunos .mui de Windows App Runtime (que va dentro
# de la app, incluir-dependencias.ps1) traen identificadores de idioma que la validacion de MSI rechaza (ICE03: "Invalid
# Language Id") o listas mas largas que la columna. Esa columna solo sirve para desempatar dos archivos con la misma version
# al actualizar, y el .msi hace MajorUpgrade (quita la version anterior entera antes de instalar): no cambia que se instala.
# (CompanionFile no vale: un archivo companero no puede ser la clave de su componente, y aqui hay uno por archivo.)
#
# Uso, entre "wix build" y "wix msi validate":
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/idioma-neutro-msi.ps1 -Msi <ruta del .msi>
param([Parameter(Mandatory = $true)][string]$Msi)
$ErrorActionPreference = 'Stop'
$Msi = (Resolve-Path -LiteralPath $Msi).Path

function Llamar($objeto, [string]$metodo, [object[]]$argumentos) {
    $objeto.GetType().InvokeMember($metodo, [Reflection.BindingFlags]::InvokeMethod, $null, $objeto, $argumentos)
}

$installer = New-Object -ComObject WindowsInstaller.Installer
$db = Llamar $installer 'OpenDatabase' @($Msi, 1)                      # 1 = msiOpenDatabaseModeTransact
try {
    $cuenta = Llamar $db 'OpenView' @('SELECT `File` FROM `File` WHERE `Language` IS NOT NULL')
    Llamar $cuenta 'Execute' @() | Out-Null
    $n = 0
    while (Llamar $cuenta 'Fetch' @()) { $n++ }
    Llamar $cuenta 'Close' @() | Out-Null
    $cambio = Llamar $db 'OpenView' @("UPDATE ``File`` SET ``Language`` = '0' WHERE ``Language`` IS NOT NULL")
    Llamar $cambio 'Execute' @() | Out-Null
    Llamar $cambio 'Close' @() | Out-Null
    Llamar $db 'Commit' @() | Out-Null
    Write-Host "Idioma neutro (0) en $n archivos de $(Split-Path $Msi -Leaf)"
} finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
