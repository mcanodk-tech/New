#!/usr/bin/env bash
# Android/iOS platform klasörlerini üretir, uygulamaya özel dosyaları yazar,
# imzalama/plist yamalarını uygular ve uygulama ikonlarını üretir.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org com.ayakizi --project-name ayakizi --platforms android,ios --no-pub .
cp -R overrides/android/. android/
flutter pub get
python3 tool/patch_platforms.py
dart run flutter_launcher_icons
echo "Hazır. Mağaza paketi için: flutter build appbundle --release"
