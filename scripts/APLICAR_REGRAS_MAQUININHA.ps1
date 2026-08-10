param(
  [string]$Projeto = "."
)

$ErrorActionPreference = "Stop"

$raiz = (Resolve-Path $Projeto).Path
$origem = Join-Path $PSScriptRoot "lib"

$arquivos = @(
  "lib\pages\pagamentos_page.dart",
  "lib\pages\regras_taxa_page.dart",
  "lib\repositories\pagamento_repository.dart"
)

foreach ($rel in $arquivos) {
  $destino = Join-Path $raiz $rel
  if (-not (Test-Path (Split-Path -Parent $destino))) {
    throw "Pasta do projeto não encontrada para: $rel"
  }
}

$backup = Join-Path $raiz ("backup_regras_maquininha_" + (Get-Date -Format "yyyyMMdd_HHmmss"))

foreach ($rel in $arquivos) {
  $destino = Join-Path $raiz $rel

  if (Test-Path $destino) {
    $backupArquivo = Join-Path $backup $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $backupArquivo) -Force | Out-Null
    Copy-Item $destino $backupArquivo -Force
  }

  $fonte = Join-Path $PSScriptRoot $rel
  if (-not (Test-Path $fonte)) {
    throw "Arquivo do pacote não encontrado: $fonte"
  }

  Copy-Item $fonte $destino -Force
}

Write-Host ""
Write-Host "Regras da maquininha aplicadas com sucesso." -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host ""
Write-Host "Agora rode:"
Write-Host "  flutter analyze"
Write-Host "  flutter test"
Write-Host "  flutter build apk --release"
