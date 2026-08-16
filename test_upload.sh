#!/bin/bash

# 使用更现代的altool上传方法
APP_PASSWORD="$1"
IPA_FILE="ios/translate_app.ipa"

if [ -z "$APP_PASSWORD" ]; then
    echo "错误：请提供应用专用密码"
    exit 1
fi

if [ ! -f "$IPA_FILE" ]; then
    echo "错误：找不到 IPA 文件 $IPA_FILE"
    exit 1
fi

echo "正在上传 IPA 文件到 App Store Connect..."
echo "文件：$IPA_FILE"
echo "Bundle ID: com.example.translateApp"

# 尝试上传
xcrun altool --upload-app -f "$IPA_FILE" \
    -u quanwei_114514@qq.com \
    -p "$APP_PASSWORD" \
    --wait \
    --verbose

if [ $? -eq 0 ]; then
    echo "✅ 上传成功！"
else
    echo "❌ 上传失败"
    echo "可能需要："
    echo "1. 创建应用专用密码"
    echo "2. 在App Store Connect中创建对应的应用"
    echo "3. 启用双重验证"
fi
