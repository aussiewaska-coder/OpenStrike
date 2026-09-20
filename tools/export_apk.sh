#!/usr/bin/env bash
# Numbered on-device APK export. Usage: tools/export_apk.sh [number]
# Without a number, bumps VERSION by one. Writes build/android/OpenStrike-v<N>.apk
# plus a Download copy, and stamps the preset version code/name to match.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [ "${1:-}" != "" ]; then
  build="$1"
else
  build=$(( $(cat VERSION) + 1 ))
fi
echo "$build" > VERSION
sed -i "s|^version/code=.*|version/code=${build}|" export_presets.cfg
sed -i "s|^version/name=.*|version/name=\"0.1.${build}\"|" export_presets.cfg
godot_bin="${GODOT_BIN:-$HOME/tools/godot/Godot_v4.7.2-stable_linux.arm64}"
mkdir -p build/android
"$godot_bin" --headless --path . --import
"$godot_bin" --headless --path . --export-debug "Android" "build/android/OpenStrike-v${build}.apk"
cp "build/android/OpenStrike-v${build}.apk" /sdcard/Download/
cp "build/android/OpenStrike-v${build}.apk" /sdcard/OpenStrike-latest.apk
echo "released v${build}"
