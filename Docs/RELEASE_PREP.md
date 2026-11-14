# Release Prep

Este documento deja lista la preparacion inicial para publicar PLAYCE iOS/watchOS. No reemplaza la validacion con cuenta Apple Developer, firma real ni TestFlight.

## Estado actual

- Version local: `MARKETING_VERSION = 1.1.0`.
- Build local: `CURRENT_PROJECT_VERSION = 7`.
- `1.1.0 (7)` trae el modo 21 en iPhone y Apple Watch y deja el stub de Paredón fuera del selector en Release (`PlayMode.isWallStubAvailable`, solo DEBUG). Esta preparacion no se compilo en el entorno del cambio (sin Xcode); correr el preflight de abajo en la Mac antes de archivar.
- Apple Developer Team: `Atilio Maculus`.
- Team ID: `63U9A75L6R`.
- App Store Connect app name: `PLAYCE Tennis & Padel`.
- iPhone bundle id productivo: `com.agm.playce`.
- Watch bundle id productivo: `com.agm.playce.watchkitapp`.
- In-app purchase usado por StoreKit: `premium_unlock`.
- Privacy policy URL: `https://tenniscounter.vercel.app/privacy`.
- Privacy manifest: `Resources/PrivacyInfo.xcprivacy`.
- Garmin Connect IQ iPhone URL scheme: `playce-ciq`.
- Garmin Connect IQ app id: `c4f18a72-b93e-4d6f-a1c8-e5b2079d3a44`.
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

## Rechazo Guideline 2.1(b) - IAP no enviado a review (junio 2026)

App Review no puede aprobar la version porque el in-app purchase referenciado por la app no esta incluido en la submission. El producto es un no consumible (`premium_unlock`); el texto de Apple sobre "subscriptions" es plantilla generica. Pasos para resolver, todos en App Store Connect:

1. Ir a `Apps > PLAYCE Tennis & Padel > Monetizacion > Compras dentro de la app` y abrir `premium_unlock`.
2. Verificar el estado del producto. Si dice `Ready to Submit` o `Developer Action Needed`, falta metadata o el screenshot de review.
3. Subir el **screenshot de App Review** del IAP (obligatorio): captura del paywall de la app mostrando el boton Unlock Premium con el precio. Sirve una captura de iPhone del tab History/Stats bloqueado.
4. Completar display name y descripcion en ingles y espanol si falta alguno (ver seccion In-App Purchase de este doc).
5. En la pagina de la **version** de la app (la que esta en estado Rejected), buscar la seccion `In-App Purchases and Subscriptions` y **agregar `premium_unlock` a la submission**. Este paso es el que App Review reclama: el IAP debe viajar junto con la version.
6. Subir un binario nuevo (Apple lo pide explicitamente en el rechazo): bump de `CURRENT_PROJECT_VERSION`, archive, upload, seleccionar el build nuevo en la version.
7. Reenviar la version a App Review. El IAP debe aparecer en la misma submission con estado `Waiting for Review`.

Notas:
- Si `premium_unlock` figura `Approved` (quedo aprobado con 1.0.0), el paso 5 no aplica y el rechazo seria por otro producto IAP creado a medias; revisar que no haya productos extra en estado borrador y borrarlos o completarlos.
- El screenshot de review del IAP no se muestra en el App Store, es solo para el reviewer.

## Proxima reanudacion

Estado al 2026-07-01:

- `main` local y `origin/main` quedaron sincronizados en `b3cf9fb`.
- Commits recientes ya pusheados:
  - `a819997 Add Garmin Connect IQ bridge`
  - `4a36b70 Collect active energy for watch workouts`
  - `8c4603d Centralize iOS typography scale`
  - `b3cf9fb Bump iOS release to 1.0.3`
- Se subio a App Store Connect el build `1.0.3 (6)` usando Xcode session renovada para `atomaculus@hotmail.com`.
- Archive usado: `build/archives/Playce-1.0.3-6-20260701-1453.xcarchive`.
- Export/upload path local: `build/uploads/Playce-1.0.3-6-20260701-1453`.
- App Store Connect respondio `Upload succeeded` y el paquete quedo `processing`.
- Warning no bloqueante durante upload: falta el dSYM de `ConnectIQ.framework` para UUID `FA1FD640-51C3-3CDD-9B9B-7DB757A6A082`.
- La version `1.0.2` ya estaba cerrada en App Store Connect; por eso se subio `1.0.3 (6)`.
- HealthKit en watchOS actualmente inicia workout con `HKWorkoutSession`/`HKLiveWorkoutBuilder`, solicita permisos para workout, energia activa y lectura de heart rate, y usa `HKLiveWorkoutDataSource` para que watchOS estime calorias. No se agrego conteo de pasos dedicado.
- La tipografia iOS quedo centralizada en `PlayceType` dentro de `iOS/PlayceIOSApp.swift`, alineada con el criterio de Android. La share card mantiene su escala responsive propia.

