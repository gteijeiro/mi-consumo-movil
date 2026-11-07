# Guía rápida para agentes

Este archivo es el punto de entrada para trabajar en **Mi Consumo Móvil**. El [README](README.md) contiene las instrucciones completas para usuarios. La raíz del repositorio es un proyecto Xcode sin dependencias externas; no hace falta inspeccionar otros directorios para empezar.

## Qué hace y cómo se ejecuta

- App macOS 14+ escrita en SwiftUI y extensión WidgetKit. Proyecto: `PersonalDataWidget.xcodeproj`; esquema principal: `PersonalDataWidget`; target del widget: `PersonalUsageWidgetExtension`.
- Nombre visible: **Mi Consumo Móvil**. Los nombres internos, el esquema, los identificadores originales y el paquete `PersonalDataWidget.app` se conservaron para mantener las instalaciones existentes. No los renombres por un cambio de texto visible.
- La app abre Mi Personal en un `WKWebView` **propio**, separado de Safari. Lee el saldo y vencimiento del texto visible de “Mis disponibles”. No usa una API pública documentada ni extrae una sesión de otro navegador.
- El widget solo lee el último `UsageSnapshot` del App Group. La app hace la consulta; el widget no inicia sesión ni consulta la web.

## Mapa de archivos

| Archivo | Responsabilidad |
| --- | --- |
| `App/PersonalDataWidgetApp.swift` | Ventana, icono de barra de menús y ciclo de vida de la app. |
| `App/ContentView.swift` | Pantalla principal, login por email o SMS y acciones de cuenta. |
| `App/LoginWebView.swift` | Adaptador `NSViewRepresentable` del `WKWebView`. |
| `App/UsageModel.swift` | Estado, consulta, reingreso, cierre de sesión, guardado y actualización programada. |
| `App/UsageProvider.swift` | Proveedor real, ayuda al login y parser del texto de Personal; incluye un proveedor mock. |
| `App/SessionCookieVault.swift` | Cookies de sesión y contraseña opcional en Keychain local. |
| `Shared/UsageSnapshot.swift` | Modelo compartido, App Group, enlaces y `SnapshotStore`. |
| `Widget/PersonalUsageWidget.swift` | Vista y timeline del widget; no contiene secretos. |
| `Configuration/` | Info.plist y entitlements de los dos targets. |
| `scripts/configure_signing.py` | Cambia Team ID, Bundle IDs y App Group para un fork. |
| `.github/workflows/build.yml` | Compilación sin firma en GitHub Actions. |

## Comandos de verificación

Desde la raíz del repositorio:

```sh
git diff --check
python3 -m py_compile scripts/configure_signing.py
xcodebuild -project PersonalDataWidget.xcodeproj \
  -scheme PersonalDataWidget \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/MiConsumoMovilBuild \
  CODE_SIGNING_ALLOWED=NO build
```

Ese build comprueba código y widget, pero **no** prueba App Group, Keychain ni instalación real. Para probarlos, firmá ambos targets con el mismo Apple Team y App Group. Podés probar `configure_signing.py` en una copia temporal con un Team ID y Bundle ID ficticios; no ejecutes esa prueba sobre la instalación del usuario. Para una compilación firmada en el Mac configurado, usá `CODE_SIGN_STYLE=Manual` y omití `CODE_SIGNING_ALLOWED=NO`. Verificá el paquete con `codesign --verify --deep --strict`.

## Invariantes y límites

- `SharedSettings.appGroup` debe coincidir con `Configuration/App.entitlements` y `Configuration/Widget.entitlements`. Ambos targets deben pertenecer al mismo equipo. Si cambiás identificadores para un fork, usá `scripts/configure_signing.py` y comprobá la firma en Xcode.
- No guardes contraseñas, códigos SMS, cookies ni tokens en el repositorio, App Group, logs o pruebas. No imprimas respuestas de autenticación. El email y la línea van a preferencias locales; la contraseña opcional y las cookies de sesión van a Keychain; el widget recibe solo cifras y estado.
- Los nombres de servicio de Keychain en `SessionCookieVault.swift` son heredados de la primera versión. Cambiarlos sin una migración haría perder el acceso guardado de instalaciones actuales.
- `UsageModel` usa `NSBackgroundActivityScheduler` con intervalo de 3600 segundos; WidgetKit decide cuándo recargar. La app debe seguir ejecutándose en la barra de menús. ⌘Q detiene las consultas. `SMAppService.mainApp` intenta iniciar la app al entrar a macOS y puede requerir aprobación del usuario.
- El reingreso automático solo intenta el flujo web con email y contraseña ya guardados. Si Personal exige SMS u otra validación, la persona debe completarla. Una expiración de sesión no demuestra que el servidor permita acceso automático.
- El parser de `UsageProvider.swift` depende del texto actual del portal. Si cambia, ajustá el proveedor con evidencia de una sesión autorizada y actualizá el README. No inventes endpoints ni reutilices encabezados o cookies de Safari.
- **Cerrar sesión** y **Cambiar cuenta** deben borrar también el snapshot compartido para que el widget no muestre datos de la cuenta anterior. Al tocar estas rutas, protegé las consultas en curso con `sessionGeneration`.

## Publicación

El repositorio público usa licencia MIT y distribuye **código fuente**. No subas `.app`, ZIP de desarrollo, perfiles, certificados privados, capturas de login o archivos HAR. La única identidad de firma verificada en el Mac original era **Apple Development**; un instalador para terceros requiere Developer ID, Hardened Runtime y notarización. No presentes un build de desarrollo como instalación universal ni aconsejes desactivar Gatekeeper. Para cambios de código, mantené el README y la compilación de GitHub Actions actualizados.
