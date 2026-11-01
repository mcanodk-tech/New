#!/usr/bin/env bash
# Android/iOS platform klasörlerini üretir ve uygulamaya özel dosyaları üzerine yazar.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org com.ayakizi --project-name ayakizi --platforms android,ios --no-pub .
cp -R overrides/android/. android/
flutter pub get
echo "Hazır. Derlemek için: flutter build apk --release"
