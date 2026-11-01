#!/usr/bin/env bash
# Google Play yükleme anahtarı oluşturur ve GitHub Secrets için değerleri yazdırır.
# Anahtar dosyasını ve şifreyi güvenli bir yerde saklayın: kaybederseniz
# uygulamayı güncellemek için Play Console'dan anahtar sıfırlama istemeniz gerekir.
set -euo pipefail
OUT="${1:-$HOME/ayakizi-upload-keystore.jks}"
ALIAS="upload"
if [ -e "$OUT" ]; then echo "$OUT zaten var; üzerine yazılmadı." >&2; exit 1; fi
read -r -s -p "Anahtar deposu şifresi (en az 6 karakter): " PASS; echo
keytool -genkeypair -v -keystore "$OUT" -storetype JKS -keyalg RSA -keysize 2048 \
  -validity 10000 -alias "$ALIAS" -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=ayakizi, O=ayakizi, C=TR"
echo
echo "Oluşturuldu: $OUT"
echo "GitHub → Settings → Secrets and variables → Actions → New repository secret:"
echo "  ANDROID_KEYSTORE_BASE64   = (aşağıdaki satır)"
echo "  ANDROID_KEYSTORE_PASSWORD = (girdiğiniz şifre)"
echo "  ANDROID_KEY_ALIAS         = $ALIAS"
echo
base64 -w0 "$OUT" 2>/dev/null || base64 -i "$OUT"
echo
