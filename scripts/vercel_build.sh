#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.44.8"
FLUTTER_DIR="${PWD}/.vercel_flutter"

if [[ ! -x "${FLUTTER_DIR}/bin/flutter" ]]; then
  rm -rf "${FLUTTER_DIR}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
export PUB_CACHE="${PWD}/.pub-cache"

flutter config --no-analytics
flutter config --enable-web
flutter --version
flutter pub get
flutter build web --target lib/main_web.dart --release
