#!/bin/bash
# 스티커 투두 빌드 스크립트
#   ./build.sh            빌드하고 바로 실행
#   ./build.sh --install  빌드해서 응용 프로그램 폴더에 설치하고 실행
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StickerTodo"
APP="build/${APP_NAME}.app"

echo "▸ 컴파일 중..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ 앱 묶는 중..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP/Contents/Info.plist"

echo "▸ 서명 중 (ad-hoc)..."
codesign --force --sign - "$APP"

# 이미 실행 중이면 종료
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    open "/Applications/${APP_NAME}.app"
    echo "✓ /Applications 에 설치하고 실행했어요."
else
    open "$APP"
    echo "✓ $APP 실행했어요."
fi
