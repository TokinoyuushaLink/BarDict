
#!/bin/bash
# 只需要 xcode-select（Command Line Tools），不需要完整 Xcode
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/BarDict.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BIN="$MACOS/BarDict"

echo "📖 BarDict — 开始构建..."

# 1. 检查编译环境
if ! command -v swiftc &>/dev/null; then
    echo "❌ 找不到 swiftc，请先安装 Command Line Tools："
    echo "   xcode-select --install"
    exit 1
fi

# 2. 清理旧的构建产物并创建目录
rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# 3. 图标生成（沿用你原来的逻辑，未改动）
if [ -f "$SCRIPT_DIR/icon.png" ]; then
    echo "🎨 发现 icon.png，正在全自动渲染标准 macOS 圆角图标..."
    TMP_SET="$SCRIPT_DIR/Generated_AppIcon.iconset"
    mkdir -p "$TMP_SET"

    cat > "$SCRIPT_DIR/clip_icon.swift" << 'SWIFTSCRIPT'
    import AppKit
    guard CommandLine.arguments.count == 3 else { exit(1) }
    let inputPath = CommandLine.arguments[1]
    let outputPath = CommandLine.arguments[2]
    guard let sizeStr = outputPath.components(separatedBy: "icon_").last?.components(separatedBy: "x").first,
          let size = Double(sizeStr),
          let image = NSImage(contentsOfFile: inputPath) else { exit(1) }
    let isRetina = outputPath.contains("@2x")
    let pixelSize = isRetina ? size * 2 : size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixelSize), pixelsHigh: Int(pixelSize),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let padding = pixelSize * 0.09
    let contentSize = pixelSize - (padding * 2)
    let cornerRadius = contentSize * 0.225
    let rect = NSRect(x: padding, y: padding, width: contentSize, height: contentSize)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: outputPath))
    }
SWIFTSCRIPT

    for sz in 16 32 128 256 512; do
        swift "$SCRIPT_DIR/clip_icon.swift" "$SCRIPT_DIR/icon.png" "$TMP_SET/icon_${sz}x${sz}.png"
        swift "$SCRIPT_DIR/clip_icon.swift" "$SCRIPT_DIR/icon.png" "$TMP_SET/icon_${sz}x${sz}@2x.png"
    done

    rm -f "$SCRIPT_DIR/clip_icon.swift"
    iconutil -c icns "$TMP_SET" -o "$RESOURCES/AppIcon.icns"
    rm -rf "$TMP_SET"
    echo "✅ 图标处理完成！"
else
    echo "⚠️ 提示: 未在脚本目录找到 icon.png，将使用系统空白图标。"
fi

# 4. 编译所有 Swift 源码
echo "🚀 正在编译二进制文件..."
swiftc \
    -O \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework WebKit \
    -lsqlite3 \
    -target "$(uname -m)-apple-macos14.0" \
    "$SCRIPT_DIR/Localize.swift" \
    "$SCRIPT_DIR/BarDict.swift" \
    "$SCRIPT_DIR/HTMLNode.swift" \
    "$SCRIPT_DIR/DictStore.swift" \
    "$SCRIPT_DIR/EntryView.swift" \
    "$SCRIPT_DIR/DictManager.swift" \
    "$SCRIPT_DIR/WebEntryView.swift" \
    "$SCRIPT_DIR/DictPanel.swift" \
    -o "$BIN"

# 5. 生成 Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>            <string>BarDict</string>
    <key>CFBundleIdentifier</key>            <string>com.linkapps.BarDict</string>
    <key>CFBundleName</key>                  <string>BarDict</string>
    <key>CFBundleDisplayName</key>           <string>BarDict</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.1.0</string>
    <key>CFBundleVersion</key>               <string>1.1.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "🎉 构建成功：$APP"
echo ""
read -rp "是否立即运行该应用？[y/N] " yn
[[ $yn =~ ^[Yy] ]] && open "$APP" || true
