#!/bin/zsh
set -e

echo "==== Flutter iOS 生成修复框架签名的未签名IPA ===="

flutter clean
flutter pub get

cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# 编译无签名App
xcodebuild -workspace ios/Runner.xcworkspace \
-scheme Runner \
-configuration Debug \
-sdk iphoneos \
-derivedDataPath ./build/ios/DerivedData \
CODE_SIGNING_REQUIRED=NO \
CODE_SIGNING_ALLOWED=NO

APP_PATH="./build/ios/DerivedData/Build/Products/Debug-iphoneos/Runner.app"
OUT_IPA="./build/ios/fixed.ipa"

# 判断编译产物是否存在
if [ ! -d "$APP_PATH" ];then
    echo "❌编译失败，Runner.app不存在，请检查上面xcodebuild日志！"
    exit 1
fi

rm -rf Payload
mkdir Payload
cp -r "$APP_PATH" Payload/

# 关键：清除残留旧签名、给所有flutter框架逐个预签名
rm -rf Payload/Runner.app/_CodeSignature
rm -rf Payload/Runner.app/Frameworks/*/_CodeSignature
codesign -s - --force Payload/Runner.app/Frameworks/*

zip -r "$OUT_IPA" Payload
rm -rf Payload

echo ""
echo "✅已生成修复框架签名的ipa：$OUT_IPA"
echo "⚠️重要：此ipa仍是未签名包，需要Sideloadly/爱思助手重新签名才能安装手机"
echo "⚠️使用企业证书签名务必把手机UDID加入描述文件，否则会闪退！"
open ./build/ios