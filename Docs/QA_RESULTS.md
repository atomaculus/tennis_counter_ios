# QA Results

Este archivo registra resultados reales de QA manual. Marcar cada item cuando el usuario lo pruebe e incluir bugs con pasos reproducibles.

## Estado operativo

- Fecha de inicio QA: 2026-05-05.
- Commit base antes de esta actualizacion: `7ec7db8 Bump iOS build for App Store upload`.
- GitHub push: al dia contra `origin/main`.
- Dispositivos disponibles hoy:
  - iPhone fisico: disponible.
  - iPhone Simulator: disponible.
  - Apple Watch Simulator: disponible.
  - Apple Watch fisico: no disponible.

## Orden recomendado de pruebas

1. iPhone fisico: contador local y flujos premium/history/stats/share.
2. iPhone Simulator: confirmar que el comportamiento coincide con fisico.
3. Apple Watch Simulator: scorer y HealthKit no-crash.
4. iPhone Simulator + Apple Watch Simulator emparejados: sync basico.
5. Apple Watch fisico futuro: sync real y HealthKit real cuando haya dispositivo disponible.
6. App Store Review: version `1.0.0` enviada con build `1.0.0 (2)`; esperar respuesta de Apple.

## Sesion 1 - iPhone Simulator

- [x] App instala y abre.
- [x] Wordmark y pantalla principal se ven bien.
- [x] Configuracion de nombres funciona. El problema de letras convertidas a `a` solo ocurre con teclado fisico/remoto; con teclado en pantalla del simulador funciona correctamente.
- [x] Cambio de formato Standard / Grand Slam / Fast4 funciona.
- [x] Sumar punto A/B funciona.
- [x] Undo A/B funciona.
- [x] Timer start/pause/resume funciona.
- [x] Reset game funciona.
- [x] Reset match funciona como `Nuevo partido`.
- [x] Se puede terminar un partido.
- [x] Se puede guardar partido.
- [x] History muestra el partido guardado.
- [x] Detail abre el partido correcto.
- [x] Adjuntar foto funciona.
- [x] Quitar foto funciona.
- [x] Share card preview se ve bien. Share sheet abre, pero en simulador no se valido destino final externo.
- [x] Stats muestra totales correctos.
- [x] Export CSV abre share sheet.
- [x] Modo gratis bloquea features premium y deja usar contador.
- [x] En modo gratis, guardar un partido muestra `Guardado para Premium` y explica que se vera en Historial al desbloquear Premium.
- [x] Al desbloquear Premium en DEBUG, el partido guardado en modo gratis aparece en History.
- [x] DEBUG unlock premium permite acceder a History/Stats/Share.
- [x] Boton eliminar partido disponible en detalle.
- [x] Lado de saque inicial arranca en `Right`.

Resultado:

- Estado: aprobado para iPhone Simulator en el alcance MVP probado.
- Bugs encontrados: QA-001, QA-002, QA-003, QA-004, QA-005.

## Sesion 2 - Apple Watch Simulator

- [x] Watch app instala y abre.
- [x] HealthKit prompt no produce crash.
- [x] Pantalla principal se renderiza bien, con ajuste de orden visual confirmado en QA-006.
- [x] Sumar punto A/B funciona.
- [x] Undo A/B funciona.
- [x] Timer start/pause/resume funciona.
- [x] Reset game funciona.
- [x] Reset match funciona.
- [x] Finish match funciona.
- [ ] Sync status se entiende para testing. Pendiente revisar copy final para usuario en QA-008.
- [x] Lado de saque inicial arranca en `Right`.

Resultado:

- Estado: funcional aprobado para scorer local. Queda pendiente revisar copy final de status.
- Bugs encontrados: QA-006, QA-008.

## Sesion 3 - Sync simuladores iPhone/Watch

- [x] iPhone Simulator y Apple Watch Simulator estan emparejados.
- [x] iPhone envia nombres/formato al Watch.
- [x] Watch aplica nombres/formato.
- [x] Watch envia live score.
- [x] iPhone muestra live score read-only.
- [x] Timer live Watch -> iPhone actualiza continuamente y respeta pausa/reanudacion.
- [x] Watch termina partido.
- [x] iPhone guarda partido terminado en History.
- [x] No hay duplicados por reenvio: el boton queda en `Saved` y no permite reenviar manualmente el mismo partido.

Resultado:

- Estado: sync basico aprobado en simuladores emparejados.
- Bugs encontrados: QA-007, QA-008.

