#!/bin/bash

# 快速安全设置检查脚本
echo "=== Apple ID 安全设置检查 ==="
echo

# 检查网络连接
echo "🔍 检查网络连接..."
if curl -s https://appleid.apple.com > /dev/null; then
    echo "✅ Apple ID 网站可访问"
else
    echo "❌ 无法访问 Apple ID 网站"
    echo "请检查网络连接"
    exit 1
fi
echo

# 安全设置位置提示
echo "📍 安全设置位置："
echo "📱 网页端：https://appleid.apple.com"
echo "   1. 登录 quanwei_114514@qq.com"
echo "   2. 点击顶部的【安全】按钮"
echo "   3. 查找【应用专用密码】选项"
echo

echo "📱 iOS设备："
echo "   1. 打开【设置】→【Apple ID】→【密码与安全性】"
echo "   2. 找到【应用专用密码】"
echo

echo "⚠️  重要提醒："
echo "   • 确保双重验证已开启"
echo "   • 为'App Store Connect'创建专用密码"
echo "   • 生成的16位密码务必保存"
echo

echo "🔧 创建步骤："
echo "   1. 进入安全设置"
echo "   2. 点击'生成应用专用密码'"
echo "   3. 应用名称输入：'App Store Connect'"
echo "   4. 复制生成的16位密码"
echo "   5. 使用 ./final_upload_solution.sh \"密码\" 重新上传"
echo

read -p "按回车键打开Apple ID网站..." x
open https://appleid.apple.com
