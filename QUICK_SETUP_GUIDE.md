# 🚀 TestFlight 快速设置指南

## 📋 必要步骤清单

### 🔐 第一步：创建应用专用密码（必须在浏览器中完成）

1. **访问**：https://appleid.apple.com
2. **登录**：quanwei_114514@qq.com
3. **密码**：Wsc-15689
4. **操作**：
   - 点击"密码与安全性"
   - 点击"生成密码"
   - 命名为："TestFlight 分发"
   - **复制保存生成的密码**

### 📱 第二步：在 App Store Connect 中创建应用

1. **访问**：https://appstoreconnect.apple.com
2. **登录**：相同的 Apple ID
3. **创建应用**：
   - 点击 "My Apps" → "+" → "New App"
   - **名称**：翻译应用
   - **Bundle ID**：com.example.translateApp
   - **SKU**：translate_app_001
   - **平台**：iOS

### ⚡ 第三步：上传 IPA 文件

**方法 1：使用自动化脚本**
```bash
./upload_to_testflight.sh "您的专用密码"
```

**方法 2：手动上传**
1. 在 App Store Connect 中选择您的应用
2. 点击 "App Store" → "+ New Release"
3. 点击 "Upload a new build"
4. 选择文件：`ios/translate_app.ipa`

### 👥 第四步：配置测试人员

1. 在 App Store Connect 中点击 "Test" 标签
2. 选择 "Internal Testing" 或 "External Testing"
3. 添加测试人员的 Apple ID
4. 提交审核

## 🎯 完成时间估计
- 创建应用专用密码：2分钟
- 创建 App Connect 应用：5分钟
- 上传和配置：10分钟
- **总计：约 17 分钟**

## 📞 如果遇到问题

### 常见错误：
1. **"请使用应用专用密码"** → 按第一步创建专用密码
2. **"Bundle ID 未找到"** → 在 App Store Connect 中先创建应用
3. **"上传失败"** → 检查网络连接和文件完整性

### 帮助资源：
- 查看 `APP_SETUP_INSTRUCTIONS.md` 获取详细说明
- 查看 `INSTALL_INSTRUCTIONS.md` 获取分发说明

## 🎉 完成标志
- ✅ 应用已上传到 TestFlight
- ✅ 测试人员已收到邀请邮件
- ✅ 应用可在 iPhone 上安装
