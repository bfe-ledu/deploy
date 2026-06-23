---
name: "Init"
description: 初始化项目的 .claude/deploy.json 部署配置
disable-model-invocation: true
category: Deploy
tags: [deploy, init, config, ldc]
---

初始化项目的部署配置文件 `.claude/deploy.json`。

**输入**: 无参数

**步骤**

1. **检查配置是否已存在**

   读取当前项目根目录的 `.claude/deploy.json`：
   - 已存在 → 展示当前配置内容，使用 AskUserQuestion 询问是否覆盖
     - 用户选择不覆盖 → 中止
   - 不存在 → 继续

2. **收集项目信息**

   使用 AskUserQuestion 依次收集：
   - 项目名称（默认使用当前目录名）
   - 测试环境 App ID（从未来云项目管理页 URL 中获取）
   - 生产环境 App ID（可选，输入 "无" 则跳过）

3. **生成配置文件**

   创建 `.claude/deploy.json`，内容格式：

   ```json
   {
     "projectName": "<用户输入的项目名>",
     "apps": {
       "test": {
         "appId": "<用户输入的测试 App ID>",
         "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
       },
       "prod": {
         "appId": "<用户输入的生产 App ID>",
         "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
       }
     }
   }
   ```

   如果用户未提供生产 App ID，则 `apps.prod` 部分不写入。

4. **展示结果**

   - 输出配置摘要（项目名、各环境 appId）
   - 提示 "配置已生成，现在可以使用 `/ship test` 部署测试环境"

**护栏**
- 不自动覆盖已有配置
- cloudUrl 中的 `<appId>` 替换为实际 App ID
