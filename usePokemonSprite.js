/**
 * Motor de lectura/escritura del save "main" de Pokémon X/Y (Gen 6, 3DS).
 *
 * ⚠️ LÉELO ANTES DE USAR ESTO CON UN SAVE REAL ⚠️
 * ---------------------------------------------------------------------------
 * Los offsets de abajo salen de la documentación pública de Project Pokemon
 * ("X/Y Save Structure") y del algoritmo de checksum que usa PKHeX (CRC16
 * CCITT-FALSE, el mismo desde Gen 4). Son válidos para Pokémon X/Y — NO son
 * válidos para ORAS (la estructura está desplazada, según la misma
 * documentación) ni para otra generación.
 *
 * Antes de conectar esto a la Parte 5 (el endpoint que recibe saves de
 * jugadores reales):
 *   1. Consigue un save de X/Y de prueba (uno tuyo, no el de un jugador).
 *   2. `node test-engine.js verify ruta/al/main` — tiene que decir ✅.
 *      Si dice ❌, el layout no coincide con este archivo y NO hay que
 *      seguir (puede ser ORAS, un save corrupto, o un formato distinto al
 *      que exporta Checkpoint/JKSM).
 *   3. `node test-engine.js dump ruta/al/main` — compara lo que imprime
 *      contra lo que muestra PKHeX abriendo el mismo archivo. Tiene que
 *      coincidir objeto por objeto.
 *   4. `node test-engine.js add ruta/al/main <itemId> <qty> items salida.bin`
 *      — abre salida.bin en PKHeX (en la PC, NO en la consola todavía) y
 *      confirma con "Verify Checksums" que no marca error y que el objeto
 *      aparece en la bolsa.
 *   5. Recién ahí, probar en una consola/emulador de prueba antes de
 *      tocar el save de un jugador real.
 *
 * Este motor nunca debe usarse "a ciegas" en producción sin ese chequeo.
 * ---------------------------------------------------------------------------
 */

