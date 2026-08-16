#!/bin/bash

# App Store Connect 应用创建脚本
echo "=== 创建App Store Connect应用 ==="
echo

# 检查网络连接
echo "🔍 检查网络连接..."
if curl -s https://appstoreconnect.apple.com > /dev/null; then
    echo "✅ App Store Connect 可访问"
else
    echo "❌ 无法访问 App Store Connect"
    echo "请检查网络连接"
    exit 1
fi
echo

echo "📋 应用信息："
echo "   Bundle ID: com.example.translateApp"
echo "   App类型: iOS"
echo "   开发者: quanwei_114514@qq.com"
echo

echo "🚀 创建步骤："
echo "   1. 打开 https://appstoreconnect.apple.com"
echo "   2. 登录 quanwei_114514@qq.com"
echo "   3. 点击 '+ 创建App'"
echo "   4. 选择 'iOS App'"
echo "   5. 输入Bundle ID: com.example.translateApp"
echo "   6. 输入App名称: translate_app"
echo "   7. 点击 '创建'"
echo

echo "⏱️  预计创建时间: 1-2分钟"
echo "✅ 创建完成后即可上传ipa文件"
echo

read -p "按回车键打开App Store Connect..." x
open https://appstoreconnect.apple.com

echo
echo "📌 创建完成后，请运行以下命令重新上传："
echo "   ./final_upload_solution.sh 'fned-xmbw-abih-lsgb'"
