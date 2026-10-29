import Combine

/// Secondary pages reached from Settings > Data.
enum SettingsSubpage: Hashable {
    case storageManage
    case storageGroup(StorageGroupKey)
}

/// Shared navigation state for the existing SwiftUI settings split view.
///
/// The upstream storage feature expects its overview, manage and group pages to
/// share one history stack. MosaClip deliberately keeps its existing
/// `NavigationSplitView`; only this state model is synced from upstream.
@MainActor
final class SettingsNavigationModel: ObservableObject {
    private struct Location: Hashable {
        var category: SettingsCategory
        var subpage: SettingsSubpage?
    }

    @Published var selection: SettingsCategory = .general {
        didSet {
            guard oldValue != selection else { return }
            if !isNavigatingHistory { subpage = nil }
            recordHistory()
            onLocationChange?(title)
        }
    }

    @Published private(set) var subpage: SettingsSubpage?
    var onLocationChange: ((String) -> Void)?

    @Published private var history: [Location] = [Location(category: .general)]
    @Published private var historyIndex = 0
    private var isNavigatingHistory = false

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    var title: String {
        switch subpage {
        case nil: return L10n.tr(selection.titleKey)
        case .storageManage: return L10n.tr("storage.manage.title")
        case .storageGroup(.source(let name)): return name.isEmpty ? L10n.tr("filter.other") : name
        case .storageGroup(.category(let category)): return category.label
        }
    }

    func select(_ category: SettingsCategory) {
        guard category == selection else {
            selection = category
            return
        }
        guard subpage != nil else { return }
        subpage = nil
        recordHistory()
        onLocationChange?(title)
    }

    func push(_ page: SettingsSubpage) {
        guard page != subpage else { return }
        subpage = page
        recordHistory()
        onLocationChange?(title)
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        apply(history[historyIndex])
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        apply(history[historyIndex])
    }

    private func apply(_ location: Location) {
        isNavigatingHistory = true
        subpage = location.subpage
        selection = location.category
        isNavigatingHistory = false
        onLocationChange?(title)
    }

    private func recordHistory() {
        guard !isNavigatingHistory else { return }
        let location = Location(category: selection, subpage: subpage)
        guard history.indices.contains(historyIndex), history[historyIndex] != location else { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(location)
        historyIndex = history.count - 1
    }
}
