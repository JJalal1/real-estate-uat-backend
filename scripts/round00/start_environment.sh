#!/usr/bin/env bash
set -euo pipefail
test "${GITHUB_ACTIONS}" = true
test "${AQER_ROUND00_DISPOSABLE}" = 20261030
test "${DB_DATABASE}" = aqer_round00
test "${DB_HOST}" = 127.0.0.1
test -f "$RUNNER_TEMP/round00-app.apk"
test -c /dev/kvm
printf '%s\n' 'Real /dev/kvm available on this disposable GitHub runner.' > round00-out/kvm.txt

export ROUND00_TLS_KEY="$RUNNER_TEMP/round00-test-ca.key"
export ROUND00_TLS_CERT="$RUNNER_TEMP/round00-test-ca.crt"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$ROUND00_TLS_KEY" -out "$ROUND00_TLS_CERT" -subj '/CN=Aqer Round00 disposable test CA' -addext 'subjectAltName=DNS:real-estate-uat-api-frankfurt.onrender.com' -addext 'basicConstraints=critical,CA:TRUE' >/dev/null 2>&1
chmod 600 "$ROUND00_TLS_KEY"
PHP_CLI_SERVER_WORKERS=6 setsid php -S 127.0.0.1:8000 -t backend-api-runtime/public scripts/round00/router.php > "$RUNNER_TEMP/round00-php.log" 2>&1 &
sudo --preserve-env=GITHUB_ACTIONS,AQER_ROUND00_DISPOSABLE,DB_DATABASE,ROUND00_TLS_KEY,ROUND00_TLS_CERT python3 scripts/round00/transport.py > "$RUNNER_TEMP/round00-transport.log" 2>&1 &
for attempt in $(seq 1 30); do
  if curl --silent --fail --max-time 2 --cacert "$ROUND00_TLS_CERT" --resolve real-estate-uat-api-frankfurt.onrender.com:443:127.0.0.1 https://real-estate-uat-api-frankfurt.onrender.com/api/health > round00-out/isolated-health.json; then break; fi
  sleep 1
done
curl --silent --fail --max-time 5 --cacert "$ROUND00_TLS_CERT" --resolve real-estate-uat-api-frankfurt.onrender.com:443:127.0.0.1 'https://real-estate-uat-api-frankfurt.onrender.com/api/properties?types%5B%5D=apartment&types%5B%5D=villa' -D round00-out/isolated-contract-headers.txt -o round00-out/isolated-contract-body.json
grep -iq 'X-Aqer-Filter-Contract: 2' round00-out/isolated-contract-headers.txt

rm -rf mobile_app/build "$HOME/.gradle/caches" "$ANDROID_HOME/ndk" "$ANDROID_HOME/cmake"
sdkmanager --install 'emulator' 'system-images;android-36;google_apis;x86_64'
export ANDROID_USER_HOME="$RUNNER_TEMP/round00-android"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
mkdir -p "$ANDROID_AVD_HOME"
avdmanager create avd --force --name aqer-round00 --device pixel --path "$ANDROID_AVD_HOME/aqer-round00.avd" --package 'system-images;android-36;google_apis;x86_64'
sudo chmod 666 /dev/kvm
QT_QPA_PLATFORM=offscreen "$ANDROID_HOME/emulator/emulator" -avd aqer-round00 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory 3072 -cores 2 -writable-system > "$RUNNER_TEMP/round00-emulator.log" 2>&1 &
ready=false
for attempt in $(seq 1 120); do
  if [ "$(timeout 3s adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then ready=true; break; fi
  sleep 2
done
test "$ready" = true
adb root
adb wait-for-device
adb shell 'id; getprop ro.build.version.sdk; getconf PAGESIZE' > round00-out/android-environment.txt
adb shell wm size 1080x2160
adb shell wm density 420
adb shell svc power stayon true
adb shell settings put global window_animation_scale 1
adb shell settings put global transition_animation_scale 1
adb shell settings put global animator_duration_scale 1
adb shell settings put global private_dns_mode off
adb shell input keyevent 82
adb shell setenforce 0
adb shell svc wifi enable
adb shell cmd wifi help > round00-out/android-wifi-help.txt
if grep -q 'connect-network' round00-out/android-wifi-help.txt; then
  timeout 15s adb shell cmd wifi connect-network AndroidWifi open > round00-out/android-wifi-connect.txt 2>&1 || true
fi
for attempt in $(seq 1 8); do
  if adb shell ip route get 1.1.1.1 > round00-out/android-network-route.txt 2>&1; then break; fi
  sleep 2
done
adb shell cmd wifi status > round00-out/android-wifi-status.txt 2>&1 || true
adb reverse tcp:443 tcp:443
adb reverse --list > round00-out/adb-reverse.txt

# Dart3.6 loads Android roots from /system/etc/security/cacerts. Install only
# this runner's temporary test CA, before starting the APK. Keep normal roots.
cert_hash="$(openssl x509 -in "$ROUND00_TLS_CERT" -subject_hash_old -noout)"
adb shell mkdir -p /data/local/tmp/round00-cacerts
adb shell 'cp /system/etc/security/cacerts/* /data/local/tmp/round00-cacerts/'
adb push "$ROUND00_TLS_CERT" "/data/local/tmp/round00-cacerts/$cert_hash.0"
adb shell 'chmod 755 /data/local/tmp/round00-cacerts; chmod 644 /data/local/tmp/round00-cacerts/*; chown -R root:root /data/local/tmp/round00-cacerts; mount -o bind /data/local/tmp/round00-cacerts /system/etc/security/cacerts'
adb shell 'for proc in $(pidof zygote64) $(pidof zygote); do nsenter -t "$proc" -m -- /system/bin/mount -o bind /data/local/tmp/round00-cacerts /system/etc/security/cacerts; done'
adb shell ls "/system/etc/security/cacerts/$cert_hash.0" > round00-out/test-ca-installed.txt
# Keep the emulator's working public DNS for real map tiles. Route only the
# compiled application API to the synthetic backend through its hosts file.
adb shell 'cat /system/etc/hosts > /data/local/tmp/round00-hosts'
adb shell 'printf "\n127.0.0.1 real-estate-uat-api-frankfurt.onrender.com\n" >> /data/local/tmp/round00-hosts; chmod 644 /data/local/tmp/round00-hosts; mount -o bind /data/local/tmp/round00-hosts /system/etc/hosts'
adb shell 'for proc in $(pidof netd) $(pidof zygote64) $(pidof zygote); do nsenter -t "$proc" -m -- /system/bin/mount -o bind /data/local/tmp/round00-hosts /system/etc/hosts; done'
timeout 15s adb shell ping -c 1 real-estate-uat-api-frankfurt.onrender.com > round00-out/isolated-dns.txt || true
grep -Fq '(127.0.0.1)' round00-out/isolated-dns.txt
adb install "$RUNNER_TEMP/round00-app.apk"
adb shell dumpsys package com.aqer.yemen.uat | sed -n '/versionCode=/p' > round00-out/installed-version.txt
