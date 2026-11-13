// 应用级启动检查状态：多个窗口共享结果，并用请求编号排除过期回调。
import Foundation

/// 界面阶段与真实检查结果分开建模；跳过检查不能显示为连接成功。
enum CodexStartupPhase: Equatable {
    case waiting
    case checking
    case ready(CodexHealthReport)
    case failed(String)
    case skipped

    var isChecking: Bool { self == .waiting || self == .checking }
}

/// 由 App 的 @State 持有，普通窗口刷新不会重复发起检查。
struct CodexStartupState {
    private(set) var phase: CodexStartupPhase = .waiting
    private(set) var configuration: AIConfiguration?
    private(set) var revision = UUID()
    private(set) var workspaceAvailable = false
    private(set) var activeCheckID: UUID?

    /// 相同配置只允许一个窗口取得检查权；配置改变后原结果立即失效。
    mutating func begin(configuration: AIConfiguration) -> UUID? {
        guard self.configuration != configuration || phase == .waiting else { return nil }
        self.configuration = configuration
        let id = UUID()
        activeCheckID = id
        phase = .checking
        return id
    }

    /// 只有仍在进行的请求能解锁工作台，已取消或旧配置的结果会被忽略。
    mutating func succeed(_ report: CodexHealthReport, for id: UUID) {
        guard activeCheckID == id else { return }
        activeCheckID = nil
        phase = .ready(report)
        workspaceAvailable = true
    }

    /// 保留可操作的失败原因；已进入工作台时不销毁正在编辑的视图。
    mutating func fail(_ message: String, for id: UUID) {
        guard activeCheckID == id else { return }
        activeCheckID = nil
        phase = .failed(message)
    }

    /// 刷新任务身份触发重试，同时使上一请求的延迟回调失效。
    mutating func retry() {
        activeCheckID = nil
        phase = .waiting
        revision = UUID()
    }

    /// 允许离线使用颜色库；主动取消尚未完成的检查，保留已有失败信息。
    mutating func continueInWorkspace(configuration: AIConfiguration) {
        self.configuration = configuration
        activeCheckID = nil
        if phase.isChecking { phase = .skipped }
        workspaceAvailable = true
        revision = UUID()
    }

    /// 拥有检查任务的窗口关闭时释放检查权，其他窗口可接续一次新检查。
    mutating func cancel(_ id: UUID) {
        guard activeCheckID == id else { return }
        retry()
    }
}
