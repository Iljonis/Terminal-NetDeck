# Quita el registro del Sparse Package de Terminal NetDeck del usuario que desinstala (o actualiza). No falla nunca.
$ErrorActionPreference = 'Stop'
try {
    Get-AppxPackage -Name 'Iljonis.TerminalNetDeck' | Remove-AppxPackage
} catch {
    Write-Warning ('No se pudo quitar el Sparse Package: ' + $_.Exception.Message)
}
exit 0
