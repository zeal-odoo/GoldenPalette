// 启动检查界面：首次连接前显示检查卡片，进入工作台后保留简洁状态栏。
import SwiftUI

/// 通过绑定共享检查状态，网络与进程工作由注入的服务承担。
struct CodexStartupView<Content: View>: View {
    @Binding var state: CodexStartupState
    let configuration: AIConfiguration
    let check: CodexHealthChecker
    @ViewBuilder var content: (CodexConnectionBar) -> Content

    /// 配置与重试编号共同决定任务身份；SwiftUI 负责取消旧任务。
    private struct CheckIdentity: Equatable {
        let configuration: AIConfiguration
        let revision: UUID
    }

    /// 新配置尚未进入异步任务时也不能短暂显示旧配置的绿色通过状态。
    private var displayedPhase: CodexStartupPhase {
        state.configuration == configuration ? state.phase : .waiting
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.workspaceAvailable {
                content(CodexConnectionBar(phase: displayedPhase) {
                    if displayedPhase.isChecking {
                        state.continueInWorkspace(configuration: configuration)
                    } else {
                        state.retry()
                    }
                })
            } else {
                CodexStartupCard(
                    phase: displayedPhase, configuration: configuration,
                    retry: { state.retry() },
                    continueLocally: { state.continueInWorkspace(configuration: configuration) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 700, minHeight: 440)
                .background(AppPalette.canvas)
                .navigationTitle("调色谱")
            }
        }
        .task(id: CheckIdentity(configuration: configuration, revision: state.revision)) {
            await runCheck(configuration: configuration)
        }
    }

    /// 防抖配置编辑；请求完成后再次检查取消，避免旧配置响应覆盖新状态。
    @MainActor
    private func runCheck(configuration: AIConfiguration) async {
        guard let id = state.begin(configuration: configuration) else { return }
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            let report = try await check(configuration)
            try Task.checkCancellation()
            state.succeed(report, for: id)
        } catch is CancellationError {
            state.cancel(id)
        } catch {
            if Task.isCancelled {
                state.cancel(id)
            } else {
                state.fail(error.localizedDescription, for: id)
            }
        }
    }
}

/// 连接状态位于详情栏底部，侧栏折叠后仍可检查或取消连接。
struct CodexConnectionBar: View {
    let phase: CodexStartupPhase
    let performAction: () -> Void

    /// 通过后保留最后检查时间；失败和跳过仍可从工作台重试。
    var body: some View {
        HStack(spacing: 8) {
            if phase.isChecking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }
            Text(statusTitle)
                .font(.callout.weight(.medium))
                .fixedSize()
                .accessibilityIdentifier("codexConnectionStatus")
            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(statusDetail)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Divider().frame(height: 14)
            Button(phase.isChecking ? "取消检查" : "重新检查", action: performAction)
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityIdentifier(phase.isChecking ? "cancelCodexCheckButton" : "retryCodexCheckButton")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .workspaceControlCapsule()
    }

    private var statusTitle: String {
        switch phase {
        case .waiting, .checking: return "正在检查 Codex CLI…"
        case .ready: return "Codex 已连接"
        case .failed: return "Codex 检查未通过"
        case .skipped: return "Codex 尚未验证"
        }
    }

    private var statusDetail: String {
        switch phase {
        case .ready(let report):
            return "\(report.configuration.model.summary) · 检查于 \(report.checkedAt.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): return message
        case .waiting, .checking: return "使用当前模型验证连接，最多等待 90 秒。"
        case .skipped: return "可继续使用本地颜色库，准备好后重新检查。"
        }
    }

    private var statusSymbol: String {
        switch phase {
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch phase {
        case .ready: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }
}

/// 独立的展示组件，预览和失败场景不需要运行真实 CLI。
private struct CodexStartupCard: View {
    let phase: CodexStartupPhase
    let configuration: AIConfiguration
    let retry: () -> Void
    let continueLocally: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("调色谱", systemImage: AppPalette.librarySymbol)
                .font(.largeTitle.weight(.bold))
            if phase.isChecking {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在检查 Codex CLI…")
                        .font(.headline)
                        .accessibilityIdentifier("codexStartupProgress")
                }
                Text("正在验证账号与模型连接，最长约 90 秒。你可以先进入本地颜色库。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = phase {
                Label("Codex CLI 检查未通过", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("codexStartupFailure")
                ScrollView {
                    Text(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .accessibilityIdentifier("codexStartupError")
            }
            Text(configuration.model.summary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Divider()
            HStack {
                AISettingsLink()
                    .workspaceButton()
                Spacer()
                Button("先使用本地颜色库", action: continueLocally)
                    .workspaceButton(prominent: phase.isChecking)
                    .accessibilityIdentifier("continueWithoutCodexButton")
                if !phase.isChecking {
                    Button("重新检查", action: retry)
                        .workspaceButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("retryCodexCheckButton")
                }
            }
            .workspaceGlassGroup()
        }
        .padding(24)
        .frame(maxWidth: 528)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppPalette.outlineVariant) }
        .padding(24)
    }
}

/// 静态预览始终使用固定状态，打开 Canvas 不会发起模型请求。
#Preview("启动连接检查") {
    CodexStartupCard(phase: .checking, configuration: AIConfiguration(), retry: {}, continueLocally: {})
        .padding(30)
        .background(AppPalette.canvas)
}

#Preview("连接检查失败") {
    CodexStartupCard(
        phase: .failed("Codex 登录已失效或尚未登录。请在终端执行 codex login 后重试。"),
        configuration: AIConfiguration(), retry: {}, continueLocally: {}
    )
    .padding(30)
    .background(AppPalette.canvas)
}
