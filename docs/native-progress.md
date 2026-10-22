# 原生开发记录

## 2026-10-22 开始实现

- 依据已确认设计与 Demo V2.4，在 `feat/native-mvp` 分支实现。
- 用户提供 GitHub 仓库 `https://github.com/wenna/pickt`，已读取其现有 main 分支标识；接入时保留远程历史。
- 当前 Windows 没有 Swift/Xcode，也没有 gh 命令。本地不冒充原生编译验证；使用 macOS CI 执行真正的 Swift 测试与 Xcode 构建。
- 技能：使用 writing-plans 和 executing-plans 按任务实现，沿用测试先行与完成前验证；最终做一次独立只读审查。
- 执行取舍：当前干净仓库使用开发分支隔离，不额外创建工作树，避免引入第二份未配置的工作目录。
- 当前状态：计划已记录，原生功能尚待实现。
