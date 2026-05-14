# Release Prep

Este documento deja lista la preparacion inicial para publicar PLAYCE iOS/watchOS. No reemplaza la validacion con cuenta Apple Developer, firma real ni TestFlight.

## Estado actual

- Version local: `MARKETING_VERSION = 1.0.0`.
- Build local: `CURRENT_PROJECT_VERSION = 1`.
- Apple Developer Team: `Atilio Maculus`.
- Team ID: `63U9A75L6R`.
- App Store Connect app name: `PLAYCE Tennis & Padel`.
- iPhone bundle id productivo: `com.agm.playce`.
- Watch bundle id productivo: `com.agm.playce.watchkitapp`.
- In-app purchase usado por StoreKit: `premium_unlock`.
- Privacy policy URL: `https://tenniscounter.vercel.app/privacy`.
- Privacy manifest: `Resources/PrivacyInfo.xcprivacy`.
- HealthKit entitlement Watch: `Watch/PlayceWatchApp.entitlements`.

## Antes de App Store Connect

- [x] Confirmar Team ID y cuenta Apple Developer que firmara la app: `Atilio Maculus` / `63U9A75L6R`.
- [x] Confirmar bundle ids productivos con el owner de la cuenta Apple Developer: `com.agm.playce` y `com.agm.playce.watchkitapp`.
- [x] Actualizar `project.yml` si los bundle ids productivos cambian.
- [x] Crear App ID iOS y Watch App ID.
- [x] Habilitar HealthKit para el Watch App ID.
- [x] Crear app en App Store Connect con nombre `PLAYCE Tennis & Padel`.
- [x] Confirmar product id de Premium: se mantiene `premium_unlock`.
- [x] Crear `premium_unlock` como in-app purchase no consumible en App Store Connect.
- [x] Definir precio inicial de Premium: `3.99`.
- [x] Quitar u ocultar controles visibles `Debug: Lock Premium` / `Debug: Unlock Premium`. Estan dentro de `#if DEBUG` y no entran al build Release.
- [x] Definir URL publica de privacy policy: `https://tenniscounter.vercel.app/privacy`.
- [ ] Definir categoria, edad, pricing y disponibilidad.
- [ ] Preparar screenshots iPhone y Apple Watch.
- [ ] Validar iPhone + Apple Watch reales con el checklist de `Docs/MVP_QA_CHECKLIST.md`.

## Proxima reanudacion

Cuando la cuenta Apple Developer este aprobada, retomar por estos pasos:

1. Correr el preflight local de este documento y confirmar que `main` esta limpio.
2. Crear App IDs/capabilities y el producto StoreKit `premium_unlock`.
3. Quitar u ocultar los controles DEBUG visibles de premium.
4. Generar build firmado para dispositivo fisico y validar iPhone + Apple Watch reales.
5. Preparar metadata/screenshots/privacy y subir a TestFlight.

## App Store Connect - valores sugeridos

- Nombre de app en App Store Connect: `PLAYCE Tennis & Padel`.
- Nombre visible dentro de la app: `PLAYCE`.
- Bundle ID iPhone: `com.agm.playce`.
- Bundle ID Watch: `com.agm.playce.watchkitapp`.
- SKU: `PLAYCE-IOS-001` o cualquier identificador interno unico.
- Categoria primaria sugerida: `Sports`.
- Categoria secundaria sugerida: `Health & Fitness` si se mantiene HealthKit/workouts; si no, dejar sin secundaria o usar `Utilities`.
- Disponibilidad: empezar con el pais principal de publicacion; ampliar despues si hace falta.
- Precio app: gratis si Premium se monetiza con in-app purchase.
- In-app purchase: no consumible, product id `premium_unlock`, precio inicial `3.99`.
- Privacy Policy URL: `https://tenniscounter.vercel.app/privacy`.

## In-App Purchase

- Tipo: `Non-Consumable`.
- Reference name: `PLAYCE Premium`.
- Product ID: `premium_unlock`.
- Precio inicial: `3.99`.
- Display name: `PLAYCE Premium`.
- Descripcion sugerida en ingles: `Unlock match history, stats, export and share tools.`
- Descripcion sugerida en espanol: `Desbloquea historial de partidos, estadisticas, exportacion y herramientas para compartir.`
- Offer codes: no configurados para el MVP inicial.
- Imagen: no configurada por ahora.
- Informacion para review:
  `PLAYCE Premium is a non-consumable unlock for match history, match details, statistics, CSV export, photo attachment and share card features. The live tennis/padel counter remains available for free.`

## Permisos y privacidad

- HealthKit requiere textos de uso al leer y escribir datos de salud. El target Watch ya declara:
  - `NSHealthShareUsageDescription`
  - `NSHealthUpdateUsageDescription`
- El target Watch declara `com.apple.developer.healthkit`.
- La app usa `UserDefaults` para premium/debug state y pendientes de sync, por eso `PrivacyInfo.xcprivacy` declara `NSPrivacyAccessedAPICategoryUserDefaults` con razon `CA92.1`.
- El flujo actual usa almacenamiento local y WatchConnectivity; no hay tracking ni dominios de tracking declarados.
- La respuesta de App Privacy en App Store Connect debe revisarse con producto/legales antes de publicar, especialmente por HealthKit/workouts y fotos adjuntas locales.

## Comandos de preflight local

```bash
xcodegen generate
xcodebuild test -project Playce.xcodeproj -scheme PlayceSharedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild -project Playce.xcodeproj -scheme PlayceIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Playce.xcodeproj -scheme PlayceWatchApp -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Playce.xcodeproj -scheme PlayceIOS -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

## Verificacion Release

- [x] `PlayceIOS` compila en configuracion `Release` para iOS Simulator.
- [x] El binario Release no contiene los textos `Debug: Lock Premium` ni `Debug: Unlock Premium`.

## Archive firmado

- [x] Cuenta Apple Developer agregada en Xcode: `Atilio Maculus` / `63U9A75L6R`.
- [x] Signing automatico seleccionado para `PlayceIOS` y `PlayceWatchApp`.
- [x] HealthKit agregado al target `PlayceWatchApp` y persistido en `project.yml`.
- [x] Crear o descargar certificado `Apple Distribution` en esta Mac.
- [ ] Crear/descargar provisioning profiles validos para archive.
- [ ] Generar archive firmado para `Any iOS Device`.
- [ ] Subir build a TestFlight.

Intento de archive por terminal:

- Resultado: bloqueado.
- Certificados disponibles: `Apple Development` y `Apple Distribution: Atilio Maculus (63U9A75L6R)`.
- Motivo actual: Xcode automatic signing intenta usar/generar provisioning profiles de desarrollo para el archive y el team no tiene dispositivos registrados.
- Siguiente accion posible A: registrar un iPhone fisico en Apple Developer para que Xcode pueda crear perfiles de desarrollo automaticos.
- Siguiente accion posible B: crear perfiles de distribucion/App Store para `com.agm.playce` y `com.agm.playce.watchkitapp`, descargarlos en esta Mac y configurar signing manual para Release.

## Fuentes Apple consultadas

- HealthKit usage descriptions: https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSHealthShareUsageDescription
- HealthKit privacy guidance: https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Required reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- StoreKit products: https://developer.apple.com/documentation/storekit/product
- App privacy in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
