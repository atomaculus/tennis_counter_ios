# QA Results

Este archivo registra resultados reales de QA manual. Marcar cada item cuando el usuario lo pruebe e incluir bugs con pasos reproducibles.

## Estado operativo

- Fecha de inicio QA: 2026-05-05.
- Commit local del MVP: `d6cd62a Build iOS watchOS MVP port`.
- GitHub push: pendiente por permisos. El repo local esta `main...origin/main [ahead 1]`.
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
5. Apple Watch fisico futuro: sync real y HealthKit real antes de TestFlight.

## Sesion 1 - iPhone fisico

- [ ] App instala y abre.
- [ ] Wordmark y pantalla principal se ven bien.
- [ ] Configuracion de nombres funciona.
- [ ] Cambio de formato Standard / Grand Slam / Fast4 funciona.
- [ ] Sumar punto A/B funciona.
- [ ] Undo A/B funciona.
- [ ] Timer start/pause/resume funciona.
- [ ] Reset game funciona.
- [ ] Reset match funciona.
- [ ] Se puede terminar un partido.
- [ ] Se puede guardar partido.
- [ ] History muestra el partido guardado.
- [ ] Detail abre el partido correcto.
- [ ] Adjuntar foto funciona.
- [ ] Quitar foto funciona.
- [ ] Share card abre share sheet.
- [ ] Stats muestra totales correctos.
- [ ] Export CSV abre share sheet.
- [ ] Modo gratis bloquea features premium y deja usar contador.
- [ ] DEBUG unlock premium permite acceder a History/Stats/Share.

Resultado:

- Estado: pendiente.
- Bugs encontrados: ninguno registrado todavia.

## Sesion 2 - Apple Watch Simulator

- [ ] Watch app instala y abre.
- [ ] HealthKit prompt no produce crash.
- [ ] Pantalla principal se renderiza bien.
- [ ] Sumar punto A/B funciona.
- [ ] Undo A/B funciona.
- [ ] Timer start/pause/resume funciona.
- [ ] Reset game funciona.
- [ ] Reset match funciona.
- [ ] Finish match funciona.
- [ ] Sync status se entiende.

Resultado:

- Estado: pendiente.
- Bugs encontrados: ninguno registrado todavia.

## Sesion 3 - Sync simuladores iPhone/Watch

- [ ] iPhone Simulator y Apple Watch Simulator estan emparejados.
- [ ] iPhone envia nombres/formato al Watch.
- [ ] Watch aplica nombres/formato.
- [ ] Watch envia live score.
- [ ] iPhone muestra live score read-only.
- [ ] Watch termina partido.
- [ ] iPhone guarda o rechaza segun premium.
- [ ] No hay duplicados por reenvio.

Resultado:

- Estado: pendiente.
- Bugs encontrados: ninguno registrado todavia.

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

## Decisiones de producto pendientes

- Decidir si el timer visible del Apple Watch pasa a ser comportamiento oficial y luego se replica en Wear OS.
- Decidir si iOS/watchOS mantiene botones Undo o adopta long press como Android/Wear.
- Decidir si alguna diferencia visual de iOS debe preservarse por ser mas nativa de Apple.
