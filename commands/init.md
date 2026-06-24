---
name: "Init"
description: 初始化项目的 .claude/deploy.json 部署配置
category: Deploy
tags: [deploy, init, config, ldc]
---

初始化 `.claude/deploy.json` 部署配置文件。

## 编排流程

1. **检查已有配置**
   - `Read: .claude/deploy.json`
   - 已存在 → 展示内容，`AskUserQuestion` 询问是否覆盖：
     - 选项："覆盖重新配置"、"保留现有配置"
     - 选择保留 → 结束

2. **收集配置信息**
   - `AskUserQuestion`：项目名称（默认使用当前目录名）
   - `AskUserQuestion`：测试环境 App ID
   - `AskUserQuestion`：生产环境 App ID（可选，留空跳过）

3. **写入配置文件**
   - 写入 `.claude/deploy.json`：

```json
{
  "projectName": "<项目名>",
  "apps": {
    "test": {
      "appId": "<test-appId>",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    },
    "prod": {
      "appId": "<prod-appId>",
      "cloudUrl": "https://cloud.xuepeiyou.com/k8s-fe/appManage/appManageCenter/detail?id=<appId>"
    }
  }
}
```

   - 未提供生产 App ID 则不写 `apps.prod`
   - `cloudUrl` 中 `<appId>` 替换为实际值

4. **输出结果**
   - 展示写入的配置内容
   - 提示可以执行 `/ship test` 开始部署
