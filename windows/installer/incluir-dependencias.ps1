# Mete en la carpeta del instalador (la de preparar-instalador.ps1, que lo llama al final) lo que la app necesita para no pedir
# NADA al PC: ni instalar Windows App Runtime ni activar el cliente OpenSSH. Asi el .msi, el Setup.exe y la portable (.zip) valen
# igual en un PC sin permisos de administrador o con las tiendas y las caracteristicas opcionales bloqueadas.
#
#   1. Windows App Runtime 1.5 "self-contained", lo mismo que hace WindowsAppSDKSelfContained de MSBuild
#      (build/Microsoft.WindowsAppSDK.SelfContained.targets del paquete NuGet), que SwiftPM no tiene:
#        - del NuGet oficial Microsoft.WindowsAppSDK saca el paquete Framework x64 (.msix) y copia junto al exe sus .dll, .mui,
#          .png, .winmd, .xaml, .xbf, RestartAgent.exe y map.html, y su resources.pri como Microsoft.UI.Xaml.Controls.pri;
#        - genera el manifiesto con una entrada activatableClass por cada clase WinRT del Framework (RegFree WinRT) y lo mete en
#          NetDeckWindows.exe con mt.exe, mezclado con el que ya tuviera.
#      Con Microsoft.WindowsAppRuntime.dll junto al exe, Arranque.swift no usa el bootstrapper (que solo sabe buscar el runtime
#      instalado) y la app arranca sin nada instalado. Una compilacion de desarrollo (desktop.ps1) sigue usando el instalado.
#   2. El cliente de Win32-OpenSSH de Microsoft en la carpeta OpenSSH (SystemTools lo prefiere al de Windows).
#
# Todo se baja de las URL fijas de dependencias.json, con su sha256, y se comprueba la firma de Microsoft de cada .exe y .dll.
# Las descargas se guardan en -Descargas para no repetirlas.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/installer/incluir-dependencias.ps1 -Destino <carpeta>
param(
    [Parameter(Mandatory = $true)][string]$Destino,
    [string]$Descargas = (Join-Path $env:LOCALAPPDATA 'NetDeckInstaller/descargas')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fijado = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'dependencias.json') | ConvertFrom-Json
$Destino = (Resolve-Path -LiteralPath $Destino).Path
$exe = Join-Path $Destino 'NetDeckWindows.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Falta ${exe}: ejecuta antes preparar-instalador.ps1." }
if (Test-Path -LiteralPath (Join-Path $Destino 'Microsoft.WindowsAppRuntime.dll')) { throw "${Destino} ya lleva el runtime: vuelve a prepararla con preparar-instalador.ps1." }

$temporal = Join-Path $env:TEMP ('netdeck-dependencias-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $temporal | Out-Null

function Bajar($dependencia, [string]$nombre) {
    New-Item -ItemType Directory -Force $Descargas | Out-Null
    $archivo = Join-Path $Descargas $nombre
    $valido = (Test-Path -LiteralPath $archivo) -and ((Get-FileHash -Algorithm SHA256 -LiteralPath $archivo).Hash.ToLower() -eq $dependencia.sha256)
    if (!$valido) {
        Write-Host "Bajando $($dependencia.url) ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'          # (con la barra de progreso, Invoke-WebRequest de 5.1 va muchisimo mas lento)
        Invoke-WebRequest -UseBasicParsing -Uri $dependencia.url -OutFile $archivo
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivo).Hash.ToLower()
        if ($hash -ne $dependencia.sha256) {
            Remove-Item -LiteralPath $archivo -Force
            throw "El sha256 de $nombre ($hash) no es el de dependencias.json ($($dependencia.sha256))."
        }
    }
    return $archivo
}

# Cada .exe y .dll, firmado por Microsoft y con la firma valida (ademas del sha256 del paquete entero).
function ComprobarFirmas($archivos) {
    foreach ($archivo in $archivos) {
        if ($archivo.Extension -notin '.exe', '.dll') { continue }
        $firma = Get-AuthenticodeSignature -LiteralPath $archivo.FullName
        $sujeto = if ($firma.SignerCertificate) { $firma.SignerCertificate.Subject } else { '' }
        # (el campo O= entero del sujeto, no un trozo: "O=Microsoft Corporation Ltd" no vale)
        if ($firma.Status -ne 'Valid' -or $sujeto -notmatch ('(^|,\s*)' + [regex]::Escape($fijado.firmante) + '(,|$)')) {
            throw "$($archivo.Name): la firma no es valida o no es de Microsoft ($($firma.Status), '$sujeto')."
        }
    }
}

