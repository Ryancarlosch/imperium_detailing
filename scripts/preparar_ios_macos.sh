#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${1:-}"

if [[ -z "$BUNDLE_ID" ]]; then
  echo "ERRO: informe o Bundle Identifier como primeiro argumento."
  echo "Exemplo: bash scripts/preparar_ios_macos.sh br.com.suaempresa.imperiummanager"
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERRO: este script deve ser executado em um Mac."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERRO: Flutter nao foi encontrado no PATH."
  exit 1
fi

if [[ -d "ios" ]]; then
  echo "ERRO: a pasta ios/ ja existe. Nao sera sobrescrita."
  exit 1
fi

if command -v git >/dev/null 2>&1 && [[ -n "$(git status --porcelain)" ]]; then
  echo "ERRO: existem alteracoes locais. Deixe a arvore Git limpa antes de gerar ios/."
  exit 1
fi

flutter pub get
flutter create . --platforms ios

if [[ ! -f "ios/Runner/Info.plist" ]]; then
  echo "ERRO: Flutter nao gerou ios/Runner/Info.plist."
  exit 1
fi

python3 scripts/configurar_ios_imperium.py "$BUNDLE_ID"

echo ""
echo "BASE IOS GERADA E CONFIGURADA."
echo "Bundle Identifier: $BUNDLE_ID"
echo "Revise Signing & Capabilities no Xcode conforme IOS-PREPARACAO-E-HOMOLOGACAO.md."
echo "Depois execute: bash scripts/validar_ios_macos.sh"
