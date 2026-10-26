# Crop Interaction Repair Implementation Plan

> Use superpowers:executing-plans for the existing interaction repair; the larger capture/answer redesign remains a proposal.

**Goal:** 修复用户视频中框选不能移动或缩放的问题，保留 iOS 15.5、原图和已有数据规则。

**Architecture:** PicktCore 的纯坐标交互负责创建/移动/八方向缩放与边界约束；UIKit CropSurface 负责手势、缩放坐标转换和手柄显示。MaskEditor 继续使用仅重画选区模式。

**Scope:** 此修复属于已确认手动框选功能；不接入云端，不上传视频或试卷，不宣称自动分题/答案识别已完成。

## Tasks

- [ ] 先写移动、边界钳制、八方向缩放、反向重画、最小范围和整页初始框的行为测试。
- [ ] 实现纯 Swift 交互会话，手势期间保留初始快照以避免累计偏移。
- [ ] 接入 CropSurface，显示可拖动手柄，保护拖动中选区不被 SwiftUI 旧值覆盖，取消手势恢复原框。
- [ ] 更新提示，支持重置；遮盖画布明确为仅重画模式，避免整图无法选择局部遮盖。
- [ ] 运行 macOS 领域/存储测试及设备/模拟器编译，记录未做真实触控验收的限制。
- [ ] 同步设计、原生使用说明、技术方案、CHANGELOG，提交并上传开发分支。

## Review focus

整页初始选区内部仍能重画；手柄触控范围按屏幕点转换；框不能越出原图；缩放后坐标仍归一化；从纸外空白开始不创建错误选区；换页/旋转/遮盖不复用错误变换。Windows 没有 Swift 编译器，不伪称本地执行过 RED/GREEN；以实际 CI 为准。
