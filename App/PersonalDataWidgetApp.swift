import SwiftUI

@main
@MainActor
enum PersonalDataWidgetMain {
    static func main() {
        if CommandLine.arguments.contains("--background-refresh") {
            BackgroundRefreshAgent.run()
        } else {
            PersonalDataWidgetApp.main()
        }
    }
}

@MainActor
private enum BackgroundRefreshAgent {
    static let delegate = BackgroundRefreshDelegate()

    static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.delegate = delegate
        application.run()
    }
}

private final class BackgroundRefreshDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let model = UsageModel()
            if CommandLine.arguments.contains("--force-refresh") {
                await model.refresh()
            } else {
                await model.refreshIfDue()
            }
            print("background-refresh: \(model.snapshot.state.rawValue)")
            NSApp.terminate(nil)
        }
    }

}

final class PersonalDataWidgetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct PersonalDataWidgetApp: App {
    @NSApplicationDelegateAdaptor(PersonalDataWidgetAppDelegate.self) private var appDelegate
    @StateObject private var model = UsageModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model)
                .onAppear { model.start() }
                .onOpenURL { model.handle($0) }
        }
        MenuBarExtra("Mi Consumo Móvil", systemImage: "cellularbars") {
            MenuBarControls(model: model)
                .onAppear { model.start() }
        }
    }
}

private struct MenuBarControls: View {
    @ObservedObject var model: UsageModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.snapshot.remainingDisplay ?? "Sin datos")
        if let updatedAt = model.snapshot.updatedAt {
            Text("Actualizado: \(updatedAt.formatted(.dateTime.day().month().hour().minute()))")
        }
        Divider()
        Button("Actualizar ahora") { Task { await model.refresh(promptForLogin: false) } }
            .disabled(model.isRefreshing)
        Button("Abrir app") { openWindow(id: "main") }
    }
}
