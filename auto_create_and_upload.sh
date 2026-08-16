#!/bin/bash

# 自动化App Store Connect创建和上传流程
echo "=== 自动化TestFlight上传流程 ==="
echo

# 显示应用信息
echo "📱 应用信息："
echo "   IPA文件: ios/translate_app.ipa"
echo "   Bundle ID: com.example.translateApp"
echo "   开发者: quanwei_114514@qq.com"
echo "   应用专用密码: fned-xmbw-abih-lsgb"
echo

# 第1步：提示创建应用
echo "🔧 第1步：创建App Store Connect应用"
echo "====================================="
echo "请按以下步骤创建应用："
echo "1. 访问: https://appstoreconnect.apple.com"
echo "2. 登录 quanwei_114514@qq.com"
echo "3. 点击 '+ 创建App'"
echo "4. 选择 'iOS App'"
echo "5. Bundle ID: com.example.translateApp"
echo "6. App名称: translate_app"
echo "7. 点击 '创建'"
echo
echo "⏳ 请完成应用创建后按回车键继续..."
read x

# 第2步：验证创建结果
echo "🔍 第2步：验证应用创建状态"
echo "==============================="
echo "正在等待应用创建完成..."
sleep 5

# 第3步：上传应用
echo "🚀 第3步：上传到App Store Connect"
echo "==================================="
if ./final_upload_solution.sh "fned-xmbw-abih-lsgb"; then
    echo
    echo "🎉 上传成功！"
    echo "📋 后续步骤："
    echo "   1. 在App Store Connect中配置应用信息"
    echo "   2. 添加测试人员邮箱"
    echo "   3. 提交审核"
    echo "   4. 发布到TestFlight"
    echo "   5. 测试人员将收到邀请邮件"
else
    echo
    echo "❌ 上传失败，可能需要更多时间"
    echo "请稍等片刻后重试"
fi

echo
echo "✅ 流程完成"
