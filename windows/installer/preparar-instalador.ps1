# Reune en una carpeta todo lo que lleva el instalador (la entrada de NetDeckWindows.wxs):
#   - lo que compila windows/scripts/desktop.ps1: NetDeckWindows.exe, sus .dll y el bootstrapper de Windows App SDK
#   - los .dll del runtime de Swift (la app los busca junto al exe; desktop.ps1 los pone en el PATH)
#   - la carpeta Temas (los temas de color del terminal), AppxManifest.xml y sus iconos, los scripts de registro del Sparse Package y, si existe, NetDeckSparse.msix
# Uso (desde la raiz del repo, tras compilar con desktop.ps1):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/preparar-instalador.ps1 [-Destino carpeta]
# Y despues:  wix build windows/installer/NetDeckWindows.wxs <carpeta>/../archivos.wxs -arch x64 -d SourceDir=<carpeta> -o NetDeckWindows.msi
param(
    [string]$Destino = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller/files'),
    # debug (el de desktop.ps1 por defecto) o release (desktop.ps1 -Configuration release): decide la carpeta de Productos
    [ValidateSet('debug', 'release')][string]$Configuracion = 'debug',
    [string]$Productos = (Join-Path $env:LOCALAPPDATA ('NetDeckDesktopBuild/out/Products/' + (Get-Culture).TextInfo.ToTitleCase($Configuracion) + '-windows-x86_64')),
    [string]$Runtime = (Join-Path $env:LOCALAPPDATA 'Programs/Swift/Runtimes/6.4.2/usr/bin')
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# detectar-runtime.js lleva detectar-runtime.ps1 codificado en base64: que no se desincronicen (si falla, ver la cabecera de detectar-runtime.ps1).
$deteccion = (Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'detectar-runtime.ps1')) -replace "`r`n", "`n"
$esperado = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($deteccion))
$js = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'detectar-runtime.js')
if ($js -notmatch '-EncodedCommand ([A-Za-z0-9+/=]+)' -or $Matches[1] -ne $esperado) {
    throw 'detectar-runtime.js no lleva la version actual de detectar-runtime.ps1 en base64: regenerala (ver la cabecera de ese script).'
}
if (!(Test-Path (Join-Path $Productos 'NetDeckWindows.exe'))) { throw "Falta NetDeckWindows.exe en ${Productos}: compila antes con windows/scripts/desktop.ps1." }
if (!(Test-Path $Runtime)) { throw "Falta el runtime de Swift en ${Runtime}." }

# Se vacia el destino, asi que solo si esta vacio o lo creo este mismo script (marcador): nunca una carpeta ajena.
$marcador = Join-Path $Destino '.preparado-por-netdeck'
if (Test-Path $Destino) {
    $hay = @(Get-ChildItem -LiteralPath $Destino -Force)
    if ($hay.Count -gt 0 -and !(Test-Path $marcador)) { throw "${Destino} no esta vacia ni la creo este script: elige otra carpeta con -Destino." }
    Remove-Item -LiteralPath $Destino -Recurse -Force
}
New-Item -ItemType Directory -Force $Destino | Out-Null

# La app y sus dependencias (sin los .lib, .exp, .swiftmodule ni .objlib: son de compilar, no de ejecutar)
Get-ChildItem -LiteralPath $Productos -Recurse -File |
    Where-Object { $_.Extension -in '.exe', '.dll' -or $_.FullName -match 'swift-windowsappsdk_CWinAppSDK' } |
    Where-Object { $_.Name -ne 'SwiftTermBuildInfoGenerator.exe' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($Productos.Length).TrimStart('\', '/')
        $to = Join-Path $Destino $rel
        New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $to -Force
    }
# El runtime de Swift (solo los .dll)
Get-ChildItem -LiteralPath $Runtime -Filter '*.dll' -File | Copy-Item -Destination $Destino -Force

# Sparse Package
$desktop = Join-Path $repo 'windows/Desktop'
# Los temas de color del terminal (NetDeckCore los busca en «Temas», junto al exe)
Copy-Item (Join-Path $repo 'Temas') (Join-Path $Destino 'Temas') -Recurse -Force
Copy-Item (Join-Path $desktop 'AppxManifest.xml') $Destino -Force
Copy-Item (Join-Path $desktop 'Assets') (Join-Path $Destino 'Assets') -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'registrar-sparse.ps1'), (Join-Path $PSScriptRoot 'quitar-sparse.ps1') $Destino -Force
$msix = Join-Path $PSScriptRoot 'NetDeckSparse.msix'
if (Test-Path $msix) { Copy-Item $msix $Destino -Force }

Set-Content -LiteralPath $marcador -Value 'carpeta generada por preparar-instalador.ps1' -Encoding ASCII
# La lista de archivos para WiX (WiX 4.0 no tiene el elemento Files): un componente por archivo, en archivos.wxs, junto a la carpeta.
$origen = $Destino.TrimEnd('\', '/')
$lineas = New-Object System.Collections.Generic.List[string]
$i = 0
Get-ChildItem -LiteralPath $Destino -Recurse -File | Where-Object { $_.Name -ne '.preparado-por-netdeck' } | Sort-Object FullName | ForEach-Object {
    $i++
    $rel = $_.FullName.Substring($origen.Length).TrimStart('\', '/')
    $sub = Split-Path $rel -Parent
    $subAttr = ''
    if ($sub) { $subAttr = ' Subdirectory="' + [System.Security.SecurityElement]::Escape($sub) + '"' }
    $src = [System.Security.SecurityElement]::Escape('$(var.SourceDir)\' + $rel)
    $lineas.Add('      <Component Id="Archivo' + $i + '"' + $subAttr + ' Guid="*">')
    $lineas.Add('        <File Id="Fichero' + $i + '" Source="' + $src + '" KeyPath="yes" />')
    $lineas.Add('      </Component>')
}
$wxs = @('<?xml version="1.0" encoding="utf-8"?>', '<!-- Generado por preparar-instalador.ps1: no se edita. -->',
         '<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">', '  <Fragment>',
         '    <ComponentGroup Id="ArchivosDeLaApp" Directory="INSTALLFOLDER">') + $lineas + @('    </ComponentGroup>', '  </Fragment>', '</Wix>')
$archivosWxs = Join-Path (Split-Path $Destino -Parent) 'archivos.wxs'
Set-Content -LiteralPath $archivosWxs -Value $wxs -Encoding UTF8

$n = (Get-ChildItem -LiteralPath $Destino -Recurse -File | Measure-Object).Count
$mb = [math]::Round((Get-ChildItem -LiteralPath $Destino -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "Carpeta del instalador: ${Destino} ($n archivos, $mb MB); lista para WiX: $archivosWxs"