// -----------------------------------------------------------------------
// CRC16/CCITT-FALSE — el algoritmo que usa PKHeX para todos los checksums
// de bloque en saves de Gen 4 en adelante (init 0xFFFF, polinomio 0x1021).
// -----------------------------------------------------------------------
function crc16ccitt(buffer, start, length) {
  let crc = 0xffff;
  const end = start + length;
  for (let i = start; i < end; i++) {
    crc ^= buffer[i] << 8;
    for (let b = 0; b < 8; b++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc & 0xffff;
}

// -----------------------------------------------------------------------
// Layout de Pokémon X/Y. El save físico son 0x100000 bytes (1 MB) con DOS
// copias completas del juego (slot A en 0x00000, slot B en 0x7F000) que
// se alternan como respaldo cada vez que guardas. Para no dejar el save
// en un estado raro, este motor escribe SIEMPRE en las dos copias.
//
// Fuente: https://projectpokemon.org/home/docs/gen-6/xy-save-structure-r82/
// -----------------------------------------------------------------------
const SAVE_SIZE = 0x100000;
const SLOT_OFFSETS = [0x00000, 0x7f000];

// Bloque 0001 = "Bolsa" completa (todos los bolsillos juntos).
const BAG_BLOCK = { id: 0x0001, start: 0x05800, length: 0x00000b88 };

// Bolsillos dentro del bloque de la Bolsa. En X/Y los objetos con efecto en
// combate (Restos, Cinta Elegida, etc.) viven en "items" junto con los
// objetos normales — todavía no existe un bolsillo separado de "objetos de
// batalla" (eso llegó en Gen 7). Las bayas tienen su propio bolsillo.
const POUCHES = {
  items: { start: 0x05800, end: 0x05e40 }, // objetos "competitivo"/"objeto"
  keyItems: { start: 0x05e40, end: 0x05fc0 },
  tms: { start: 0x05fc0, end: 0x06168 },
  medicine: { start: 0x06168, end: 0x06268 },
  berries: { start: 0x06268, end: 0x06388 }, // Baya Zidra y demás bayas
};

// Tabla de checksums al final de cada copia del save: cabecera de 0x14
// bytes (timestamps + marca "BEEF"), seguida de entradas de 8 bytes
// (u32 longitud, u16 ID de bloque, u16 checksum CRC16).
const FOOTER = { start: 0x6a800, length: 0x800, headerLength: 0x14, entrySize: 8 };

const ITEM_SLOT_SIZE = 4; // u16 itemId + u16 cantidad, sin bits de flag
const MAX_STACK = 999;

function categoryToPouch(category) {
  return category === 'baya' ? 'berries' : 'items';
}

// -----------------------------------------------------------------------
// Helpers de lectura/escritura little-endian
// -----------------------------------------------------------------------
function readU16LE(buf, off) {
  return buf[off] | (buf[off + 1] << 8);
}
function writeU16LE(buf, off, val) {
  buf[off] = val & 0xff;
  buf[off + 1] = (val >> 8) & 0xff;
}

// -----------------------------------------------------------------------
// Lectura de la bolsa (solo para inspección/depuración, no muta nada)
// -----------------------------------------------------------------------
function dumpPouch(buffer, slotBase, pouchName) {
  const pouch = POUCHES[pouchName];
  if (!pouch) throw new Error(`Bolsillo desconocido: ${pouchName}`);
  const start = slotBase + pouch.start;
  const end = slotBase + pouch.end;
  const items = [];
  for (let off = start; off + ITEM_SLOT_SIZE <= end; off += ITEM_SLOT_SIZE) {
    const itemId = readU16LE(buffer, off);
    if (itemId === 0) continue;
    const quantity = readU16LE(buffer, off + 2);
    items.push({ itemId, quantity, offset: off });
  }
  return items;
}

function dumpBag(buffer, { slot = 0 } = {}) {
  const slotBase = SLOT_OFFSETS[slot];
  const result = {};
  for (const name of Object.keys(POUCHES)) result[name] = dumpPouch(buffer, slotBase, name);
  return result;
}

// -----------------------------------------------------------------------
// Verificación: si el checksum guardado del bloque de la Bolsa no coincide
// con el que calculamos, el layout documentado NO aplica a este archivo
// (p.ej. es un save de ORAS, o no es un save de X/Y) — no hay que escribir.
// -----------------------------------------------------------------------
function findFooterEntry(buffer, slotBase, blockId) {
  const footerStart = slotBase + FOOTER.start + FOOTER.headerLength;
  const footerEnd = slotBase + FOOTER.start + FOOTER.length;
  for (let off = footerStart; off + FOOTER.entrySize <= footerEnd; off += FOOTER.entrySize) {
    const len = buffer.readUInt32LE(off);
    const id = readU16LE(buffer, off + 4);
    if (len === 0 && id === 0) break; // fin de la tabla
    if (id === blockId) return { offset: off, len, checksumOffset: off + 6 };
  }
  return null;
}

function verifyLayout(buffer, { slot = 0 } = {}) {
  const issues = [];
  if (buffer.length !== SAVE_SIZE) {
    issues.push(`Tamaño inesperado: ${buffer.length} bytes (se esperaban ${SAVE_SIZE}). ¿Es un save de X/Y exportado con Checkpoint/JKSM?`);
    return { ok: false, issues };
  }

  const slotBase = SLOT_OFFSETS[slot];
  const entry = findFooterEntry(buffer, slotBase, BAG_BLOCK.id);
  if (!entry) {
    issues.push(`No se encontró la entrada de checksum del bloque de la Bolsa en la tabla del footer (slot ${slot}).`);
    return { ok: false, issues };
  }

  const expected = readU16LE(buffer, entry.checksumOffset);
  const actual = crc16ccitt(buffer, slotBase + BAG_BLOCK.start, BAG_BLOCK.length);
  if (expected !== actual) {
    issues.push(
      `Checksum de la Bolsa no coincide en el slot ${slot} (guardado 0x${expected.toString(16)}, calculado 0x${actual.toString(16)}). El layout documentado no aplica a este archivo — no seguir.`
    );
  }

  return { ok: issues.length === 0, issues };
}

// -----------------------------------------------------------------------
// Escritura
// -----------------------------------------------------------------------
function addItemToSlot(buffer, slotIndex, pouchName, itemId, quantity) {
  const slotBase = SLOT_OFFSETS[slotIndex];
  const pouch = POUCHES[pouchName];
  const start = slotBase + pouch.start;
  const end = slotBase + pouch.end;

  let targetOffset = null;
  let emptyOffset = null;
  for (let off = start; off + ITEM_SLOT_SIZE <= end; off += ITEM_SLOT_SIZE) {
    const currentId = readU16LE(buffer, off);
    if (currentId === itemId) {
      targetOffset = off;
      break;
    }
    if (currentId === 0 && emptyOffset === null) emptyOffset = off;
  }

  if (targetOffset !== null) {
    const currentQty = readU16LE(buffer, targetOffset + 2);
    const newQty = Math.min(MAX_STACK, currentQty + quantity);
    writeU16LE(buffer, targetOffset + 2, newQty);
    return { ok: true, added: newQty - currentQty };
  }

  if (emptyOffset !== null) {
    writeU16LE(buffer, emptyOffset, itemId);
    writeU16LE(buffer, emptyOffset + 2, Math.min(MAX_STACK, quantity));
    return { ok: true, added: Math.min(MAX_STACK, quantity) };
  }

  return { ok: false, reason: 'POUCH_FULL' };
}

function fixChecksum(buffer, slotIndex) {
  const slotBase = SLOT_OFFSETS[slotIndex];
  const entry = findFooterEntry(buffer, slotBase, BAG_BLOCK.id);
  if (!entry) throw new Error('No se encontró la entrada de checksum de la Bolsa; no se puede guardar de forma segura.');
  const checksum = crc16ccitt(buffer, slotBase + BAG_BLOCK.start, BAG_BLOCK.length);
  writeU16LE(buffer, entry.checksumOffset, checksum);
}

/**
 * Aplica una lista de compras pendientes { itemId, category, quantity, name }
 * a un save de X/Y. NO muta el buffer de entrada — siempre trabaja sobre una
 * copia y la devuelve. Escribe en las dos copias del save (slot A y B) y
 * recalcula el checksum de la Bolsa en ambas.
 *
 * Lanza un error (sin escribir nada) si el save no pasa verifyLayout() en
 * cualquiera de los dos slots — mejor fallar fuerte que corromper un save.
 */
function applyPurchases(originalBuffer, purchases) {
  const buffer = Buffer.from(originalBuffer);
  const applied = [];
  const failed = [];

  for (const slotIndex of [0, 1]) {
    const check = verifyLayout(buffer, { slot: slotIndex });
    if (!check.ok) {
      throw new Error(`El save no pasó la verificación de layout (slot ${slotIndex}): ${check.issues.join(' ')}`);
    }
  }

  for (const purchase of purchases) {
    const pouchName = categoryToPouch(purchase.category);
    let ok = true;
    let reason = null;
    for (const slotIndex of [0, 1]) {
      const result = addItemToSlot(buffer, slotIndex, pouchName, purchase.itemId, purchase.quantity);
      if (!result.ok) {
        ok = false;
        reason = result.reason;
        break;
      }
    }
    if (ok) applied.push(purchase);
    else failed.push({ ...purchase, reason });
  }

  for (const slotIndex of [0, 1]) fixChecksum(buffer, slotIndex);

  return { buffer, applied, failed };
}

export {
  crc16ccitt,
  dumpBag,
  verifyLayout,
  applyPurchases,
  categoryToPouch,
  SAVE_SIZE,
  POUCHES,
};
