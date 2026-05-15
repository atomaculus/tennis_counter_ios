# Release Prep

Este documento deja lista la preparacion inicial para publicar PLAYCE iOS/watchOS. No reemplaza la validacion con cuenta Apple Developer, firma real ni TestFlight.

## Estado actual

- Version local: `MARKETING_VERSION = 1.0.0`.
- Build local: `CURRENT_PROJECT_VERSION = 2`.
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
- [x] Completar metadata de `premium_unlock`, asociarlo a la version `1.0.0` y validar compra sandbox en TestFlight.
- [x] Quitar u ocultar controles visibles `Debug: Lock Premium` / `Debug: Unlock Premium`. Estan dentro de `#if DEBUG` y no entran al build Release.
- [x] Definir URL publica de privacy policy: `https://tenniscounter.vercel.app/privacy`.
- [x] Definir categoria, edad, pricing y disponibilidad inicial.
- [x] Preparar screenshots iPhone y Apple Watch en `/Users/nicolasolivares/AGM/screenshots_app_store`.
- [ ] Validar iPhone + Apple Watch reales con el checklist de `Docs/MVP_QA_CHECKLIST.md`. iPhone fisico validado via TestFlight; falta Apple Watch fisico.

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
- Estado App Store Connect: completo, asociado a la version `1.0.0` y listo para enviar junto con la primera version de la app.
- Offer codes: no configurados para el MVP inicial.
- Imagen: no configurada por ahora.
- Informacion para review:
  `PLAYCE Premium is a non-consumable unlock for match history, match details, statistics, CSV export, photo attachment and share card features. The live tennis/padel counter remains available for free.`
- Resultado TestFlight: compra sandbox/ficticia ejecutada correctamente en iPhone fisico y Premium desbloquea la app.

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
- [x] Crear/descargar provisioning profiles validos para archive.
- [x] Generar archive firmado para `Any iOS Device`.
- [x] Exportar `.ipa` para App Store Connect.
- [x] Subir build inicial a App Store Connect/TestFlight: `1.0.0 (1)`.
- [x] Subir build actualizado a App Store Connect/TestFlight: `1.0.0 (2)`.
- [x] Resolver export compliance: la app no usa criptografia propia.
- [x] Esperar procesamiento del build en App Store Connect.
- [x] Validar build disponible en App Store Connect/TestFlight: estado `Lista para enviar`.
- [x] Agregar tester e instalar build via TestFlight en iPhone fisico.
- [x] Ejecutar QA basico en iPhone fisico via TestFlight.
- [x] Validar StoreKit real en TestFlight con compra sandbox de `premium_unlock`.
- [x] Cargar metadata, screenshots, categoria, App Privacy y datos para review.
- [x] Enviar version `1.0.0` a App Review con build `1.0.0 (2)` y `premium_unlock` asociado.

Resultado:

- Se registro un iPhone fisico en Apple Developer para destrabar automatic signing.
- `xcodebuild archive` genero `build/Playce.xcarchive`.
- `xcodebuild -exportArchive` genero `build/export/PlayceIOS.ipa`.
- `xcodebuild -exportArchive` con `destination=upload` subio el build a App Store Connect.
- App Store Connect respondio: `Uploaded package is processing` / `Upload succeeded`.
- El build `1.0.0 (2)` se subio correctamente el 2026-05-15 despues de regenerar screenshots Release y ajustar el texto de estado del Watch.
- Se completo export compliance indicando que la app no usa criptografia propia.
- App Store Connect muestra la version `1.0.0` como `Lista para enviar`.
- La version `1.0.0` fue enviada a App Review con build `1.0.0 (2)`. Apple indico una espera estimada de hasta 48 horas para respuesta.
- `premium_unlock` inicialmente no cargaba en TestFlight porque faltaba completar metadata/asociacion a version y la configuracion comercial/fiscal estaba en proceso. Al completar metadata, asociar el IAP a `1.0.0` y avanzar con Business/Tax/Banking, StoreKit devolvio el producto y la compra sandbox funciono.

## Fuentes Apple consultadas

- HealthKit usage descriptions: https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSHealthShareUsageDescription
- HealthKit privacy guidance: https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Required reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- StoreKit products: https://developer.apple.com/documentation/storekit/product
- App privacy in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
