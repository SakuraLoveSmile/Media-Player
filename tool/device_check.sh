#!/usr/bin/env bash
# 设备自检：把 release APK 装到已连接的 Android 设备，启动应用并截一张首页图。
# 用法： tool/device_check.sh [输出目录]
# 退出码：0 成功；2 没有设备；3 缺少 APK。
set -euo pipefail
cd "$(dirname "$0")/.."

APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="${1:-/tmp/device-check}"

mkdir -p "$OUT"
SERIAL="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
if [[ -z "${SERIAL}" ]]; then
  echo "没有已连接的 Android 设备（adb devices 为空）。" >&2
  echo "请确认 USB 连接与 USB 调试授权，然后重试。" >&2
  exit 2
fi
if [[ ! -f "$APK" ]]; then
  echo "缺少 $APK，请先运行 flutter build apk --release。" >&2
  exit 3
fi

echo "设备: $SERIAL"
adb -s "$SERIAL" install -r "$APK"
adb -s "$SERIAL" shell am force-stop cn.sakuralovesmile.mediaplayer
adb -s "$SERIAL" shell am start -n cn.sakuralovesmile.mediaplayer/.MainActivity >/dev/null
sleep 8
adb -s "$SERIAL" exec-out screencap -p > "$OUT/home.png"
echo "已截图: $OUT/home.png"
echo "逐屏核对清单见 docs/yamby-parity-gaps.md「设备核对清单」。"
