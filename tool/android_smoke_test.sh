#!/usr/bin/env bash
set -euo pipefail

package="com.songs.geulbom"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
created_signing=0
key_file="$root/android/app/fantextviewer-local.jks"
properties_file="$root/android/key.properties"
apk_v1="$root/build/android-smoke-v1.apk"
apk_v2="$root/build/android-smoke-v2.apk"

cleanup() {
  rm -f "$apk_v1" "$apk_v2"
  if [[ "$created_signing" == 1 ]]; then
    rm -f "$key_file" "$properties_file"
  fi
}
trap cleanup EXIT

cd "$root"
flutter build apk --debug

(
  cd android
  ./gradlew installDebug
)
adb shell appops set --uid "$package" MANAGE_EXTERNAL_STORAGE allow
(
  cd android
  ./gradlew connectedDebugAndroidTest
)

if [[ -f "$properties_file" ]]; then
  configured_store_file="$(
    sed -n 's/^storeFile=//p' "$properties_file" |
      head -n 1 |
      tr -d '\r'
  )"
  test -n "$configured_store_file"
  if [[ "$configured_store_file" = /* ]]; then
    key_file="$configured_store_file"
  else
    key_file="$root/android/$configured_store_file"
  fi
  if [[ ! -f "$key_file" ]]; then
    echo "The keystore configured by android/key.properties does not exist." >&2
    exit 1
  fi
elif [[ -f "$key_file" ]]; then
  echo "android/key.properties is required for the existing keystore." >&2
  exit 1
else
  created_signing=1
  password="$(openssl rand -hex 24)"
  keytool -genkeypair \
    -keystore "$key_file" \
    -storetype PKCS12 \
    -alias fantextviewer-local \
    -keyalg RSA \
    -keysize 3072 \
    -validity 3650 \
    -dname "CN=FanTextViewer Local, OU=Personal Sideload, O=Local, C=KR" \
    -storepass "$password" \
    -keypass "$password"
  printf '%s\n' \
    "storeFile=app/fantextviewer-local.jks" \
    "storePassword=$password" \
    "keyAlias=fantextviewer-local" \
    "keyPassword=$password" > "$properties_file"
fi

flutter build apk --release --build-number=900001
cp build/app/outputs/flutter-apk/app-release.apk "$apk_v1"
flutter build apk --release --build-number=900002
cp build/app/outputs/flutter-apk/app-release.apk "$apk_v2"

adb uninstall "$package" >/dev/null 2>&1 || true
adb install "$apk_v1"
first_install_time="$(
  adb shell dumpsys package "$package" |
    sed -n 's/.*firstInstallTime=//p' |
    head -n 1 |
    tr -d '\r'
)"
test -n "$first_install_time"

adb shell appops set --uid "$package" MANAGE_EXTERNAL_STORAGE allow
adb shell appops get --uid "$package" MANAGE_EXTERNAL_STORAGE | grep -q "allow"

adb shell monkey -p "$package" 1 >/dev/null
sleep 2
test -n "$(adb shell pidof "$package" | tr -d '\r')"
adb shell am force-stop "$package"
test -z "$(adb shell pidof "$package" | tr -d '\r')"
adb shell monkey -p "$package" 1 >/dev/null
sleep 2
test -n "$(adb shell pidof "$package" | tr -d '\r')"

adb install -r "$apk_v2"
adb shell dumpsys package "$package" | grep -q "versionCode=900002"
updated_first_install_time="$(
  adb shell dumpsys package "$package" |
    sed -n 's/.*firstInstallTime=//p' |
    head -n 1 |
    tr -d '\r'
)"
test "$updated_first_install_time" = "$first_install_time"
adb shell monkey -p "$package" 1 >/dev/null
sleep 2
test -n "$(adb shell pidof "$package" | tr -d '\r')"
