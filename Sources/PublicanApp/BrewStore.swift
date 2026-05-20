import Foundation
import Combine

@MainActor
final class BrewStore: ObservableObject {
    @Published private(set) var brewPath: String?
    @Published private(set) var installedPackages: [BrewPackage] = []
    @Published private(set) var searchResults: [BrewPackage] = []
    @Published private(set) var outdatedPackages: [BrewPackage] = []
    @Published private(set) var packageInfo: BrewPackageInfo = .placeholder
    @Published private(set) var healthIssues: [BrewHealthIssue] = []
    @Published private(set) var healthSummary = "Homebrew health has not been checked yet."
    @Published private(set) var commandLog: String = "Ready."
    @Published private(set) var permissionNotice: String?
    @Published private(set) var currentOperation: String?
    @Published private(set) var lastCommandIssue: BrewCommandIssue?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Checking Homebrew..."
    @Published var pendingCommand: BrewPendingCommand?

    @Published var searchText = ""

    private var runner: BrewCommandRunner?

    var isHomebrewAvailable: Bool {
        runner != nil
    }

    init() {
        detectHomebrew()
    }

    func detectHomebrew() {
        runner = BrewCommandRunner.detect()
        brewPath = runner?.brewPath
        if let brewPath {
            status = "Homebrew found at \(brewPath)."
            healthIssues.removeAll { $0.title == "Homebrew executable not found" }
            healthSummary = healthIssues.isEmpty ? "Homebrew health has not been checked yet." : healthSummary
        } else {
            status = "Homebrew not found."
            healthSummary = status
            healthIssues = [
                BrewHealthIssue(
                    title: "Homebrew executable not found",
                    detail: BrewCommandError.executableNotFound.localizedDescription,
                    guidance: "Install Homebrew from brew.sh, then use Re-check Homebrew in Publican.",
                    severity: .error
                )
            ]
        }
    }

