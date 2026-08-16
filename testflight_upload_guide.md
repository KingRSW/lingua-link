# TestFlight 上传完整指南

## 问题分析

从上传日志中可以看出两个主要问题：

1. **认证失败**: "Please sign in with an app-specific password"
   - 当前的密码不是Apple应用专用密码

2. **Bundle ID未注册**: "Could not determine provider public id from Bundle ID 'com.example.translateApp'"
   - 该Bundle ID在App Store Connect中不存在对应的app

## 解决方案

### 第一步：创建Apple应用专用密码

1. 访问 https://appleid.apple.com
2. 登录你的Apple ID (quanwei_114514@qq.com)
3. 进入"安全"部分
4. 创建应用专用密码，选择App Store Connect作为应用
5. 保存生成的16位密码

### 第二步：在App Store Connect中创建应用

1. 访问 https://appstoreconnect.apple.com
2. 使用相同的Apple ID登录
3. 点击"+ 创建App"
4. 选择Bundle ID: com.example.translateApp
5. 创建iOS应用
6. 配置基本信息

### 第三步：重新上传

创建完成后，使用以下命令上传：

```bash
./upload_to_testflight.sh "新的应用专用密码"
```

## 重要提醒

- 当前密码"Wsc-15689"可能是普通密码，不是应用专用密码
- 应用专用密码必须在Apple ID安全设置中创建
- 必须先在App Store Connect中创建应用，才能上传ipa文件

## 验证步骤

上传成功后，应用将出现在App Store Connect中，然后：
1. 添加测试人员邮箱
2. 构建版本
3. 提交审核
4. 发布到TestFlight

