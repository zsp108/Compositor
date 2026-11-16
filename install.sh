#!/usr/bin/env zsh
set -e

# 指定外置硬盘上的 Xcode
export DEVELOPER_DIR="/Volumes/spz-data/Xcode.app/Contents/Developer"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "==> 正在编译 Compositor (Release 版本)..."
xcodebuild -scheme Compositor \
  -configuration Release \
  -disableAutomaticPackageResolution \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE="Manual" \
  build

# 获取 DerivedData 路径
DERIVED_DATA="/Users/spz/Library/Developer/Xcode/DerivedData/Compositor-fttwgomfmxlwddcwclhzvgrpgtmz"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/Compositor.app"

if [ ! -d "$APP_SOURCE" ]; then
  echo "错误: 未找到构建产物 $APP_SOURCE"
  exit 1
fi

echo "==> 正在安装到 /Applications/Compositor.app..."
rm -rf /Applications/Compositor.app
cp -R "$APP_SOURCE" /Applications/

echo "==> 正在进行深度签名与权限配置..."
codesign --force --deep --sign - /Applications/Compositor.app
xattr -cr /Applications/Compositor.app

echo "==> ✅ 安装完成！"
echo "您可以在“访达 -> 应用程序”中双击打开 Compositor，或者在终端运行："
echo "    open /Applications/Compositor.app"
