# Abre NetDeckWindows.exe y comprueba que sigue abierto a los -Segundos y que su ventana no es un cuadro de error (clase #32770:
# los avisos de Arranque.swift o del bootstrapper de Microsoft tambien dejan el proceso abierto). Lo usa windows-release.yml en un
# Windows sin Windows App Runtime instalado. Sale con error si la app se cierra o si lo que abre es un aviso.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/probar-arranque.ps1 -Exe <ruta de NetDeckWindows.exe>
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [int]$Segundos = 20
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Exe)) { throw "No esta $Exe" }
Add-Type -Namespace NetDeck -Name Ventanas -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetClassName(System.IntPtr ventana, System.Text.StringBuilder clase, int maximo);
'@
$app = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru
Start-Sleep -Seconds $Segundos
if ($app.HasExited) { throw "NetDeckWindows.exe se ha cerrado a los pocos segundos (codigo $($app.ExitCode))" }
$app.Refresh()
$clase = ''
if ($app.MainWindowHandle -ne [IntPtr]::Zero) {
    $texto = New-Object System.Text.StringBuilder 256
    [void][NetDeck.Ventanas]::GetClassName($app.MainWindowHandle, $texto, 256)
    $clase = $texto.ToString()
}
Write-Host "NetDeckWindows.exe sigue abierto a los $Segundos s (PID $($app.Id)); ventana '$($app.MainWindowTitle)', clase '$clase'"
Stop-Process -Id $app.Id -Force
if ($clase -eq '#32770') { throw 'En lugar de su ventana, la app ha abierto un cuadro de aviso (error al arrancar)' }
if (!$clase) { Write-Warning 'No se ve la ventana principal (el runner puede no tener escritorio): solo se ha comprobado que sigue abierto' }
