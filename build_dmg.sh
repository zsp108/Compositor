#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

VOL_NAME="Compositor"
DMG_NAME="Compositor-1.6.7-macOS15-zh_CN.dmg"
OUTPUT_DMG="$PROJECT_DIR/$DMG_NAME"
TEMP_DMG="/tmp/Compositor_build_temp.dmg"
BG_IMG="/tmp/dmg_bg_retina.png"

# 1. 查找 Compositor.app
APP_PATH=""
if [ -d "/Applications/Compositor.app" ]; then
    APP_PATH="/Applications/Compositor.app"
elif [ -d "$PROJECT_DIR/DerivedData/Build/Products/Release/Compositor.app" ]; then
    APP_PATH="$PROJECT_DIR/DerivedData/Build/Products/Release/Compositor.app"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "==> 未找到可用的 Release 应用程序，正在编译..."
    ./install.sh
    APP_PATH="/Applications/Compositor.app"
fi

echo "==> 使用应用程序产物: $APP_PATH"

# 2. 确保签名与权限
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
xattr -cr "$APP_PATH" 2>/dev/null || true

# 3. 生成高清 Retina 背景图 (1200 x 760)
echo "==> 正在生成安装引导背景图..."
python3 - << 'PYEOF'
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 760
img = Image.new('RGB', (W, H), color='#1e1f26')
draw = ImageDraw.Draw(img)

# 纵向渐变
for y in range(H):
    f = y / H
    r = int(32 * (1 - f * 0.25))
    g = int(34 * (1 - f * 0.25))
    b = int(44 * (1 - f * 0.2))
    draw.line([(0, y), (W, y)], fill=(r, g, b))

# 装饰细边框
draw.rectangle([(2, 2), (W-3, H-3)], outline=(55, 60, 75), width=2)

# 中间箭头 (连接两个图标)
y_mid = 360
arrow_fill = (120, 135, 175)

# 箭头线条
draw.rounded_rectangle([(490, y_mid - 7), (670, y_mid + 7)], radius=7, fill=arrow_fill)
# 箭头头部
draw.polygon([(660, y_mid - 28), (715, y_mid), (660, y_mid + 28)], fill=arrow_fill)

# 左侧装饰小圆点
for dx in [-75, -45, -15]:
    draw.circle((490 + dx, y_mid), 5, fill=(80, 90, 115))

# 提示文字
try:
    font_title = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 34)
    font_sub = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
except:
    font_title = font_sub = ImageFont.load_default()

text_zh = "拖移 Compositor 到 Applications 完成安装"
text_en = "Drag Compositor to Applications to install"

bbox_zh = draw.textbbox((0, 0), text_zh, font=font_title)
draw.text(((W - (bbox_zh[2] - bbox_zh[0])) // 2, 595), text_zh, fill=(215, 222, 240), font=font_title)

bbox_en = draw.textbbox((0, 0), text_en, font=font_sub)
draw.text(((W - (bbox_en[2] - bbox_en[0])) // 2, 645), text_en, fill=(125, 135, 155), font=font_sub)

img.save('/tmp/dmg_bg_retina.png')
PYEOF

# 4. 创建临时读写镜像
rm -f "$TEMP_DMG" "$OUTPUT_DMG"
echo "==> 正在创建临时 DMG 镜像..."
hdiutil create -size 200m -fs HFS+ -volname "$VOL_NAME" -ov "$TEMP_DMG" >/dev/null

echo "==> 挂载镜像..."
MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" -nobrowse -noverify -noautoopen | grep "/Volumes/$VOL_NAME" | awk '{print $NF}')
if [ -z "$MOUNT_DIR" ]; then
    echo "错误: 镜像挂载失败"
    exit 1
fi

echo "==> 复制文件与创建替身..."
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

# 设置卷图标
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# 5. AppleScript 自动化设置窗口布局
echo "==> 正在设置 Finder 窗口布局..."
osascript << APPLESCRIPT || true
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 150, 900, 530} -- 600 x 380
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        delay 1
        set position of item "Compositor.app" of container window to {150, 180}
        set position of item "Applications" of container window to {450, 180}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

# 隐藏私有文件
SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true
SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true

# 6. 同步并卸载
echo "==> 正在卸载临时镜像..."
sync
sleep 1
hdiutil detach "$MOUNT_DIR" >/dev/null

# 7. 转换为高压缩只读 DMG
echo "==> 正在压缩生成最终 DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null
rm -f "$TEMP_DMG" "$BG_IMG"

echo "==> ✅ DMG 打包成功！"
ls -lh "$OUTPUT_DMG"
