// macOS AI 设置界面，以及兼容不同系统版本的设置入口。
import SwiftUI
import AppKit

/// 通过绑定修改应用级配置，持久化由应用根节点处理。
struct AISettingsView: View {
    @Binding var configuration: AIConfiguration

    /// 编辑模型、推理强度和 CLI 路径，并即时展示本地配置校验结果。
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Label("AI 配置", systemImage: "sparkles")
                    .font(.title2.weight(.semibold))
                Text("所有项目共用，修改后自动保存，下次生成时生效。")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("模型 ID").font(.headline)
                TextField("输入 Codex 可用的模型 ID", text: $configuration.model.modelID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("aiModelField")
                Text("可自由输入模型名称，使用当前 Codex 账户可访问的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !configuration.isValid {
                    Text("模型 ID 不能为空。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("推理强度", selection: $configuration.model.reasoningEffort) {
                    ForEach(AIReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .accessibilityIdentifier("aiReasoningPicker")
                Text("支持的强度取决于模型；不确定时可选“模型默认”。\n\(configuration.model.reasoningEffort.generationWaitDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("恢复默认模型和强度") {
                    configuration.model = AIModelSelection()
                }
                .accessibilityIdentifier("resetAIModelButton")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Codex CLI").font(.headline)
                HStack {
                    TextField("自动查找，或填写完整路径", text: $configuration.executablePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("codexPathField")
                    Button("选择…", action: chooseExecutable)
                }
                Text(CodexMixingService.executableURL(customPath: configuration.executablePath)?.path ?? "尚未找到 Codex CLI")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("使用 Codex CLI 的登录账户。首次使用请先在终端执行 codex login。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 520)
        .navigationTitle("系统设置")
    }

    /// 选择单个 CLI 可执行文件，只保存路径，不在设置界面启动进程。
    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex CLI 可执行文件"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                configuration.executablePath = url.path
            }
        }
    }
}

/// 为主界面提供统一的系统设置按钮。
struct AISettingsLink: View {
    /// 新系统使用原生 SettingsLink，旧系统按版本发送对应设置窗口动作。
    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Label("系统设置", systemImage: "gearshape")
                }
            } else {
                Button {
                    let action = if #available(macOS 13.0, *) {
                        "showSettingsWindow:"
                    } else {
                        "showPreferencesWindow:"
                    }
                    NSApp.sendAction(Selector(action), to: nil, from: nil)
                } label: {
                    Label("系统设置", systemImage: "gearshape")
                }
            }
        }
        .help("AI 配置：模型、推理强度与 Codex CLI")
        .accessibilityIdentifier("aiSettingsButton")
    }
}
