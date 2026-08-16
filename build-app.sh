#!/bin/bash
# Builds a release binary and hand-assembles a real Mailify.app bundle
# (icon slot, Info.plist, ad-hoc code signature) without Xcode.
set -e

swift build -c release

APP="Mailify.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/Mailify" "$APP/Contents/MacOS/Mailify"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mailify</string>
  <key>CFBundleDisplayName</key><string>Mailify</string>
  <key>CFBundleIdentifier</key><string>com.hari.mailify</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Mailify</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF

# Ad-hoc sign so Gatekeeper/notifications/Spotlight behave like a normal app.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run it:   open $APP"
echo "Install:  drag $APP into /Applications"
