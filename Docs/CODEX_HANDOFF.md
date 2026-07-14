# Codex Handoff

Ultima actualizacion: 2026-07-14.

## Punto de continuacion

- Repo: `/Users/nicolasolivares/AGM/tennis_counter_ios`.
- Rama activa: `feature/serve-and-deciding-tiebreak`.
- Base de `main`: `e466936` (`Update iOS release handoff notes`).
- Feature funcional auditada hasta: `2ba17c1` (`docs: reconcile Android backport audit`).
- `main` local y remoto permanecen en `e466936`; la feature todavia no fue mergeada.
- La rama feature esta publicada en `origin/feature/serve-and-deciding-tiebreak`.

Para retomar desde otra maquina o checkout:

```bash
git fetch origin
git switch feature/serve-and-deciding-tiebreak
git pull --ff-only
```

No trabajar desde `main` ni mergear automaticamente antes de completar la revision/QA final de la feature.

## Que contiene la feature

Commits, en orden:

1. `1b4873c` - seleccion del primer servidor y deciding tiebreak a 7/10.
2. `4fd79c5` - onboarding, nombres estructurados, metricas de salud y correcciones de espanol.
3. `5d6528b` - gestos Apple Watch (`tap = punto`, `long press = undo`) y pantalla de novedades.
4. `b90eb9f` - auditoria inicial de candidatos de backport Android.
5. `2ba17c1` - reconciliacion completa del documento de backport con comparacion mobile/mobile y watch/watch.

El estado cruzado y los pendientes Android estan en `Docs/ANDROID_BACKPORT_CANDIDATES.md`.

## Validacion realizada

- Suite `PlayceSharedTests`: 44 tests, 0 fallas.
- Incluye tests nuevos para:
  - disponibilidad del deciding tiebreak,
  - deciding tiebreak a 7 y 10,
  - victoria por dos puntos,
  - replay de eventos,
  - undo de la eleccion del deciding tiebreak,
  - saque inicial desde la derecha.
- Builds exitosas:
  - iPhone Debug.
  - iPhone Release.
  - Apple Watch Debug.
  - Apple Watch Release.
- `git diff --check`: sin errores.

Comando de test usado:

```bash
xcodebuild test \
  -project Playce.xcodeproj \
  -scheme PlayceSharedTests \
  -destination 'platform=iOS Simulator,id=99F8FACA-A0F5-493C-A462-C959B5D0A737' \
  -derivedDataPath build/FeatureTestDerivedData
```

## QA en simuladores

Simuladores usados:

- iPhone 17 Pro: `99F8FACA-A0F5-493C-A462-C959B5D0A737`.
- Apple Watch Series 10: `AE6E0F9D-6FE5-479F-A76D-362636C5F3DA`.

Validado visualmente:

- onboarding inicial en espanol,
- pantalla `Novedades`,
- pantalla principal del contador,
- inicio de la app Apple Watch,
- solicitud de acceso a HealthKit.

Bundle IDs correctos para esta rama:

- iPhone: `com.agm.playce`.
- Watch: `com.agm.playce.watchkitapp`.

Durante QA habia una instalacion vieja del Watch Simulator con bundle ID `com.playce.ios.watchkitapp`. Fue desinstalada y reemplazada por el bundle correcto. Si reaparece `App del reloj no disponible`, verificar primero `xcrun simctl listapps <WATCH_ID>` y eliminar instalaciones viejas antes de diagnosticar WatchConnectivity.

## Pendiente antes de mergear

- Completar QA manual interactivo en simuladores:
  - elegir primer servidor desde iPhone y Watch,
  - enviar configuracion entre dispositivos,
  - probar deciding tiebreak a 7 y 10 en UI,
  - comprobar que long press en Watch hace undo sin sumar un punto adicional,
  - comprobar persistencia de nombres y metricas en History/Detail.
- Validar HealthKit y metricas reales con Apple Watch fisico. El simulador solo permitio confirmar la solicitud de autorizacion.
- Revisar el diff completo de la feature antes del merge.
- Si el QA final pasa, mergear la feature a `main` mediante el flujo Git acordado; no adelantar `main` directamente.

## Contexto Android relacionado

- Android actualizado auditado en `/Users/nicolasolivares/AGM/tennis_counter`, commit `8e49531`.
- La suite Android no pudo ejecutarse en esta Mac porque no hay Java Runtime instalado.
- Pendientes Android confirmados estan priorizados al final de `Docs/ANDROID_BACKPORT_CANDIDATES.md`.

## Estado esperado al cerrar esta sesion

```text
feature/serve-and-deciding-tiebreak -> contiene todos los cambios y este handoff
main                               -> e466936, sin merge de la feature
working tree                       -> limpio
```
