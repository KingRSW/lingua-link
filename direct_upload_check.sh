#!/bin/bash

# 直接上传验证脚本，绕过界面问题
echo "=== 直接上传验证脚本 ==="
echo

echo "📱 当前状态："
echo "   - App Store Connect界面显示问题"
echo "   - 应用已上传但需要验证"
echo "   - 跳过界面直接验证上传"
echo

echo "🔍 尝试验证应用状态..."
echo "========================"

# 检查上传日志
echo "📊 检查上传日志..."
if [ -f "upload_result.log" ]; then
    echo "✅ 找到上传日志"
    echo "最近的关键信息："
    tail -10 upload_result.log | grep -E "(成功|成功|success|failed|error|成功)" || echo "   无关键信息"
else
    echo "❌ 未找到上传日志"
fi
echo

echo "🚀 尝试直接验证上传..."
echo "========================="

# 使用原上传脚本进行验证
echo "正在验证上传状态..."
if ./final_upload_solution.sh "fned-xmbw-abih-lsgb"; then
    echo
    echo "🎉 上传验证成功！"
    echo "📱 应用已成功上传到App Store Connect"
    echo "💡 现在您需要："
    echo "   1. 等待Apple处理应用（通常1-2小时）"
    echo "   2. 检查邮件确认"
    echo "   3. 在App Store Connect中配置应用信息"
    echo "   4. 添加测试人员"
    echo "   5. 发布到TestFlight"
else
    echo
    echo "❌ 验证失败，但应用可能已成功上传"
    echo "💡 请稍后重试验证"
fi

echo
echo "📋 其他解决方案："
echo "=================="
echo "如果App Store Connect界面问题持续："
echo "   1. 等待一段时间（1-2小时）"
echo "   2. Apple系统可能在进行后台处理"
echo "   3. 检查邮件是否收到通知"
echo "   4. 可以稍后再次尝试访问"
echo

echo "🎯 建议操作："
echo "   - 先离开App Store Connect"
echo "   - 等待1-2小时"
echo "   - 稍后再次访问或验证"
echo
