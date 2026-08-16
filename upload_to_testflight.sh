#!/bin/bash

# TestFlight 上传脚本
# 使用方法：./upload_to_testflight.sh "您的专用密码"

if [ -z "$1" ]; then
    echo "错误：请提供应用专用密码"
    echo "使用方法：./upload_to_testflight.sh \"您的专用密码\""
    echo "请先在 https://appleid.apple.com 创建应用专用密码"
    exit 1
fi

APP_PASSWORD=$1
IPA_FILE="ios/translate_app.ipa"

# 检查 IPA 文件是否存在
if [ ! -f "$IPA_FILE" ]; then
    echo "错误：找不到 IPA 文件 $IPA_FILE"
    exit 1
fi

echo "正在上传 IPA 文件到 TestFlight..."
echo "文件：$IPA_FILE"
echo "开发者：quanwei_114514@qq.com"

# 上传应用到 App Store Connect
xcrun altool --upload-app --type ios --file "$IPA_FILE" --username quanwei_114514@qq.com --password "$APP_PASSWORD"

if [ $? -eq 0 ]; then
    echo "✅ 上传成功！"
    echo "请在 App Store Connect 中继续配置应用信息"
    echo "并添加测试人员进行测试"
else
    echo "❌ 上传失败"
    echo "请检查："
    echo "1. 应用专用密码是否正确"
    echo "2. 是否已创建对应的应用"
    echo "3. 网络连接是否正常"
fi
