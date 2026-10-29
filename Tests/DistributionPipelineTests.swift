import Foundation
import Testing
@testable import PasteMemo

/// Automated guards for the release/distribution pipeline (P0–P2).
///
/// These tests execute the packaging entry points directly (via `/bin/bash`)
/// so the fail-closed policy is verified as behavior, not as documentation:
/// version resolution, identity classification, production-mode rejection of
/// ad-hoc/development certificates, entitlement safety, checksum ordering and
/// the disabled-updates posture are all locked here.
@Suite("Distribution pipeline")
struct DistributionPipelineTests {
    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let packageScript = projectRoot
        .appendingPathComponent("scripts/package.sh").path
    private static let releaseLib = projectRoot
        .appendingPathComponent("scripts/release-lib.sh").path
    private static let ciBuildScript = projectRoot
        .appendingPathComponent(".github/scripts/ci-build-dmg.sh").path

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    private func runScript(
        _ script: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + arguments
        process.currentDirectoryURL = Self.projectRoot

        var env = ProcessInfo.processInfo.environment
        // Deterministic tool lookup regardless of the invoking environment.
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        for (key, value) in environment {
            // Empty value == "explicitly unset" for our scripts' `${VAR:-}`
            // normalization; passing it keeps runs independent of CI leakage.
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return RunResult(exitCode: -1, stdout: "", stderr: "\(error)")
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func repoText(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func versionFileContents() throws -> String {
        try repoText("VERSION").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Version resolution

    @Test("Version resolution prefers an explicit VERSION override")
    func versionOverrideWins() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--print-version"],
            environment: ["VERSION": "9.9.9-test"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "9.9.9-test")
    }

    @Test("Version resolution falls back to the VERSION file")
    func versionFileFallback() throws {
        let result = runScript(Self.packageScript, arguments: ["--print-version"])
        let expected = try versionFileContents()
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }

    // MARK: - Signing policy (fail closed)

    @Test("Ad-hoc mode defaults to the local '-' identity")
    func adhocModeDefaultsToAdHocIdentity() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "adhoc"],
            environment: ["CODESIGN_IDENTITY": ""]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "-")
    }