    func refreshInstalled() async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Loading installed packages...") {
            try await loadInstalledPackages(using: runner)
            status = "Loaded \(installedPackages.count) installed packages."
        }
    }

    func refreshOutdated() async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Checking outdated packages...") {
            try await loadOutdatedPackages(using: runner)
            status = "Found \(outdatedPackages.count) outdated package(s)."
        }
    }

    func checkHealth() async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            healthSummary = status
            healthIssues = [
                BrewHealthIssue(
                    title: "Homebrew executable not found",
                    detail: BrewCommandError.executableNotFound.localizedDescription,
                    guidance: "Install Homebrew first, or make sure Publican can find brew at /opt/homebrew/bin/brew or /usr/local/bin/brew.",
                    severity: .error
                )
            ]
            return
        }

        await runBusyTask(status: "Checking Homebrew health...") {
            let doctorResult = try await runner.run(arguments: ["doctor"])
            appendLog(doctorResult)

            var issues = Self.parseDoctorOutput(doctorResult)
            issues.append(contentsOf: Self.checkWritablePaths([
                "/opt/homebrew/Cellar",
                "/usr/local/Cellar"
            ]))

            if issues.isEmpty {
                healthIssues = [
                    BrewHealthIssue(
                        title: "No health issues found",
                        detail: "Homebrew doctor did not report any problems and the usual Cellar path is writable where present.",
                        guidance: "No action needed.",
                        severity: .ok
                    )
                ]
                healthSummary = "Homebrew health looks good."
            } else {
                healthIssues = issues
                healthSummary = "Found \(issues.count) Homebrew health item(s)."
            }

            status = healthSummary
        }
    }

    func search() async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            searchResults = []
            status = "Enter a search term."
            return
        }

        await runBusyTask(status: "Searching formulae and casks...") {
            let installedIDs = Set(installedPackages.map(\.id))
            let formulaResult = try await runner.run(arguments: ["search", "--formula", trimmedSearch])
            let caskResult = try await runner.run(arguments: ["search", "--cask", trimmedSearch])
            appendLog(formulaResult)
            appendLog(caskResult)

            let formulae = Self.parseLines(formulaResult.standardOutput).map {
                BrewPackage(
                    name: $0,
                    kind: .formula,
                    installed: installedIDs.contains("\(BrewPackageKind.formula.rawValue):\($0)")
                )
            }
            let casks = Self.parseLines(caskResult.standardOutput).map {
                BrewPackage(
                    name: $0,
                    kind: .cask,
                    installed: installedIDs.contains("\(BrewPackageKind.cask.rawValue):\($0)")
                )
            }

            searchResults = (formulae + casks).sorted { left, right in
                if left.kind == right.kind {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.kind == .formula
            }
            status = "Found \(searchResults.count) result(s)."
        }
    }

    func install(_ package: BrewPackage) {
        confirm(
            title: "Install \(package.name)?",
            message: "Publican will install this \(package.kind.rawValue.lowercased()). Homebrew may require your macOS user to have administrator permissions or writable Homebrew folders before installs can complete.",
            arguments: package.kind.installArgumentsPrefix + [package.name]
        ) {
            await self.runInstall(package)
        }
    }

    func uninstall(_ package: BrewPackage) {
        Task {
            await prepareUninstall(package)
        }
    }

    func upgrade(_ package: BrewPackage) {
        confirm(
            title: "Upgrade \(package.name)?",
            message: "Publican will upgrade this \(package.kind.rawValue.lowercased()). Homebrew may require your macOS user to have administrator permissions or writable Homebrew folders before upgrades can complete.",
            arguments: package.kind.upgradeArgumentsPrefix + [package.name]
        ) {
            await self.runUpgrade(package)
        }
    }

    func upgrade(_ packages: [BrewPackage]) {
        let selectedPackages = packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !selectedPackages.isEmpty else { return }
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        let groupedArguments = upgradeArguments(for: selectedPackages)
        let commandText = groupedArguments
            .map { runner.commandText(arguments: $0) }
            .joined(separator: "\n")
        let packageNames = selectedPackages.map(\.name).joined(separator: ", ")

        pendingCommand = BrewPendingCommand(
            title: "Upgrade \(selectedPackages.count) packages?",
            message: "Publican will upgrade these selected outdated packages:\n\(packageNames)\n\nFormulae and casks are grouped into the correct Homebrew commands.",
            command: commandText,
            action: {
                await self.runUpgrade(selectedPackages)
            }
        )
    }

    func update() {
        confirm(
            title: "Run brew update?",
            message: "Publican will update Homebrew package metadata.",
            arguments: ["update"]
        ) {
            await self.runUpdate()
        }
    }

    func loadInfo(for package: BrewPackage) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Loading info for \(package.name)...") {
            let jsonResult = try await runner.run(arguments: package.kind.jsonInfoArgumentsPrefix + [package.name])
            appendLog(jsonResult)

            if let parsedInfo = Self.parsePackageInfo(from: jsonResult.standardOutput, package: package) {
                packageInfo = parsedInfo
                status = jsonResult.exitCode == 0 ? "Loaded info for \(package.name)." : "Info failed for \(package.name)."
            } else {
                let textResult = try await runner.run(arguments: package.kind.infoArgumentsPrefix + [package.name])
                appendLog(textResult)
                packageInfo = BrewPackageInfo(
                    name: package.name,
                    displayName: package.name,
                    kind: package.kind,
                    description: textResult.output.isEmpty ? "No details returned for \(package.name)." : nil,
                    homepage: nil,
                    version: nil,
                    installedVersions: [],
                    dependencies: [],
                    caveats: nil,
                    tap: nil,
                    rawInfo: textResult.output
                )
                status = textResult.exitCode == 0 ? "Loaded info for \(package.name)." : "Info failed for \(package.name)."
            }
        }
    }

    func clearPendingCommand() {
        pendingCommand = nil
    }

    func commandText(for action: BrewPackageAction, package: BrewPackage) -> String? {
        runner?.commandText(arguments: action.arguments(for: package))
    }

    func homepageForCurrentInfo(matching package: BrewPackage) -> String? {
        guard packageInfo.name == package.name || packageInfo.displayName == package.name else {
            return nil
        }

        return packageInfo.homepage
    }

    func homepage(for package: BrewPackage) async -> String? {
        if let homepage = homepageForCurrentInfo(matching: package) {
            return homepage
        }

        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return nil
        }

        do {
            let result = try await runner.run(arguments: package.kind.jsonInfoArgumentsPrefix + [package.name])
            appendLog(result)
            let parsedInfo = Self.parsePackageInfo(from: result.standardOutput, package: package)
            if let parsedInfo {
                packageInfo = parsedInfo
            }
            return parsedInfo?.homepage
        } catch {
            status = error.localizedDescription
            commandLog.append("\n\nError: \(error.localizedDescription)")
            return nil
        }
    }

    private func prepareUninstall(_ package: BrewPackage) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        guard package.kind == .formula else {
            confirmUninstall(package, dependants: [], dependencyCheckFailed: false)
            return
        }

        await runBusyTask(status: "Checking dependants for \(package.name)...") {
            let result = try await runner.run(arguments: ["uses", "--installed", package.name])
            appendLog(result, recordsIssue: false)
            let dependants = Self.parseLines(result.standardOutput)
            confirmUninstall(package, dependants: dependants, dependencyCheckFailed: result.exitCode != 0 && !result.standardError.isEmpty)
            status = dependants.isEmpty ? "No installed dependants found for \(package.name)." : "Found \(dependants.count) dependant(s) for \(package.name)."
        }
    }

    private func confirmUninstall(_ package: BrewPackage, dependants: [String], dependencyCheckFailed: Bool) {
        let dependencyMessage: String
        if dependencyCheckFailed {
            dependencyMessage = "\n\nPublican could not fully check installed dependants. Review the command output before continuing."
        } else if dependants.isEmpty {
            dependencyMessage = "\n\nNo installed formulae reported that they depend on this package."
        } else {
            dependencyMessage = "\n\nWarning: these installed formulae report that they use this package:\n\(dependants.joined(separator: ", "))"
        }

        confirm(
            title: "Uninstall \(package.name)?",
            message: "Publican will uninstall this \(package.kind.rawValue.lowercased()).\(dependencyMessage)",
            arguments: package.kind.uninstallArgumentsPrefix + [package.name]
        ) {
            await self.runUninstall(package)
        }
    }

    private func runInstall(_ package: BrewPackage) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Installing \(package.name)...") {
            let result = try await runner.run(arguments: package.kind.installArgumentsPrefix + [package.name])
            appendLog(result)
            try await loadInstalledPackages(using: runner)
            try await loadOutdatedPackages(using: runner)
            refreshPackageStateFromInstalledPackages()
            status = result.exitCode == 0 ? "Installed \(package.name)." : "Install failed for \(package.name)."
        }
    }

    private func runUninstall(_ package: BrewPackage) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Uninstalling \(package.name)...") {
            let result = try await runner.run(arguments: package.kind.uninstallArgumentsPrefix + [package.name])
            appendLog(result)
            try await loadInstalledPackages(using: runner)
            try await loadOutdatedPackages(using: runner)
            refreshPackageStateFromInstalledPackages()
            status = result.exitCode == 0 ? "Uninstalled \(package.name)." : "Uninstall failed for \(package.name)."
        }
    }

    private func runUpgrade(_ package: BrewPackage) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Upgrading \(package.name)...") {
            let result = try await runner.run(arguments: package.kind.upgradeArgumentsPrefix + [package.name])
            appendLog(result)
            try await loadInstalledPackages(using: runner)
            try await loadOutdatedPackages(using: runner)
            refreshPackageStateFromInstalledPackages()
            status = result.exitCode == 0 ? "Upgraded \(package.name)." : "Upgrade failed for \(package.name)."
        }
    }

    private func runUpgrade(_ packages: [BrewPackage]) async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        let groupedArguments = upgradeArguments(for: packages)
        await runBusyTask(status: "Upgrading \(packages.count) packages...") {
            var failedCommands = 0
            for arguments in groupedArguments {
                let result = try await runner.run(arguments: arguments)
                appendLog(result)
                if result.exitCode != 0 {
                    failedCommands += 1
                }
            }

            try await loadInstalledPackages(using: runner)
            try await loadOutdatedPackages(using: runner)
            refreshPackageStateFromInstalledPackages()
            status = failedCommands == 0 ? "Upgraded \(packages.count) package(s)." : "Upgrade finished with \(failedCommands) failed command(s)."
        }
    }

    private func upgradeArguments(for packages: [BrewPackage]) -> [[String]] {
        BrewPackageKind.allCases.compactMap { kind in
            let names = packages
                .filter { $0.kind == kind }
                .map(\.name)
            guard !names.isEmpty else { return nil }
            return kind.upgradeArgumentsPrefix + names
        }
    }

    private func runUpdate() async {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        await runBusyTask(status: "Running brew update...") {
            let result = try await runner.run(arguments: ["update"])
            appendLog(result)
            try await loadOutdatedPackages(using: runner)
            status = result.exitCode == 0 ? "Homebrew updated." : "Update failed."
        }
    }

    private func confirm(title: String, message: String, arguments: [String], action: @escaping () async -> Void) {
        guard let runner else {
            status = BrewCommandError.executableNotFound.localizedDescription
            return
        }

        pendingCommand = BrewPendingCommand(
            title: title,
            message: message,
            command: runner.commandText(arguments: arguments),
            action: action
        )
    }

    private func loadInstalledPackages(using runner: BrewCommandRunner) async throws {
        var packages: [BrewPackage] = []

        for kind in BrewPackageKind.allCases {
            let result = try await runner.run(arguments: kind.listArguments)
            let names = Self.parseLines(result.standardOutput)
            packages.append(contentsOf: names.map {
                BrewPackage(name: $0, kind: kind, installed: true)
            })
            appendLog(result)
        }

        installedPackages = packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadOutdatedPackages(using runner: BrewCommandRunner) async throws {
        var packages: [BrewPackage] = []
        let installedIDs = Set(installedPackages.map(\.id))

        for kind in BrewPackageKind.allCases {
            let result = try await runner.run(arguments: kind.outdatedJSONArguments)
            let parsedPackages = Self.parseOutdatedJSON(result.standardOutput, kind: kind, installedIDs: installedIDs)
            if parsedPackages.isEmpty && !result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).contains("\"formulae\"") {
                let fallbackResult = try await runner.run(arguments: kind.outdatedArguments)
                let names = Self.parseOutdatedLines(fallbackResult.standardOutput)
                packages.append(contentsOf: names.map {
                    BrewPackage(name: $0, kind: kind, installed: installedIDs.contains("\(kind.rawValue):\($0)"))
                })
                appendLog(fallbackResult)
            } else {
                packages.append(contentsOf: parsedPackages)
            }
            appendLog(result)
        }

        outdatedPackages = packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshPackageStateFromInstalledPackages() {
        let installedIDs = Set(installedPackages.map(\.id))
        searchResults = searchResults.map { package in
            BrewPackage(
                name: package.name,
                kind: package.kind,
                installed: installedIDs.contains(package.id),
                installedVersion: package.installedVersion,
                currentVersion: package.currentVersion
            )
        }
    }

    private func runBusyTask(status busyStatus: String, operation: () async throws -> Void) async {
        isBusy = true
        status = busyStatus
        currentOperation = busyStatus
        lastCommandIssue = nil

        do {
            try await operation()
        } catch {
            let issue = Self.issue(for: error)
            lastCommandIssue = issue
            status = issue.title
            commandLog.append("\n\nError: \(error.localizedDescription)")
        }

        currentOperation = nil
        isBusy = false
    }

    private func appendLog(_ result: BrewCommandResult, recordsIssue: Bool = true) {
        let output = result.output.isEmpty ? "(no output)" : result.output
        commandLog.append("\n\n$ \(result.command)\nExit code: \(result.exitCode)\n\(output)")

        if result.output.localizedCaseInsensitiveContains("not writable")
            || result.output.localizedCaseInsensitiveContains("permission denied") {
            permissionNotice = "Homebrew reported a permissions issue. Installs and upgrades may need administrator access or corrected Homebrew folder ownership outside Publican."
        }

        if recordsIssue, let issue = Self.issue(for: result) {
            lastCommandIssue = issue
        }
    }

    private static func issue(for error: Error) -> BrewCommandIssue {
        BrewCommandIssue(
            title: "Command could not start",
            message: error.localizedDescription,
            guidance: "Check that Homebrew and the Xcode Command Line Tools are installed, then try the action again.",
            command: "Publican could not run the requested command."
        )
    }

    private static func issue(for result: BrewCommandResult) -> BrewCommandIssue? {
        guard result.exitCode != 0 else { return nil }

        let output = result.output
        let lowercased = output.lowercased()

        if lowercased.contains("permission denied")
            || lowercased.contains("not writable")
            || lowercased.contains("operation not permitted") {
            return BrewCommandIssue(
                title: "Homebrew permission issue",
                message: "Homebrew could not write to a folder or file it needs.",
                guidance: "Fix the ownership or permissions mentioned in the command output, then run the action again.",
                command: result.command
            )
        }

        if lowercased.contains("xcode")
            || lowercased.contains("command line tools")
            || lowercased.contains("clt") {
            return BrewCommandIssue(
                title: "Xcode Command Line Tools issue",
                message: "Homebrew reported a problem with Apple's command line developer tools.",
                guidance: "Install or update the Xcode Command Line Tools, then retry the Homebrew action.",
                command: result.command
            )
        }

        if lowercased.contains("no available formula")
            || lowercased.contains("no available cask")
            || lowercased.contains("no formulae or casks found")
            || lowercased.contains("not found") {
            return BrewCommandIssue(
                title: "Package not found",
                message: "Homebrew could not find the requested package.",
                guidance: "Check the package name, try a broader search term, or review the raw Homebrew output for spelling suggestions.",
                command: result.command
            )
        }

        if lowercased.contains("already installed") {
            return BrewCommandIssue(
                title: "Package already installed",
                message: "Homebrew says this package is already installed.",
                guidance: "Refresh installed packages, or use upgrade if a newer version is available.",
                command: result.command
            )
        }

        if lowercased.contains("is not installed")
            || lowercased.contains("not installed") {
            return BrewCommandIssue(
                title: "Package is not installed",
                message: "Homebrew could not uninstall or upgrade a package that is not currently installed.",
                guidance: "Refresh installed packages and confirm the package is still present before running the action again.",
                command: result.command
            )
        }

        if lowercased.contains("timed out")
            || lowercased.contains("could not resolve")
            || lowercased.contains("failed to download")
            || lowercased.contains("network")
            || lowercased.contains("curl:") {
            return BrewCommandIssue(
                title: "Network or download issue",
                message: "Homebrew could not reach or download something it needs.",
                guidance: "Check the network connection, VPN/proxy settings, and the raw command output, then try again.",
                command: result.command
            )
        }

        if lowercased.contains("quarantine")
            || lowercased.contains("gatekeeper")
            || lowercased.contains("damaged and can't be opened")
            || lowercased.contains("malware") {
            return BrewCommandIssue(
                title: "macOS security blocked a cask",
                message: "macOS security checks appear to have blocked an app installed by Homebrew.",
                guidance: "Review the cask output. For trusted unsigned apps, you may need to remove quarantine manually or open via Finder's right-click Open flow.",
                command: result.command
            )
        }

        let message = output.isEmpty
            ? "Homebrew exited with code \(result.exitCode) and did not return any output."
            : "Homebrew exited with code \(result.exitCode)."

        return BrewCommandIssue(
            title: "Homebrew command failed",
            message: message,
            guidance: "Review the raw command output below. Publican preserved the original Homebrew message so the exact failure is visible.",
            command: result.command
        )
    }

    private static func parseLines(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseOutdatedLines(_ output: String) -> [String] {
        parseLines(output).compactMap { line in
            line.split(separator: " ").first.map(String.init)
        }
    }

    private static func parseOutdatedJSON(
        _ output: String,
        kind: BrewPackageKind,
        installedIDs: Set<String>
    ) -> [BrewPackage] {
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let key = kind == .formula ? "formulae" : "casks"
        guard let rows = root[key] as? [[String: Any]] else { return [] }

        return rows.compactMap { row in
            let name = stringValue(row["name"])
                ?? stringValue(row["token"])
                ?? stringValue(row["full_name"])
                ?? stringValue(row["full_token"])
            guard let name else { return nil }

            let installedVersion = stringValue(row["installed_versions"])
                ?? stringValue(row["installed_version"])
                ?? stringValue(row["installed"])
            let currentVersion = stringValue(row["current_version"])
                ?? stringValue(row["current"])
                ?? stringValue(row["version"])
                ?? stringValue(row["latest_version"])

            return BrewPackage(
                name: name,
                kind: kind,
                installed: installedIDs.contains("\(kind.rawValue):\(name)"),
                installedVersion: installedVersion,
                currentVersion: currentVersion
            )
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let strings as [String]:
            let joined = strings.filter { !$0.isEmpty }.joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        case let numbers as [NSNumber]:
            let joined = numbers.map { $0.stringValue }.joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func parseSearchInfo(_ output: String, installedIDs: Set<String>) -> [BrewPackage] {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BrewInfoPayload.self, from: data) else {
            return []
        }

        let formulae = payload.formulae.map { formula in
            BrewPackage(
                name: formula.name,
                kind: .formula,
                installed: installedIDs.contains("\(BrewPackageKind.formula.rawValue):\(formula.name)"),
                currentVersion: formula.versions?.stable
            )
        }

        let casks = payload.casks.map { cask in
            BrewPackage(
                name: cask.token,
                kind: .cask,
                installed: installedIDs.contains("\(BrewPackageKind.cask.rawValue):\(cask.token)"),
                currentVersion: cask.version
            )
        }

        return formulae + casks
    }

    private static func parseDoctorOutput(_ result: BrewCommandResult) -> [BrewHealthIssue] {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return [] }

        if result.exitCode == 0 && output.localizedCaseInsensitiveContains("ready to brew") {
            return []
        }

        let sections = output
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return sections.map { section in
            let lines = parseLines(section)
            let title = lines.first?.replacingOccurrences(of: "Warning: ", with: "") ?? "Homebrew doctor warning"
            let severity: BrewHealthIssue.Severity = section.localizedCaseInsensitiveContains("error:") ? .error : .warning
            return BrewHealthIssue(title: title, detail: section, guidance: guidance(forHealthText: section), severity: severity)
        }
    }

    private static func checkWritablePaths(_ paths: [String]) -> [BrewHealthIssue] {
        paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            guard !FileManager.default.isWritableFile(atPath: path) else { return nil }

            return BrewHealthIssue(
                title: "\(path) is not writable",
                detail: "Homebrew installs and upgrades may fail until this folder's ownership or permissions are corrected outside Publican.",
                guidance: "This is a Homebrew/user permissions issue rather than a Publican issue. Review the owner of \(path), then fix it from Terminal with an appropriate chown/chmod command for your Mac user.",
                severity: .warning
            )
        }
    }

    private static func guidance(forHealthText text: String) -> String? {
        let lowercased = text.lowercased()

        if lowercased.contains("not writable") || lowercased.contains("permission denied") {
            return "Homebrew cannot write to a folder it needs. Fix the folder ownership or permissions from Terminal, then run the health check again."
        }

        if lowercased.contains("unbrewed") {
            return "Homebrew found files in its prefix that it did not install. Usually this is not urgent, but it can interfere with builds if those files shadow Homebrew-managed files."
        }

        if lowercased.contains("outdated") {
            return "Run Brew Update, then review the Outdated tab and upgrade selected packages when convenient."
        }

        if lowercased.contains("xcode") || lowercased.contains("command line tools") {
            return "Install or update Apple's Xcode Command Line Tools, then rerun this check."
        }

        return "Review the raw Homebrew doctor message below. Publican is showing the original output so the exact Homebrew warning is preserved."
    }

    private static func parsePackageInfo(from output: String, package: BrewPackage) -> BrewPackageInfo? {
        guard let data = output.data(using: .utf8) else { return nil }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(BrewInfoPayload.self, from: data)

            switch package.kind {
            case .formula:
                guard let formula = payload.formulae.first else { return nil }
                return BrewPackageInfo(
                    name: formula.name,
                    displayName: formula.fullName ?? formula.name,
                    kind: .formula,
                    description: formula.desc,
                    homepage: formula.homepage,
                    version: formula.versions?.stable,
                    installedVersions: formula.installed?.map(\.version) ?? [],
                    dependencies: formula.dependencies ?? [],
                    caveats: formula.caveats,
                    tap: formula.tap,
                    rawInfo: output
                )
            case .cask:
                guard let cask = payload.casks.first else { return nil }
                return BrewPackageInfo(
                    name: cask.token,
                    displayName: cask.name?.first ?? cask.fullToken ?? cask.token,
                    kind: .cask,
                    description: cask.desc,
                    homepage: cask.homepage,
                    version: cask.version,
                    installedVersions: cask.installed.map { [$0] } ?? [],
                    dependencies: [],
                    caveats: cask.caveats,
                    tap: cask.tap,
                    rawInfo: output
                )
            }
        } catch {
            return nil
        }
    }
}

private struct BrewInfoPayload: Decodable {
    let formulae: [BrewFormulaInfo]
    let casks: [BrewCaskInfo]
}

private struct BrewFormulaInfo: Decodable {
    let name: String
    let fullName: String?
    let desc: String?
    let homepage: String?
    let versions: BrewFormulaVersions?
    let installed: [BrewFormulaInstalled]?
    let dependencies: [String]?
    let caveats: String?
    let tap: String?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case desc
        case homepage
        case versions
        case installed
        case dependencies
        case caveats
        case tap
    }
}

private struct BrewFormulaVersions: Decodable {
    let stable: String?
}

private struct BrewFormulaInstalled: Decodable {
    let version: String
}

private struct BrewCaskInfo: Decodable {
    let token: String
    let fullToken: String?
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String?
    let installed: String?
    let caveats: String?
    let tap: String?

    enum CodingKeys: String, CodingKey {
        case token
        case fullToken = "full_token"
        case name
        case desc
        case homepage
        case version
        case installed
        case caveats
        case tap
    }
}
