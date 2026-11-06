import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: UsageModel
    @AppStorage("personalPhoneNumber") private var personalPhoneNumber = ""
    @AppStorage("personalLoginMethod") private var loginMethod = "email"
    @AppStorage("personalLoginEmail") private var loginEmail = ""
    @State private var smsCode = ""
    @State private var smsStatus = ""
    @State private var loginPassword = ""
    @State private var emailStatus = ""
    @State private var hasStoredPassword = false
    @State private var editingLine = false
    @FocusState private var smsCodeFocused: Bool
    private let blue = Color(red: 0.04, green: 0.34, blue: 0.68)
    private let passwordVault = LoginPasswordVault()
    private var hasConfiguredLine: Bool {
        (10...11).contains(personalPhoneNumber.filter { $0.isASCII && $0.isNumber }.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "cellularbars")
                        .font(.title2.bold())
                        .frame(width: 42, height: 42)
                        .background(blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mi Consumo Móvil").font(.title2.bold())
                        Text("Datos de Mi Personal").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.refreshFromButton() } } label: {
                        if model.isRefreshing {
                            Label("Actualizando…", systemImage: "arrow.clockwise")
                        } else {
                            Label("Actualizar", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(model.snapshot.state == .active ? "DISPONIBLES PARA TODO USO" : "ÚLTIMA LECTURA · SESIÓN SIN ACTUALIZAR")
                        .font(.caption.bold()).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.snapshot.remainingDisplay ?? "—")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text("disponibles").font(.subheadline)
                    }
                    if let used = model.snapshot.usedGB, let total = model.snapshot.totalGB {
                        ProgressView(value: min(max(used / max(total, 0.01), 0), 1)).tint(.white)
                        Text("\(used, specifier: "%.1f") de \(total, specifier: "%.1f") GB usados")
                            .font(.caption).foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text(model.snapshot.message).font(.subheadline)
                    }
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [blue, Color(red: 0.02, green: 0.56, blue: 0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20)
                )

                if !model.snapshot.packs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tus packs").font(.headline)
                        ForEach(model.snapshot.packs) { pack in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(blue).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.name).font(.subheadline.bold())
                                    Text("Vence el \(PackDateFormat.long(pack.expiresAt))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(pack.remainingDisplay).font(.subheadline.bold())
                            }
                            .padding(14)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }

                HStack {
                    Label(model.isRefreshing ? "Consultando Mi Personal…" : model.snapshot.message,
                          systemImage: model.isRefreshing ? "arrow.clockwise" :
                            (model.snapshot.state == .active ? "checkmark.circle.fill" : "exclamationmark.circle"))
                        .font(.caption)
                        .foregroundStyle(model.snapshot.state == .active ? .green : .secondary)
                    Spacer()
                    if let date = model.snapshot.updatedAt {
                        Text("Actualizado \(date.formatted(.dateTime.hour().minute()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.launchAtLoginMessage.isEmpty {
                    Text(model.launchAtLoginMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.snapshot.state == .needsLogin ? "Iniciar sesión" : "Abrir Mi Personal") {
                        model.openLogin()
                    }
                    .buttonStyle(.bordered)
                    Button("Cambiar cuenta") { signOut(switchAccount: true) }
                        .disabled(model.isSigningOut)
                    Button("Cerrar sesión") { signOut(switchAccount: false) }
                        .disabled(model.isSigningOut)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 460, minHeight: 470)
        .sheet(isPresented: $model.showLogin) {
            VStack(spacing: 0) {
                HStack {
                    Text("Mi Personal").font(.headline)
                    Picker("Acceso", selection: $loginMethod) {
                        Text("SMS").tag("phone")
                        Text("Email").tag("email")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 155)
                    Spacer()
                    Button(model.isRefreshing ? "Actualizando…" : "Actualizar consumo") {
                        model.showLogin = false
                        Task { await model.refresh(promptForLogin: true) }
                    }
                    .disabled(model.isRefreshing)
                    Button("Cerrar") { model.showLogin = false }
                }
                .padding()
                if loginMethod == "email" {
                    HStack(spacing: 10) {
                        TextField("Email", text: $loginEmail)
                            .textContentType(.username)
                            .frame(width: 210)
                        SecureField(hasStoredPassword ? "Contraseña guardada" : "Contraseña", text: $loginPassword)
                            .textContentType(.password)
                            .frame(width: 165)
                        Button("Ingresar con email") { configureEmail() }
                        if hasStoredPassword {
                            Button("Olvidar contraseña") {
                                passwordVault.clear()
                                hasStoredPassword = false
                                emailStatus = "Contraseña eliminada del Llavero."
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    if !emailStatus.isEmpty {
                        Text(emailStatus).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                } else {
                    HStack(spacing: 10) {
                        if hasConfiguredLine && !editingLine {
                            Text("Línea ••••\(personalPhoneNumber.suffix(4))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Cambiar línea") {
                                editingLine = true
                                smsCodeFocused = false
                            }
                        } else {
                            TextField("Número de línea", text: $personalPhoneNumber)
                                .textContentType(.telephoneNumber)
                                .frame(width: 145)
                                .onSubmit { configureLine() }
                            Button("Usar línea") { configureLine() }
                        }
                        Text("Código SMS")
                        TextField("6 dígitos", text: $smsCode)
                            .textContentType(.oneTimeCode)
                            .focused($smsCodeFocused)
                            .frame(width: 95)
                            .onChange(of: smsCode) { _, newValue in
                                if newValue.filter({ $0.isASCII && $0.isNumber }).count == 6 {
                                    acceptCode(newValue)
                                }
                            }
                        Button("Pegar SMS o código") {
                            acceptCode(NSPasteboard.general.string(forType: .string) ?? "")
                        }
                        Text(smsStatus.isEmpty ? "Elegí aquí la sugerencia de macOS." : smsStatus)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                Spacer().frame(height: 10)
                LoginWebView(webView: model.provider.webView)
                    .frame(minWidth: 760, minHeight: 620)
            }
            .onAppear {
                hasStoredPassword = passwordVault.load() != nil
                if loginMethod == "email" {
                    if !model.provider.isOnPortal(),
                       let password = passwordVault.load(), !loginEmail.isEmpty {
                        model.provider.configureEmailLogin(email: loginEmail, password: password)
                        emailStatus = "Ingresando con el email guardado…"
                    }
                } else {
                    model.provider.configureLogin(phoneNumber: personalPhoneNumber)
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        if model.showLogin { smsCodeFocused = true }
                    }
                }
            }
            .onDisappear { model.provider.disableLoginAssistance() }
            .task(id: loginMethod) {
                if loginMethod == "email" { await finishEmailLoginWhenReady() }
                else { await focusCodeWhenReady() }
            }
        }
    }

    @MainActor
    private func finishEmailLoginWhenReady() async {
        var sawLoginPage = false
        for _ in 0..<480 {
            guard model.showLogin, !Task.isCancelled, loginMethod == "email" else { return }
            if model.provider.isOnLoginPage() { sawLoginPage = true }
            if sawLoginPage && model.provider.isOnPortal() {
                emailStatus = ""
                model.showLogin = false
                await model.refresh()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    @MainActor
    private func focusCodeWhenReady() async {
        for _ in 0..<120 {
            guard model.showLogin, !Task.isCancelled else { return }
            if await model.provider.isAwaitingOneTimeCode() {
                try? await Task.sleep(for: .milliseconds(400))
                smsCodeFocused = false
                try? await Task.sleep(for: .milliseconds(100))
                smsCodeFocused = true
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func configureLine() {
        let digits = String(personalPhoneNumber.filter { $0.isASCII && $0.isNumber })
        guard (10...11).contains(digits.count) else {
            smsStatus = "Ingresá una línea de 10 u 11 dígitos."
            return
        }
        personalPhoneNumber = digits
        UserDefaults.standard.set(digits, forKey: "personalPhoneNumber")
        model.provider.configureLogin(phoneNumber: digits)
        editingLine = false
        smsCodeFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            smsCodeFocused = true
        }
    }

    private func signOut(switchAccount: Bool) {
        loginPassword = ""
        smsCode = ""
        smsStatus = ""
        emailStatus = ""
        hasStoredPassword = false
        editingLine = true
        loginEmail = ""
        personalPhoneNumber = ""
        loginMethod = "email"
        Task { await model.signOut(switchAccount: switchAccount) }
    }

    private func configureEmail() {
        let address = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), address.contains(".") else {
            emailStatus = "Ingresá un email válido."
            return
        }
        if !loginPassword.isEmpty {
            guard passwordVault.save(loginPassword) else {
                emailStatus = "No se pudo guardar la contraseña en el Llavero."
                return
            }
            loginPassword = ""
            hasStoredPassword = true
        }
        guard let password = passwordVault.load() else {
            emailStatus = "Ingresá la contraseña una vez para guardarla en el Llavero."
            return
        }
        loginEmail = address
        UserDefaults.standard.set(address, forKey: "personalLoginEmail")
        model.provider.configureEmailLogin(email: address, password: password)
        emailStatus = "Ingresando con email…"
    }

    private func acceptCode(_ text: String) {
        let pattern = #"(?<![0-9])[0-9]{6}(?![0-9])"#
        let matches = (try? NSRegularExpression(pattern: pattern))?.matches(
            in: text, range: NSRange(text.startIndex..., in: text)
        ) ?? []
        guard matches.count == 1,
              let range = Range(matches[0].range, in: text) else {
            smsStatus = "Copiá el SMS o un único código de 6 dígitos."
            return
        }
        let code = String(text[range])
        smsCode = ""
        smsStatus = "Validando código…"
        Task {
            let signedIn = await model.provider.submitOneTimeCode(code)
            if signedIn {
                smsStatus = ""
                model.showLogin = false
                await model.refresh()
            } else {
                smsStatus = "Revisá el código en la página de Personal."
            }
        }
    }
}
