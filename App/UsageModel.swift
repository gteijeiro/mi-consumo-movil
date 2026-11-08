import AppKit
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot = SnapshotStore().load()
    @Published var showLogin = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var launchAtLoginMessage = ""

    let provider = PersonalUsageProvider()
    private let store = SnapshotStore()
    private var hourlyActivity: NSBackgroundActivityScheduler?
    private var freshnessTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var lastRefreshAttemptAt: Date?
    private var hasStarted = false
    private var sessionGeneration = 0
    private var signedOut: Bool { UserDefaults.standard.bool(forKey: "personalSignedOut") }

    func refreshFromButton() async {
        if signedOut {
            openLogin()
            return
        }
        await refresh(promptForLogin: true)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let activity = NSBackgroundActivityScheduler(identifier: "com.gteijeiro.PersonalDataWidget.hourlyUsage")
        activity.repeats = true
        activity.interval = 3_600
        activity.tolerance = 300
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.refreshIfDue()
                completion(.finished)
            }
        }
        hourlyActivity = activity
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
        registerLaunchAtLogin()
        if !signedOut { Task { await refresh() } }
    }

    private func refreshIfDue() async {
        guard !signedOut, !showLogin, !isRefreshing, !isSigningOut else { return }
        let now = Date()
        if let updatedAt = snapshot.updatedAt,
           now.timeIntervalSince(updatedAt) < 3_600 { return }
        // A failed request may be retried, but a wake or focus event must not
        // cause a burst of requests while the connection is unavailable.
        if let lastRefreshAttemptAt,
           now.timeIntervalSince(lastRefreshAttemptAt) < 300 { return }
        await refresh()
    }

    private func registerLaunchAtLogin() {
        guard !signedOut else { return }
        let service = SMAppService.mainApp
        if service.status == .enabled {
            launchAtLoginMessage = "Actualización al iniciar macOS activada"
            return
        }
        do {
            try service.register()
            launchAtLoginMessage = service.status == .enabled
                ? "Actualización al iniciar macOS activada"
                : "Activá Mi Consumo Móvil en Ítems de inicio de macOS"
        } catch {
            launchAtLoginMessage = "Activá Mi Consumo Móvil en Ítems de inicio de macOS"
        }
    }

    func stop() {
        hourlyActivity?.invalidate()
        hourlyActivity = nil
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
        hasStarted = false
    }

    func refresh(promptForLogin: Bool = false) async {
        guard !isRefreshing, !isSigningOut, !signedOut else { return }
        lastRefreshAttemptAt = Date()
        let generation = sessionGeneration
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let updated: UsageSnapshot
            do {
                updated = try await provider.fetchUsage()
            } catch UsageProviderError.needsLogin {
                guard generation == sessionGeneration else { return }
                guard await provider.restoreLoginWithSavedEmail() else {
                    throw UsageProviderError.needsLogin
                }
                updated = try await provider.fetchUsage()
            }
            guard generation == sessionGeneration else { return }
            snapshot = updated
        } catch UsageProviderError.needsLogin {
            guard generation == sessionGeneration else { return }
            snapshot.state = .needsLogin
            snapshot.message = "Sesión vencida. Se muestra la última lectura."
            if promptForLogin {
                showLogin = true
            }
        } catch UsageProviderError.notConfigured {
            guard generation == sessionGeneration else { return }
            snapshot.state = .unavailable
            snapshot.message = "Consulta real aún no configurada"
        } catch {
            guard generation == sessionGeneration else { return }
            snapshot.state = .unavailable
            snapshot.message = "No se pudo actualizar"
        }

        if store.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
        }
    }

    func openLogin() {
        UserDefaults.standard.set(false, forKey: "personalSignedOut")
        registerLaunchAtLogin()
        provider.openLogin()
        showLogin = true
    }

    func signOut(switchAccount: Bool) async {
        guard !isSigningOut else { return }
        isSigningOut = true
        sessionGeneration += 1
        showLogin = false
        UserDefaults.standard.set(true, forKey: "personalSignedOut")
        LoginPasswordVault().clear()
        UserDefaults.standard.removeObject(forKey: "personalPhoneNumber")
        UserDefaults.standard.removeObject(forKey: "personalLoginEmail")
        UserDefaults.standard.removeObject(forKey: "personalLoginMethod")
        snapshot = .signedOut
        if store.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
        }
        await provider.clearSession()
        isSigningOut = false
        if switchAccount { openLogin() }
    }

    func handle(_ url: URL) {
        guard url.scheme == "personaldatawidget" else { return }
        if url.host == "login" { openLogin() }
    }
}