Cuando se prepare una nueva revision, retomar por estos pasos:

1. Confirmar en App Store Connect que el build `1.0.3 (6)` termino de procesar.
2. Asociar el build a la version nueva y revisar metadata/screenshots/privacy si App Store Connect lo requiere.
3. Validar iPhone + Apple Watch reales con el checklist de `Docs/MVP_QA_CHECKLIST.md`, especialmente Garmin Connect IQ, HealthKit/workout activo, energia activa y share card.
4. Si se decide corregir el warning de simbolos, conseguir/agregar el dSYM correspondiente de `ConnectIQ.framework`.
5. Correr el preflight local de este documento antes de cualquier nuevo archive y confirmar que `main` esta limpio.

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
- Garmin Connect IQ requiere `NSBluetoothAlwaysUsageDescription`, `LSApplicationQueriesSchemes = gcm-ciq` y el URL scheme `playce-ciq` en el target iPhone.
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
- [x] Resolver rechazo Guideline 4 por icono Apple Watch con fondo negro y subir build corregido: `1.0.0 (3)`.
- [x] Resolver export compliance: la app no usa criptografia propia.
- [x] Esperar procesamiento del build en App Store Connect.
- [x] Validar build disponible en App Store Connect/TestFlight: estado `Lista para enviar`.
- [x] Agregar tester e instalar build via TestFlight en iPhone fisico.
- [x] Ejecutar QA basico en iPhone fisico via TestFlight.
- [x] Validar StoreKit real en TestFlight con compra sandbox de `premium_unlock`.
- [x] Cargar metadata, screenshots, categoria, App Privacy y datos para review.
- [x] Enviar version `1.0.0` a App Review con build `1.0.0 (2)` y `premium_unlock` asociado.
- [x] Reenviar version `1.0.0` a App Review con build `1.0.0 (3)` despues de corregir el icono de Apple Watch.
- [x] App Review aprobo la version `1.0.0 (3)`; la app quedo lista para distribucion.

Resultado:

- Se registro un iPhone fisico en Apple Developer para destrabar automatic signing.
- `xcodebuild archive` genero `build/Playce.xcarchive`.
- `xcodebuild -exportArchive` genero `build/export/PlayceIOS.ipa`.
- `xcodebuild -exportArchive` con `destination=upload` subio el build a App Store Connect.
- App Store Connect respondio: `Uploaded package is processing` / `Upload succeeded`.
- El build `1.0.0 (2)` se subio correctamente el 2026-05-15 despues de regenerar screenshots Release y ajustar el texto de estado del Watch.
- App Review rechazo `1.0.0 (2)` el 2026-05-18 por Guideline 4: el icono de Apple Watch usaba fondo negro y no aparentaba ser circular.
- Se agrego `WatchAppIcon` separado para watchOS con fondo gris oscuro no negro, manteniendo `AppIcon` para iPhone.
- El build `1.0.0 (3)` se subio correctamente el 2026-05-18 y quedo procesando en App Store Connect.
- Se completo export compliance indicando que la app no usa criptografia propia.
- App Store Connect muestra la version `1.0.0 (3)` aprobada y lista para distribucion.
- La version `1.0.0` fue reenviada a App Review con build `1.0.0 (3)` y aprobada el 2026-05-20.
- `premium_unlock` inicialmente no cargaba en TestFlight porque faltaba completar metadata/asociacion a version y la configuracion comercial/fiscal estaba en proceso. Al completar metadata, asociar el IAP a `1.0.0` y avanzar con Business/Tax/Banking, StoreKit devolvio el producto y la compra sandbox funciono.

## Fuentes Apple consultadas

- HealthKit usage descriptions: https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSHealthShareUsageDescription
- HealthKit privacy guidance: https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Required reason APIs: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- StoreKit products: https://developer.apple.com/documentation/storekit/product
- App privacy in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
