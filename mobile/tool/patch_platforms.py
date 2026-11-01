#!/usr/bin/env python3
"""`flutter create` çıktısını mağaza yayınına hazırlar.

* Android: android/key.properties varsa sürüm derlemesini yükleme anahtarıyla
  imzalar (yoksa hata ayıklama anahtarıyla; mağazaya yüklenemez).
* iOS: görünen ad ve şifreleme beyanı (yalnızca standart TLS) eklenir.

Her bağlantı noktası bulunamazsa betik hata verir; şablon değişirse sessizce
yanlış derleme yapılmaz.
"""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SIGNING_LOAD = '''
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
'''

SIGNING_CONFIG = '''
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }
'''

DEBUG_SIGNING = 'signingConfig = signingConfigs.getByName("debug")'
RELEASE_SIGNING = ('signingConfig = if (keystorePropertiesFile.exists()) '
                   'signingConfigs.getByName("release") else signingConfigs.getByName("debug")')


def fail(msg: str) -> None:
    print(f"patch_platforms: {msg}", file=sys.stderr)
    sys.exit(1)


def patch_android() -> None:
    path = ROOT / "android/app/build.gradle.kts"
    if not path.exists():
        fail(f"{path} yok; önce flutter create çalıştırın.")
    text = path.read_text(encoding="utf-8")
    if "keystorePropertiesFile" in text:
        print("android: zaten yamalı")
        return
    if text.count("\nandroid {") != 1:
        fail("build.gradle.kts içinde 'android {' bloğu bulunamadı")
    if text.count(DEBUG_SIGNING) != 1:
        fail("build.gradle.kts içinde sürüm imzalama satırı bulunamadı")
    text = text.replace("\nandroid {", SIGNING_LOAD + "\nandroid {" + SIGNING_CONFIG, 1)
    text = text.replace(DEBUG_SIGNING, RELEASE_SIGNING, 1)
    path.write_text(text, encoding="utf-8")
    print("android: imzalama yapılandırması eklendi")


def patch_ios() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    if not path.exists():
        print("ios: Info.plist yok, atlandı")
        return
    with path.open("rb") as f:
        plist = plistlib.load(f)
    plist["CFBundleDisplayName"] = "ayakizi"
    plist["ITSAppUsesNonExemptEncryption"] = False
    with path.open("wb") as f:
        plistlib.dump(plist, f)
    print("ios: Info.plist güncellendi")


if __name__ == "__main__":
    patch_android()
    patch_ios()
