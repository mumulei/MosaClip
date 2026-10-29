import Foundation
import SwiftData

enum BuiltInRules {
    private static let SEEDED_KEY = "builtInRulesSeeded_v2"
    /// Names of built-ins the user deleted. `seedMissing` skips these so a deleted
    /// rule doesn't come back at the next launch; "恢复内置规则" clears the list.
    private static let DELETED_KEY = "builtInRulesDeleted"

    static var deletedNames: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: DELETED_KEY) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: DELETED_KEY) }
    }

    static func markDeleted(_ name: String) {
        var names = deletedNames
        names.insert(name)
        deletedNames = names
    }

    /// Bring back every deleted built-in (keeps the ones still present untouched).
    @MainActor
    static func restoreDeleted(context: ModelContext) {
        deletedNames = []
        seedMissing(context: context)
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: SEEDED_KEY) else {
            seedMissing(context: context)
            return
        }

        // Remove old built-in rules before re-seeding
        let descriptor = FetchDescriptor<AutomationRule>(predicate: #Predicate { $0.isBuiltIn })
        if let oldRules = try? context.fetch(descriptor) {
            for rule in oldRules { context.delete(rule) }
        }

        for definition in definitions {
            let rule = AutomationRule(
                name: definition.name,
                enabled: definition.enabled,
                isBuiltIn: true,
                sortOrder: definition.sortOrder,
                triggerMode: definition.triggerMode,
                conditions: definition.conditions,
                actions: definition.actions
            )
            context.insert(rule)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: SEEDED_KEY)

        if !UserDefaults.standard.bool(forKey: "automationEnabled") {
            UserDefaults.standard.set(true, forKey: "automationEnabled")
        }
    }

    /// Built-ins added after the one-time seed. Matched by name (built-in names are
    /// L10n keys, so they're stable) and inserted only when absent — bumping
    /// `SEEDED_KEY` instead would wipe the user's on/off choices for every built-in.
    @MainActor
    private static func seedMissing(context: ModelContext) {
        let descriptor = FetchDescriptor<AutomationRule>(predicate: #Predicate { $0.isBuiltIn })
        let builtIns = (try? context.fetch(descriptor)) ?? []
        var inserted = false
        let existing = Set(builtIns.map(\.name))
        let deleted = deletedNames
        for definition in definitions where !existing.contains(definition.name) && !deleted.contains(definition.name) {
            let rule = AutomationRule(
                name: definition.name,
                enabled: definition.enabled,
                isBuiltIn: true,
                sortOrder: definition.sortOrder,
                triggerMode: definition.triggerMode,
                conditions: definition.conditions,
                actions: definition.actions
            )
            context.insert(rule)
            inserted = true
        }
        if inserted { try? context.save() }
    }

    private struct RuleDefinition {
        let name: String
        let enabled: Bool
        let sortOrder: Int
        var triggerMode: TriggerMode = .automatic
        let conditions: [RuleCondition]
        let actions: [RuleAction]
    }

    private static let definitions: [RuleDefinition] = [
        RuleDefinition(
            name: "automation.builtIn.cleanTracking",
            enabled: true,
            sortOrder: 0,
            conditions: [.contentType(.link)],
            actions: [.removeQueryParams(patterns: [
                "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
                "fbclid", "gclid", "mc_cid", "mc_eid",
            ])]
        ),
        RuleDefinition(
            name: "automation.builtIn.lowercaseEmail",
            enabled: true,
            sortOrder: 1,
            conditions: [.regexMatch(pattern: "^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}$")],
            actions: [.lowercased]
        ),
        RuleDefinition(
            name: "automation.builtIn.removeBlankLines",
            enabled: false,
            sortOrder: 2,
            conditions: [.contentType(.text)],
            actions: [.removeBlankLines]
        ),
    ]
}
