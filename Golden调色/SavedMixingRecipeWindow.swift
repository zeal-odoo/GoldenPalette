// 已保存配方的独立浮动窗口，使用结果快照展示用量和步骤，不重新调用 AI。
import SwiftUI
import AppKit

/// 以项目和颜色 UUID 关联主界面，供数据变更时检查窗口是否仍有效。
final class SavedMixingRecipeWindowController: NSWindowController, NSWindowDelegate {
    let itemID: UUID
    let colorID: UUID
    /// 打开窗口时的配方快照，历史来源不会随当前设置改变。
    let recipe: MixingRecipe

    private var onClose: (SavedMixingRecipeWindowController) -> Void = { _ in }

    /// 创建可拖动的原生浮动面板，并嵌入复用的 SwiftUI 配方详情。
    init(
        itemID: UUID,
        colorID: UUID,
        projectName: String,
        recipe: MixingRecipe,
        onClose: @escaping (SavedMixingRecipeWindowController) -> Void
    ) {
        self.itemID = itemID
        self.colorID = colorID
        self.recipe = recipe
        let panel = DraggableGlassPanel(
            contentRect: NSRect(origin: .zero, size: SavedMixingRecipeWindowContent.contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        self.onClose = onClose

        panel.delegate = self
        panel.title = "\(recipe.role.title)配方 · \(projectName)"
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]

        // 单层磨砂铺到标题栏下方，由 WindowServer 直接采样浮窗后面的内容。
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        panel.contentView = backdrop

        let hostingView = NSHostingView(
            rootView: SavedMixingRecipeWindowContent(recipe: recipe) { [weak self] in
                self?.close()
            }
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(hostingView)
        let contentGuide = panel.contentLayoutGuide as? NSLayoutGuide ?? backdrop.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
        panel.contentMinSize = NSSize(width: 420, height: 360)
        panel.setContentSize(SavedMixingRecipeWindowContent.contentSize)
        panel.center()
    }

    /// 此窗口仅通过代码创建，不支持从归档或 Storyboard 恢复。
    required init?(coder: NSCoder) {
        nil
    }

    /// 关闭时只通知一次并释放回调，让持有者清除窗口控制器引用。
    func windowWillClose(_ notification: Notification) {
        let closeAction = onClose
        onClose = { _ in }
        closeAction(self)
    }
}

/// 已存配方窗口内容，复用调色结果的详情组件。
struct SavedMixingRecipeWindowContent: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    static let contentSize = NSSize(width: 620, height: 680)

    let recipe: MixingRecipe
    let onClose: () -> Void

    /// 顶部提供复制与关闭，正文独立滚动以容纳长步骤。
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(recipe.role.title) · \(recipe.preparedTotalDrops) 滴配方").font(.headline)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recipe.formattedText, forType: .string)
                }
                .workspaceButton()
                .accessibilityIdentifier("copySavedMixingRecipeButton")
                Button("关闭", action: onClose)
                    .workspaceButton()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("closeSavedMixingRecipeButton")
            }
            .workspaceGlassGroup()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                MixingRecipeDetails(recipe: recipe)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
            .accessibilityIdentifier("savedMixingRecipeScrollView")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(reduceTransparency ? AppPalette.canvas : Color.clear)
    }
}
