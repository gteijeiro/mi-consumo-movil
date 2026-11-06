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
                if let self, !self.signedOut, !self.showLogin {
                    await self.refresh()
                }
                completion(.finished)
            }
        }
        hourlyActivity = activity
        registerLaunchAtLogin()
        if !signedOut { Task { await refresh() } }
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
        hasStarted = false
    }

    func refresh(promptForLogin: Bool = false) async {
        guard !isRefreshing, !isSigningOut, !signedOut else { return }
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
