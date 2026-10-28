#!/usr/bin/env bash
# Installs the APK in $1 on the running emulator, opens it, sends it to
# the background and opens it again; fails with the crash log when the
# app stopped. Used by android.yml.
set -uo pipefail
app=io.github.swz0103.expensetracker
adb install -r "$1" || exit 1
adb logcat -c
open() {
  adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 20
}
check() {
  if ! adb shell pidof "$app" > /dev/null || adb logcat -d -b crash | grep -q "$app"; then
    echo "::error::The app stopped $1."
    adb logcat -d -b crash
    adb logcat -d | grep -E 'AndroidRuntime|flutter' | tail -100
    exit 1
  fi
  echo "Still running $1."
}
open
check 'as it opened'
adb shell input keyevent KEYCODE_HOME
sleep 5
check 'in the background'
open
check 'when opened again'
