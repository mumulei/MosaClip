import SwiftUI

/// The main-window presentation preference. List mode remains the safe fallback;
/// card mode is presentation-only and consumes the same ordered ClipItem values.
enum WorkspaceLayoutMode: String, CaseIterable {
    case list
    case cards
}

enum WorkspaceNavigationDirection {
    case up
    case down
    case left
    case right
}

enum WorkspaceGridMetrics {
    static let minimumCardWidth: CGFloat = 210
    /// A stable lazy-layout contract shared by every card kind. This fits the
    /// existing 176pt image tile / 170pt SVG tile plus header, spacing and
    /// padding, while preventing heterogeneous content from changing a lazy
    /// column's estimated height as it crosses the visible region.
    static let cardHeight: CGFloat = 226
    /// XHS 风格的信息密度:卡片自带 12pt 内边距,列间距收窄到 10pt。
    static let spacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 16

    static func columnCount(for availableWidth: CGFloat) -> Int {
        let usable = max(0, availableWidth - horizontalPadding * 2)
        return max(1, Int((usable + spacing) / (minimumCardWidth + spacing)))
    }

}

/// The card workspace is a presentation of the store's authoritative order.
/// Keeping this as an explicit production helper makes it impossible for a
/// layout-specific cache to silently introduce a second ordering policy.
enum WorkspaceGridOrdering {
    static func visualOrder<T>(for items: [T]) -> [T] {
        items
    }
}

/// Row-major navigation matches LazyVGrid's visual order and therefore the
/// source array's ordering. No persistence or capture semantics are involved.
enum WorkspaceGridNavigation {
    static func neighbor<ID: Hashable>(
        in orderedIDs: [ID],
        current: ID?,
        direction: WorkspaceNavigationDirection,
        columnCount: Int
    ) -> ID? {
        guard !orderedIDs.isEmpty else { return nil }
        guard let current, let index = orderedIDs.firstIndex(of: current) else {
            return orderedIDs.first
        }

        let columns = max(1, columnCount)
        let candidate: Int
        switch direction {
        case .up: candidate = index - columns
        case .down: candidate = index + columns
        case .left:
            guard !index.isMultiple(of: columns) else { return nil }
            candidate = index - 1
        case .right:
            guard (index + 1) % columns != 0 else { return nil }
            candidate = index + 1
        }
        guard orderedIDs.indices.contains(candidate) else { return nil }
        return orderedIDs[candidate]
    }
}
