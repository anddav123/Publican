import Foundation

extension Notification.Name {
    static let publicanRefreshInstalled = Notification.Name("publicanRefreshInstalled")
    static let publicanRefreshOutdated = Notification.Name("publicanRefreshOutdated")
    static let publicanSearch = Notification.Name("publicanSearch")
    static let publicanFocusSearch = Notification.Name("publicanFocusSearch")
    static let publicanBrewUpdate = Notification.Name("publicanBrewUpdate")
    static let publicanHealthCheck = Notification.Name("publicanHealthCheck")
    static let publicanToggleCommandOutput = Notification.Name("publicanToggleCommandOutput")
}

enum PublicanCommandPoster {
    static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
