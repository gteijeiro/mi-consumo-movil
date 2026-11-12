# Mi Consumo Móvil

App macOS y widget de escritorio para ver los gigas disponibles y el vencimiento de cada pack de [Mi Personal](https://mipersonal.personal.com.ar). El proyecto de Xcode conserva el nombre interno `PersonalDataWidget`; el nombre visible de la app y el widget es **Mi Consumo Móvil**.

Para contribuir con un agente de código, empezá por [AGENTS.md](AGENTS.md): resume arquitectura, archivos, comandos de verificación y límites del proyecto.

> Proyecto comunitario no oficial. No está afiliado a Personal. Necesitás tu propia cuenta del servicio. El sitio puede cambiar su login o el formato de consumo y requerir ajustes en el proveedor.

## Requisitos

- macOS 14 o posterior, Xcode y Python 3 para el configurador. Este proyecto se compiló con Xcode 27.2 en un Mac Apple Silicon.
- Una cuenta propia de Mi Personal y conexión a Internet.
- Un equipo de firma de Apple configurado en Xcode y con capacidad para firmar ambos targets con App Groups. Si Xcode no ofrece esa capacidad para tu equipo, no podrás probar el intercambio de datos con el widget mediante esta configuración.

## Instalar desde el código, paso a paso

1. Cloná el repositorio público:

   ```sh
   git clone https://github.com/gteijeiro/mi-consumo-movil.git
   cd mi-consumo-movil
   ```

   También podés descargar **Code > Download ZIP** en GitHub y descomprimirlo; no hace falta una cuenta de GitHub para leer el repositorio.

2. Obtené el **Team ID** de tu equipo de Apple en Xcode o en tu cuenta de desarrollador. Elegí un Bundle ID propio, por ejemplo `com.tunombre.MiConsumoMovil`, y configurá esta copia:

   ```sh
   python3 scripts/configure_signing.py \
     --team-id TU_TEAM_ID \
     --bundle-id com.tunombre.MiConsumoMovil
   ```

   El script actualiza los dos identificadores de app, el equipo de firma y el App Group en Xcode, en los dos archivos de entitlements y en el código compartido. **No escribas credenciales de Personal en el comando.** Si usás el equipo original del mantenedor, este paso puede omitirse. Si vas a actualizar una copia que ya instalaste con otro identificador, conservá el mismo Team ID y Bundle ID para mantener su sesión local.

3. Abrí `PersonalDataWidget.xcodeproj` con Xcode. Elegí el esquema **PersonalDataWidget** y el destino **My Mac**. En **Signing & Capabilities**, revisá los targets **PersonalDataWidget** y **PersonalUsageWidgetExtension**: ambos deben usar tu mismo Team, tener **App Groups** habilitado y mostrar el mismo grupo generado por el script. Si Xcode solicita registrar los Bundle IDs o reparar la firma, permití que complete la configuración de tu equipo.

   El grupo de macOS usa el formato `<Team ID>.PersonalDataWidget`. [Apple documenta ese formato](https://developer.apple.com/documentation/xcode/configuring-app-groups). En el Mac original se comprobó la compilación con un certificado Apple Development. Si Xcode no encuentra tu equipo, agregá tu cuenta en **Xcode > Settings > Accounts**.

4. Elegí **Product > Run** (⌘R). La app abrirá una ventana. Iniciá sesión con tu email y contraseña o con tu línea y código SMS. Escribí los datos solamente dentro de la app. Si el acceso con email pide validar el equipo, completá ese paso en la página. No agregues contraseñas, SMS ni cookies al proyecto.

5. Esperá a que aparezcan los gigas y vencimientos. Si el sitio muestra datos pero la app no, pulsá **Actualizar**. El proveedor lee el texto visible en el `WKWebView`; un cambio de diseño del portal puede requerir actualizar `App/UsageProvider.swift`.

6. En el escritorio de macOS, hacé clic derecho sobre el fondo y elegí **Editar widgets**. Buscá **Mi Consumo Móvil** y agregá el tamaño mediano para ver varios packs. Si no aparece, cerrá y volvé a abrir la app desde Xcode para que macOS registre la extensión.

7. Para dejar una copia en **Aplicaciones**, cerrá la app con ⌘Q, elegí **Product > Show Build Folder in Finder** en Xcode y copiá `Products/Debug/PersonalDataWidget.app` a `/Applications`. Abrí esa copia una vez. El nombre visible en Finder será **Mi Consumo Móvil**. Si ya existe una instalación, reemplazá el paquete completo; conservar el mismo identificador y equipo de firma permite seguir usando los datos locales de esa instalación. No uses un ZIP de desarrollo firmado por otra persona como instalador general.

8. Para consultar sin mantener abierta la app, instalá el agente de usuario de macOS desde la carpeta clonada:

   ```sh
   python3 scripts/background_refresh.py --install
   ```

   El agente se ejecuta cada cinco minutos, aunque la ventana de la app esté abierta. Si la última lectura está vencida, consulta **sin abrir otra ventana ni icono en la barra de menús**, guarda el resultado en el App Group y termina. La app abierta también puede consultar. macOS puede aplazar las tareas mientras duerme, por lo que la hora de consulta es aproximada. Si se necesita un nuevo login, el widget indica que hay que abrir la app; los reintentos automáticos de acceso se espacian para evitar intentos continuos.

   Para quitar el agente, ejecutá `python3 scripts/background_refresh.py --uninstall`. Sin él, la app solo actualiza mientras su proceso esté abierto; cerrar la ventana con el botón rojo lo deja activo en la barra de menús y ⌘Q lo detiene. Si Personal exige un nuevo código SMS u otra validación, abrí la app para completar el login.

   Para comprobar la última lectura sin abrir la ventana, ejecutá `/Applications/PersonalDataWidget.app/Contents/MacOS/PersonalDataWidget --snapshot-status`. Muestra solo el estado y la hora de la última consulta; los gigas pueden conservar el mismo valor entre consultas.

   Si la página de login queda en blanco tras perder la conexión, la app intenta recargarla al recuperar actividad. También podés cerrar el formulario y volver a pulsar **Iniciar sesión**. Si Personal exige SMS o validación del equipo, completá ese paso en la app: el agente no puede resolverlo por sí solo.

   Si el formulario no avanza en **Continuar**, usá **Reiniciar acceso**. Borra los datos web de la app y vuelve a cargar el login, conservando la contraseña guardada en el Llavero. Personal puede pedir validar la identidad mediante un código por email o SMS; ingresalo directamente en la página. **Cerrar sesión** elimina también el acceso guardado.

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

`LoginWebView` abre el sitio en una sesión propia de `WKWebsiteDataStore.default()`, separada de Safari y Chrome. `PersonalUsageProvider` carga **Mis disponibles**, abre el detalle y extrae los saldos y vencimientos del texto visible. No reproduce directamente una API privada ni guarda encabezados de autorización. Con la app abierta, `UsageModel` programa la consulta; con la app cerrada, un agente `launchd` ejecuta el mismo binario en modo sin interfaz y consulta cuando la lectura está vencida. `SnapshotStore` comparte solo el resultado mediante el App Group. El widget lee ese resultado y abre la app mediante un enlace cuando necesita login.

El flujo depende del sitio de Personal. Se verificaron una lectura real, el widget con tres packs, la compilación firmada y la persistencia del acceso al reiniciar la app. La renovación automática después de que el servidor exija una validación nueva sigue dependiendo de ese flujo externo.

## Distribución y Mac App Store

Este repositorio público ofrece **código fuente que cada persona puede compilar con su propio equipo de Apple**. Todavía no hay un instalador binario universal: en el equipo del mantenedor solo hay un certificado **Apple Development**, que no sirve para notarizar una distribución para terceros. Para ofrecer una app descargable lista para abrir en otros Macs, el mantenedor necesitaría un certificado **Developer ID**, activar Hardened Runtime, firmar y notarizar una versión de distribución. No desactives Gatekeeper para instalar un ZIP de desarrollo.

Publicarla en la Mac App Store **no es imposible**, pero esta versión no está preparada para enviarse. Antes habría que comprobar el permiso de uso del servicio de Personal, preparar una forma de revisión sin exponer una cuenta real, revisar el consentimiento para el inicio automático, probar el funcionamiento con App Sandbox y completar los requisitos de firma, metadatos y revisión de Apple. Apple puede rechazar una app que dependa de un servicio ajeno sin autorización o que no aporte suficiente funcionalidad propia.

Documentación oficial: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [preparación para distribuir](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [notarización](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Seguridad del repositorio

No subas capturas de login, archivos HAR, bases de WebKit, cookies, tokens, códigos SMS, contraseñas, certificados privados ni perfiles de aprovisionamiento. `.gitignore` excluye salidas de compilación y varios formatos sensibles. La firma del proyecto incluye un identificador de equipo, pero ninguna clave privada.

## Licencia

El código se publica con la [licencia MIT](LICENSE). Esta licencia cubre el código de este repositorio; no concede derechos sobre marcas, contenidos ni servicios de Personal.