    @Test("Ad-hoc mode keeps accepting an explicitly provided local identity")
    func adhocModeAcceptsExplicitLocalIdentity() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "adhoc"],
            environment: [
                "CODESIGN_IDENTITY": "Apple Development: dev@example.com (ABCDE12345)",
            ]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Apple Development"))
    }

    @Test("Production mode rejects the ad-hoc '-' identity")
    func productionRejectsAdHocIdentity() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "developer-id"],
            environment: ["CODESIGN_IDENTITY": "-"]
        )
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Developer ID Application"))
    }

    @Test("Production mode rejects development and distribution certificates")
    func productionRejectsNonDeveloperIdCertificates() {
        for identity in [
            "Apple Development: dev@example.com (ABCDE12345)",
            "Mac Developer: dev@example.com (ABCDE12345)",
            "Apple Distribution: Example Co (ABCDE12345)",
        ] {
            let result = runScript(
                Self.packageScript,
                arguments: ["--resolve-signing", "developer-id"],
                environment: ["CODESIGN_IDENTITY": identity]
            )
            #expect(result.exitCode != 0, "should reject: \(identity)")
        }
    }

    @Test("Production mode rejects unknown identity strings")
    func productionRejectsUnknownIdentities() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "developer-id"],
            environment: ["CODESIGN_IDENTITY": "My Self Made Certificate"]
        )
        #expect(result.exitCode != 0)
    }

    @Test("Production mode accepts a well-formed Developer ID common name")
    func productionAcceptsWellFormedDeveloperIdIdentity() {
        let identity = "Developer ID Application: Example Co (ABCDE12345)"
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "developer-id"],
            environment: ["CODESIGN_IDENTITY": identity]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == identity)
    }

    @Test("Production auto-detection never falls back to ad-hoc signing")
    func productionAutoDetectNeverFallsBackToAdHoc() {
        let result = runScript(
            Self.packageScript,
            arguments: ["--resolve-signing", "developer-id"],
            environment: ["CODESIGN_IDENTITY": ""]
        )
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 {
            // A Developer ID certificate exists on this machine: it must be selected.
            #expect(resolved.hasPrefix("Developer ID Application:"))
        } else {
            // No certificate available: must fail closed with actionable guidance.
            #expect(resolved != "-")
            #expect(result.stderr.contains("no valid 'Developer ID Application' identity"))
        }
        // Either way the resolved identity is never ad-hoc.
        #expect(resolved != "-")
    }

    // MARK: - Metadata consistency

    @Test("Package metadata stays aligned with ReleaseIdentity")
    func packageMetadataMatchesReleaseIdentity() throws {
        let result = runScript(Self.packageScript, arguments: ["--print-metadata"])
        #expect(result.exitCode == 0)

        var metadata: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                metadata[String(parts[0])] = String(parts[1])
            }
        }

        #expect(metadata["APP_NAME"] == ReleaseIdentity.displayName)
        #expect(metadata["EXECUTABLE_NAME"] == ReleaseIdentity.displayName)
        #expect(metadata["MCP_EXECUTABLE_NAME"] == "pastememo-mcp")
        #expect(metadata["BUNDLE_ID"] == ReleaseIdentity.bundleIdentifier)
        #expect(metadata["MIN_SYSTEM_VERSION"] == "14.0")
        let expectedVersion = try versionFileContents()
        #expect(metadata["VERSION"] == expectedVersion)

        // The helper remains a dedicated SwiftPM executable target.
        let packageSwift = try repoText("Package.swift")
        #expect(packageSwift.contains(#"name: "pastememo-mcp""#))
    }

    // MARK: - Entitlements safety

    @Test("Release entitlements stay minimal and never enable get-task-allow")
    func entitlementsStaySafeForHardenedRuntime() throws {
        let url = Self.projectRoot.appendingPathComponent(".github/scripts/release-entitlements.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try #require(plist as? [String: Any])

        // Exactly one entitlement is authorized: outgoing Apple Events toward
        // Finder (ClipboardManager.getFinderSelectedFolder uses NSAppleScript).
        #expect(entitlements.keys.sorted() == ["com.apple.security.automation.apple-events"])
        #expect(try #require(entitlements["com.apple.security.automation.apple-events"] as? Bool) == true)

        #expect(entitlements["com.apple.security.get-task-allow"] == nil)
        #expect(entitlements["com.apple.security.cs.allow-jit"] == nil)
        #expect(entitlements["com.apple.security.cs.allow-unsigned-executable-memory"] == nil)
        #expect(entitlements["com.apple.security.cs.disable-library-validation"] == nil)
    }

    // MARK: - Packaging structure

    @Test("package.sh signs nested code before the app and enforces hardened flags")
    func packagingSignsInsideOut() throws {
        let script = try repoText("scripts/package.sh")

        let helperSignIndex = try #require(
            script.range(of: #"codesign --force ${SIGN_TIMESTAMP[@]+"${SIGN_TIMESTAMP[@]}"} --options runtime \"#),
            "helper codesign invocation missing"
        )
        let appSignIndex = try #require(
            script.range(of: "--entitlements \"$ENTITLEMENTS_FILE\""),
            "app codesign invocation missing"
        )
        #expect(helperSignIndex.lowerBound < appSignIndex.lowerBound)

        #expect(script.contains("--options runtime"))
        #expect(script.contains("--timestamp"))
        #expect(script.contains("verify_entitlements_safety"))
        #expect(script.contains("get-task-allow"))
        #expect(script.contains("--resolve-signing"))
        #expect(script.contains("SIGNING_MODE"))
    }

    // MARK: - Notarization pipeline ordering

    @Test("CI pipeline notarizes, staples, then computes the final SHA-256")
    func ciPipelineComputesChecksumAfterStapling() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        let stapleIndex = try #require(script.range(of: "stapler staple"))
        let validateIndex = try #require(script.range(of: "stapler validate"))
        let shaIndex = try #require(script.range(of: "shasum -a 256"))

        // Stapling mutates the DMG, so the published checksum MUST be taken
        // only after staple + validate succeed.
        #expect(stapleIndex.lowerBound < validateIndex.lowerBound)
        #expect(validateIndex.lowerBound < shaIndex.lowerBound)

        #expect(script.contains("notarytool submit"))
        #expect(script.contains("--wait"))
        #expect(script.contains("Accepted"))
        #expect(script.contains("notarytool log"))
        #expect(script.contains("spctl --assess"))
        #expect(script.contains("com.apple.quarantine"))
        // The DMG is signed with the same Developer ID identity policy.
        #expect(script.contains("--resolve-signing developer-id"))
    }

    @Test("CI pipeline refuses to run without credentials or with updates enabled")
    func ciPipelineFailsClosedOnCredentialsAndUpdatePolicy() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        // Fail-closed credential probes: both paths terminate before building.
        #expect(script.contains("is not configured. Create it once with"))
        #expect(script.contains("does not match APPLE_TEAM_ID"))
        #expect(script.contains("onlineUpdatesEnabled = false"))
    }

    @Test("VERIFY_ONLY re-verification gates the staple ticket before checksums")
    func verifyOnlyModeGatesTicketBeforeChecksum() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        let voBinding = try #require(script.range(of: "VERIFY_ONLY=\"${VERIFY_ONLY:-}\""))
        let ticketGate = try #require(
            script.range(of: "does not carry a valid notarization ticket")
        )
        let shaIndex = try #require(script.range(of: "shasum -a 256"))

        // The documented mode must exist and reject unticketed DMGs before any
        // SHA-256/report can be produced.
        #expect(voBinding.lowerBound < ticketGate.lowerBound)
        #expect(ticketGate.lowerBound < shaIndex.lowerBound)
        #expect(script.contains("assert_bundle_metadata \"$MOUNTED_APP\""))
    }

    // MARK: - CI secret contract & disabled publishing

    @Test("build-sign workflow declares the full secret contract and never swallows failures")
    func workflowDeclaresSecretContract() throws {
        let workflow = try repoText(".github/workflows/build-sign.yml")

        for secret in [
            "DEVELOPER_ID_APPLICATION_P12_BASE64",
            "DEVELOPER_ID_APPLICATION_P12_PASSWORD",
            "APPLE_TEAM_ID",
            "APPLE_API_KEY_ID",
            "APPLE_API_ISSUER_ID",
            "APPLE_API_KEY_P8_BASE64",
        ] {
            #expect(workflow.contains(secret), "missing secret reference: \(secret)")
        }

        #expect(!workflow.contains("continue-on-error"))
        #expect(workflow.contains("permissions:\n  contents: read"))
        #expect(workflow.contains("actions/upload-artifact"))
        // Publishing stays out of this workflow.
        #expect(!workflow.contains("softprops/action-gh-release"))
        #expect(!workflow.contains("publish-release.sh"))
    }

    @Test("Online publishing stays disabled across workflows and scripts")
    func onlinePublishingRemainsDisabled() throws {
        let autoRelease = try repoText(".github/workflows/auto-release.yml")
        #expect(autoRelease.contains("disabled"))
        // No push/tag/release triggers may sneak back into the publisher.
        #expect(!autoRelease.contains("push:"))
        #expect(!autoRelease.contains("release:"))

        let publishScript = try repoText(".github/scripts/publish-release.sh")
        #expect(publishScript.contains("exit 1"))
        #expect(!publishScript.contains("curl "))
        #expect(!publishScript.contains("gh release"))
    }

    // MARK: - Launch smoke safety boundary

    /// MosaClip resolves all user-domain storage via Foundation's passwd-based
    /// home resolution; HOME cannot isolate it. The launch smoke must therefore
    /// never pretend to be isolated and must only run on GitHub-hosted
    /// runners — self-hosted runners also fail closed.
    @Test("Launch smoke no longer fakes HOME isolation or creates an unused SMOKE_HOME")
    func launchSmokeDropsFakeIsolation() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        // The former mechanism created SMOKE_HOME but never passed it to the
        // launched process, and even a passed HOME would not isolate
        // Foundation user-domain storage on current macOS.
        #expect(!script.contains("SMOKE_HOME"))
        #expect(!script.contains("isolated-home launch"))
    }

    @Test("Launch smoke fails closed outside GitHub-hosted Actions runners")
    func launchSmokeFailsClosedOutsideGitHubHostedRunners() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        // Runner conditions, evaluated only when the flag is set. GITHUB_ACTIONS
        // alone would also match self-hosted runners, so the gate additionally
        // requires GitHub's RUNNER_ENVIRONMENT signal to report "github-hosted".
        let flagBinding = try #require(script.range(of: #"LAUNCH_SMOKE="${MOSACLIP_LAUNCH_SMOKE:-0}""#))
        let smokeBranch = try #require(script.range(of: #"if [[ "$LAUNCH_SMOKE" == "1" ]]; then"#))
        let gate = try #require(
            script.range(of: #"if [[ "${GITHUB_ACTIONS:-}" != "true" ||"#),
            "GITHUB_ACTIONS condition missing"
        )
        let hostedCondition = try #require(
            script.range(of: #""${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then"#),
            "RUNNER_ENVIRONMENT github-hosted condition missing"
        )
        #expect(flagBinding.lowerBound < smokeBranch.lowerBound)
        #expect(smokeBranch.lowerBound < gate.lowerBound)

        // Both conditions belong to one combined gate evaluated before any
        // launch: the RUNNER_ENVIRONMENT check continues the same if-statement.
        let launchIndex = try #require(
            script.range(of: #""$QUARANTINE_APP/Contents/MacOS/MosaClip" &"#)
        )
        #expect(gate.upperBound < hostedCondition.upperBound)
        #expect(hostedCondition.upperBound < launchIndex.lowerBound)

        // Fail-closed message names the allowed place and the rejected ones.
        #expect(script.contains(
            "launch smoke is allowed only on GitHub-hosted Actions runners"
        ))
        #expect(script.contains(
            "Local and self-hosted environments fail closed because MosaClip user-domain storage cannot currently be proven isolated"
        ))
    }

    @Test("Self-hosted runners are rejected by exact-value comparison, not heuristics")
    func selfHostedRunnersFailClosedByExactValueComparison() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        // The gate demands the literal "github-hosted" value; any other value
        // (self-hosted, unset, unknown) fails closed by construction.
        #expect(script.contains(#""${RUNNER_ENVIRONMENT:-}" != "github-hosted""#))
        // No hostname / platform probing stands in for the runner signal.
        #expect(!script.contains("hostname"))
        // The guardrail's honest framing: safe-by-default, not anti-spoofing.
        #expect(script.contains("safe-by-default guardrail"))
    }

    @Test("Default pipeline keeps launch smoke off without requiring any runner condition")
    func defaultPipelineDoesNotRequireRunnerCondition() throws {
        let script = try repoText(".github/scripts/ci-build-dmg.sh")

        // Exactly one reference to each runner-condition expression, living
        // strictly inside the opt-in smoke branch — so VERIFY_ONLY and the
        // normal non-smoke pipeline never evaluate or depend on either of
        // them. (Prose comments may mention the identifiers; only the actual
        // condition fragments count here.)
        let ghActionsCondition = #""${GITHUB_ACTIONS:-}" != "true""#
        let ghActionsOccurrences = script.ranges(of: ghActionsCondition)
        #expect(ghActionsOccurrences.count == 1)
        let runnerEnvCondition = #""${RUNNER_ENVIRONMENT:-}" != "github-hosted""#
        let runnerEnvOccurrences = script.ranges(of: runnerEnvCondition)
        #expect(runnerEnvOccurrences.count == 1)
        #expect(script.contains(#"LAUNCH_SMOKE="${MOSACLIP_LAUNCH_SMOKE:-0}""#))
        let smokeBranch = try #require(script.range(of: #"if [[ "$LAUNCH_SMOKE" == "1" ]]; then"#))
        #expect(try #require(ghActionsOccurrences.first).lowerBound > smokeBranch.lowerBound)
        #expect(try #require(runnerEnvOccurrences.first).lowerBound > smokeBranch.lowerBound)
    }


    // MARK: - Shared policy library integrity

    @Test("release-lib classifies identities without executing anything")
    func releaseLibClassifiesIdentityKinds() throws {
        let lib = try repoText("scripts/release-lib.sh")
        // Classification table covers every family we must separate.
        for marker in [
            "Developer ID Application:",
            "Apple Development:",
            "Mac Developer:",
            "Apple Distribution:",
            "adhoc",
            "unknown",
        ] {
            #expect(lib.contains(marker), "classifier missing rule for: \(marker)")
        }
    }
}
