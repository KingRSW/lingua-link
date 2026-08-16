# App Store Connect 应用设置指南

## 步骤 1：创建应用专用密码

### 1.1 访问 Apple ID 管理页面
1. 打开浏览器访问：https://appleid.apple.com
2. 登录您的 Apple ID：quanwei_114514@qq.com
3. 输入密码：Wsc-15689

### 1.2 创建专用密码
1. 点击"密码与安全性"
2. 选择"生成密码"
3. 输入您的 Apple ID 密码
4. 为密码命名："TestFlight 分发"
5. 保存生成的密码（格式：XXXX-XXXX-XXXX-XXXX）

## 步骤 2：在 App Store Connect 中创建应用

### 2.1 登录 App Store Connect
1. 访问：https://appstoreconnect.apple.com
2. 使用相同的 Apple ID 登录
3. 提供两步验证码（如果需要）

### 2.2 创建新应用
1. 点击 "My Apps"
2. 点击 "+" 号
3. 选择 "New App"
4. 填写以下信息：
   - **名称**：翻译应用
   - **Bundle ID**：com.example.translateApp
   - **SKU**：translate_app_001
   - **平台**：iOS
   - **初级语言**：简体中文

### 2.3 配置应用信息
1. **基本信息**：
   - 主副标题：翻译应用
   - 隐私政策：添加您的隐私政策链接
   - 应用分类：工具类

2. **屏幕截图**：
   - 添加应用截图（至少1张）
   - 尺寸要求：1242x2208 或 1242x2688

3. **应用描述**：
   - 详细描述翻译应用的功能和特点
   - 支持的版本信息

## 步骤 3：上传 IPA 文件

### 3.1 使用命令行上传
```bash
# 使用您创建的专用密码
xcrun altool --upload-app --type ios --file ios/translate_app.ipa --username quanwei_114514@qq.com --password "您的专用密码"
```

### 3.2 手动上传
1. 在 App Store Connect 中选择您的应用
2. 点击 "App Store" 标签
3. 点击 "+ New Release"
4. 点击 "Upload a new build"
5. 选择 IPA 文件：ios/translate_app.ipa

## 步骤 4：配置 TestFlight 测试

### 4.1 添加测试人员
1. 点击 "Test" 标签
2. 选择 "Internal Testing" 或 "External Testing"
3. 添加测试人员的 Apple ID

### 4.2 发布测试版本
1. 等待构建处理完成
2. 提交审核
3. 测试人员会收到邀请邮件

## 步骤 5：测试人员安装

### 5.1 安装 TestFlight
测试人员需要：
1. 在 iPhone 上安装 TestFlight
2. 检查邮件中的邀请链接
3. 点击链接下载应用

### 5.2 应用安装
1. 在 TestFlight 中点击"安装"
2. 等待下载完成
3. 在 iPhone 主屏幕找到应用图标

## 常见问题解决

### 问题 1：上传失败
- 检查应用专用密码是否正确
- 确保 Bundle ID 与创建的应用一致
- 检查应用信息是否完整

### 问题 2：测试无法安装
- 确保测试人员安装了最新版本的 TestFlight
- 检查邀请是否已发送
- 确保应用审核通过

### 问题 3：签名错误
- 确保 IPA 文件已正确签名
- 检查证书是否有效
- 验证构建过程是否完整

## 完成检查清单

- [ ] 创建应用专用密码
- [ ] 在 App Store Connect 中创建应用
- [ ] 上传 IPA 文件
- [ ] 配置 TestFlight 测试
- [ ] 添加测试人员
- [ ] 发布测试版本
- [ ] 测试人员安装应用
