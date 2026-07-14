# Android Backport Candidates

> **Auditoría 2026-07-14** (verificada contra código, ver estado por ítem):
> - **Ya resuelto**: lado inicial de saque (Kotlin ya arranca Right, test `serve starts on right then alternates`), timer visible en Wear (footer Start/Pause/Resume existe), undo (UX oficial definida: tap = punto / long-press = deshacer; Apple Watch alineado en `5d6528b`).
> - **Ya agendado**: sync status card (= D6, lote F0) y status de broadcasting en Wear (mismo lote, con copy de usuario, no "ACK inserted").
> - **Gaps reales confirmados, implementar** (lote "backport" post-QA): eliminar partido en Android (hoy NO existe ninguna forma de borrar), timer live congelado en el teléfono Android entre puntos (extrapolar localmente con isMatchActive en vez de ticks por radio), indicador de saque en counter mobile (trivial ahora que existe `currentServerIsPlayerA()`), feedback del botón Aplicar (Send ya lo tiene, Apply no).
> - **Baja prioridad**: preview de share card en detalle Android (el editor ya existe).

Este documento compara decisiones nacidas o refinadas en iOS/watchOS con el estado actual de Android mobile/Wear OS. No implica modificar Android automaticamente.

Repos auditados: `tennis_counter_ios` en `b90eb9f` y `tennis_counter` en `8e49531`.

## Regla de trabajo

- Comparar siempre superficies equivalentes: iPhone vs Android mobile y Apple Watch/watchOS vs Wear OS.
- No usar una implementacion del reloj como evidencia de paridad en mobile, ni viceversa.
- No corregir diferencias iOS vs Android sin decision explicita de producto.
- Antes de tocar Android, decidir si cada diferencia queda como:
  - comportamiento oficial compartido,
  - adaptacion nativa especifica de Apple,
  - bug de iOS/watchOS,
  - bug de Android/Wear OS.
- Mantener la arquitectura Android: `:mobile` telefono, `:app` Wear OS, `:shared` logica comun.

## Candidatos actuales

### Feedback del boton Aplicar

- iPhone: al tocar `Apply`, el boton cambia temporalmente a `Applied`.
- Android mobile: `Apply` aplica la configuracion, pero no cambia temporalmente; `Send to Watch` si cambia a `Sent!`.
- Estado: pendiente en Android mobile para paridad del feedback local.

### Barra/card de status de sync

- iPhone: muestra una card dedicada de sync (`Session ready`, pending transfer, errores de config, etc.).
- Android mobile: muestra confirmacion de config enviada y badge Garmin, pero no una card general equivalente para Wear OS/Data Layer.
- Estado: parcial y ya agendado como D6/lote F0; pendiente ajustar copy para no confundir `ready` con Watch realmente conectado.

### Status de broadcasting en reloj

- watchOS: muestra status orientado al usuario durante sesion y sync.
- Wear OS: muestra sync final (`SYNCING`, retry y `SENT`), pero no broadcasting durante live score.
- Cuidado de producto: evitar exponer mensajes tecnicos internos al usuario final, por ejemplo `ACK inserted`. Mantener esos mensajes solo como debug/testing o reemplazarlos por copy orientado a usuario antes de release.
- Estado: parcial y agendado en D6/lote F0, con copy final pendiente.

### Servidor y lado de saque

- iPhone: `ScoreboardCard` muestra servidor actual y lado de saque.
- Android mobile: no muestra servidor ni lado de saque en el contador local.
- watchOS: muestra `SRV/TB` y `SIDE`.
- Wear OS: muestra servidor e indicador dinamico del lado de saque.
- Estado: completo entre relojes; pendiente en Android mobile respecto de iPhone.

### Lado inicial de saque

- Regla de producto: tanto tenis como padel arrancan sacando desde el lado derecho.
- iOS/watchOS: implementado en `Shared/PlayceModels.swift`; arranca en `Right` y alterna `Right -> Left -> Right`.
- Android mobile/Wear OS: implementado en `:shared` y cubierto por test.
- Estado: completado en ambas plataformas.

### Timer visible en Watch/Wear

- iOS/watchOS: Apple Watch tiene control visible de timer.
- Wear OS: tiene footer visible `START`, `PAUSE` y `RESUME`.
- Estado: completado en ambos relojes.

### Inicio manual del timer

- iPhone, Android mobile, watchOS y Wear OS requieren inicio explicito del usuario.
- Estado: criterio compartido adoptado.
- Nota: el `AGENTS.md` Android todavia describe auto-start y debe alinearse con el codigo.

### Timer live sincronizado Watch/Wear -> telefono

- iOS/watchOS: el Watch emite actualizaciones de live score tambien cuando avanza el timer, no solo cuando hay puntos/undo/pausa.
- Wear OS -> Android mobile: el timer queda congelado entre eventos discretos.
- Criterio acordado: extrapolar el tiempo localmente en Android mobile mientras `isMatchActive`, en vez de transmitir ticks constantes por radio.
- Estado: pendiente en Android.

### Preview/editor de share card

- iPhone y Android mobile: tienen editor previo con preview, posicion, nombres y seleccion de datos visibles.
- Estado: completado en ambos mobile; baja prioridad cualquier ajuste fino restante.

### Eliminar partido desde detalle

- iOS: el detalle del partido incluye boton para eliminar el match guardado.
- Android mobile: no tiene ninguna forma de borrar un partido.
- Estado: gap confirmado, pendiente en Android mobile.

### Undo

- iPhone y Android mobile: botones Undo visibles.
- watchOS y Wear OS: UX oficial `tap = punto`, `long press = undo`; Apple Watch fue alineado en `5d6528b`.
- Estado: resuelto.

## Criterios nuevos posteriores al documento original

### Seleccion del primer servidor y deciding tiebreak

- Android definio el criterio y iOS/watchOS lo adopto en `1b4873c`.
- La configuracion permite elegir primer servidor y ofrecer deciding tiebreak a 7 o 10 cuando corresponde.
- Estado: implementado en la rama feature de iOS; requiere QA cruzado antes de integrar a `main`.

### Salud y actividad

- watchOS y Wear OS registran el partido como workout y recolectan energia/frecuencia cardiaca.
- La rama feature de iOS persiste calorias, pulso promedio/maximo y nombres en History/Detail, alineandose con Android mobile.
- Estado: implementado; requiere QA con permisos y datos disponibles.

### Onboarding y novedades

- iPhone incorpora onboarding inicial y pantalla de novedades para explicar los gestos del reloj.
- Estado: implementado en la rama feature; requiere validar primera ejecucion, persistencia y localizacion.

## Resumen pendiente

Android:

1. Extrapolar el timer live en mobile mientras el partido esta activo.
2. Mostrar servidor y lado de saque en el contador mobile.
3. Permitir eliminar partidos.
4. Agregar feedback temporal `Apply -> Applied`.
5. Completar D6/lote F0 para status de sync/broadcasting.

iOS antes de integrar la feature:

1. Validar primer servidor y deciding tiebreak a 7/10.
2. Validar `tap = punto` y `long press = undo` sin doble disparo.
3. Validar onboarding/What's New y localizacion.
4. Validar HealthKit, metricas persistidas y compatibilidad con historiales anteriores.
