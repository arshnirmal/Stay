#!/bin/bash
set -e

echo "🔨 Building Stay in release mode..."
swift build -c release --target Stay

APP_DIR="Stay.app"
echo "📦 Packaging ${APP_DIR}..."
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp ".build/release/Stay" "${APP_DIR}/Contents/MacOS/Stay"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

echo "✍️ Signing ${APP_DIR} with ad-hoc signature..."
codesign --force --deep -s - "${APP_DIR}"

echo "✅ Successfully created and signed ${APP_DIR}!"
echo "👉 Launch with: open ${APP_DIR}"
