# Registra el Sparse Package de Terminal NetDeck para el usuario que instala (identidad de paquete sin MSIX completo,
# ADR-0003). Lo llama el instalador (NetDeckWindows.wxs) desde la carpeta de instalacion. Un fallo NO aborta la
# instalacion: la app funciona igual sin identidad de paquete (el registro es opcional).
#
#   - Con NetDeckSparse.msix (firmado, lo que produce el CI): Add-AppxPackage -Path ... -ExternalLocation <carpeta>
#   - Sin el: Add-AppxPackage -Register AppxManifest.xml -ExternalLocation <carpeta> (solo con el modo desarrollador)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$msix = Join-Path $dir 'NetDeckSparse.msix'
$manifest = Join-Path $dir 'AppxManifest.xml'
try {
    if (Test-Path -LiteralPath $msix) {
        Add-AppxPackage -Path $msix -ExternalLocation $dir
    } elseif (Test-Path -LiteralPath $manifest) {
        Add-AppxPackage -Register $manifest -ExternalLocation $dir
    } else {
        Write-Warning 'No esta NetDeckSparse.msix ni AppxManifest.xml: no se registra el Sparse Package.'
    }
} catch {
    Write-Warning ('No se pudo registrar el Sparse Package (la app funciona sin el): ' + $_.Exception.Message)
}
exit 0
