import SwiftUI

final class PersonalDataWidgetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
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
