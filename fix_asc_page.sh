#!/bin/bash

# App Store Connect 页面问题解决脚本
echo "=== App Store Connect 页面问题解决 ==="
echo

echo "📊 当前问题："
echo "   - 页面显示两个按钮但白屏"
echo "   - 可能的原因：浏览器兼容性问题"
echo

echo "💡 解决方案："
echo "=============================="
echo "1. 尝试使用Chrome浏览器"
echo "   - 打开Chrome"
echo "   - 访问：https://appstoreconnect.apple.com"
echo
echo "2. 清除浏览器缓存"
echo "   - Chrome菜单 → 设置 → 隐私和安全 → 清除浏览数据"
echo
echo "3. 禁用浏览器扩展"
echo "   - 临时禁用所有扩展程序"
echo
echo "4. 检查网络代理"
echo "   - 确保没有VPN或代理"
echo
echo "5. 尝试直接访问登录页面"
echo "   https://appstoreconnect.apple.com/apps"
echo

echo "🔧 如果问题持续，请尝试："
echo "   - 使用无痕模式访问"
echo "   - 等待一段时间后重试"
echo "   - 检查Apple服务状态"
echo

echo "📋 推荐操作顺序："
echo "   1. 先尝试Chrome浏览器"
echo "   2. 清除缓存和扩展"
echo "   3. 访问直接链接"
echo

read -p "尝试Chrome浏览器访问 (Y/n)：" choice
if [ "$choice" != "n" ] && [ "$choice" != "N" ]; then
    echo "🌐 正在打开Chrome浏览器..."
    open -a "Google Chrome" https://appstoreconnect.apple.com
fi

echo
echo "✨ 完成浏览器调整后，回到终端按回车键继续..."
read x
