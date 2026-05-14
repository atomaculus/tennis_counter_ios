# MVP QA Checklist

Este checklist valida el MVP iOS/watchOS de PLAYCE sin tocar archivos fuera de `/Users/nicolasolivares/AGM`.

## Objetivo de QA

Confirmar que la app permite contar un partido desde iPhone o Apple Watch, sincronizar estado en vivo, guardar partidos terminados, consultar historial/detalle, ver estadisticas, exportar CSV, compartir tarjeta y mantener el gate premium sin crashes.

## Verificacion automatica

Ejecutar desde `/Users/nicolasolivares/AGM/tennis_counter_ios`:

```bash
xcodegen generate
xcodebuild test -project Playce.xcodeproj -scheme PlayceSharedTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
xcodebuild -project Playce.xcodeproj -scheme PlayceIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Playce.xcodeproj -scheme PlayceWatchApp -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Resultado esperado:

- Tests compartidos: 34 tests, 0 fallas.
- Build iOS Simulator: `BUILD SUCCEEDED`.
- Build watchOS Simulator: `BUILD SUCCEEDED`.
- `git diff --check`: sin salida.

## Checklist manual iPhone

Prioridad actual: alta. Se puede validar en iPhone fisico o iPhone Simulator.

- [x] Abrir `PlayceIOS` en iPhone Simulator.
- [x] Confirmar que carga el wordmark y la pantalla principal sin textos cortados.
- [x] Configurar nombres de jugadores.
- [x] Cambiar formato entre Standard, Grand Slam y Fast4.
- [x] Sumar puntos para A y B.
- [x] Usar undo para A y B.
- [x] Resetear game y match.
- [x] Iniciar, pausar y reanudar timer.
- [x] Terminar un partido completo.
- [x] Guardar partido terminado.
- [x] Abrir History.
- [x] Abrir detalle de un partido.
- [x] Adjuntar y quitar foto.
- [x] Compartir tarjeta del partido. En simulador se valido preview/share sheet, no un destino externo final.
- [x] Abrir Stats.
- [x] Exportar CSV.
- [x] Verificar que el modo gratis mantiene usable el contador y bloquea features premium.
- [x] En `DEBUG`, usar unlock premium local y repetir History/Stats/Share.

## Checklist manual Apple Watch

Prioridad actual: media-alta. Hoy se valida en Apple Watch Simulator. La validacion final requiere Apple Watch fisico.

- [x] Abrir `PlayceWatchApp` en Apple Watch Simulator.
- [x] Aceptar o rechazar HealthKit sin crash.
- [x] Confirmar que aparece la pantalla principal del contador.
- [x] Sumar puntos para A y B.
- [x] Usar undo para A y B.
- [x] Iniciar, pausar y reanudar timer.
- [x] Resetear game y match.
- [x] Terminar partido desde el Watch.
- [x] Confirmar que la pantalla no se cierra inesperadamente.
- [ ] Confirmar que el estado de sync se muestra de forma entendible para producto final. Para testing esta aprobado; falta quitar copy tecnico tipo `ACK inserted`.

## Checklist manual sync iPhone/Watch

Prioridad actual: alta para simulador, bloqueada para validacion final real hasta tener Apple Watch fisico.

- [x] Abrir iPhone y Apple Watch Simulator emparejados.
- [x] Desde iPhone, configurar nombres/formato.
- [x] Enviar configuracion al Watch.
- [x] Confirmar que el Watch aplica nombres/formato.
- [x] Sumar puntos desde Watch.
- [x] Confirmar que iPhone muestra live score read-only.
- [x] Terminar partido desde Watch.
- [x] Confirmar que iPhone guarda o rechaza segun estado premium.
- [ ] Reintentar con iPhone cerrado o no reachable si el simulador lo permite.
- [x] Confirmar que no se duplican partidos al reenviar el mismo `idempotencyKey`.

## Regresion contra Android

Casos cubiertos por tests Swift:

- Scoring clasico `0, 15, 30, 40, AD`.
- Deuce y ventaja.
- No-ad.
- Tiebreak a 6-6.
- Super tiebreak en set final.
- Fast4.
- Best of three y best of five.
- Replay de puntos.
- Servidor y lado de saque.
- Historial versionado y migracion legacy.
- Idempotencia de guardado.
- Estadisticas y CSV.
- Share card data.
- Premium debug fallback.

## Bugs y decisiones conocidas

- GitHub esta al dia hasta `f409d71 Update MVP QA checklist status`.
- En Android Wear, el undo puede abrirse con long press sobre `+A` o `+B`; en el MVP iOS/watchOS todavia existen botones `Undo A` y `Undo B`. Esto queda como ajuste de paridad UX posterior al MVP.
- No ajustar automaticamente diferencias iOS vs Android: algunas decisiones iOS/watchOS pueden pasar a ser oficiales y luego replicarse en Android, por ejemplo el boton de timer en Apple Watch/Wear OS.
- El segundo reloj espectador de Wear OS no tiene equivalente directo en watchOS estandar iPhone + Apple Watch.
- StoreKit usa producto `premium_unlock`; ya fue creado en App Store Connect como compra no consumible con precio inicial `3.99`.
- HealthKit ya no crashea en simulador porque el target Watch incluye `NSHealthShareUsageDescription` y `NSHealthUpdateUsageDescription`, pero entitlements/firma deben validarse en dispositivo real.
- Sync WatchConnectivity fue validado con iPhone Simulator + Apple Watch Simulator emparejados; la validacion final debe hacerse con iPhone + Apple Watch reales antes de release publico.
- Los controles visibles `Debug: Lock Premium` / `Debug: Unlock Premium` son solo para QA en builds Debug; se verifico que no aparecen en build Release antes de subir a App Store Connect.