## Sesion 4 - iPhone fisico TestFlight

- [x] Build `1.0.0 (1)` instalado desde TestFlight en iPhone fisico.
- [x] La app abre y el contador funciona correctamente en el dispositivo fisico.
- [x] `premium_unlock` completo en App Store Connect y asociado a la version `1.0.0`.
- [x] Compra sandbox/ficticia de Premium ejecutada correctamente desde la app.
- [x] Premium queda desbloqueado y las funciones premium funcionan en build TestFlight.

Resultado:

- Estado: aprobado para iPhone fisico/TestFlight en el alcance probado.
- Nota: la compra no aparecia mientras `premium_unlock` no estaba completamente listo/asociado y la configuracion Business/Tax/Banking seguia pendiente.

## Bugs

Registrar cada bug con este formato:

```text
ID:
Ambiente: iPhone fisico / iPhone Simulator / Watch Simulator / Sync simulador
Pasos:
Resultado esperado:
Resultado real:
Captura/log si aplica:
Severidad: bloqueante / alta / media / baja
Estado: abierto / corregido / no reproducible / decision de producto
```

### QA-001

Ambiente: iPhone Simulator controlado por escritorio remoto.
Pasos: abrir Config. partido, tocar campo de jugador y escribir `test`.
Resultado esperado: el campo muestra `test`.
Resultado real: el campo muestra `aaaa`.
Severidad: alta.
Estado: no reproducible en la app. La logica SwiftUI solo recibe el texto del sistema y lo recorta a 12 caracteres; el problema fue causado por teclado fisico/remoto.
Resolucion: no es bug de la app. Con teclado en pantalla del simulador se puede escribir correctamente. Queda documentado como limitacion del escritorio remoto.

### QA-002

Ambiente: iPhone Simulator.
Pasos: cambiar nombres y tocar `Aplicar`.
Resultado esperado: feedback visual claro de que se aplico.
Resultado real: aplicaba cambios, pero el boton no daba feedback suficientemente visible.
Severidad: baja.
Estado: corregido y confirmado por QA. `Aplicar` cambia a `Aplicado` y los botones tienen escala on-press.

### QA-003

Ambiente: iPhone Simulator + Apple Watch Simulator.
Pasos: ver estado `Session ready`, tocar `Enviar reloj`.
Resultado esperado: si no hay conexion efectiva, el estado previo no deberia sugerir que el Watch esta listo.
Resultado real: antes de enviar decia `Session ready`; luego `Config sync unavailable`.
Severidad: media.
Estado: corregido y confirmado por QA. El estado inicial distingue `Watch reachable`, `Watch not reachable`, `Watch app unavailable` o `Watch not paired`. El boton de envio ya no cambia a `Enviado` cuando el envio falla; puede mostrar `En cola` o `No disponible`. Si el Watch esta reachable, se intenta envio inmediato ademas del application context.
Resultado de repro: con simuladores sin pair, la app muestra `Reloj no emparejado` y el boton cambia temporalmente a `No disponible`; comportamiento aprobado por producto. Con pair activo `F53F0C00-3900-4743-BAC1-E28328925E99`, la configuracion se envio y el Watch confirmo recibo.

### QA-004

Ambiente: iPhone Simulator DEBUG con premium desbloqueado.
Pasos: abrir pantalla principal.
Resultado esperado: mostrar herramientas premium desbloqueadas sin mensaje de error.
Resultado real: mostraba `Premium no esta disponible todavia. Intenta mas tarde.` aunque las features premium estaban disponibles.
Severidad: baja.
Estado: corregido y confirmado por QA. El mensaje de StoreKit no disponible se oculta si premium esta desbloqueado y en DEBUG usa copy local. Debe mostrarse un mensaje equivalente solo si el usuario no tiene Premium o StoreKit no esta disponible.

### QA-005

Ambiente: iPhone Simulator.
Pasos: abrir pantalla principal.
Resultado esperado: wordmark integrado visualmente con el fondo.
Resultado real: el wordmark parece tener fondo mas negro que la card/superficie.
Severidad: baja.
Estado: corregido y confirmado por QA. `WordmarkView` ahora replica el wordmark textual de Android (`PLAY` blanco + `CE` verde) y evita el rectangulo negro del PNG. Revisar tipografia final mas adelante.

### QA-006

