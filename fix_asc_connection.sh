#!/bin/bash

# App Store Connect 连接问题解决脚本
echo "=== App Store Connect 连接问题解决 ==="
echo

# 检查网络
echo "🔍 检查网络连接..."
if curl -s https://appleid.apple.com > /dev/null; then
    echo "✅ Apple ID 可访问"
else
    echo "❌ 无法访问Apple ID"
    exit 1
fi
echo

echo "📱 App Store Connect 状态："
echo "   当前显示: 登录失败页面"
echo "   原因可能:"
echo "   1. 未登录Apple ID"
echo "   2. 需要双重验证"
echo "   3. 网络代理问题"
echo

echo "💡 解决方案："
echo "================================="
echo "1. 手动访问：https://appstoreconnect.apple.com"
echo "2. 登录 quanwei_114514@qq.com"
echo "3. 如果要求双重验证，请完成验证"
echo "4. 完成登录后，再回来运行上传脚本"
echo

echo "🔗 尝试其他连接方式..."
echo "请尝试在新的浏览器标签页访问:"
echo "   https://appstoreconnect.apple.com"
echo

read -p "完成登录后按回车键继续..." x

echo "🚀 验证登录状态..."
if curl -s -L -I https://appstoreconnect.apple.com | grep -q "302.*login"; then
    echo "❌ 仍然需要登录"
    echo "请确保已成功登录Apple ID"
else
    echo "✅ 登录成功"
fi

echo
echo "📋 如果问题持续，请尝试："
echo "   - 清除浏览器缓存"
echo "   - 使用Chrome浏览器"
echo "   - 检查网络代理设置"
echo "   - 确保Apple ID没有锁定"