# Nunca pisa un archivo de la app: si coincidiera un nombre, se para.
function Copiar([string]$origen, [string]$relativa) {
    $destino = Join-Path $Destino $relativa
    if (Test-Path -LiteralPath $destino) { throw "Ya existe $relativa en ${Destino}: no se pisa un archivo de la app." }
    New-Item -ItemType Directory -Force (Split-Path $destino) | Out-Null
    Copy-Item -LiteralPath $origen -Destination $destino
}

function Mt([string[]]$argumentos) {
    # (con 'Stop', la primera linea de stderr de mt.exe cortaria el script; se mira el codigo de salida)
    $ErrorActionPreference = 'Continue'
    $salida = & $script:mt @argumentos 2>&1 | Out-String
    return @{ Codigo = $LASTEXITCODE; Salida = $salida }
}

try {
    # ---- 1. Windows App Runtime 1.5 ----
    $nupkg = Bajar $fijado.windowsAppSDK "Microsoft.WindowsAppSDK.$($fijado.windowsAppSDK.version).nupkg"
    $msix = Join-Path $temporal 'framework.msix'
    $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
    try {
        $entrada = $zip.Entries | Where-Object { $_.FullName -eq $fijado.windowsAppSDK.msix } | Select-Object -First 1
        if (!$entrada) { throw "El paquete NuGet no trae $($fijado.windowsAppSDK.msix)." }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entrada, $msix)
        # Su licencia (codigo distribuible: va con la app) y sus avisos de terceros, junto al exe
        foreach ($par in @(@('license.txt', 'WindowsAppSDK-LICENSE.txt'), @('NOTICE.txt', 'WindowsAppSDK-NOTICE.txt'))) {
            $texto = $zip.Entries | Where-Object { $_.FullName -eq $par[0] } | Select-Object -First 1
            if (!$texto) { throw "El paquete NuGet no trae $($par[0])." }
            $ruta = Join-Path $Destino $par[1]
            if (Test-Path -LiteralPath $ruta) { throw "Ya existe $($par[1]) en ${Destino}." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($texto, $ruta)
        }
    } finally { $zip.Dispose() }
    $framework = Join-Path $temporal 'framework'
    [IO.Compression.ZipFile]::ExtractToDirectory($msix, $framework)
    $todos = @(Get-ChildItem -LiteralPath $framework -Recurse -File)
    ComprobarFirmas $todos

    # Los mismos tipos de archivo que AddMicrosoftWindowsAppSDKPayloadFiles, con su ruta relativa (las .mui van en carpetas de idioma).
    $tipos = '*.dll', '*.mui', '*.png', '*.winmd', '*.xaml', '*.xbf'
    $sueltos = 'RestartAgent.exe', 'map.html'
    $copiados = 0
    # (la raiz tal como la escribe Get-ChildItem: con TEMP en nombre corto 8.3, Join-Path y FullName podrian no coincidir)
    $raiz = (Get-Item -LiteralPath $framework).FullName.TrimEnd('\', '/')
    foreach ($archivo in $todos) {
        $nombre = $archivo.Name
        if (!(($tipos | Where-Object { $nombre -like $_ }) -or ($sueltos -contains $nombre))) { continue }
        Copiar $archivo.FullName $archivo.FullName.Substring($raiz.Length).TrimStart('\', '/')
        $copiados++
    }
    # (MSBuild deshace el cambio de nombre que hace el paquete: su resources.pri es el Microsoft.UI.Xaml.Controls.pri de WinUI)
    Copiar (Join-Path $framework 'resources.pri') 'Microsoft.UI.Xaml.Controls.pri'
    # Y es tambien el resources.pri de la app: MSBuild genera uno propio mezclando ese dentro, y alli busca WinUI lo que carga
    # XamlControlsResources (ms-appx:///Microsoft.UI.Xaml/Themes/...). Sin el, la app se paraba al arrancar (0xC000001D en el CI).
    # La app no tiene recursos propios: el mismo archivo hace el papel del mezclado.
    Copiar (Join-Path $framework 'resources.pri') 'resources.pri'

    # El manifiesto RegFree WinRT: lo mismo que GenerateAppManifestFromAppx (RedirectDlls=false).
    [xml]$appx = Get-Content -Raw -Encoding UTF8 (Join-Path $framework 'AppxManifest.xml')
    $ns = New-Object Xml.XmlNamespaceManager($appx.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $lineas = New-Object System.Collections.Generic.List[string]
    $lineas.Add("<?xml version='1.0' encoding='utf-8' standalone='yes'?>")
    $lineas.Add("<assembly manifestVersion='1.0' xmlns:asmv3='urn:schemas-microsoft-com:asm.v3' xmlns:winrtv1='urn:schemas-microsoft-com:winrt.v1' xmlns='urn:schemas-microsoft-com:asm.v1'>")
    $clases = 0
    foreach ($servidor in $appx.SelectNodes('/m:Package/m:Extensions/m:Extension/m:InProcessServer', $ns)) {
        $dll = $servidor.SelectSingleNode('m:Path', $ns).InnerText
        if (!(Test-Path -LiteralPath (Join-Path $Destino $dll))) { throw "El manifiesto del runtime nombra $dll y no se ha copiado." }
        $lineas.Add("    <asmv3:file name='$([Security.SecurityElement]::Escape($dll))'>")
        foreach ($clase in $servidor.SelectNodes('m:ActivatableClass', $ns)) {
            $lineas.Add("        <winrtv1:activatableClass name='$([Security.SecurityElement]::Escape($clase.GetAttribute('ActivatableClassId')))' threadingModel='both'/>")
            $clases++
        }
        $lineas.Add('    </asmv3:file>')
    }
    $lineas.Add('</assembly>')
    # (la 1.5 trae unas 900; muchas menos querria decir que el manifiesto del paquete ha cambiado de forma)
    if ($clases -lt 500) { throw "Solo hay $clases clases WinRT en el manifiesto del runtime: revisa el formato de AppxManifest.xml." }
    $generado = Join-Path $temporal 'WindowsAppSDK.manifest'
    [IO.File]::WriteAllLines($generado, $lineas, (New-Object Text.UTF8Encoding $false))

    # mt.exe del Windows SDK (lo instala la toolchain de Swift; en el CI, Visual Studio)
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $script:mt = Get-ChildItem -Path (Join-Path $kits '10.*\x64\mt.exe') -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (!$script:mt -and (Test-Path (Join-Path $kits 'x64\mt.exe'))) { $script:mt = Join-Path $kits 'x64\mt.exe' }
    if (!$script:mt) { throw "No esta mt.exe del Windows SDK en ${kits}." }

    # Si el exe ya lleva manifiesto (recurso 1), se mezcla; si no, va el generado.
    $actual = Join-Path $temporal 'actual.manifest'
    $leido = Mt @('-nologo', "-inputresource:$exe;#1", "-out:$actual")
    $final = $generado
    if ($leido.Codigo -eq 0 -and (Test-Path -LiteralPath $actual)) {
        $final = Join-Path $temporal 'final.manifest'
        $mezcla = Mt @('-nologo', '-manifest', $actual, $generado, "-out:$final")
        if ($mezcla.Codigo -ne 0) { throw "mt.exe no ha podido mezclar los manifiestos ($($mezcla.Codigo)): $($mezcla.Salida)" }
        Write-Host 'NetDeckWindows.exe ya llevaba manifiesto: mezclado con el del runtime.'
    }
    $escrito = Mt @('-nologo', '-manifest', $final, "-outputresource:$exe;#1")
    if ($escrito.Codigo -ne 0) { throw "mt.exe no ha podido meter el manifiesto en NetDeckWindows.exe ($($escrito.Codigo)): $($escrito.Salida)" }
    $comprobado = Join-Path $temporal 'comprobado.manifest'
    $releido = Mt @('-nologo', "-inputresource:$exe;#1", "-out:$comprobado")
    $entradas = if ($releido.Codigo -eq 0) { @(Select-String -LiteralPath $comprobado -Pattern 'activatableClass' -SimpleMatch).Count } else { 0 }
    if ($entradas -lt $clases) { throw "NetDeckWindows.exe lleva $entradas clases WinRT en su manifiesto y tendria que llevar $clases." }
    Write-Host "Windows App Runtime $($fijado.windowsAppSDK.version) incluido: $copiados archivos y $clases clases WinRT en el manifiesto."

    # ---- 2. OpenSSH ----
    $zipSsh = Bajar $fijado.openssh "OpenSSH-Win64-$($fijado.openssh.version).zip"
    $openssh = Join-Path $temporal 'openssh'
    [IO.Compression.ZipFile]::ExtractToDirectory($zipSsh, $openssh)
    $origen = Join-Path $openssh $fijado.openssh.carpeta
    $elegidos = foreach ($nombre in $fijado.openssh.archivos) {
        $ruta = Join-Path $origen $nombre
        if (!(Test-Path -LiteralPath $ruta)) { throw "El .zip de OpenSSH no trae $nombre." }
        Get-Item -LiteralPath $ruta
    }
    ComprobarFirmas $elegidos
    foreach ($archivo in $elegidos) { Copiar $archivo.FullName (Join-Path 'OpenSSH' $archivo.Name) }
    Write-Host "OpenSSH $($fijado.openssh.version) incluido en OpenSSH\ ($(@($elegidos).Count) archivos)."
} finally {
    Remove-Item -LiteralPath $temporal -Recurse -Force -ErrorAction SilentlyContinue
}
