import SwiftData
import SwiftUI

/// Independent Gate 7 prototype wrapper. Gate 8 can connect it to the main
/// window without changing the existing list implementation or action owners.
struct WorkspaceContentView<ListContent: View, Menu: View, Palette: View>: View {
    let mode: WorkspaceLayoutMode
    let items: [ClipItem]
    let selectedItemIDs: Set<PersistentIdentifier>
    let focusedItemID: PersistentIdentifier?
    let showCommandPalette: Bool
    let onTap: (PersistentIdentifier) -> Void
    let onNavigate: (PersistentIdentifier) -> Void
    let onColumnCountChange: (Int) -> Void
    let onCommandPaletteDismiss: () -> Void
    let onLoadMore: () -> Void
    @ViewBuilder let listContent: () -> ListContent
    @ViewBuilder let contextMenu: (ClipItem) -> Menu
    @ViewBuilder let commandPalette: (ClipItem) -> Palette

    var body: some View {
        switch mode {
        case .list:
            listContent()
        case .cards:
            MixedClipboardGrid(
                items: items,
                selectedItemIDs: selectedItemIDs,
                focusedItemID: focusedItemID,
                showCommandPalette: showCommandPalette,
                onTap: onTap,
                onNavigate: onNavigate,
                onColumnCountChange: onColumnCountChange,
                onCommandPaletteDismiss: onCommandPaletteDismiss,
                onLoadMore: onLoadMore,
                contextMenu: contextMenu,
                commandPalette: commandPalette
            )
        }
    }
}

struct MixedClipboardGrid<Menu: View, Palette: View>: View {
    let items: [ClipItem]
    let selectedItemIDs: Set<PersistentIdentifier>
    let focusedItemID: PersistentIdentifier?
    let showCommandPalette: Bool
    let onTap: (PersistentIdentifier) -> Void
    let onNavigate: (PersistentIdentifier) -> Void
    let onColumnCountChange: (Int) -> Void
    let onCommandPaletteDismiss: () -> Void
    let onLoadMore: () -> Void
    @ViewBuilder let contextMenu: (ClipItem) -> Menu
    @ViewBuilder let commandPalette: (ClipItem) -> Palette

    private var trailingIDs: Set<PersistentIdentifier> {
        Set(items.suffix(12).map(\.persistentModelID))
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = WorkspaceGridMetrics.columnCount(for: geometry.size.width)
            let gridColumns = Array(
                repeating: GridItem(
                    .flexible(minimum: 0),
                    spacing: WorkspaceGridMetrics.spacing,
                    alignment: .top
                ),
                count: columns
            )
            let visualItems = WorkspaceGridOrdering.visualOrder(for: items)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: gridColumns,
                        alignment: .leading,
                        spacing: WorkspaceGridMetrics.spacing
                    ) {
                        ForEach(visualItems, id: \.persistentModelID) { item in
                            card(for: item)
                        }
                    }
                    .padding(.horizontal, WorkspaceGridMetrics.horizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: focusedItemID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
                .onMoveCommand { direction in
                    guard let mapped = navigationDirection(direction),
                          let target = WorkspaceGridNavigation.neighbor(
                            in: visualItems.map(\.persistentModelID),
                            current: focusedItemID,
                            direction: mapped,
                            columnCount: columns
                          )
                    else { return }
                    onNavigate(target)
                }
                .task(id: columns) {
                    onColumnCountChange(columns)
                }
            }
        }
    }

    private func card(for item: ClipItem) -> some View {
        WorkspaceClipCard(
            item: item,
            isFocused: item.persistentModelID == focusedItemID,
            isSelected: selectedItemIDs.contains(item.persistentModelID),
            isPaletteTarget: showCommandPalette
                && item.persistentModelID == focusedItemID,
            onTap: onTap,
            onCommandPaletteDismiss: onCommandPaletteDismiss,
            contextMenu: contextMenu,
            commandPalette: commandPalette
        )
        .id(item.persistentModelID)
        .onAppear {
            if trailingIDs.contains(item.persistentModelID) {
                onLoadMore()
            }
        }
    }

    private func navigationDirection(_ direction: MoveCommandDirection) -> WorkspaceNavigationDirection? {
        switch direction {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        @unknown default: nil
        }
    }
}

private struct WorkspaceClipCard<Menu: View, Palette: View>: View {
    let item: ClipItem
    let isFocused: Bool
    let isSelected: Bool
    let isPaletteTarget: Bool
    let onTap: (PersistentIdentifier) -> Void
    let onCommandPaletteDismiss: () -> Void
    let contextMenu: (ClipItem) -> Menu
    let commandPalette: (ClipItem) -> Palette

