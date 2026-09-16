# macOS 客户端架构与实施计划

## 目标

客户端定位为 MailEdge 的原生日常收发入口：启动快、支持多信箱、阅读安全、写信顺手，同时继续让 Web 管理后台承载低频且敏感的服务端设置。

第一版不复制服务端业务逻辑。邮件存储、权限、渠道选择、失败重试、Markdown 转换和智能附件仍由 Worker 决定，macOS 端只维护视图状态并调用 API。

## 数据流

```text
SwiftUI Views
    │ 用户操作 / 状态绑定
    ▼
AppStore（@MainActor）
    │ 页面状态、请求竞态保护、错误与会话流转
    ▼
APIClient（actor）
    │ URLSession + HttpOnly Cookie + Codable
    ▼
MailEdge Worker /api
    ├── D1：账户、渠道与发送状态
    ├── Durable Objects：信箱和邮件
    └── R2 / KV：附件与归档正文
```

## 目录

```text
app/
├── Package.swift
├── Sources/MailEdgeApp/
│   ├── MailEdgeApp.swift          # App 生命周期、菜单与窗口
│   ├── Design/GlassStyle.swift    # Liquid Glass / 旧系统材质回退
│   ├── Models/MailModels.swift    # 与 Worker JSON 对齐的 Codable 模型
│   ├── Networking/APIClient.swift # URL、Cookie、HTTP、上传和下载
│   ├── State/AppStore.swift       # 单一 UI 状态与业务编排
│   └── Views/                     # 登录、三栏工作台、详情和写信
├── Tests/MailEdgeAppTests/
├── Resources/Info.plist
└── Scripts/build-app.sh
```

## API 映射

| 客户端能力 | 方法与路径 | 当前状态 |
| --- | --- | --- |
| 实例探测 | `GET /api/health` | 已接入 |
| 判断首次初始化 | `GET /api/auth/setup` | 已接入 |
| 创建管理员 | `POST /api/auth/setup` | 已接入 |
| 密码登录 | `POST /api/auth/login` | 已接入 |
| 恢复会话 | `GET /api/auth/me` | 已接入 |
| 退出 | `POST /api/auth/logout` | 已接入 |
| 自定义文件夹 | `GET /api/folders` | 已接入读取 |
| 文件夹统计 | `GET /api/stats?mailboxId=` | 已接入 |
| 邮件列表/搜索/分页 | `GET /api/messages` | 已接入 |
| 邮件详情 | `GET /api/messages/:id` | 已接入 |
| 已读、星标、移动 | `PATCH /api/messages/:id` | 已接入 |
| 全部已读 | `POST /api/messages/read-all` | 已接入 |
| 删除/永久删除 | `DELETE /api/messages/:id` | 已接入 |
| 附件暂存 | `POST /api/mail/attachment` | 已接入 |
| 清理暂存附件 | `DELETE /api/mail/attachment/:token` | 已接入 |
| 发信 | `POST /api/mail/send` | 已接入 |
| 下载收到的附件 | `GET /api/messages/:id/attachments/:attachmentId` | 已接入 |
| WebSocket 新信通知 | `GET /api/mailboxes/:id/stream` | 下一阶段；当前 60 秒轮询 |
| AI 回复/总结/分类 | `/api/ai/messages/...` | 下一阶段 |
| 发件箱与失败重试 | `/api/mail/outbox...` | 下一阶段 |
| 信箱、渠道、AI、存储管理 | 现有设置 API | 保留 Web 管理后台入口 |

## UI 结构

主窗口使用 `NavigationSplitView`：

1. 左栏：品牌、写信、信箱选择、系统/自定义文件夹和账户入口。
2. 中栏：当前范围、搜索、刷新、全部已读、分页邮件列表。
3. 右栏：邮件动作、信头、安全正文、AI 摘要（已有缓存时）和附件。

Liquid Glass 策略：

- macOS 26+：使用 `glassEffect` 和 Glass button style。
- macOS 15–25：使用 `ultraThinMaterial`、描边、柔和阴影和渐变背景。
- 所有内容保持系统动态字体、键盘操作和浅/深色自适应。

## 会话与安全边界

- Session 不写入 `UserDefaults`，由 `URLSession` 的 Cookie 存储接收 HttpOnly Cookie。
- 本地只保存服务器根地址。
- HTML 邮件使用非持久化 `WKWebsiteDataStore`，禁用 JavaScript。
- Content Security Policy 默认阻止网络、脚本、frame、表单和远程图片；用户点击链接后交给默认浏览器。
- 附件下载仍通过客户端的已登录 `URLSession`，不会把会话暴露给浏览器。
- APIClient 限制附件 URL 与当前服务端同 host，避免携带会话请求第三方地址。

## 迭代计划

### 阶段 1：可用原生客户端（已完成）

- SwiftUI 工程、三栏 UI、Liquid Glass 兼容层
- 连接、初始化、密码登录与会话恢复
- 邮件列表、详情、搜索、分页和主要状态操作
- Markdown 写信、回复、抄送/密送、附件上传与下载
- 单元测试与 `.app` 本地打包脚本

### 阶段 2：实时与智能能力

- 为所选信箱建立 `URLSessionWebSocketTask`，监听 `new_message`
- 保留轮询作为断线兜底，并在睡眠唤醒后恢复连接
- 接入 AI 总结、AI 回复与重新分类
- 增加发件箱、deferred/failed 状态和手动重试

### 阶段 3：macOS 深度集成

- `UNUserNotificationCenter` 新信通知和通知点击定位
- Dock 未读角标、菜单栏快速写信、Spotlight 搜索
- Keychain 保存可选的多实例配置；支持实例快速切换
- Passkey 登录（AuthenticationServices + 现有 WebAuthn challenge API）

### 阶段 4：发布

- AppIcon、品牌资源与本地化
- Xcode Release 配置、Developer ID 签名、Hardened Runtime
- Notarization、Sparkle 更新或 Mac App Store 分发策略
- API 契约测试、UI 测试、断网/过期会话/大附件专项测试

## 服务端建议

当前第一版不要求修改 Worker。后续为了原生客户端体验，可以新增但不破坏 Web 端的能力：

- 提供聚合信箱 WebSocket 入口，避免客户端为每个信箱各建连接。
- 给 `/api/health` 增加稳定的 `apiVersion` 和 `capabilities`，客户端可做版本协商。
- 为原生 Passkey 增加明确的关联域与 Universal Links 文档。
- 为邮件列表返回 ETag 或增量游标，减少定时刷新流量。
