import SwiftUI
import AppKit

struct ContentView: View {
    private let minimumWindowSize = NSSize(width: 640, height: 560)
    private let homebrewInstallCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    @StateObject private var store = BrewStore()
    @State private var selectedSearchResultID: BrewPackage.ID?
    @State private var selectedManagedPackageIDs = Set<BrewPackage.ID>()
    @State private var activePackageSelection: PackageSelection?
    @State private var manageFilter = ""
    @State private var manageSortOrder = [KeyPathComparator(\BrewPackage.name)]
    @State private var searchSortOrder = [KeyPathComparator(\BrewPackage.name)]
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
        .onChange(of: selectedSearchResultID) { packageID in
            loadInfo(for: packageID, in: store.searchResults, source: .search)
        }
        .onChange(of: selectedManagedPackageIDs) { packageIDs in
            loadInfo(for: packageIDs.first, in: managedPackages, source: .manage)
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
        .padding(10)
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
                    searchTab
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }

                    manageTab
                        .tabItem {
                            Label("Manage", systemImage: "shippingbox")
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
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
        }
    }

    private func compactMainContent(isNarrow: Bool) -> some View {
        VStack(spacing: 0) {
            TabView {
                searchTab
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                manageTab
                    .tabItem {
                        Label("Manage", systemImage: "shippingbox")
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

    private var searchTab: some View {
        VStack(spacing: 0) {
            searchBar

            searchResultsPanel
            .frame(minHeight: 320)
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
            sortOrder: $searchSortOrder,
            actionTitle: "Install",
            actionIcon: "plus.circle",
            primaryAction: .install,
            action: { package in
                store.install(package)
            }
        )
    }

    private var manageTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Installed Formulae & Casks")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshInstalled() }
                } label: {
                    Label("Refresh Installed", systemImage: "arrow.clockwise")
                }
                .disabled(store.isBusy)

                Button {
                    Task { await store.refreshOutdated() }
                } label: {
                    Label("Check Outdated", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
                .disabled(store.isBusy)
            }

            filterField("Filter installed or outdated", text: $manageFilter)

            ZStack {
                Table(managedPackages, selection: $selectedManagedPackageIDs, sortOrder: $manageSortOrder) {
                    TableColumn("Name", value: \BrewPackage.name) { package in
                        Text(package.name)
                            .contextMenu {
                                packageActionItems(
                                    package: package,
                                    primaryTitle: packageIsOutdated(package) ? "Upgrade" : "Uninstall",
                                    primaryAction: packageIsOutdated(package) ? .upgrade : .uninstall,
                                    action: { selectedPackage in
                                        if packageIsOutdated(selectedPackage) {
                                            store.upgrade(selectedPackage)
                                        } else {
                                            store.uninstall(selectedPackage)
                                        }
                                    }
                                )
                            }
                    }
                    TableColumn("Type", value: \BrewPackage.kindSortValue) { package in
                        Text(package.kind.rawValue)
                    }
                    TableColumn("Installed Version", value: \BrewPackage.installedVersionSortValue) { package in
                        Text(manageInstalledVersionText(for: package))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Latest Version", value: \BrewPackage.currentVersionSortValue) { package in
                        Text(manageLatestVersionText(for: package))
                            .foregroundStyle(packageIsOutdated(package) ? .primary : .secondary)
                    }
                    TableColumn("State", value: \BrewPackage.manageStateSortValue) { package in
                        Text(packageIsOutdated(package) ? "Outdated" : "Current")
                            .foregroundStyle(packageIsOutdated(package) ? .orange : .green)
                    }
                }

                if managedPackages.isEmpty {
                    emptyState(
                        title: store.installedPackages.isEmpty ? "No Installed Packages Loaded" : "No Matching Packages",
                        message: store.installedPackages.isEmpty ? "Use Refresh Installed to load Homebrew packages." : "Clear or change the manage filter."
                    )
                }
            }

            HStack {
                Text("\(selectedManagedPackages.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedManagedPackages.count == 1, let selectedPackage = selectedManagedPackages.first {
                    packageActionsMenu(
                        package: selectedPackage,
                        primaryTitle: packageIsOutdated(selectedPackage) ? "Upgrade" : "Uninstall",
                        primaryAction: packageIsOutdated(selectedPackage) ? .upgrade : .uninstall,
                        action: { package in
                            if packageIsOutdated(package) {
                                store.upgrade(package)
                            } else {
                                store.uninstall(package)
                            }
                        }
                    )
                }
                Button {
                    store.upgrade(selectedManagedOutdatedPackages)
                } label: {
                    Label(selectedManagedOutdatedPackages.count > 1 ? "Upgrade Outdated (\(selectedManagedOutdatedPackages.count))" : "Upgrade Outdated", systemImage: "arrow.up.circle")
                }
                .disabled(selectedManagedOutdatedPackages.isEmpty || store.isBusy)
            }
        }
        .padding(10)
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
        .padding(10)
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
        .padding(10)
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
        sortOrder: Binding<[KeyPathComparator<BrewPackage>]>,
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
                Table(packages, selection: selection, sortOrder: sortOrder) {
                    TableColumn("Name", value: \BrewPackage.name) { package in
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
                    TableColumn("Type", value: \BrewPackage.kindSortValue) { package in
                        Text(package.kind.rawValue)
                    }
                    TableColumn("State", value: \BrewPackage.installedStateSortValue) { package in
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
        .padding(10)
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
        let selectedPackage = selectedDetailPackage

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Package Info")
                    .font(.headline)
                Spacer()
                if let selectedPackage {
                    packageStateBadge(selectedPackage)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                if let selectedPackage {
                    VStack(alignment: .leading, spacing: 12) {
                        packageInfoHeader(store.packageInfo, selectedPackage: selectedPackage)

                        packageDetailActions(for: selectedPackage)

                        if let description = store.packageInfo.description {
                            Text(description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        packageMetadataGrid(for: selectedPackage)

                        if let homepage = store.packageInfo.homepage {
                            infoRow("Homepage", homepage)
                        }

                        if !store.packageInfo.dependencies.isEmpty {
                            detailSection(title: "Dependencies") {
                                Text(store.packageInfo.dependencies.joined(separator: ", "))
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let caveats = store.packageInfo.caveats, !caveats.isEmpty {
                            detailSection(title: "Caveats") {
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
                } else {
                    emptyDetailState
                }
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

    private func packageInfoHeader(_ info: BrewPackageInfo, selectedPackage: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.displayName.isEmpty ? selectedPackage.name : info.displayName)
                .font(.title3.bold())
                .lineLimit(2)

            HStack(spacing: 6) {
                Label(selectedPackage.kind.rawValue, systemImage: selectedPackage.kind == .formula ? "terminal" : "app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedPackage.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .textSelection(.enabled)
        }
    }

    private func packageDetailActions(for package: BrewPackage) -> some View {
        let action = primaryDetailAction(for: package)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Button {
                    runPrimaryDetailAction(action, for: package)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .disabled(store.isBusy || !action.isEnabled)

                secondaryDetailButtons(for: package)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    runPrimaryDetailAction(action, for: package)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isBusy || !action.isEnabled)

                secondaryDetailButtons(for: package)
            }
        }
    }

    private func secondaryDetailButtons(for package: BrewPackage) -> some View {
        HStack(spacing: 8) {
            Button {
                openHomepage(for: package)
            } label: {
                Image(systemName: "safari")
                    .frame(width: 18, height: 18)
            }
            .help("Open homepage")
            .disabled(store.isBusy || store.packageInfo.homepage == nil)

            Button {
                copyToPasteboard(package.name)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .help("Copy package name")

            Button {
                Task { await store.loadInfo(for: package) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 18, height: 18)
            }
            .help("Reload package info")
            .disabled(store.isBusy)
        }
        .buttonStyle(.bordered)
    }

    private func packageMetadataGrid(for package: BrewPackage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            metadataRow("Type", package.kind.rawValue)
            metadataRow("State", packageStateText(for: package))
            metadataRow("Version", store.packageInfo.version ?? package.currentVersion ?? "-")
            metadataRow("Installed Version", installedVersionText(for: package))
            if let currentVersion = package.currentVersion {
                metadataRow("Latest Version", currentVersion)
            }
            metadataRow("Tap", store.packageInfo.tap ?? "Unknown")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a Package")
                .font(.headline)
            Text("Choose a package from Search or Manage to view details and actions here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func packageStateBadge(_ package: BrewPackage) -> some View {
        Text(packageStateText(for: package))
            .font(.caption.bold())
            .foregroundStyle(packageIsOutdated(package) ? .orange : (package.installed ? .green : .secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((packageIsOutdated(package) ? Color.orange : (package.installed ? Color.green : Color.secondary)).opacity(0.12))
            .clipShape(Capsule())
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
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.currentOperation ?? "Working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

            if let issue = store.lastCommandIssue {
                commandIssueView(issue)
            } else if let currentOperation = store.currentOperation {
                currentOperationView(currentOperation)
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

    private func currentOperationView(_ operation: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(operation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func commandIssueView(_ issue: BrewCommandIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline.bold())
                Text(issue.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.command)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var formulaSearchResults: [BrewPackage] {
        sortedPackages(store.searchResults.filter { $0.kind == .formula }, using: searchSortOrder)
    }

    private var caskSearchResults: [BrewPackage] {
        sortedPackages(store.searchResults.filter { $0.kind == .cask }, using: searchSortOrder)
    }

    private var managedPackages: [BrewPackage] {
        let outdatedByID = Dictionary(uniqueKeysWithValues: store.outdatedPackages.map { ($0.id, $0) })
        let mergedPackages = store.installedPackages.map { package in
            guard let outdatedPackage = outdatedByID[package.id] else { return package }
            return BrewPackage(
                name: package.name,
                kind: package.kind,
                installed: true,
                installedVersion: outdatedPackage.installedVersion,
                currentVersion: outdatedPackage.currentVersion
            )
        }

        return sortedPackages(filteredPackages(mergedPackages, by: manageFilter), using: manageSortOrder)
    }

    private var selectedManagedPackages: [BrewPackage] {
        managedPackages.filter { selectedManagedPackageIDs.contains($0.id) }
    }

    private var selectedManagedOutdatedPackages: [BrewPackage] {
        selectedManagedPackages.filter(packageIsOutdated)
    }

    private var selectedDetailPackage: BrewPackage? {
        guard let activePackageSelection else { return nil }

        switch activePackageSelection.source {
        case .manage:
            return managedPackages.first { $0.id == activePackageSelection.id }
        case .search:
            return (formulaSearchResults + caskSearchResults).first { $0.id == activePackageSelection.id }
        }
    }

    private func primaryDetailAction(for package: BrewPackage) -> DetailAction {
        if packageIsOutdated(package) {
            return DetailAction(title: "Upgrade", systemImage: "arrow.up.circle", action: .upgrade, isEnabled: true)
        }

        if package.installed {
            return DetailAction(title: "Uninstall", systemImage: "trash", action: .uninstall, isEnabled: true)
        }

        return DetailAction(title: "Install", systemImage: "plus.circle", action: .install, isEnabled: true)
    }

    private func runPrimaryDetailAction(_ detailAction: DetailAction, for package: BrewPackage) {
        switch detailAction.action {
        case .install:
            store.install(package)
        case .uninstall:
            store.uninstall(package)
        case .upgrade:
            store.upgrade(package)
        case .info:
            Task { await store.loadInfo(for: package) }
        }
    }

    private func openHomepage(for package: BrewPackage) {
        Task {
            let homepage: String?
            if let currentHomepage = store.homepageForCurrentInfo(matching: package) {
                homepage = currentHomepage
            } else {
                homepage = await store.homepage(for: package)
            }

            guard let homepage,
                  let url = URL(string: homepage) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func installedVersionText(for package: BrewPackage) -> String {
        if !store.packageInfo.installedVersions.isEmpty {
            return store.packageInfo.installedVersions.joined(separator: ", ")
        }

        if let installedVersion = package.installedVersion {
            return installedVersion
        }

        return package.installed ? "Installed" : "Not installed"
    }

    private func manageInstalledVersionText(for package: BrewPackage) -> String {
        package.installedVersion ?? "-"
    }

    private func manageLatestVersionText(for package: BrewPackage) -> String {
        packageIsOutdated(package) ? (package.currentVersion ?? "-") : "-"
    }

    private func packageIsOutdated(_ package: BrewPackage) -> Bool {
        store.outdatedPackages.contains { $0.id == package.id }
    }

    private func packageStateText(for package: BrewPackage) -> String {
        if packageIsOutdated(package) {
            return "Outdated"
        }

        return package.installed ? "Installed" : "Available"
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

    private func sortedPackages(
        _ packages: [BrewPackage],
        using sortOrder: [KeyPathComparator<BrewPackage>]
    ) -> [BrewPackage] {
        packages.sorted(using: sortOrder)
    }

    private func loadInfo(
        for packageID: BrewPackage.ID?,
        in packages: [BrewPackage],
        source: PackageSelectionSource
    ) {
        guard let packageID,
              let package = packages.first(where: { $0.id == packageID }) else {
            return
        }

        activePackageSelection = PackageSelection(id: packageID, source: source)
        Task { await store.loadInfo(for: package) }
    }

    private struct PackageSelection {
        let id: BrewPackage.ID
        let source: PackageSelectionSource
    }

    private enum PackageSelectionSource {
        case manage
        case search
    }

    private struct DetailAction {
        let title: String
        let systemImage: String
        let action: BrewPackageAction
        let isEnabled: Bool
    }
}
