# Mi Consumo Móvil

App macOS y widget de escritorio para ver los gigas disponibles y el vencimiento de cada pack de [Mi Personal](https://mipersonal.personal.com.ar). El proyecto de Xcode conserva el nombre interno `PersonalDataWidget`; el nombre visible de la app y el widget es **Mi Consumo Móvil**.

> Proyecto personal no oficial. No está afiliado a Personal. El sitio puede cambiar su login o el formato de consumo y requerir ajustes en el proveedor.

## Requisitos

- macOS 14 o posterior y Xcode. Este proyecto se compiló con Xcode 27.2 en un Mac Apple Silicon.
- Una cuenta propia de Mi Personal y conexión a Internet.
- Un equipo de firma de Apple configurado en Xcode. Para usar App Groups y WidgetKit, ambos targets deben firmarse con el mismo equipo y compartir el mismo App Group.

## Instalar desde el código, paso a paso

1. Cloná el repositorio y abrí el proyecto:

   ```sh
   git clone https://github.com/gteijeiro/mi-consumo-movil.git
   cd mi-consumo-movil
   open PersonalDataWidget.xcodeproj
   ```

   Como el repositorio es privado, GitHub te pedirá acceso. También podés descargar el código desde la página del repositorio si ya iniciaste sesión allí.

2. En Xcode, elegí el esquema **PersonalDataWidget** y el destino **My Mac**.

3. Revisá **Signing & Capabilities** en los targets **PersonalDataWidget** y **PersonalUsageWidgetExtension**. Ambos deben usar el mismo **Team**. El proyecto trae el equipo `6WV47G2CGZ` y el App Group `6WV47G2CGZ.PersonalDataWidget` para la instalación original. Si compilás con otro equipo, cambiá:

   - `DEVELOPMENT_TEAM` y, si Xcode lo requiere, los dos `PRODUCT_BUNDLE_IDENTIFIER` en `PersonalDataWidget.xcodeproj`;
   - el App Group en `Configuration/App.entitlements` y `Configuration/Widget.entitlements`;
   - `SharedSettings.appGroup` en `Shared/UsageSnapshot.swift`.

   Usá exactamente el mismo App Group en los tres lugares. Xcode puede necesitar que habilites la capacidad **App Groups** para ambos identificadores en tu equipo de desarrollador. En el Mac original se comprobó la compilación con el certificado Apple Development instalado; Xcode no tenía conectada la cuenta para firma automática. En ese caso, conectá tu cuenta en **Xcode > Settings > Accounts** o configurá la firma manual con tu certificado.

4. Elegí **Product > Run** (⌘R). La app abrirá una ventana. Iniciá sesión con tu email y contraseña o con tu línea y código SMS. Escribí los datos solamente dentro de la app. Si el acceso con email pide validar el equipo, completá ese paso en la página. No agregues contraseñas, SMS ni cookies al proyecto.

5. Esperá a que aparezcan los gigas y vencimientos. Si el sitio muestra datos pero la app no, pulsá **Actualizar**. El proveedor lee el texto visible en el `WKWebView`; un cambio de diseño del portal puede requerir actualizar `App/UsageProvider.swift`.

6. En el escritorio de macOS, hacé clic derecho sobre el fondo y elegí **Editar widgets**. Buscá **Mi Consumo Móvil** y agregá el tamaño mediano para ver varios packs. Si no aparece, cerrá y volvé a abrir la app desde Xcode para que macOS registre la extensión.

7. Para dejar una copia en **Aplicaciones**, cerrá la app con ⌘Q, elegí **Product > Show Build Folder in Finder** en Xcode y copiá `Products/Debug/PersonalDataWidget.app` a `/Applications`. Abrí esa copia una vez. El nombre visible en Finder será **Mi Consumo Móvil**. Si ya existe una instalación, reemplazá el paquete completo; conservar el mismo identificador y equipo de firma permite seguir usando los datos locales de esa instalación.

8. Comprobá que aparece el icono de barras en la barra de menús. La app consulta al abrirse y programa otra consulta aproximadamente cada hora mientras su proceso siga activo, aunque cierres la ventana. Para volver a abrirla, usá el icono o buscá **Mi Consumo Móvil** en Aplicaciones. La app intenta habilitar el inicio automático con macOS; si muestra un aviso, autorizala en **Ajustes del Sistema > General > Ítems de inicio**. Salir con ⌘Q detiene las consultas hasta que vuelvas a abrirla.

### Compilar desde Terminal

Después de configurar la firma en Xcode, también podés compilar con:

```sh
xcodebuild -project PersonalDataWidget.xcodeproj \
  -scheme PersonalDataWidget \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build-local build
```

La app resultante estará en `.build-local/Build/Products/Debug/PersonalDataWidget.app`. `.build-local` está excluido de Git. Un build con `CODE_SIGNING_ALLOWED=NO` sirve para revisar errores de compilación, pero no permite probar correctamente el App Group y el widget instalado.

## Uso y privacidad

- **Actualizar** consulta el portal de inmediato. El widget muestra la última lectura guardada y se recarga cuando la app publica una nueva. macOS y WidgetKit pueden retrasar una actualización; no es una garantía de minuto exacto.
- **Cambiar cuenta** y **Cerrar sesión** eliminan la sesión de WebKit, la copia de cookies y la contraseña guardadas en el Llavero, el email y la línea locales, y los datos de la cuenta anterior que ve el widget.
- La app no lee Mensajes. En el acceso por SMS podés escribir el código, aceptar la sugerencia de macOS si funciona o copiar el SMS completo y pulsar **Pegar SMS o código**.
- El email y la línea se guardan como preferencias locales. La contraseña opcional y las cookies de sesión seguras se guardan solo en el Llavero del Mac. El App Group contiene exclusivamente el resumen de consumo y su estado; el widget no recibe credenciales.
- El sitio observado usa un token con vencimiento de alrededor de una hora, pero eso no establece la duración total del login. La app intenta recuperar la sesión mediante el flujo web con el email guardado. Si Personal exige una verificación adicional, hay que hacerla en la ventana.

## Cómo funciona

`LoginWebView` abre el sitio en una sesión propia de `WKWebsiteDataStore.default()`, separada de Safari y Chrome. `PersonalUsageProvider` carga **Mis disponibles**, abre el detalle y extrae los saldos y vencimientos del texto visible. No reproduce directamente una API privada ni guarda encabezados de autorización. `UsageModel` programa la consulta con `NSBackgroundActivityScheduler`; `SnapshotStore` comparte solo el resultado mediante el App Group. El widget lee ese resultado y abre la app mediante un enlace cuando necesita login.

El flujo depende del sitio de Personal. Se verificaron una lectura real, el widget con tres packs, la compilación firmada y la persistencia del acceso al reiniciar la app. La renovación automática después de que el servidor exija una validación nueva sigue dependiendo de ese flujo externo.

## Distribución y Mac App Store

Este repositorio publica **código fuente**, no una app lista para instalar en cualquier Mac. El ZIP local de desarrollo está firmado con **Apple Development**; no es un lanzamiento para terceros. Para distribuir una app fuera de la Store hay que firmarla con **Developer ID** y notarizarla. No pidas a otros usuarios que desactiven Gatekeeper para instalarla.

Publicarla en la Mac App Store **no es imposible**, pero esta versión no está preparada para enviarse. Antes habría que comprobar el permiso de uso del servicio de Personal, preparar una forma de revisión sin exponer una cuenta real, revisar el consentimiento para el inicio automático, probar el funcionamiento con App Sandbox y completar los requisitos de firma, metadatos y revisión de Apple. Apple puede rechazar una app que dependa de un servicio ajeno sin autorización o que no aporte suficiente funcionalidad propia.

Documentación oficial: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [preparación para distribuir](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [notarización](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Seguridad del repositorio

No subas capturas de login, archivos HAR, bases de WebKit, cookies, tokens, códigos SMS, contraseñas, certificados privados ni perfiles de aprovisionamiento. `.gitignore` excluye salidas de compilación y varios formatos sensibles. La firma del proyecto incluye un identificador de equipo, pero ninguna clave privada.
