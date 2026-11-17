# Comprueba si esta instalado el Windows App Runtime que necesita Terminal NetDeck (el Framework x64 y su DDLM, que el
# bootstrapper de la app exige). Escribe WAR-OK y sale con 0 si esta; si falta, no escribe nada y sale con 1.
#
# El instalador (NetDeckWindows.wxs -> detectar-runtime.js, CustomAction DetectarWindowsAppRuntime) lleva ESTE script codificado en
# base64 (-EncodedCommand) para no pelear con las comillas ni con el formato de propiedades de MSI; preparar-instalador.ps1
# comprueba que el .js y este archivo dicen lo mismo. Para regenerarlo:
#   [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-Content -Raw detectar-runtime.ps1 -Encoding UTF8)))
#
# Se mira con -AllUsers (el instalador va elevado) y, si no se puede, solo con el usuario actual. NETDECK_WAR_VERSION cambia la
# version (solo para probar la ausencia).
$ErrorActionPreference = 'SilentlyContinue'
$version = if ($env:NETDECK_WAR_VERSION) { $env:NETDECK_WAR_VERSION } else { '1.5' }
$menor = $version.Split('.')[1]
$marco = @(Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.$version") + @(Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.$version")
$ddlm = @(Get-AppxPackage -AllUsers -Name "Microsoft.WinAppRuntime.DDLM.${menor}0*-x6") + @(Get-AppxPackage -Name "Microsoft.WinAppRuntime.DDLM.${menor}0*-x6")
if (($marco | Where-Object { $_.Architecture -eq 'X64' }) -and $ddlm) { 'WAR-OK'; exit 0 } else { exit 1 }
