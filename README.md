# 拾题：错题积累 App

面向小学高年级至初中，计划支持 iOS 15.5 及以上。当前交付为产品设计、技术方案与使用模拟数据的 HTML Demo V2.4；尚无原生工程、可安装 IPA 或本项目 GitHub 构建。

## 项目入口

- [协作规范](AGENTS.md)：每次逻辑改动完成后必须提交 Git，并同步相关文档和变更记录。
- [产品设计](outputs/错题积累App-首版设计方案.md)：流程、状态、删除条件及原生验收要求。
- [技术栈复核与实现方案](outputs/技术栈复核与实现方案.md)：保留的技术栈、需细化的架构及开发边界。
- [Demo V2.4](outputs/shiti-demo-v2.4.html)：用电脑浏览器直接打开，不需要服务端。
- [演示使用说明](outputs/演示使用说明.md)与[功能合并说明](outputs/新版功能合并说明.md)。
- [变更记录](CHANGELOG.md)。

## 构建和检查 Demo

源文件在 `work/`，生成文件在 `outputs/`。建议使用 Node.js 22 或更高版本；本次以 Node.js 24 验证。

```powershell
node work/build-demo-v2.cjs
node --test work/verify-delete-rules.cjs work/verify-v24.cjs
node work/verify-demo-v2.cjs
```

旧的 `shiti-demo-v2*.html` 文件名为兼容入口，生成内容与最新文件相同；需要查看旧实现请使用 Git 历史。`verify-demo.cjs` 为早期留档，当前流程检查使用上面的入口。

## 正式 App 方向

SwiftUI + UIKit，Core Data 与本地图片文件，VisionKit 扫描、Vision 辅助 OCR，系统 PDF 与打印能力。核心无自建后端；可选模型服务不阻塞本地功能。蓝色配色与 Demo 保持一致，数据和业务规则按原生方式实现。

构建沿用 StudyBuddy 的交付路径：代码推送到已确认的 GitHub 仓库，在 macOS CI 编译，下载未签名 IPA 后自行重签侧载。已接入用户指定仓库 https://github.com/wenna/pickt ，原生代码在 feat/native-mvp 分支开发，macOS CI 先执行领域测试。当前仍无可交付 IPA，原生实现状态见 docs/native-progress.md。

## 本地版本管理

V2.4 基线已保存为独立提交，后续每个完成的逻辑改动均有独立提交。查看记录使用 `git log --oneline`，查看改动使用 `git show <提交号>`；撤回已提交改动优先使用新增 revert 提交。

不要提交真实试卷、个人学习资料、API 密钥和签名文件。`.gitignore` 已排除本地资料目录、密钥、证书、IPA 和常见构建产物；示例文件仍应人工确认只包含虚构内容。

## 原生开发

实施计划见 [原生实施计划](docs/superpowers/plans/2026-10-22-native-mvp.md)，当前状态见 [开发记录](docs/native-progress.md)。macOS / Xcode 环境执行 `swift test`；Windows 当前没有 Swift/Xcode，使用 GitHub Actions 执行。

首轮原生操作及实现边界见 [试用说明](docs/native-user-guide.md)。生成工程：`python3 scripts/generate_project.py`；macOS 编译：`xcodebuild -project Pickt.xcodeproj -scheme Pickt -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build`。CI 输出未签名 IPA，完整 App 编译状态以 Actions 记录为准。
