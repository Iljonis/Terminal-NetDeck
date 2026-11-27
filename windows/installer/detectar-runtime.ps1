# Comprueba si esta instalado en Windows el Windows App Runtime 1.5 (el Framework x64 y su DDLM). Escribe WAR-OK y sale con 0 si
# esta; si falta, no escribe nada y sale con 1.
#
# La app ya no lo necesita instalado: lo lleva dentro (incluir-dependencias.ps1). Lo usa windows-release.yml para probar en un
# Windows SIN el runtime que la portable y el Setup.exe arrancan y no lo instalan. (Hasta la 1.1.0, el .msi lo llevaba en base64 en
# detectar-runtime.js para negarse a instalar sin el.)
#
# Se mira con -AllUsers (el instalador va elevado) y, si no se puede, solo con el usuario actual. NETDECK_WAR_VERSION cambia la
# version (solo para probar la ausencia).
$ErrorActionPreference = 'SilentlyContinue'
$version = if ($env:NETDECK_WAR_VERSION) { $env:NETDECK_WAR_VERSION } else { '1.5' }
$menor = $version.Split('.')[1]
$marco = @(Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.$version") + @(Get-AppxPackage -Name "Microsoft.WindowsAppRuntime.$version")
$ddlm = @(Get-AppxPackage -AllUsers -Name "Microsoft.WinAppRuntime.DDLM.${menor}0*-x6") + @(Get-AppxPackage -Name "Microsoft.WinAppRuntime.DDLM.${menor}0*-x6")
if (($marco | Where-Object { $_.Architecture -eq 'X64' }) -and $ddlm) { 'WAR-OK'; exit 0 } else { exit 1 }
