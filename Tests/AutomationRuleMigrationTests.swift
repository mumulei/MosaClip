import Foundation
import SwiftData
import Testing
@testable import PasteMemo

// Frozen pre-sync rule model. Its stored fields match b27cbb8; the entity
// name remains AutomationRule so this exercises a real on-disk schema upgrade.
private enum BeforeUpstreamSync {
    @Model
    final class AutomationRule {
        var ruleID: String = UUID().uuidString
        var name: String = ""
        var enabled: Bool = true
        var isBuiltIn: Bool = false
        var sortOrder: Int = 0
        var triggerModeRaw: String = TriggerMode.automatic.rawValue
        var notifyBeforeApply: Bool = false
        var notifyOnTrigger: Bool = false
        var writeBackToPasteboard: Bool = false
        var conditionLogicRaw: String = ConditionLogic.all.rawValue
        var conditionsData: Data = Data()
        var actionsData: Data = Data()
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Transient
        var triggerMode: TriggerMode {
            get { TriggerMode(rawValue: triggerModeRaw) ?? .automatic }
            set { triggerModeRaw = newValue.rawValue }
        }

        @Transient
        var conditionLogic: ConditionLogic {
            get { ConditionLogic(rawValue: conditionLogicRaw) ?? .all }
            set { conditionLogicRaw = newValue.rawValue }
        }

        var conditions: [RuleCondition] {
            get { (try? JSONDecoder().decode([RuleCondition].self, from: conditionsData)) ?? [] }
            set { conditionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
        }

        var actions: [RuleAction] {
            get { (try? JSONDecoder().decode([RuleAction].self, from: actionsData)) ?? [] }
            set { actionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
        }

        init(
            name: String,
            enabled: Bool = true,
            isBuiltIn: Bool = false,
            sortOrder: Int = 0,
            triggerMode: TriggerMode = .automatic,
            notifyBeforeApply: Bool = false,
            writeBackToPasteboard: Bool = false,
            conditions: [RuleCondition] = [],
            actions: [RuleAction] = []
        ) {
            self.name = name
            self.enabled = enabled
            self.isBuiltIn = isBuiltIn
            self.sortOrder = sortOrder
            self.triggerModeRaw = triggerMode.rawValue
            self.notifyBeforeApply = notifyBeforeApply
            self.writeBackToPasteboard = writeBackToPasteboard
            self.conditions = conditions
            self.actions = actions
        }

        /// Whether this rule should surface as an option for `item` in ⌘K / right-
        /// click menus. Two gates:
        /// 1. The rule's own conditions must match the clip (empty = always match).
        /// 2. Non-text clips (image, file, …) only surface rules that include at
        ///    least one `.runShortcut` action — built-in text transforms like
        ///    `lowercased` or `urlEncode` are meaningless on binary data.
        func matches(item: ClipItem) -> Bool {
            if !conditions.isEmpty {
                let ok = AutomationEngine.matchesConditions(
                    conditions,
                    logic: conditionLogic,
                    content: item.content,
                    contentType: item.contentType,
                    sourceApp: item.sourceAppBundleID
                )
                guard ok else { return false }
            }
            if item.contentType.isMergeable { return true }
            return actions.contains { if case .runShortcut = $0 { return true }; return false }
        }
    }
}

@Suite("Upstream rule storage migration", .serialized)
@MainActor
struct AutomationRuleMigrationTests {
    @Test("Old disk store upgrades and retains clips, groups and rule behavior")
    func upgradesExistingStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mosaclip-rule-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("PasteMemo.store")

        try autoreleasepool {
            let schema = Schema([ClipItem.self, SmartGroup.self, BeforeUpstreamSync.AutomationRule.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let rule = BeforeUpstreamSync.AutomationRule(
                name: "existing", triggerMode: .manual, writeBackToPasteboard: true,
                conditions: [.anyText], actions: [.lowercased, .pin]
            )
            rule.ruleID = "existing-rule"
            context.insert(rule)
            let clip = ClipItem(content: "KEEP ORIGINAL", contentType: .text)
            clip.isSensitive = true
            clip.groupName = "Saved"
            context.insert(clip)
            context.insert(SmartGroup(name: "Saved"))
            try context.save()
        }

        try autoreleasepool {
            let schema = Schema([ClipItem.self, SmartGroup.self, AutomationRule.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let rule = try #require(context.fetch(FetchDescriptor<AutomationRule>()).first)
            #expect(rule.ruleID == "existing-rule")
            #expect(rule.outputMode == .clipboard)
            #expect(rule.outputParam.isEmpty)
            #expect(rule.conditions == [.anyText])
            #expect(rule.actions == [.lowercased, .pin])
            let clip = try #require(context.fetch(FetchDescriptor<ClipItem>()).first)
            #expect(clip.content == "KEEP ORIGINAL")
            #expect(clip.isSensitive && clip.groupName == "Saved")
            #expect(try context.fetch(FetchDescriptor<SmartGroup>()).map(\.name) == ["Saved"])
            rule.outputMode = .saveToFile
            rule.outputParam = root.path
            try context.save()
        }

        let schema = Schema([ClipItem.self, SmartGroup.self, AutomationRule.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let saved = try #require(context.fetch(FetchDescriptor<AutomationRule>()).first)
        #expect(saved.outputMode == .saveToFile && saved.outputParam == root.path)
        #expect(try context.fetchCount(FetchDescriptor<ClipItem>()) == 1)
    }
}
