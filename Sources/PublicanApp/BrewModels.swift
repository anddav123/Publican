import Foundation

enum BrewPackageKind: String, CaseIterable, Identifiable {
    case formula = "Formula"
    case cask = "Cask"

    var id: String { rawValue }

    var listArguments: [String] {
        switch self {
        case .formula:
            return ["list", "--formula"]
        case .cask:
            return ["list", "--cask"]
        }
    }

    var searchPrefix: String {
        switch self {
        case .formula:
            return "formula:"
        case .cask:
            return "cask:"
        }
    }

    var installArgumentsPrefix: [String] {
        switch self {
        case .formula:
            return ["install"]
        case .cask:
            return ["install", "--cask"]
        }
    }

    var uninstallArgumentsPrefix: [String] {
        switch self {
        case .formula:
            return ["uninstall"]
        case .cask:
            return ["uninstall", "--cask"]
        }
    }

    var infoArgumentsPrefix: [String] {
        switch self {
        case .formula:
            return ["info"]
        case .cask:
            return ["info", "--cask"]
        }
    }

    var jsonInfoArgumentsPrefix: [String] {
        switch self {
        case .formula:
            return ["info", "--json=v2"]
        case .cask:
            return ["info", "--cask", "--json=v2"]
        }
    }

    var outdatedArguments: [String] {
        switch self {
        case .formula:
            return ["outdated", "--formula"]
        case .cask:
            return ["outdated", "--cask"]
        }
    }

    var outdatedJSONArguments: [String] {
        switch self {
        case .formula:
            return ["outdated", "--formula", "--json=v2"]
        case .cask:
            return ["outdated", "--cask", "--json=v2"]
        }
    }

    var upgradeArgumentsPrefix: [String] {
        switch self {
        case .formula:
            return ["upgrade"]
        case .cask:
            return ["upgrade", "--cask"]
        }
    }
}

struct BrewPackage: Identifiable, Hashable {
    let name: String
    let kind: BrewPackageKind
    let installed: Bool
    let installedVersion: String?
    let currentVersion: String?

    init(
        name: String,
        kind: BrewPackageKind,
        installed: Bool,
        installedVersion: String? = nil,
        currentVersion: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.installed = installed
        self.installedVersion = installedVersion
        self.currentVersion = currentVersion
    }

    var id: String {
        "\(kind.rawValue):\(name)"
    }
}

struct BrewPendingCommand: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let command: String
    let action: () async -> Void
}

enum BrewPackageAction {
    case install
    case uninstall
    case upgrade
    case info

    func arguments(for package: BrewPackage) -> [String] {
        switch self {
        case .install:
            return package.kind.installArgumentsPrefix + [package.name]
        case .uninstall:
            return package.kind.uninstallArgumentsPrefix + [package.name]
        case .upgrade:
            return package.kind.upgradeArgumentsPrefix + [package.name]
        case .info:
            return package.kind.infoArgumentsPrefix + [package.name]
        }
    }
}

struct BrewPackageInfo: Equatable {
    var name: String
    var displayName: String
    var kind: BrewPackageKind
    var description: String?
    var homepage: String?
    var version: String?
    var installedVersions: [String]
    var dependencies: [String]
    var caveats: String?
    var tap: String?
    var rawInfo: String

    static let placeholder = BrewPackageInfo(
        name: "",
        displayName: "Select a package",
        kind: .formula,
        description: "Select a package to view structured Homebrew details.",
        homepage: nil,
        version: nil,
        installedVersions: [],
        dependencies: [],
        caveats: nil,
        tap: nil,
        rawInfo: ""
    )
}

struct BrewHealthIssue: Identifiable, Equatable {
    enum Severity: String {
        case ok = "OK"
        case warning = "Warning"
        case error = "Error"
    }

    let id = UUID()
    let title: String
    let detail: String
    let guidance: String?
    let severity: Severity

    init(title: String, detail: String, guidance: String? = nil, severity: Severity) {
        self.title = title
        self.detail = detail
        self.guidance = guidance
        self.severity = severity
    }
}
