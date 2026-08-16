#!/bin/bash

# TestFlight 上传综合解决方案脚本
echo "=== TestFlight 上传综合解决方案 ==="
echo

# 检查文件存在性
if [ ! -f "ios/translate_app.ipa" ]; then
    echo "❌ 错误：找不到ipa文件 ios/translate_app.ipa"
    exit 1
fi

echo "✅ 找到ipa文件: ios/translate_app.ipa"
echo "✅ Bundle ID: com.example.translateApp"
echo "✅ 开发者账号: quanwei_114514@qq.com"
echo

echo "=== 必需的步骤 ==="
echo "1. 创建Apple应用专用密码"
echo "   访问: https://appleid.apple.com"
echo "   登录后创建应用专用密码"
echo

echo "2. 在App Store Connect中创建应用"
echo "   访问: https://appstoreconnect.apple.com"
echo "   创建应用并选择Bundle ID: com.example.translateApp"
echo

echo "3. 验证上传条件"
if [ -z "$1" ]; then
    echo "❌ 请提供正确的应用专用密码"
    echo "使用方法: ./final_upload_solution.sh \"应用专用密码\""
    exit 1
fi

APP_PASSWORD="$1"
echo "✅ 应用专用密码已提供"
echo

echo "=== 开始上传 ==="
echo "正在上传到App Store Connect..."

# 使用最可靠的上传方法
if xcrun altool --upload-app -f "ios/translate_app.ipa" \
    -u quanwei_114514@qq.com \
    -p "$APP_PASSWORD" \
    --wait \
    --verbose 2>&1 | tee upload_result.log; then

    echo
    echo "🎉 上传成功！"
    echo "📱 应用现在出现在App Store Connect中"
    echo "⚠️  请继续完成以下步骤："
    echo "   1. 配置应用信息"
    echo "   2. 添加测试人员"
    echo "   3. 提交审核"
    echo "   4. 发布到TestFlight"
    echo
    echo "📋 结果已保存到: upload_result.log"
    
else
    echo
    echo "❌ 上传失败，请检查："
    echo "   1. 应用专用密码是否正确"
    echo "   2. 应用是否已在App Store Connect中创建"
    echo "   3. 网络连接是否正常"
    echo
    echo "📋 详细错误信息已保存到: upload_result.log"
    exit 1
fi