    @State private var isHovered = false

    /// 卡片元数据在 init 时解析一次。之前是计算属性,body 每次求值会重复执行
    /// ~6 次完整语义解析(含 Markdown 正则),快速滚动时成为主线程热点。
    let descriptor: WorkspaceCardDescriptor

    init(
        item: ClipItem,
        isFocused: Bool,
        isSelected: Bool,
        isPaletteTarget: Bool,
        onTap: @escaping (PersistentIdentifier) -> Void,
        onCommandPaletteDismiss: @escaping () -> Void,
        contextMenu: @escaping (ClipItem) -> Menu,
        commandPalette: @escaping (ClipItem) -> Palette
    ) {
        self.item = item
        self.isFocused = isFocused
        self.isSelected = isSelected
        self.isPaletteTarget = isPaletteTarget
        self.onTap = onTap
        self.onCommandPaletteDismiss = onCommandPaletteDismiss
        self.contextMenu = contextMenu
        self.commandPalette = commandPalette
        self.descriptor = WorkspaceCardDescriptor(item: item)
    }

    @ViewBuilder
    var body: some View {
        if item.modelContext == nil || item.isDeleted {
            EmptyView()
        } else {
        VStack(alignment: .leading, spacing: 10) {
            header
            if item.isSensitive {
                sensitivePlaceholder
            } else {
                cardContent
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: WorkspaceGridMetrics.cardHeight,
            maxHeight: WorkspaceGridMetrics.cardHeight,
            alignment: .topLeading
        )
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isFocused || isSelected
                        ? Color.accentColor
                        : Color.primary.opacity(isHovered ? 0.18 : 0.09),
                    lineWidth: isFocused ? 3 : (isSelected ? 2 : 1)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // 与 ClipItemListRow 同款:掐断继承的隐式动画,重排/重载时卡片
        // 直接就位而不是带着弹簧来回摆(抖动的放大器)。
        .transaction { $0.animation = nil }
        .onHover { isHovered = $0 }
        .onTapGesture { onTap(item.persistentModelID) }
        .popover(
            isPresented: Binding(
                get: { isPaletteTarget },
                set: { if !$0 { onCommandPaletteDismiss() } }
            ),
            arrowEdge: .trailing
        ) {
            commandPalette(item)
        }
        .contextMenu { contextMenu(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: descriptor.kind.icon)
                .foregroundStyle(.secondary)
            Text(descriptor.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(descriptor.kind.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        // imageData 是 externalStorage 属性,每次读取都可能触发磁盘故障;
        // 这里只读一次,同时供 data 与 fallback 判断使用。
        let thumbnailData = item.imageData
        Group {
            switch descriptor.kind {
            case .image:
                AsyncPreviewImageView(
                    data: thumbnailData,
                    cacheKey: "workspace:\(item.itemID)",
                    maxPixelSize: 360,
                    cornerRadius: 8,
                    thumbnailSize: 180,
                    fallbackFileURL: thumbnailData == nil ? item.sourceImageFileURL : nil
                )
                // 定高瓦片:占位图 → 缩略图 → 预览图的异步切换不再改变卡片高度,
                // 图片加载不改变固定网格的行高,避免下方卡片跳动。
                .frame(maxWidth: .infinity)
                .frame(height: 176)
                .clipped()
                .allowsHitTesting(false)
        case .svg(let source):
            SVGPreviewView(source: source, showsModePicker: false, compact: true)
                .frame(height: 170)
                .allowsHitTesting(false)
        case .color(let parsed):
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: parsed.nsColor))
                    .frame(height: 112)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                Text(descriptor.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .link(let domain):
            VStack(alignment: .leading, spacing: 8) {
                if let domain, !domain.isEmpty {
                    Label(domain, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                summaryText(monospaced: false)
            }
        case .code:
            summaryText(monospaced: true)
        case .markdown, .text, .file:
            summaryText(monospaced: false)
            }
        }
    }

    private func summaryText(monospaced: Bool) -> some View {
        Text(descriptor.summary.isEmpty ? "—" : descriptor.summary)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.secondary)
            .lineLimit(7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        // 不开 textSelection:可选中文本容器会吞掉鼠标点击,卡片既选不中,
        // 被截断的摘要还会在点击时整体展开。与图片/SVG 预览的 allowsHitTesting(false)
        // 同一处理原则 —— 卡片是点选入口,文本复制走详情面板/右键菜单。
    }

    private var sensitivePlaceholder: some View {
        Label(L10n.tr("sensitive.contentHidden"), systemImage: "lock.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 116)
    }
}
