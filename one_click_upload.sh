#!/bin/bash

# 一键执行TestFlight上传流程
echo "🚀 一键TestFlight上传流程"
echo "============================"

# 检查文件存在性
if [ ! -f "ios/translate_app.ipa" ]; then
    echo "❌ 错误：找不到ipa文件 ios/translate_app.ipa"
    exit 1
fi

echo "✅ 找到ipa文件: ios/translate_app.ipa"
echo "✅ Bundle ID: com.example.translateApp"
echo "✅ 开发者: quanwei_114514@qq.com"
echo "✅ 应用专用密码: fned-xmbw-abih-lsgb"
echo

# 自动打开App Store Connect
echo "🔗 正在打开App Store Connect..."
open https://appstoreconnect.apple.com

echo "📋 请按以下步骤操作："
echo "====================="
echo "1. 登录 quanwei_114514@qq.com"
echo "2. 点击 '+ 创建App'"
echo "3. 选择 'iOS App'"
echo "4. Bundle ID: com.example.translateApp"
echo "5. App名称: translate_app"
echo "6. 点击 '创建'"
echo "7. 等待应用创建完成（约1-2分钟）"
echo "8. 回到终端按回车键继续上传"
echo

# 等待用户完成应用创建
read -p "完成应用创建后按回车键开始上传..." x

echo "🚀 开始上传..."
echo "=============="

# 执行上传
if ./final_upload_solution.sh "fned-xmbw-abih-lsgb"; then
    echo
    echo "🎉 成功！"
    echo "📱 现在可以在App Store Connect中："
    echo "   ✅ 配置应用信息"
    echo "   ✅ 添加测试人员"
    echo "   ✅ 提交审核"
    echo "   ✅ 发布到TestFlight"
    echo
    echo "💡 测试人员将收到邀请邮件"
else
    echo
    echo "❌ 上传失败"
    echo "💡 请检查应用是否创建完成"
fi
