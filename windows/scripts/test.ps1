# windows\scripts\test.ps1 - los tests del nucleo en Windows, como ./test.sh en macOS: con un NETDECK_HOME temporal
# para que nada escriba en tu carpeta de usuario. Los argumentos van a swift test (por ejemplo --filter SessionTests).
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test.ps1 [--filter ...]
# Sale con el codigo de swift test.

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

# Configuracion del toolchain de Swift 6.4.2 en Windows
$base    = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
$toolBin = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\bin'
$rtBin   = Join-Path $base 'Runtimes\6.4.2\usr\bin'
$mapi    = Join-Path $base 'Toolchains\6.4.2+Asserts\usr\lib\swift\pm\ManifestAPI'
$sdk     = Join-Path $base 'Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk'
$gitWin  = 'C:\Program Files\Git\bin'

foreach ($dir in @($toolBin, $rtBin, $mapi, $sdk)) {
    if (-not (Test-Path $dir)) { Write-Error "No existe: $dir (instalar Swift 6.4.2?)"; exit 1 }
}

$env:PATH    = "$gitWin;$toolBin;$rtBin;$mapi;" + $env:PATH
$env:SDKROOT = $sdk

# Ruta de build fuera de Documents para evitar el bloqueo de Windows Defender Controlled Folder Access
$scratchPath = Join-Path $env:LOCALAPPDATA 'NetDeckBuild'
New-Item -ItemType Directory -Force $scratchPath | Out-Null

$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$casa = Join-Path $env:TEMP ("netdeck-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $casa | Out-Null
$anterior = $env:NETDECK_HOME
$codigo = 1
try {
    $env:NETDECK_HOME = $casa
    Push-Location $raiz
    $swift = Join-Path $toolBin 'swift.exe'
    # En Windows, `swift test` sin --filter activa el runner XCTest (0 tests). Con --filter y un nombre de suite
    # concreto activa el runner de Swift Testing. Incluimos sólo los suites compatibles con Windows (los envueltos
    # en #if !os(Windows), #if canImport(Security/AppKit/CoreGraphics/SwiftTerm) quedan fuera).
    # MainTurnTests excluido: usa RunLoop.main.perform que no cicla en Windows sin AppKit (deadlock).
    $suitesWindows = 'AccesibilidadTests|EscTests|PasswordAutomationTests|SafePasteTests' +
        '|JumpBatchTests|TypedPasswordTests|PromptRegexRegresionesTests|MacroIdentificadorRegresionesTests' +
        '|MacroAsincronaRegresionesTests|PegadoSecretosRegresionesTests|GrabacionSecretosRegresionesTests' +
        '|CredencialesPromptRegresionesTests|AutopassReintentosTests|AutopassRobustoTests|AvisosTests' +
        '|ButtonTests|EntradaAutenticacionTests|FueraDelPrincipalTests|CredencialesEnSegundoPlanoTests' +
        '|CredentialManagementTests|CredentialRenamerTests|DataBackupTests|DeviceListTests' +
        '|EdicionCopiaExclusivaTests|EdicionReintentoTests|ErrorLogTests|EspaciosTests' +
        '|EspaciosAuditoriaTests|AtribucionCredencialesTests|FiltrosPantallaTests|HighlightTests' +
        '|IdiomaTests|IntegracionSSHTests|ListaReservasCredencialesTests|JumpSharingTests|EarlyConfirmTests' +
        '|LedgerProcesosTests|DesbloquearTests|OfertaGuardarTests|HaEntradoHacePocoTests|LimpiezaTests' +
        '|MacroFormatTests|MacroRecorderTests|MacroPlayerTests|MacroPegadoTests|MacroPegadoEnTrozosTests' +
        '|MacroGuardadoSeguroTests|MultiExecPeligrosasTests|MultiExecReservaTests|AutenticacionAnidadaTests' +
        '|FinDelProcesoTests|PasteRulesTests|PerfilesTests|PerfilesMultiExecTests|SFTPPacketTests' +
        '|RemotePathTests|FTPParseTests|TransferTests|MoveTests|SFTPServerTests|SessionDefaultsTests' +
        '|ReservaAutomaticaTests|PasswordPromptTests|CredentialPolicyTests|LedgerTests|AskpassTests' +
        '|KeychainQuotingTests|SessionFileTests|ImporterTests|SafeFileTests|SessionKindTests' +
        '|SessionOrderTests|GroupTreeTests|SessionExportTests|SessionLogTests|PromptDeviceTests' +
        '|SSHConfigParserTests|RouteTests|UpdateCheckTests|LoopbackTests|TerminalEnvironmentTests' +
        '|LocalTerminalTests|SFTPPanelRouteTests|SFTPPanelStoreTests|RemoteEditTests|AskpassScopeTests' +
        '|TerminalSelectionTests|ThemeOverridesTests|ThemeTests|ConPTYProcessTests|ProcesosHijosWindowsTests|SerialWindowsTests'
    $filtroExtra = if ($args -notcontains '--filter') { @('--filter', $suitesWindows) } else { @() }
    # -DOPENSSL_NO_ASM: BoringSSL necesita NASM para ASM en Windows; con este flag usa C puro.
    & $swift test --scratch-path $scratchPath -Xcc -DOPENSSL_NO_ASM @filtroExtra @args
    $codigo = $LASTEXITCODE
} finally {
    Pop-Location
    $env:NETDECK_HOME = $anterior
    Remove-Item -Recurse -Force $casa -ErrorAction SilentlyContinue
}
exit $codigo