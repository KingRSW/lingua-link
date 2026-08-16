#!/bin/bash
# ============================================================
# 翻译应用一键打包脚本（macOS 本地运行）
# 生成：APK (Android) + IPA (iOS) + DMG (macOS)
# ============================================================
# 使用方法：
#   1. 将此脚本保存到项目根目录：translate_app/build_all.sh
#   2. 给执行权限：chmod +x build_all.sh
#   3. 运行：./build_all.sh
# ============================================================

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   翻译应用一键打包 (APK + IPA + DMG)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ 未找到 Flutter SDK，请先安装：${NC}"
    echo -e "   https://docs.flutter.dev/get-started/install/macos"
    exit 1
fi

echo -e "${GREEN}✅ Flutter 版本：${NC}"
flutter --version
echo ""

# 创建输出目录
OUTPUT_DIR="$(pwd)/build_output"
mkdir -p "$OUTPUT_DIR"

# ============================================================
# 步骤 1：清理并获取依赖
# ============================================================
echo -e "${BLUE}📦 [1/5] 清理项目并获取依赖...${NC}"
flutter clean
flutter pub get
echo -e "${GREEN}✅ 依赖获取完成${NC}"
echo ""

# ============================================================
# 步骤 2：构建 APK (Android)
# ============================================================
echo -e "${BLUE}📦 [2/5] 构建 Android APK...${NC}"
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$OUTPUT_DIR/translate_app.apk"
APK_SIZE=$(du -h "$OUTPUT_DIR/translate_app.apk" | cut -f1)
echo -e "${GREEN}✅ APK 构建完成：$OUTPUT_DIR/translate_app.apk ($APK_SIZE)${NC}"
echo ""

# ============================================================
# 步骤 3：构建 IPA (iOS)
# ============================================================
echo -e "${BLUE}📦 [3/5] 构建 iOS IPA...${NC}"
echo -e "${YELLOW}   注意：iOS 打包需要有效的 Apple 开发者证书和配置文件${NC}"

# 检查是否在 macOS 上
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ IPA 打包必须在 macOS 上进行${NC}"
else
    # 构建 iOS release
    flutter build ios --release --no-codesign
    
    # 使用 Xcode 打包（需要配置签名）
    echo -e "${YELLOW}   请在 Xcode 中配置签名后继续...${NC}"
    echo -e "${YELLOW}   如果已有证书，将自动生成 IPA${NC}"
    
    # 尝试使用 xcodebuild 创建 archive
    cd ios
    xcodebuild -workspace Runner.xcworkspace \
        -scheme Runner \
        -configuration Release \
        -archivePath build/Runner.xcarchive \
        archive \
        -allowProvisioningUpdates 2>/dev/null || true
    
    # 导出 IPA
    if [ -d "build/Runner.xcarchive" ]; then
        xcodebuild -exportArchive \
            -archivePath build/Runner.xcarchive \
            -exportPath build/ipa \
            -exportOptionsPlist ExportOptions.plist 2>/dev/null || true
        
        if [ -f "build/ipa/Runner.ipa" ]; then
            cp build/ipa/Runner.ipa "$OUTPUT_DIR/translate_app.ipa"
            IPA_SIZE=$(du -h "$OUTPUT_DIR/translate_app.ipa" | cut -f1)
            echo -e "${GREEN}✅ IPA 构建完成：$OUTPUT_DIR/translate_app.ipa ($IPA_SIZE)${NC}"
        else
            echo -e "${YELLOW}⚠️  自动签名失败，请手动在 Xcode 中打包：${NC}"
            echo -e "   1. 打开 Xcode: open ios/Runner.xcworkspace"
            echo -e "   2. 选择 Product > Archive"
            echo -e "   3. 在 Organizer 中点击 Distribute App"
        fi
    else
        echo -e "${YELLOW}⚠️  Archive 失败，请手动在 Xcode 中打包${NC}"
    fi
    cd ..
fi
echo ""

# ============================================================
# 步骤 4：构建 macOS 应用并打包为 DMG
# ============================================================
echo -e "${BLUE}📦 [4/5] 构建 macOS 应用并打包 DMG...${NC}"
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ DMG 打包必须在 macOS 上进行${NC}"
else
    # 启用 macOS 桌面支持
    flutter config --enable-macos-desktop
    flutter build macos --release
    
    APP_PATH="build/macos/Build/Products/Release/translate_app.app"
    
    if [ -d "$APP_PATH" ]; then
        # 创建 DMG
        echo -e "${BLUE}   正在创建 DMG 镜像...${NC}"
        hdiutil create -volname "translate_app" \
            -srcfolder "$APP_PATH" \
            -ov -format UDZO \
            "$OUTPUT_DIR/translate_app.dmg"
        
        if [ -f "$OUTPUT_DIR/translate_app.dmg" ]; then
            DMG_SIZE=$(du -h "$OUTPUT_DIR/translate_app.dmg" | cut -f1)
            echo -e "${GREEN}✅ DMG 构建完成：$OUTPUT_DIR/translate_app.dmg ($DMG_SIZE)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  macOS 应用构建失败${NC}"
        echo -e "${YELLOW}   请检查 macos/ 目录配置${NC}"
    fi
fi
echo ""

# ============================================================
# 步骤 5：汇总输出
# ============================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}🎉 打包完成！${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "输出目录：${YELLOW}$OUTPUT_DIR${NC}"
echo ""
echo -e "文件列表："
ls -lh "$OUTPUT_DIR" 2>/dev/null
echo ""
echo -e "${BLUE}安装说明：${NC}"
echo -e "  📱 APK: 传输到 Android 手机，开启\"允许未知来源\"后安装"
echo -e "  📱 IPA: 使用 Xcode > Window > Devices and Simulators 安装到 iPhone"
echo -e "  💻 DMG: 双击挂载，将 .app 拖入 Applications 文件夹"
echo ""
