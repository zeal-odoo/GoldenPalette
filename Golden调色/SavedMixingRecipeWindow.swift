import SwiftUI
import AppKit

final class SavedMixingRecipeWindowController: NSWindowController, NSWindowDelegate {
    let itemID: UUID
    let colorID: UUID
    let recipe: MixingRecipe

    private var onClose: (SavedMixingRecipeWindowController) -> Void = { _ in }

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
            styleMask: [.titled, .closable],
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
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Keep the native title-bar background, just like the color editor.
        panel.titlebarAppearsTransparent = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: SavedMixingRecipeWindowContent(recipe: recipe) { [weak self] in
                self?.close()
            }
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.setContentSize(SavedMixingRecipeWindowContent.contentSize)
        panel.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        let closeAction = onClose
        onClose = { _ in }
        closeAction(self)
    }
}

struct SavedMixingRecipeWindowContent: View {
    static let contentSize = NSSize(width: 620, height: 680)

    let recipe: MixingRecipe
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(recipe.role.title) · 200 滴配方").font(.headline)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recipe.formattedText, forType: .string)
                }
                .accessibilityIdentifier("copySavedMixingRecipeButton")
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("closeSavedMixingRecipeButton")
            }
            .padding(20)

            Divider()

            ScrollView {
                MixingRecipeDetails(recipe: recipe)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("savedMixingRecipeScrollView")
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(FrostedWindowBackground())
    }
}
