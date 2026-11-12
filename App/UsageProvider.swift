import Foundation
import WebKit

enum UsageProviderError: Error {
    case needsLogin
    case notConfigured
    case networkUnavailable
    case unavailable
}

@MainActor
protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot
}

// Demonstration only. No request to Personal is made by this provider.
struct MockUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        UsageSnapshot(
            usedGB: 12.4,
            totalGB: 30,
            remainingDisplay: "17,6 GB",
            periodDescription: "Datos de ejemplo",
            packs: [],
            updatedAt: Date(),
            state: .demo,
            message: "Modo demostración"
        )
    }
}

// Reads the visible consumption from this app's own WebKit session. Session
// cookies and an optional email password stay in the app's local Keychain.
@MainActor
final class PersonalUsageProvider: NSObject, UsageProvider, WKNavigationDelegate {
    let webView: WKWebView
    private let portalURL = URL(string: "https://mipersonal.personal.com.ar")!
    private let detailsURL = URL(string: "https://mipersonal.personal.com.ar/mis-disponibles")!
    private let cookieVault = SessionCookieVault()
    private let portalSessionVault = PortalSessionVault()
    private var cookiesRestored = false
    private var sessionGeneration = 0
    private var recoverableLoadFailure = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        recoverableLoadFailure = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code != NSURLErrorCancelled {
            recoverableLoadFailure = true
        }
    }

    func retryLoginAfterLoadFailure() -> Bool {
        guard recoverableLoadFailure else { return false }
        recoverableLoadFailure = false
        openLogin()
        return true
    }

    // The phone number stays in this app's preferences. The code only exists in memory
    // while WebKit fills the six fields; neither value is sent to the widget.
    func configureLogin(phoneNumber: String) {
        let digits = phoneNumber.filter { $0.isASCII && $0.isNumber }
        guard (10...11).contains(digits.count) else { return }
        let script = #"""
        (function () {
          if (location.hostname !== 'login.personal.com.ar') return;
          window.__pdwPhone = '\#(digits)';
          window.__pdwLoginAssistEnabled = true;
          window.__pdwEmailAssistEnabled = false;
          if (window.__pdwLoginHelper) return;
          window.__pdwLoginHelper = true;
          let numberSubmitted = false;
          let codeRequested = false;
          const visible = e => e.getClientRects().length > 0;
          const buttons = () => Array.from(document.querySelectorAll('button')).filter(visible);
          const buttonNamed = name => buttons().find(e => e.textContent.trim() === name);
          const codeBoxes = () => {
            const fields = Array.from(document.querySelectorAll('input'))
              .filter(e => visible(e) && e.type !== 'hidden');
            return (document.body?.innerText || '').includes('Ingresá el código que recibiste') && fields.length === 6
              ? fields : [];
          };
          const setInput = (field, value) => {
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
            field.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          };
          window.__pdwFillCode = code => {
            if (!/^\d{6}$/.test(code)) return false;
            const fields = codeBoxes();
            if (fields.length !== 6) return false;
            fields.forEach((field, index) => setInput(field, code[index]));
            let attempts = 0;
            const submit = () => {
              const validate = buttonNamed('Validar');
              if (validate && !validate.disabled && codeBoxes().every((field, index) => field.value === code[index])) {
                validate.click();
              } else if (++attempts < 10) {
                setTimeout(submit, 250);
              }
            };
            setTimeout(submit, 250);
            return true;
          };
          document.addEventListener('paste', event => {
            if (!codeBoxes().includes(event.target)) return;
            const code = event.clipboardData?.getData('text').trim();
            if (code && /^\d{6}$/.test(code)) {
              event.preventDefault();
              window.__pdwFillCode(code);
            }
          }, true);
          document.addEventListener('beforeinput', event => {
            if (codeBoxes().includes(event.target) && /^\d{6}$/.test(event.data || '')) {
              event.preventDefault();
              window.__pdwFillCode(event.data);
            }
          }, true);
          const advance = () => {
            if (!window.__pdwLoginAssistEnabled) return;
            const text = document.body?.innerText || '';
            if (!numberSubmitted && text.includes('Ingresa tu usuario')) {
              const fields = Array.from(document.querySelectorAll('input')).filter(e => visible(e) && e.type !== 'hidden');
              if (fields.length === 1) {
                numberSubmitted = true;
                setInput(fields[0], window.__pdwPhone);
                let attempts = 0;
                const submitNumber = () => {
                  const next = buttonNamed('Continuar');
                  if (next && !next.disabled) next.click();
                  else if (++attempts < 10) setTimeout(submitNumber, 250);
                  else numberSubmitted = false;
                };
                setTimeout(submitNumber, 250);
              }
            }
            if (!codeRequested && text.includes('Tendrás que ingresar el código')) {
              const send = buttonNamed('Enviar código');
              if (send && !send.disabled) {
                codeRequested = true;
                send.click();
              }
            }
          };
          setInterval(advance, 400);
          advance();
        })();
        """#
        installLoginScript(script)
    }

    func configureEmailLogin(email: String, password: String) {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !password.isEmpty,
              let emailData = try? JSONEncoder().encode(address),
              let passwordData = try? JSONEncoder().encode(password),
              let emailLiteral = String(data: emailData, encoding: .utf8),
              let passwordLiteral = String(data: passwordData, encoding: .utf8)
        else { return }
        let script = #"""
        (function () {
          if (location.hostname !== 'login.personal.com.ar') return;
          window.__pdwLoginAssistEnabled = false;
          window.__pdwEmailAssistEnabled = true;
          window.__pdwEmailGeneration = (window.__pdwEmailGeneration || 0) + 1;
          const generation = window.__pdwEmailGeneration;
          const email = \#(emailLiteral);
          let password = \#(passwordLiteral);
          let emailAttempts = 0;
          let lastEmailAttempt = 0;
          let passwordSubmitted = false;
          const visible = e => e.getClientRects().length > 0;
          const buttons = () => Array.from(document.querySelectorAll('button')).filter(visible);
          const continueButton = () => buttons().find(e => e.textContent.trim() === 'Continuar');
          const setInput = (field, value) => {
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
            field.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          };
          const submit = (finished, attempts = 0) => {
            const next = continueButton();
            if (next && !next.disabled) {
              next.click();
              finished();
            } else if (attempts < 10) {
              setTimeout(() => submit(finished, attempts + 1), 250);
            }
          };
          const advance = () => {
            if (!window.__pdwEmailAssistEnabled || window.__pdwEmailGeneration !== generation) {
              password = '';
              clearInterval(timer);
              return;
            }
            const text = document.body?.innerText || '';
            if (text.includes('Ingresa tu usuario') && emailAttempts < 3 &&
                Date.now() - lastEmailAttempt >= 3000) {
              const fields = Array.from(document.querySelectorAll('input')).filter(e => visible(e) && e.type !== 'hidden');
              if (fields.length === 1) {
                emailAttempts += 1;
                lastEmailAttempt = Date.now();
                setInput(fields[0], email);
                submit(() => {});
              }
            }
            if (!passwordSubmitted && text.includes('Ahora, ingresá la contraseña')) {
              const field = Array.from(document.querySelectorAll('input[type="password"]')).find(visible);
              if (field) {
                passwordSubmitted = true;
                setInput(field, password);
                submit(() => { password = ''; });
              }
            }
          };
          const timer = setInterval(advance, 400);
          window.__pdwEmailAdvance = advance;
          advance();
        })();
        """#
        installLoginScript(script)
    }

    private func installLoginScript(_ script: String) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        Task { _ = try? await webView.evaluateJavaScript(script) }
    }

    func disableLoginAssistance() {
        webView.configuration.userContentController.removeAllUserScripts()
        Task { _ = try? await webView.evaluateJavaScript("window.__pdwLoginAssistEnabled = false; window.__pdwEmailAssistEnabled = false") }
    }

    func submitOneTimeCode(_ code: String) async -> Bool {
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return false }
        let script = "window.__pdwFillCode?.('" + code + "') === true"
        guard (try? await webView.evaluateJavaScript(script) as? Bool) == true else { return false }
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(1))
            if webView.url?.host == portalURL.host { return true }
        }
        return false
    }

    func isAwaitingOneTimeCode() async -> Bool {
        guard webView.url?.host == "login.personal.com.ar" else { return false }
        let script = "document.body?.innerText.includes('Ingresá el código que recibiste') === true"
        return (try? await webView.evaluateJavaScript(script) as? Bool) == true
    }

    func isOnPortal() -> Bool {
        webView.url?.host == portalURL.host && webView.url?.path != "/callback" && !webView.isLoading
    }

    func isOnLoginPage() -> Bool {
        webView.url?.host == "login.personal.com.ar"
    }

    func requiresIdentityValidation() async -> Bool {
        guard isOnLoginPage() else { return false }
        let script = "(() => { const text = document.body?.innerText || ''; return text.includes('necesitamos validar tu identidad') || text.includes('Ingresá el código que recibiste'); })()"
        return (try? await webView.evaluateJavaScript(script) as? Bool) == true
    }

    func clearSession() async {
        sessionGeneration += 1
        webView.stopLoading()
        disableLoginAssistance()
        cookieVault.clear()
        portalSessionVault.clear()
        cookiesRestored = true
        webView.loadHTMLString("", baseURL: nil)
        let dataStore = webView.configuration.websiteDataStore
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        URLCache.shared.removeAllCachedResponses()
    }

    func openLogin() {
        loadFreshPage(portalURL)
    }

    private func loadFreshPage(_ url: URL) {
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    // The app retries the normal website login with the locally saved account.
    // A server challenge still requires the user to complete it in the login sheet.
    func restoreLoginWithSavedEmail() async -> Bool {
        guard let email = UserDefaults.standard.string(forKey: "personalLoginEmail"),
              !email.isEmpty, let password = LoginPasswordVault().load() else { return false }
        let generation = sessionGeneration
        var sawLoginPage = isOnLoginPage()
        configureEmailLogin(email: email, password: password)
        loadFreshPage(portalURL)
        for _ in 0..<75 {
            try? await Task.sleep(for: .seconds(1))
            guard generation == sessionGeneration else { return false }
            if isOnLoginPage() {
                sawLoginPage = true
                if await requiresIdentityValidation() {
                    disableLoginAssistance()
                    return false
                }
                _ = try? await webView.evaluateJavaScript("window.__pdwEmailAdvance?.(); true")
            }
            if sawLoginPage && isOnPortal() {
                disableLoginAssistance()
                return true
            }
        }
        disableLoginAssistance()
        return false
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let generation = sessionGeneration
        if !cookiesRestored {
            cookiesRestored = true
            if let json = portalSessionVault.load(),
               let data = json.data(using: .utf8),
               (try? JSONDecoder().decode([String: String].self, from: data)) != nil {
                let script = "if (location.origin === 'https://mipersonal.personal.com.ar') { const saved = " + json + "; for (const [key, value] of Object.entries(saved)) { if (sessionStorage.getItem(key) === null) sessionStorage.setItem(key, value); } }"
                webView.configuration.userContentController.addUserScript(
                    WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                )
            }
            for cookie in cookieVault.load() {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
        }
        loadFreshPage(detailsURL)
        var requestedDetails = false
        for _ in 0..<35 {
            try await Task.sleep(for: .seconds(1))
            guard generation == sessionGeneration else { throw CancellationError() }
            let host = webView.url?.host ?? ""
            if host == "idpsesion.personal.com.ar" || host == "login.personal.com.ar" {
                cookieVault.clear()
                portalSessionVault.clear()
                throw UsageProviderError.needsLogin
            }
            guard !webView.isLoading, host == portalURL.host else { continue }
            guard let visibleText = try? await webView.evaluateJavaScript("document.body.innerText") as? String else {
                continue
            }
            if webView.url?.path == detailsURL.path {
                if let snapshot = Self.parseDetailedUsage(visibleText) {
                    guard generation == sessionGeneration else { throw CancellationError() }
                    await saveSessionCookies(generation: generation)
                    guard generation == sessionGeneration else { throw CancellationError() }
                    return snapshot
                }
                if !requestedDetails, visibleText.contains("Pack mensual activo") {
                    requestedDetails = true
                    let script = "Array.from(document.querySelectorAll('button,[role=button]')).find(e => /consultar detalle/i.test([e.innerText,e.getAttribute('aria-label'),e.title].join(' ')))?.click(); true"
                    _ = try? await webView.evaluateJavaScript(script)
                }
            } else if let snapshot = Self.parseVisibleUsage(visibleText) {
                guard generation == sessionGeneration else { throw CancellationError() }
                await saveSessionCookies(generation: generation)
                guard generation == sessionGeneration else { throw CancellationError() }
                return snapshot
            }
        }
        if recoverableLoadFailure { throw UsageProviderError.networkUnavailable }
        throw UsageProviderError.unavailable
    }

    private func saveSessionCookies(generation: Int) async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard generation == sessionGeneration else { return }
        cookieVault.save(cookies)
        let script = "location.origin === 'https://mipersonal.personal.com.ar' ? JSON.stringify(Object.fromEntries(Object.entries(sessionStorage))) : null"
        if let json = try? await webView.evaluateJavaScript(script) as? String,
           generation == sessionGeneration {
            portalSessionVault.save(json)
        }
    }

    private static func parseDetailedUsage(_ text: String) -> UsageSnapshot? {
        guard text.localizedCaseInsensitiveContains("Datos para todo uso") else { return nil }
        let pattern = #"([^\n]{3,60})\s+(\d+(?:[.,]\d+)?)\s*(MB|GB)\s+de\s+(\d+(?:[.,]\d+)?)\s*(MB|GB)\s+Vence el\s+(\d{2}/\d{2}/\d{2})\s+a las\s+(\d{2}:\d{2})\s*h\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let packs = matches.compactMap { match -> DataPack? in
            guard let name = value(at: 1, in: match, from: text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let remainingText = value(at: 2, in: match, from: text),
                  let remainingUnit = value(at: 3, in: match, from: text),
                  let totalText = value(at: 4, in: match, from: text),
                  let totalUnit = value(at: 5, in: match, from: text),
                  let dateText = value(at: 6, in: match, from: text),
                  let timeText = value(at: 7, in: match, from: text),
                  let remaining = amountInGB(remainingText, unit: remainingUnit),
                  let total = amountInGB(totalText, unit: totalUnit),
                  let expiry = expiration(dateText, timeText)
            else { return nil }
            return DataPack(name: name, remainingGB: remaining, totalGB: total,
                            remainingDisplay: "\(remainingText) \(remainingUnit.uppercased())",
                            expiresAt: expiry)
        }
        guard !packs.isEmpty else { return nil }
        let total = packs.reduce(0) { $0 + $1.totalGB }
        let remaining = packs.reduce(0) { $0 + $1.remainingGB }
        let remainingDisplay = remaining < 1
            ? "\(Int((remaining * 1_000).rounded())) MB"
            : String(format: "%.1f GB", remaining)
        return UsageSnapshot(
            usedGB: max(0, total - remaining),
            totalGB: total,
            remainingDisplay: remainingDisplay,
            periodDescription: "Datos para todo uso",
            packs: packs.sorted { $0.expiresAt < $1.expiresAt },
            updatedAt: Date(),
            state: .active,
            message: "Consumo actualizado"
        )
    }

    private static func amountInGB(_ amount: String, unit: String) -> Double? {
        guard let number = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return unit.uppercased() == "MB" ? number / 1_000 : number
    }

    private static func expiration(_ date: String, _ time: String) -> Date? {
        let dateParts = date.split(separator: "/").compactMap { Int($0) }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count == 2 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Argentina/Cordoba")!
        return calendar.date(from: DateComponents(year: 2000 + dateParts[2], month: dateParts[1], day: dateParts[0], hour: timeParts[0], minute: timeParts[1]))
    }

    private static func parseVisibleUsage(_ text: String) -> UsageSnapshot? {
        guard let heading = text.range(of: "Datos para todo uso", options: .caseInsensitive) else { return nil }
        let section = String(text[heading.upperBound...].prefix(700))
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(MB|GB)\s+disponibles\s+(\d+(?:[.,]\d+)?)\s*(MB|GB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: section, range: NSRange(section.startIndex..., in: section)),
              let remainingNumber = value(at: 1, in: match, from: section),
              let remainingUnit = value(at: 2, in: match, from: section),
              let totalNumber = value(at: 3, in: match, from: section),
              let totalUnit = value(at: 4, in: match, from: section),
              let remaining = Double(remainingNumber.replacingOccurrences(of: ",", with: ".")),
              let total = Double(totalNumber.replacingOccurrences(of: ",", with: "."))
        else { return nil }

        let remainingGB = remainingUnit.uppercased() == "MB" ? remaining / 1_000 : remaining
        let totalGB = totalUnit.uppercased() == "MB" ? total / 1_000 : total
        guard totalGB > 0, remainingGB >= 0, remainingGB <= totalGB else { return nil }
        return UsageSnapshot(
            usedGB: totalGB - remainingGB,
            totalGB: totalGB,
            remainingDisplay: "\(remainingNumber) \(remainingUnit.uppercased())",
            periodDescription: "Datos para todo uso",
            packs: [],
            updatedAt: Date(),
            state: .active,
            message: "Consulta de la página actualizada"
        )
    }

    private static func value(at index: Int, in match: NSTextCheckingResult, from text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
