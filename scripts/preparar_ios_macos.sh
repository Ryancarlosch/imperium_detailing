#!/usr/bin/env bash
set -euo pipefail

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

echo ""
echo "BASE IOS GERADA."
echo "Agora configure Info.plist e Signing conforme IOS-PREPARACAO-E-HOMOLOGACAO.md."
echo "Depois execute: bash scripts/validar_ios_macos.sh"
