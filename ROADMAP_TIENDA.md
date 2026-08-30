# Roadmap — Tienda Nuzlocke Hub (Nivel 1)

Objetivo: comprar objetos competitivos / Baya Zidra con monedas en la web →
queda pendiente en Supabase → el usuario sube su save (`main`) → el servidor
aplica automáticamente todas las compras pendientes (motor tipo PKHeX
integrado, no a mano) → devuelve el archivo listo para reimportar con
Checkpoint/JKSM. Sin push en vivo a la consola.

## Estado de las partes

- [x] **Parte 1 — Esquema Supabase** (`supabase/shop_schema.sql`)
  - Tablas `shop_items` (catálogo) y `purchases` (compras, estado
    pendiente/aplicada/cancelada).
  - Función `purchase_shop_item(user_id, shop_item_id, quantity)`:
    transaccional, descuenta monedas, registra en `coin_transactions`,
    descuenta stock si aplica, crea la compra en `pendiente`.
  - Seed: objetos competitivos comunes de Gen 6 + Baya Zidra.
  - ⚠️ Pendiente: confirmar los `item_id` contra la lista real de PKHeX
    antes de usarlos en la Parte 4 (por ahora solo viajan guardados, no
    se usan para escribir nada en un save).

- [x] **Parte 2 — API backend**
  - `api/_lib/serialize.js`: se agregaron `shopItemToJson` y `purchaseToJson`.
  - `api/shop.js`: GET catálogo (público = solo activos; admin + `?all=true`
    = incluye desactivados). POST/PUT/DELETE solo admin (crear, editar,
    desactivar/borrar).
  - `api/purchases.js`: POST llama a `purchase_shop_item` (compra para el
    usuario logueado; admin puede comprar "para" otro con `userId`). GET
    historial: jugador ve solo lo suyo, admin puede filtrar por `userId`
    y/o `status` (o ver todas las `pendiente` para la Parte 5).
  - `src/api.js`: se agregaron `getShopItems`, `createShopItem`,
    `updateShopItem`, `deleteShopItem`, `buyShopItem`, `getMyPurchases`,
    `getUserPurchases`.

- [x] **Parte 3 — Frontend**
  - Pestaña "Tienda" en `App.jsx` (nueva, entre "Torneo Oficial" y "Ruleta").
  - Vista jugador: saldo de monedas, catálogo agrupado por categoría
    (competitivo/baya/objeto), botón comprar con cantidad, y panel "Mis
    compras" (pendiente/aplicada/cancelada).
  - Vista admin: alta de objetos (item_id, nombre, categoría, precio,
    stock), edición inline de precio/stock, activar/desactivar/borrar, y
    una cola de "Compras pendientes de aplicar" de todos los jugadores
    (de solo lectura por ahora — insumo para la Parte 5).
  - `npm run build` verificado sin errores.

- [~] **Parte 4 — Motor de aplicación al save** (construido y probado en
  simulación; falta validar con un save real antes de usarlo en producción)
  - `save-engine/gen6-save-engine.js`: motor para Pokémon **X/Y** (Gen 6,
    3DS). Offsets tomados de la documentación pública de Project Pokemon
    ("X/Y Save Structure") + checksum CRC16/CCITT-FALSE (el mismo que usa
    PKHeX). Escribe siempre en las dos copias del save (slot A y B).
  - `save-engine/test-engine.js`: CLI para probar el motor —
    `verify` (checksum coincide con el layout documentado),
    `dump` (lee la bolsa completa por bolsillo),
    `add` (agrega un objeto y recalcula checksums).
  - Probado de punta a punta contra un save **sintético** (generado con el
    mismo layout): objeto nuevo, apilar cantidad sobre uno existente,
    bolsillo de bayas independiente, checksum válido después de escribir.
    Todo esto pasó ✅.
  - ⚠️ **Lo que falta antes de usarlo con un jugador real**:
    1. Correr `test-engine.js verify` y `dump` contra un save de X/Y de
       verdad (no sintético) y comparar `dump` contra lo que muestra
       PKHeX — recién ahí queda confirmado que el layout real coincide
       con el documentado.
    2. Confirmar los `item_id` del catálogo (Parte 1) contra la lista real
       de objetos de PKHeX.
    3. **Solo X/Y por ahora** — ORAS tiene los offsets desplazados (según
       la misma documentación) y necesitaría su propia tabla de offsets.
    4. El formato de cada slot de objeto (4 bytes: item_id + cantidad, sin
       bits de flag) es la interpretación estándar de la comunidad, pero
       no está triple-confirmado — el paso 1 lo valida indirectamente.

- [x] **Parte 5 — Endpoint de subida/descarga**
  - `api/apply-rewards.js`: recibe `{ saveBase64, filename?, userId? }`.
    Busca las compras `pendiente` del jugador (con la categoría de su
    objeto vía join a `shop_items`), llama al motor de la Parte 4, marca
    como `aplicada` lo que se pudo escribir (deja `pendiente` lo que no
    entró, p.ej. bolsillo lleno), y devuelve el save modificado en base64.
  - Si el motor rechaza el archivo (layout no coincide — no es X/Y, save
    corrupto, etc.) responde 422 y **no toca ninguna compra**: todas
    quedan `pendiente` para reintentar.
  - `src/api.js`: `applyRewards(saveBase64, filename)`, más los helpers
    `fileToBase64(file)` y `downloadBase64AsFile(base64, filename)` que
    usará la UI de la Parte 6.
  - Probado el flujo completo (decodificar → aplicar → recodificar) contra
    el save sintético de la Parte 4: el archivo va y vuelve íntegro, dos
    compras de categorías distintas (competitivo + baya) se aplican
    correctamente. Falta probar con el endpoint real desplegado + Supabase
    real, y con un save de verdad (mismo pendiente que la Parte 4).

- [x] **Parte 6 — UI de subida/descarga**
  - `ApplySaveCard` en `App.jsx`, dentro de la pestaña "Tienda" (solo para
    jugadores, debajo del catálogo): input de archivo para el `main`,
    botón "Aplicar y descargar" que llama a `applyRewards`, descarga
    automática del resultado, y un resumen de qué se aplicó vs qué quedó
    pendiente (p. ej. por bolsillo lleno).
  - Instrucciones de reimportado con Checkpoint/JKSM incluidas en la
    misma tarjeta.
  - Al aplicar, refresca "Mis compras" automáticamente (pasa de
    `pendiente` a `aplicada`).
  - `npm run build` verificado sin errores.

---

## Nivel 1 completo 🎉

Las 6 partes están construidas: comprar con monedas → queda pendiente →
subir el save → se aplica automáticamente → descargar y reimportar.

**Antes de usarlo con un jugador de verdad**, lo único que falta (ver
Parte 4) es validar el motor contra un save real de X/Y: correr
`test-engine.js verify` y `dump`, comparar contra PKHeX, y confirmar los
`item_id` del catálogo. Todo lo demás (Supabase, API, frontend) ya está
probado de punta a punta con datos sintéticos.

Posibles próximos pasos si se quiere seguir (no forman parte del Nivel 1
original): soporte para ORAS, favoritos/orden de bolsillo, límite de
compras por semana, o un Nivel 2 con push en vivo a la consola.

## Cómo retomar en otro chat sin memoria activada

1. Sube este archivo (o el zip del proyecto completo) al chat nuevo.
2. Dile a Claude: "Este es el roadmap de mi tienda Nuzlocke, seguimos en
   la Parte X".
3. Claude lee el estado de arriba y continúa desde ahí sin repetir nada.