Ambiente: Apple Watch Simulator.
Pasos: abrir contador en Watch.
Resultado esperado: orden visual solicitado por producto: sets/games/timer arriba, luego score del game actual, luego server y serve side.
Resultado real: el score del game actual estaba arriba de sets/games/timer.
Severidad: baja.
Estado: corregido y confirmado por QA. `Watch/PlayceWatchApp.swift` ahora muestra sets/games/timer antes del score del game actual.

### QA-007

Ambiente: iPhone Simulator + Apple Watch Simulator emparejados.
Pasos: iniciar timer en Watch y mirar live score en iPhone sin sumar puntos.
Resultado esperado: el timer del iPhone avanza a la par del timer del Watch y refleja pausa/reanudacion.
Resultado real: el timer del iPhone solo actualizaba cuando se sumaba punto, se hacia undo o se pausaba el timer.
Severidad: media.
Estado: corregido y confirmado por QA. Watch emite live score al cambiar `elapsedSeconds` mientras el timer corre, y el payload ahora incluye `isTimerRunning`/`hasTimerStarted` para que iPhone muestre running/paused correctamente.
Nota posterior: en modo broadcast, el timer del iPhone es solo display. Se cambio la UI para mostrar un pill de estado `Running`/`Paused`/`Not started` en vez de un boton accionable `Pause`/`Resume`.

### QA-008

Ambiente: Apple Watch Simulator + sync con iPhone Simulator.
Pasos: guardar partido terminado desde Watch y observar status bar.
Resultado esperado: durante testing, el status ayuda a confirmar sync; para usuario final, no deberia exponer mensajes tecnicos internos.
Resultado real: la barra muestra mensajes como `ACK inserted`, utiles para QA pero demasiado tecnicos para producto final.
Severidad: baja.
Estado: corregido para release. El build `1.0.0 (2)` mantiene estados utiles como broadcasting/sync, pero traduce mensajes tecnicos tipo `ACK inserted` a copy user-facing como `PARTIDO GUARDADO` o `RELOJ LISTO`.

### QA-009

Ambiente: iPhone Simulator DEBUG.
Pasos: bloquear Premium con control DEBUG, terminar un partido en modo gratis, guardarlo, desbloquear Premium con control DEBUG y abrir History.
Resultado esperado: el contador sigue funcionando gratis; History/Stats quedan bloqueados; al guardar desde gratis, el feedback no promete acceso inmediato y aclara que el partido queda disponible al desbloquear Premium.
Resultado real: comportamiento aprobado por QA. El boton muestra `Guardado para Premium`, el mensaje indica que se vera en Historial al desbloquear Premium y el partido aparece en History luego del unlock DEBUG.
Severidad: baja.
Estado: corregido y confirmado por QA.

### QA-010

Ambiente: iPhone fisico con build TestFlight `1.0.0 (1)`.
Pasos: instalar desde TestFlight, abrir app, tocar Premium.
Resultado esperado: StoreKit muestra la compra sandbox/ficticia de `premium_unlock` y, al completarla, Premium queda desbloqueado.
Resultado real inicial: la app mostraba `Premium no esta disponible todavia. Intenta mas tarde.`
Severidad: alta para release.
Estado: corregido por configuracion de App Store Connect. Faltaba completar metadata/asociacion de la primera IAP a la version `1.0.0` y avanzar con Business/Tax/Banking. Luego de completar eso, la compra sandbox funciono y Premium desbloqueo correctamente.

## Decisiones de producto pendientes

- Decidir si el timer visible del Apple Watch pasa a ser comportamiento oficial y luego se replica en Wear OS. Producto lo marco como deseable para Android/Wear.
- Revisar en Android/Wear si el timer live tiene el mismo problema de actualizar el telefono solo con eventos discretos; si ocurre, replicar timer live continuo.
- Evaluar status visible de `broadcasting` en Android/Wear como comportamiento oficial, evitando exponer mensajes tecnicos internos tipo ACK al usuario final.
- Evaluar replicar en Android mobile el preview de share card antes de compartir.
- Evaluar replicar en Android mobile el boton de eliminar partido desde detalle.
- Decidir si iOS/watchOS mantiene botones Undo o adopta long press como Android/Wear.
- Decidir si alguna diferencia visual de iOS debe preservarse por ser mas nativa de Apple.
- Los controles `Debug: Lock Premium` / `Debug: Unlock Premium` quedan disponibles solo en builds `DEBUG`; no aparecen en Release/TestFlight.
- Revisar `Docs/ANDROID_BACKPORT_CANDIDATES.md` antes de hacer cambios de paridad Android/iOS.
