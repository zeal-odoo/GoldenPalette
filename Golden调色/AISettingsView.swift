// macOS AI 设置界面，以及兼容不同系统版本的设置入口。
import SwiftUI
import AppKit

/// 通过绑定修改应用级配置，持久化由应用根节点处理。
struct AISettingsView: View {
    @Binding var configuration: AIConfiguration

    /// 编辑模型、推理强度和 CLI 路径，并即时展示本地配置校验结果。
    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                settingsForm.formStyle(.grouped)
            } else {
                ScrollView { settingsForm.padding(24) }
            }
        }
        .frame(width: 520, height: 432)
        .navigationTitle("AI 配置")
    }

    private var settingsForm: some View {
        Form {
            Section {
                TextField("模型 ID", text: $configuration.model.modelID)
                    .accessibilityIdentifier("aiModelField")
                if !configuration.isValid {
                    Text("模型 ID 不能为空。")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Picker("推理强度", selection: $configuration.model.reasoningEffort) {
                    ForEach(AIReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .workspaceMenuPicker()
                .accessibilityIdentifier("aiReasoningPicker")
                Text(configuration.model.reasoningEffort.generationWaitDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("恢复默认模型和强度") {
                    configuration.model = AIModelSelection()
                }
                .accessibilityIdentifier("resetAIModelButton")
            } header: {
                Text("生成参数")
            } footer: {
                Text("设置适用于所有项目，修改后自动保存。")
            }

            Section {
                HStack {
                    TextField("可执行文件", text: $configuration.executablePath, prompt: Text("自动查找或输入完整路径"))
                        .accessibilityIdentifier("codexPathField")
                    Button("选择…", action: chooseExecutable)
                        .workspaceButton()
                }
                Text(CodexMixingService.executableURL(customPath: configuration.executablePath)?.path ?? "尚未找到 Codex CLI")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Codex CLI")
            } footer: {
                Text("首次使用时，在终端运行 codex login 登录。")
            }
        }
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
