# Native MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 实现可构建、可侧载的原生本地核心版本，逐步落实 V2.4 已确认流程。

**Architecture:** SwiftUI 页面调用可测试的纯 Swift 领域用例；Core Data 事务保存元数据，文件库保留原图/片段。系统扫描、OCR、PDF 与分享单独封装，所有批改先进入草稿再确认。

**Tech Stack:** Swift、SwiftUI/UIKit、Core Data、VisionKit/Vision、PDFKit、GitHub macOS CI；iOS 15.5。

**Spec:** `outputs/错题积累App-首版设计方案.md`、`outputs/技术栈复核与实现方案.md`。

## Global Constraints

- 最低 iOS 15.5；首开空库，蓝色主题，本地可用，不接必需的付费模型。
- 暂未做不等于尚未重做；单个/批量删除共用规则，整批校验，软删除可恢复。
- 历史题图快照不变；批改幂等、草稿可恢复；卷名、UUID、序号分别保存。
- 提交时更新文档和变更记录；当前 Windows 无 Swift/Xcode，以真实 macOS CI 输出判断编译和测试。
- 在当前干净仓库的 `feat/native-mvp` 分支实现，保留 main 基线，不另建工作树；不重写远程已有历史。

## Review Focus

- 保存失败后 UI 和内存不能显示成功，原数据仍可读取。
- 确认框打开后出现新草稿，批量删除必须整批拒绝。
- 题图路径或备份包损坏不能读写应用目录外文件。
- 重新排版和旧卷拍照使用不同布局版本时不能静默匹配。
- 没有参考答案、字迹不清或不支持题型时不得伪造自动判对。

## File Structure

- `Sources/PicktCore/`：值模型、筛选、状态、事务式领域变更、有限答案比较。
- `Tests/PicktCoreTests/`：领域的真实行为测试。
- `Sources/PicktPersistence/`：Core Data 存储和文件/备份校验。
- `Tests/PicktPersistenceTests/`：持久化失败、恢复及损坏输入。
- `PicktApp/`：原生页面、扫描/框选、OCR、PDF/打印与家长设置。
- `scripts/`：可重复生成 Xcode 工程、检查配置及打包。
- `.github/workflows/ios.yml`：Swift 测试、设备构建、IPA 与清单。
- `docs/native-progress.md`：执行记录、真实验证与尚未完成的能力。

### Task 1: 领域规则与可执行测试

**Interfaces:** `StudyLibrary` 为 Codable 值快照；`LibraryCommands` 在临时副本上执行变更，成功后返回新快照。`Question`、`Paper`、`GradingDraft`、`ResultEvent` 保存独立标识。

- [x] 先写 XCTest：空库/编号、筛选 OR/AND、最近结果、删除限制/整批失败、草稿阻止删除、确认幂等、快照不被题库修改。
- [x] 在 macOS CI 上确认测试先失败，再补实现；本机缺 Swift 时明确记录，不能声称本地通过。
- [x] 创建 Swift Package 和仅测试的初始 CI，使用已核查的 macos-15 / Xcode 16.4。
- [x] 运行 `swift test`；Expected: 所有领域测试通过。
- [x] 更新进度和变更记录，提交独立 commit。

### Task 2: 持久化与图片/备份

**Interfaces:** `LibraryRepository.load/save`；Core Data 单次保存整个变更；`AssetStore` 只允许受控 UUID 文件名；版本化备份包含所有引用资源及校验值。

- [x] 测试保存/重载、失败保留旧值、未知备份版本和路径逃逸拒绝、图片损坏拒绝恢复。
- [x] 实现 Core Data 元数据记录、临时图片提交、备份先校验再替换，恢复前输出旧库备份。
- [x] 运行 `swift test`；Expected: 领域和数据层测试通过。
- [x] 更新文档、提交。

### Task 3: 原生收题与错题本

**Interfaces:** `AppStore` 串行提交领域快照并在持久化成功后发布；图像来源采用扫描/相册，框选输出归一化片段。

- [x] 原生工程和空库三标签页，iOS 15.5 导航、主题、错误提示与加载失败保护。
- [x] 真扫描/相册导入、缩放后框选、多个片段、旋转、手动遮盖/撤销、原卷关联。
- [x] 分类建议来源、多选知识点/错因、自填目录、搜索和筛选、题图详情与历史、单个/批量删除和恢复。
- [x] Xcode 设备/模拟器编译；Expected: 编译成功，不使用新系统专属 API。
- [x] 更新实际能力表、提交。

### Task 4: 原生组卷、PDF 和核对

**Interfaces:** `PaperLayout` 固定题目顺序、留白和页坐标；`GradingDraft` 绑定布局 ID，保存完成卷照片及逐题识别/人工判断。

- [x] 手动/推荐选题、组合筛选、保留隐藏已选、独立卷列表/管理、默认名与改名。
- [x] 实现图片题 PDF、分页/留白、学生及家长页分纸、双面补白、预览/打印/分享、布局版本。
- [x] 完成卷拍摄、显式选择对应布局和作答区、真实 OCR 建议、人工逐题核对、草稿暂存、统一确认及结果历史。
- [ ] PDF 页段的独立原生自动化测试尚未补齐；有限数值/未知答案、历史快照与原生构建已经验证。纸面分页继续待验收。
- [x] 更新文档、提交。

### Task 5: CI 产物与复核

- [x] 工程共享 scheme、固定部署版本、确定 App 路径；未签名 IPA、版本/提交/工具链清单与 SHA-256。
- [x] 推送到用户指定的 `https://github.com/wenna/pickt`，保留远程初始化内容，不强推。
- [x] 跟踪 CI，修复实际编译/测试失败，确认下载产物对应提交。
- [x] 按 executing-plans 的最终审查要求请求一次只读代码审查，处理重要问题，再跑完整验证。
- [x] 交付实际状态、提交号与 Actions 下载入口；未验证的 iOS 15.5 真机/扫描/打印效果明确列出。

## 首轮收尾状态

代码完成项表示已实现，真机验收另列，不由勾选代替。9fdccf3 的 25 项测试、设备及模拟器编译与启动截图通过，IPA 已下载核验。完整记录与仍未实现功能见 ../../native-progress.md。先交付首轮试用包，保留开发分支；不自动合并 main。
