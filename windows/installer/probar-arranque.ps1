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
$inicio = Get-Date
$salida = Join-Path $env:TEMP ('netdeck-salida-' + [guid]::NewGuid().ToString('N') + '.txt')
$errores = "$salida.err"
# (salida y errores a archivos: si la app se para, Swift escribe ahi el motivo, "Fatal error: ...")
$app = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru -RedirectStandardOutput $salida -RedirectStandardError $errores
Start-Sleep -Seconds $Segundos
if ($app.HasExited) {
    $codigo = $app.ExitCode
    Write-Host ('--- codigo de salida: {0} (0x{1:X8})' -f $codigo, $codigo)
    foreach ($f in $salida, $errores) {
        if ((Test-Path $f) -and (Get-Item $f).Length -gt 0) { Write-Host "--- $(Split-Path $f -Leaf):"; Get-Content $f -Tail 40 | Write-Host }
    }
    # El registro de aplicaciones de Windows: modulo y desplazamiento del fallo (Application Error, 1000) y avisos de .NET/WER
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $inicio } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'NetDeckWindows' } | Select-Object -First 4 |
        ForEach-Object { Write-Host "--- evento $($_.Id) ($($_.ProviderName)):"; Write-Host $_.Message }
    # Lo que la app haya dejado en su registro de errores (portable: datos junto al exe; si no, NETDECK_HOME)
    foreach ($carpeta in (Join-Path (Split-Path $Exe) 'datos'), $env:NETDECK_HOME) {
        if ($carpeta -and (Test-Path $carpeta)) {
            Get-ChildItem $carpeta -Recurse -File -Include '*.log', '*.txt' -ErrorAction SilentlyContinue | Select-Object -First 5 |
                ForEach-Object { Write-Host "--- $($_.FullName):"; Get-Content $_.FullName -Tail 30 | Write-Host }
        }
    }
    throw "NetDeckWindows.exe se ha cerrado a los pocos segundos (codigo $codigo)"
}
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
