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

PLIST="ios/Runner/Info.plist"

if [[ ! -f "$PLIST" ]]; then
  echo "ERRO: $PLIST nao existe. Gere a plataforma iOS primeiro."
  exit 1
fi

plutil -lint "$PLIST"

if ! grep -q "NSCameraUsageDescription" "$PLIST"; then
  echo "ERRO: falta NSCameraUsageDescription no Info.plist."
  exit 1
fi

if ! grep -q "NSPhotoLibraryUsageDescription" "$PLIST"; then
  echo "ERRO: falta NSPhotoLibraryUsageDescription no Info.plist."
  exit 1
fi

if ! grep -q "imperiumdetailing" "$PLIST"; then
  echo "ERRO: falta o URL scheme imperiumdetailing no Info.plist."
  exit 1
fi

if grep -q "com.example" "ios/Runner.xcodeproj/project.pbxproj"; then
  echo "ERRO: Bundle Identifier ainda usa com.example."
  exit 1
fi

flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign

echo ""
echo "VALIDACAO IOS SEM ASSINATURA APROVADA."
echo "Proximo passo: abrir no Xcode, configurar Team e testar em iPhone fisico."
