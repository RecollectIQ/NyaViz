#!/bin/bash
set -e

# NyaViz Build Script - Generates icons and creates DMG

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SOURCE="$PROJECT_DIR/icon.png"
ICON_DIR="$PROJECT_DIR/NyaViz/Assets.xcassets/AppIcon.appiconset"
BUILD_DIR="$PROJECT_DIR/release_build"
APP_NAME="NyaViz"
DMG_NAME="NyaViz"

echo "🎨 NyaViz Build Script"
echo "======================"

# Step 1: Generate App Icons
echo ""
echo "📐 Generating app icons from icon.png..."

# Check if source icon exists
if [ ! -f "$ICON_SOURCE" ]; then
    echo "❌ Error: icon.png not found at $ICON_SOURCE"
    exit 1
fi

# Generate all required icon sizes
# macOS requires: 16, 32, 64, 128, 256, 512, 1024 pixels
declare -a SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for SIZE_PAIR in "${SIZES[@]}"; do
    SIZE="${SIZE_PAIR%%:*}"
    FILENAME="${SIZE_PAIR##*:}"
    echo "  → Generating $FILENAME (${SIZE}x${SIZE})"
    sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" --out "$ICON_DIR/$FILENAME" > /dev/null 2>&1
done

echo "✅ Icons generated successfully!"

# Step 2: Update Contents.json
echo ""
echo "📝 Updating AppIcon Contents.json..."

cat > "$ICON_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "✅ Contents.json updated!"

# Step 3: Build Release
echo ""
echo "🔨 Building Release version..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build with xcodebuild
xcodebuild -project "$PROJECT_DIR/NyaViz.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="Developer ID Application: Yanfei Ding (55VR37C6LP)" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="55VR37C6LP" \
    CODE_SIGN_STYLE="Manual"

echo "✅ Build completed!"

# Step 4: Export app from archive
echo ""
echo "📦 Exporting app..."

APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Built app not found at $APP_PATH"
    echo "Checking archive contents..."
    find "$BUILD_DIR/$APP_NAME.xcarchive" -name "*.app" 2>/dev/null || echo "No .app found"
    exit 1
fi

# Step 5: Create DMG
echo ""
echo "💿 Creating DMG..."

DMG_DIR="$BUILD_DIR/dmg_staging"
DMG_OUTPUT="$PROJECT_DIR/$DMG_NAME.dmg"

# Clean up any existing DMG
rm -f "$DMG_OUTPUT"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to staging
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symlink to Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

echo ""
echo "✅ Build complete!"
echo "📍 DMG location: $DMG_OUTPUT"
echo ""
echo "🎉 Done! You can distribute $DMG_NAME.dmg"

