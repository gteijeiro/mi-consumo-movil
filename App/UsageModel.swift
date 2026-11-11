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

    let provider = PersonalUsageProvider()
    private let store = SnapshotStore()
    private var hourlyActivity: NSBackgroundActivityScheduler?
    private var freshnessTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var lastRefreshAttemptAt: Date?
    private var hasStarted = false
    private var sessionGeneration = 0
    private let lastLoginAttemptKey = "personalLastAutomaticLoginAttempt"
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
        let activity = NSBackgroundActivityScheduler(identifier: "com.gteijeiro.PersonalDataWidget.periodicUsage")
        activity.repeats = true
        activity.interval = SharedSettings.refreshInterval
        activity.tolerance = 60
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
        let timer = Timer(timeInterval: SharedSettings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
        removePreviousMainAppLoginItem()
        if !signedOut { Task { await refresh() } }
    }

    func refreshIfDue() async {
        guard !signedOut, !isRefreshing, !isSigningOut else { return }
        if showLogin {
            if provider.isOnPortal() {
                showLogin = false
                await refresh()
            } else {
                _ = provider.retryLoginAfterLoadFailure()
            }
            return
        }
        let now = Date()
        if snapshot.state == .needsLogin,
           let lastLoginAttempt = UserDefaults.standard.object(forKey: lastLoginAttemptKey) as? Date,
           now.timeIntervalSince(lastLoginAttempt) < 1_800 { return }
        if let updatedAt = snapshot.updatedAt,
           now.timeIntervalSince(updatedAt) < SharedSettings.refreshDueAfter { return }
        // A failed request may be retried, but a wake or focus event must not
        // cause a burst of requests while the connection is unavailable.
        if let lastRefreshAttemptAt,
           now.timeIntervalSince(lastRefreshAttemptAt) < SharedSettings.refreshInterval { return }
        await refresh()
    }

    private func removePreviousMainAppLoginItem() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() }
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
            guard generation == sessionGeneration, !signedOut else { return }
            snapshot = updated
            UserDefaults.standard.removeObject(forKey: lastLoginAttemptKey)
        } catch UsageProviderError.needsLogin {
            guard generation == sessionGeneration else { return }
            UserDefaults.standard.set(Date(), forKey: lastLoginAttemptKey)
            snapshot.state = .needsLogin
            snapshot.message = "Sesión vencida. Se muestra la última lectura."
            if promptForLogin {
                showLogin = true
            }
        } catch UsageProviderError.notConfigured {
            guard generation == sessionGeneration else { return }
            snapshot.state = .unavailable
            snapshot.message = "Consulta real aún no configurada"
        } catch UsageProviderError.networkUnavailable {
            guard generation == sessionGeneration else { return }
            snapshot.state = .unavailable
            snapshot.message = "Sin conexión. Reintentará la consulta."
        } catch {
            guard generation == sessionGeneration else { return }
            snapshot.state = .unavailable
            snapshot.message = "No se pudo actualizar"
        }

        UserDefaults.standard.synchronize()
        guard !signedOut else { return }
        if store.save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
        }
    }

    func openLogin() {
        UserDefaults.standard.set(false, forKey: "personalSignedOut")
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
        UserDefaults.standard.removeObject(forKey: lastLoginAttemptKey)
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
