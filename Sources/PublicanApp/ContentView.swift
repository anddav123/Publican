import SwiftUI
import AppKit

struct ContentView: View {
    private let minimumWindowSize = NSSize(width: 640, height: 560)
    private let homebrewInstallCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    @StateObject private var store = BrewStore()
    @State private var selectedInstalledPackageID: BrewPackage.ID?
    @State private var selectedSearchResultID: BrewPackage.ID?
    @State private var selectedOutdatedPackageIDs = Set<BrewPackage.ID>()
    @State private var installedFilter = ""
    @State private var outdatedFilter = ""
    @AppStorage("autoRefreshInstalledOnLaunch") private var autoRefreshInstalledOnLaunch = true
    @AppStorage("autoRefreshOutdatedOnLaunch") private var autoRefreshOutdatedOnLaunch = true
    @AppStorage("commandOutputExpandedByDefault") private var showsCommandOutput = true
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        Group {
            if store.isHomebrewAvailable {
                GeometryReader { geometry in
                    let showSidebar = geometry.size.width >= 1120
                    let isCompact = geometry.size.width < 1120
                    let isNarrow = geometry.size.width < 780

                    Group {
                        if showSidebar {
                            HStack(spacing: 0) {
                                sidebar
                                    .frame(width: 180)

                                Divider()

                                mainContent(isCompact: isCompact, isNarrow: isNarrow)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            compactShell(isNarrow: isNarrow)
                        }
                    }
                }
            } else {
                missingHomebrewView
            }
        }
        .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
        .background(WindowSizingView(minimumSize: minimumWindowSize))
        .task {
            guard store.isHomebrewAvailable else { return }
            if autoRefreshInstalledOnLaunch {
                await store.refreshInstalled()
            }
            if autoRefreshOutdatedOnLaunch {
                await store.refreshOutdated()
            }
            searchFieldFocused = true
        }
        .onChange(of: selectedInstalledPackageID) { packageID in
            loadInfo(for: packageID, in: store.installedPackages)
        }
        .onChange(of: selectedSearchResultID) { packageID in
            loadInfo(for: packageID, in: store.searchResults)
        }
        .onChange(of: selectedOutdatedPackageIDs) { packageIDs in
            loadInfo(for: packageIDs.first, in: store.outdatedPackages)
        }
        .alert(item: $store.pendingCommand) { pendingCommand in
            Alert(
                title: Text(pendingCommand.title),
                message: Text("\(pendingCommand.message)\n\n\(pendingCommand.command)"),
                primaryButton: .default(Text("Run")) {
                    let action = pendingCommand.action
                    store.clearPendingCommand()
                    Task { await action() }
                },
                secondaryButton: .cancel {
                    store.clearPendingCommand()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanRefreshInstalled)) { _ in
            Task { await store.refreshInstalled() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanRefreshOutdated)) { _ in
            Task { await store.refreshOutdated() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanSearch)) { _ in
            Task { await store.search() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanFocusSearch)) { _ in
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanBrewUpdate)) { _ in
            store.update()
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanHealthCheck)) { _ in
            Task { await store.checkHealth() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .publicanToggleCommandOutput)) { _ in
            withAnimation(.snappy) {
                showsCommandOutput.toggle()
            }
        }
    }

    private var missingHomebrewView: some View {
        VStack(spacing: 18) {
            Image(systemName: "mug")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Homebrew Not Found")
                    .font(.title2.bold())
                Text("Publican needs Homebrew installed before it can search, install, update, or manage packages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Official install command")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(homebrewInstallCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 560)

            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "https://brew.sh/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Homebrew Install Page", systemImage: "safari")
                }

                Button {
                    copyToPasteboard(homebrewInstallCommand)
                } label: {
                    Label("Copy Install Command", systemImage: "doc.on.doc")
                }

                Button {
                    store.detectHomebrew()
                } label: {
                    Label("Re-check Homebrew", systemImage: "arrow.clockwise")
                }
            }

            Text("After installing Homebrew, reopen Publican or use Re-check Homebrew.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Publican")
                    .font(.title2.bold())
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button {
                Task { await store.refreshInstalled() }
            } label: {
                Label("Refresh Installed", systemImage: "arrow.clockwise")
            }
            .disabled(store.isBusy)

            Button {
                store.update()
            } label: {
                Label("Brew Update", systemImage: "square.and.arrow.down")
            }
            .disabled(store.isBusy)

            Button {
                Task { await store.refreshOutdated() }
            } label: {
                Label("Check Outdated", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }
            .disabled(store.isBusy)

            Button {
                Task { await store.checkHealth() }
            } label: {
                Label("Health Check", systemImage: "stethoscope")
            }
            .disabled(store.isBusy)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                countRow("Formulae", count: store.installedPackages.filter { $0.kind == .formula }.count)
                countRow("Casks", count: store.installedPackages.filter { $0.kind == .cask }.count)
                countRow("Outdated", count: store.outdatedPackages.count)
                countRow("Health", count: store.healthIssues.filter { $0.severity != .ok }.count)
            }
            .font(.caption)

            if let permissionNotice = store.permissionNotice {
                Divider()

                Label(permissionNotice, systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let path = store.brewPath {
                Label(path, systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func mainContent(isCompact: Bool, isNarrow: Bool) -> some View {
        Group {
            if isCompact {
                compactMainContent(isNarrow: isNarrow)
            } else {
                regularMainContent
            }
        }
    }

    private func compactShell(isNarrow: Bool) -> some View {
        VStack(spacing: 0) {
            compactActionBar

            Divider()

            compactMainContent(isNarrow: isNarrow)
        }
    }

    private var compactActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("Publican")
                    .font(.headline)

                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                compactActionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Publican")
                        .font(.headline)
                    Spacer()
                    if store.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                compactActionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var compactActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                compactActionButton("Installed", systemImage: "arrow.clockwise") {
                    Task { await store.refreshInstalled() }
                }

                compactActionButton("Update", systemImage: "square.and.arrow.down") {
                    store.update()
                }

                compactActionButton("Outdated", systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                    Task { await store.refreshOutdated() }
                }

                compactActionButton("Health", systemImage: "stethoscope") {
                    Task { await store.checkHealth() }
                }
            }

            HStack(spacing: 8) {
                compactIconButton("Refresh Installed", systemImage: "arrow.clockwise") {
                    Task { await store.refreshInstalled() }
                }

                compactIconButton("Brew Update", systemImage: "square.and.arrow.down") {
                    store.update()
                }

                compactIconButton("Check Outdated", systemImage: "exclamationmark.arrow.triangle.2.circlepath") {
                    Task { await store.refreshOutdated() }
                }

                compactIconButton("Health Check", systemImage: "stethoscope") {
                    Task { await store.checkHealth() }
                }
            }
        }
    }

    private func compactActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .disabled(store.isBusy)
    }

    private func compactIconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .help(title)
        .disabled(store.isBusy)
    }

    private var regularMainContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TabView {
                    browseTab(isNarrow: false)
                        .tabItem {
                            Label("Browse", systemImage: "magnifyingglass")
                        }

                    outdatedTab
                        .tabItem {
                            Label("Outdated", systemImage: "arrow.up.circle")
                        }

                    healthTab
                        .tabItem {
                            Label("Health", systemImage: "stethoscope")
                        }
                }

                commandOutput
                    .frame(minHeight: showsCommandOutput ? 180 : 0)
            }
            .frame(maxWidth: .infinity)

            Divider()

            packageInfoPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 320)
        }
    }

    private func compactMainContent(isNarrow: Bool) -> some View {
        VStack(spacing: 0) {
            TabView {
                browseTab(isNarrow: isNarrow)
                    .tabItem {
                        Label("Browse", systemImage: "magnifyingglass")
                    }

                outdatedTab
                    .tabItem {
                        Label("Outdated", systemImage: "arrow.up.circle")
                    }

                healthTab
                    .tabItem {
                        Label("Health", systemImage: "stethoscope")
                    }

                packageInfoPanel
                    .tabItem {
                        Label("Info", systemImage: "info.circle")
                    }
            }

            commandOutput
                .frame(height: showsCommandOutput ? 170 : 54)
        }
    }

    private func browseTab(isNarrow: Bool) -> some View {
        VStack(spacing: 0) {
            searchBar

            Group {
                if isNarrow {
                    TabView {
                        installedPackagePanel
                            .tabItem {
                                Label("Installed", systemImage: "shippingbox")
                            }

                        searchResultsPanel
                            .tabItem {
                                Label("Search Results", systemImage: "magnifyingglass")
                            }
                    }
                } else {
                    HStack(spacing: 0) {
                        installedPackagePanel
                            .frame(minWidth: 230, maxWidth: .infinity)

                        Divider()

                        searchResultsPanel
                            .frame(minWidth: 230, maxWidth: .infinity)
                    }
                }
            }
            .frame(minHeight: 320)
        }
    }

    private var installedPackagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterField("Filter installed", text: $installedFilter)

            packagePanel(
                title: "Installed Formulae & Casks",
                packages: filteredInstalledPackages,
                selection: $selectedInstalledPackageID,
                actionTitle: "Uninstall",
                actionIcon: "trash",
                primaryAction: .uninstall,
                action: { package in
                    store.uninstall(package)
                }
            )
        }
    }

    private var searchResultsPanel: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                searchResultPackagePanel(
                    title: "Formula Results",
                    packages: formulaSearchResults
                )

                Divider()

                searchResultPackagePanel(
                    title: "Cask Results",
                    packages: caskSearchResults
                )
            }

            TabView {
                searchResultPackagePanel(
                    title: "Formula Results",
                    packages: formulaSearchResults
                )
                .tabItem {
                    Label("Formulae", systemImage: "terminal")
                }

                searchResultPackagePanel(
                    title: "Cask Results",
                    packages: caskSearchResults
                )
                .tabItem {
                    Label("Casks", systemImage: "app")
                }
            }
        }
    }

    private func searchResultPackagePanel(title: String, packages: [BrewPackage]) -> some View {
        packagePanel(
            title: title,
            packages: packages,
            selection: $selectedSearchResultID,
            actionTitle: "Install",
            actionIcon: "plus.circle",
            primaryAction: .install,
            action: { package in
                store.install(package)
            }
        )
    }

    private var outdatedTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Outdated Formulae & Casks")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshOutdated() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isBusy)
            }

            filterField("Filter outdated", text: $outdatedFilter)

            ZStack {
                Table(filteredOutdatedPackages, selection: $selectedOutdatedPackageIDs) {
                    TableColumn("Name") { package in
                        Text(package.name)
                            .contextMenu {
                                packageActionItems(
                                    package: package,
                                    primaryTitle: "Upgrade",
                                    primaryAction: .upgrade,
                                    action: { selectedPackage in
                                        store.upgrade(selectedPackage)
                                    }
                                )
                            }
                    }
                    TableColumn("Type") { package in
                        Text(package.kind.rawValue)
                    }
                    TableColumn("Installed") { package in
                        Text(package.installedVersion ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Current") { package in
                        Text(package.currentVersion ?? "Unknown")
                            .foregroundStyle(package.currentVersion == nil ? .secondary : .primary)
                    }
                    TableColumn("State") { _ in
                        Text("Outdated")
                            .foregroundStyle(.orange)
                    }
                }

                if filteredOutdatedPackages.isEmpty {
                    emptyState(
                        title: store.outdatedPackages.isEmpty ? "No Outdated Packages" : "No Matching Packages",
                        message: store.outdatedPackages.isEmpty ? "Run Check Outdated to refresh. If Homebrew is current, this list will stay empty." : "Clear or change the outdated filter."
                    )
                }
            }

            HStack {
                Text("\(selectedOutdatedPackages.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedOutdatedPackages.count == 1, let selectedPackage = selectedOutdatedPackages.first {
                    packageActionsMenu(
                        package: selectedPackage,
                        primaryTitle: "Upgrade",
                        primaryAction: .upgrade,
                        action: { package in
                            store.upgrade(package)
                        }
                    )
                }
                Button {
                    store.upgrade(selectedOutdatedPackages)
                } label: {
                    Label(selectedOutdatedPackages.count > 1 ? "Upgrade Selected (\(selectedOutdatedPackages.count))" : "Upgrade Selected", systemImage: "arrow.up.circle")
                }
                .disabled(selectedOutdatedPackages.isEmpty || store.isBusy)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    private func filterField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
    }

    private var healthTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew Health")
                        .font(.headline)
                    Text(store.healthSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await store.checkHealth() }
                } label: {
                    Label("Run Doctor", systemImage: "stethoscope")
                }
                .disabled(store.isBusy)
            }

            ScrollView {
                ZStack {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.healthIssues) { issue in
                            healthIssueRow(issue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if store.healthIssues.isEmpty {
                        emptyState(
                            title: "Health Not Checked",
                            message: "Run Doctor to check Homebrew health and see guidance here."
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    private func healthIssueRow(_ issue: BrewHealthIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: healthIcon(for: issue.severity))
                .foregroundStyle(healthColor(for: issue.severity))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title)
                    .font(.subheadline.bold())

                if let guidance = issue.guidance {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .ok ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup("Raw detail") {
                    Text(issue.detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var searchBar: some View {
        ViewThatFits(in: .horizontal) {
            horizontalSearchBarContent

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    searchField
                    searchButton
                }
            }
        }
        .padding()
    }

    private var horizontalSearchBarContent: some View {
        HStack(alignment: .bottom, spacing: 8) {
            searchField
            searchButton
        }
    }

    private var searchField: some View {
        TextField("Search Homebrew", text: $store.searchText)
            .textFieldStyle(.roundedBorder)
            .focused($searchFieldFocused)
            .frame(minWidth: 160)
            .onSubmit {
                Task { await store.search() }
            }
            .onAppear {
                searchFieldFocused = true
            }
    }

    private var searchButton: some View {
        Button {
            Task { await store.search() }
        } label: {
            Label("Search", systemImage: "magnifyingglass")
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(store.isBusy)
    }

    private func packagePanel(
        title: String,
        packages: [BrewPackage],
        selection: Binding<BrewPackage.ID?>,
        actionTitle: String,
        actionIcon: String,
        primaryAction: BrewPackageAction,
        action: @escaping (BrewPackage) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(packages.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Table(packages, selection: selection) {
                    TableColumn("Name") { package in
                        Text(package.name)
                            .contextMenu {
                                packageActionItems(
                                    package: package,
                                    primaryTitle: actionTitle,
                                    primaryAction: primaryAction,
                                    action: action
                                )
                            }
                    }
                    TableColumn("Type") { package in
                        Text(package.kind.rawValue)
                    }
                    TableColumn("State") { package in
                        Text(package.installed ? "Installed" : "Available")
                            .foregroundStyle(package.installed ? .green : .secondary)
                    }
                }

                if packages.isEmpty {
                    emptyState(
                        title: emptyTitle(for: title),
                        message: emptyMessage(for: title)
                    )
                }
            }

            HStack {
                Spacer()
                if let selectedPackage = selectedPackage(in: packages, selection: selection.wrappedValue) {
                    packageActionsMenu(
                        package: selectedPackage,
                        primaryTitle: actionTitle,
                        primaryAction: primaryAction,
                        action: action
                    )
                }
                Button {
                    if let package = selectedPackage(in: packages, selection: selection.wrappedValue) {
                        action(package)
                    }
                } label: {
                    Label(actionTitle, systemImage: actionIcon)
                }
                .disabled(!canRunPrimaryAction(primaryAction, for: selectedPackage(in: packages, selection: selection.wrappedValue)) || store.isBusy)
            }
        }
        .padding()
    }

    private func canRunPrimaryAction(_ action: BrewPackageAction, for package: BrewPackage?) -> Bool {
        guard let package else { return false }

        switch action {
        case .install:
            return !package.installed
        case .uninstall, .upgrade, .info:
            return true
        }
    }

    private func selectedPackage(in packages: [BrewPackage], selection: BrewPackage.ID?) -> BrewPackage? {
        guard let selection else { return nil }
        return packages.first { $0.id == selection }
    }

    private func packageActionsMenu(
        package: BrewPackage,
        primaryTitle: String,
        primaryAction: BrewPackageAction,
        action: @escaping (BrewPackage) -> Void
    ) -> some View {
        Menu {
            packageActionItems(
                package: package,
                primaryTitle: primaryTitle,
                primaryAction: primaryAction,
                action: action
            )
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .disabled(store.isBusy)
    }

    @ViewBuilder
    private func packageActionItems(
        package: BrewPackage,
        primaryTitle: String,
        primaryAction: BrewPackageAction,
        action: @escaping (BrewPackage) -> Void
    ) -> some View {
        Button(primaryTitle) {
            action(package)
        }

        Button("Load Info") {
            Task { await store.loadInfo(for: package) }
        }

        Button("Open Homepage") {
            Task {
                guard let homepage = await store.homepage(for: package),
                      let url = URL(string: homepage) else {
                    return
                }
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("Copy Package Name") {
            copyToPasteboard(package.name)
        }

        Button("Copy \(primaryTitle) Command") {
            if let command = store.commandText(for: primaryAction, package: package) {
                copyToPasteboard(command)
            }
        }

        Button("Copy Info Command") {
            if let command = store.commandText(for: .info, package: package) {
                copyToPasteboard(command)
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var packageInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Package Info")
                    .font(.headline)
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    packageInfoHeader(store.packageInfo)

                    if let description = store.packageInfo.description {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Type", store.packageInfo.kind.rawValue)
                        infoRow("Version", store.packageInfo.version ?? "Unknown")
                        infoRow("Installed", store.packageInfo.installedVersions.isEmpty ? "Not installed" : store.packageInfo.installedVersions.joined(separator: ", "))
                        infoRow("Tap", store.packageInfo.tap ?? "Unknown")
                    }

                    if let homepage = store.packageInfo.homepage {
                        infoRow("Homepage", homepage)
                    }

                    if !store.packageInfo.dependencies.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dependencies")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(store.packageInfo.dependencies.joined(separator: ", "))
                                .font(.caption)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let caveats = store.packageInfo.caveats, !caveats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Caveats")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(caveats)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !store.packageInfo.rawInfo.isEmpty {
                        DisclosureGroup("Raw JSON") {
                            Text(store.packageInfo.rawInfo)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let permissionNotice = store.permissionNotice {
                Label(permissionNotice, systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func packageInfoHeader(_ info: BrewPackageInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.displayName)
                .font(.title3.bold())
                .lineLimit(2)
            if !info.name.isEmpty && info.name != info.displayName {
                Text(info.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commandOutput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Command Output")
                    .font(.headline)
                Spacer()
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    withAnimation(.snappy) {
                        showsCommandOutput.toggle()
                    }
                } label: {
                    Image(systemName: showsCommandOutput ? "chevron.down" : "chevron.right")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(showsCommandOutput ? "Collapse command output" : "Expand command output")
            }

            if showsCommandOutput {
                ScrollView {
                    Text(store.commandLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func countRow(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding()
    }

    private func emptyTitle(for panelTitle: String) -> String {
        switch panelTitle {
        case "Installed Formulae & Casks":
            return store.installedPackages.isEmpty ? "No Installed Packages Loaded" : "No Matching Packages"
        case "Formula Results":
            return store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search Formulae" : "No Formula Results"
        case "Cask Results":
            return store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search Casks" : "No Cask Results"
        default:
            return "No Packages"
        }
    }

    private func emptyMessage(for panelTitle: String) -> String {
        switch panelTitle {
        case "Installed Formulae & Casks":
            return store.installedPackages.isEmpty ? "Use Refresh Installed to load Homebrew packages." : "Clear or change the installed filter."
        case "Formula Results":
            return store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a package name above to search Homebrew formulae." : "Try a broader search term."
        case "Cask Results":
            return store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter an app name above to search Homebrew casks." : "Try a broader search term."
        default:
            return "Nothing to show here yet."
        }
    }

    private func healthIcon(for severity: BrewHealthIssue.Severity) -> String {
        switch severity {
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private func healthColor(for severity: BrewHealthIssue.Severity) -> Color {
        switch severity {
        case .ok:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var filteredInstalledPackages: [BrewPackage] {
        filteredPackages(store.installedPackages, by: installedFilter)
    }

    private var filteredOutdatedPackages: [BrewPackage] {
        filteredPackages(store.outdatedPackages, by: outdatedFilter)
    }

    private var formulaSearchResults: [BrewPackage] {
        store.searchResults.filter { $0.kind == .formula }
    }

    private var caskSearchResults: [BrewPackage] {
        store.searchResults.filter { $0.kind == .cask }
    }

    private var selectedOutdatedPackages: [BrewPackage] {
        filteredOutdatedPackages.filter { selectedOutdatedPackageIDs.contains($0.id) }
    }

    private func filteredPackages(_ packages: [BrewPackage], by filter: String) -> [BrewPackage] {
        let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilter.isEmpty else { return packages }

        return packages.filter { package in
            package.name.localizedCaseInsensitiveContains(trimmedFilter)
                || package.kind.rawValue.localizedCaseInsensitiveContains(trimmedFilter)
                || (package.installedVersion?.localizedCaseInsensitiveContains(trimmedFilter) ?? false)
                || (package.currentVersion?.localizedCaseInsensitiveContains(trimmedFilter) ?? false)
        }
    }

    private func loadInfo(for packageID: BrewPackage.ID?, in packages: [BrewPackage]) {
        guard let packageID,
              let package = packages.first(where: { $0.id == packageID }) else {
            return
        }

        Task { await store.loadInfo(for: package) }
    }
}
