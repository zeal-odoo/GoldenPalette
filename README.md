# Golden 调色

用于记录项目颜色和生成丙烯颜料调色配方的 macOS 应用。

- 输入 RGB 或选择颜色，通过本机 Codex CLI 生成本色、阴影色、高光色配方。
- 固定使用 12 种 GOLDEN SoFlat 颜料，每种配方独立按 200 滴计算，列出颜料用量和调色步骤。
- 支持多个 RGB 按比例交给 AI 合成目标色；比例总和不足或超过 100% 时按相对权重处理。
- 按项目保存颜色和配方，支持单独删除颜色；查看配方和编辑颜色窗口采用毛玻璃背景。
- 在应用内的系统设置中配置模型、推理强度和 Codex CLI 路径。

## 安装和使用

系统要求为 macOS 12.7 或更新版本。发布的 Universal DMG 支持 Apple 芯片和 Intel Mac。

从 GitHub Releases 下载 DMG，将 `Golden调色.app` 拖入 `Applications`，退出磁盘映像后从“应用程序”打开。

AI 功能需要本机已安装并登录 Codex CLI。打开应用的“系统设置 → AI 配置”，填写当前账号可用的模型，必要时指定 CLI 路径。安装包不包含 Codex CLI 或登录凭据。

当前安装包使用 Apple Development 证书签名，尚未使用 Developer ID 签名或经过 Apple 公证；其他 Mac 可能显示安全验证提示或阻止打开。

AI 配方和屏幕色样仅供参考，实际颜料请先少量试调。

## 开发

使用 Xcode 打开 `Golden调色.xcodeproj`，在 Signing & Capabilities 中选择自己的开发团队，然后使用 `Golden调色` scheme 构建和运行。

`Golden调色 Release` 是共享的 Release scheme。生成通用安装包时，选择 `Any Mac (arm64, x86_64)` 构建目标。

单元测试位于 `Golden调色Tests`，界面测试位于 `Golden调色UITests`，可在 Xcode 中执行。AI 服务测试使用固定数据和模拟 CLI，不需要调用真实模型。

版本号由项目的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 管理。每次应用迭代递增版本号和构建号；DMG 与校验文件存放在不纳入 Git 的 `dist/` 目录，通过 GitHub Releases 分发。
