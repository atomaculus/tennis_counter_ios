# Android Backport Candidates

Este documento lista decisiones nacidas o refinadas en iOS/watchOS que podrian pasar a ser comportamiento oficial del producto y luego replicarse en Android/Wear OS. No implica modificar Android automaticamente.

## Regla de trabajo

- No corregir diferencias iOS vs Android sin decision explicita de producto.
- Antes de tocar Android, decidir si cada diferencia queda como:
  - comportamiento oficial compartido,
  - adaptacion nativa especifica de Apple,
  - bug de iOS/watchOS,
  - bug de Android/Wear OS.
- Mantener la arquitectura Android: `:mobile` telefono, `:app` Wear OS, `:shared` logica comun.

## Candidatos actuales

### Feedback del boton Aplicar

- iOS: al tocar `Aplicar` en configuracion, el boton cambia temporalmente a `Aplicado` y los botones tienen feedback on-press mas visible.
- Android candidato: agregar feedback equivalente en `mobile` cuando se aplica configuracion local o se envia al reloj.
- Estado: candidato a comportamiento oficial.

### Barra/card de status de sync

- iOS: el contador mobile muestra una card dedicada de sync (`Session ready`, pending transfer, errores de config, etc.).
- Android candidato: revisar si mobile deberia exponer un status de sync mas visible y consistente.
- Estado: candidato a comportamiento oficial, pendiente ajustar copy para no confundir `ready` con Watch realmente conectado.

### Server y serve side en contador mobile

- iOS: el contador mobile muestra servidor actual y lado de saque.
- Android candidato: si no esta visible en `mobile`, incorporar una indicacion equivalente para scorer local.
- Estado: candidato a comportamiento oficial.

### Lado inicial de saque

- Regla de producto: tanto tenis como padel arrancan sacando desde el lado derecho.
- Android: actualmente registrado por producto como invertido.
- iOS/watchOS: corregido en `Shared/PlayceModels.swift`; ahora arranca en `Right` y alterna `Right -> Left -> Right`.
- Estado: corregido en iOS/watchOS. Pendiente replicar en Android `:shared` cuando se decida trabajar Android.

### Timer visible en Watch/Wear

- iOS/watchOS: Apple Watch tiene control visible de timer.
- Android/Wear OS: producto reporta que hoy no existe boton visible equivalente.
- Estado: candidato fuerte a comportamiento oficial para replicar en Wear OS. Producto lo valido positivamente durante QA.

### Timer live sincronizado Watch/Wear -> telefono

- iOS/watchOS: el Watch emite actualizaciones de live score tambien cuando avanza el timer, no solo cuando hay puntos/undo/pausa.
- Android candidato: revisar si Wear OS tiene el mismo problema y, si existe, emitir ticks de timer al telefono mientras el partido esta activo.
- Estado: candidato a comportamiento oficial. Producto quiere que el timer del telefono vaya a la par del timer real y refleje pausa/reanudacion.

### Preview de share card

- iOS: antes de compartir, el detalle muestra preview de la share card.
- Android candidato: incorporar preview equivalente antes de abrir el flujo de compartir para que el usuario valide la tarjeta final.
- Estado: candidato a comportamiento oficial.

### Eliminar partido desde detalle

- iOS: el detalle del partido incluye boton para eliminar el match guardado.
- Android candidato: revisar si el detalle/history mobile deberia tener accion equivalente.
- Estado: candidato a comportamiento oficial.

### Undo

- Android/Wear OS: long press sobre `+A`/`+B` abre opcion de undo.
- iOS/watchOS: MVP mantiene botones `Undo A`/`Undo B`.
- Estado: decision pendiente. No cambiar iOS ni Android hasta definir UX oficial.
