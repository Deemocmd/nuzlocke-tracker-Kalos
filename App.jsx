#!/usr/bin/env node
// -----------------------------------------------------------------------
// Herramienta de verificación MANUAL. Úsala con un save de X/Y de PRUEBA
// (no el save real de un jugador) para confirmar que el motor lee/escribe
// bien antes de conectarlo a la Parte 5 (el endpoint de subida/descarga).
//
// Uso:
//   node test-engine.js verify ruta/al/main
//   node test-engine.js dump   ruta/al/main
//   node test-engine.js add    ruta/al/main <itemId> <cantidad> <bolsillo> salida.bin
//     bolsillo: items | berries | keyItems | tms | medicine
// -----------------------------------------------------------------------

import fs from 'fs';
import * as engine from './gen6-save-engine.js';

const [, , cmd, path, ...rest] = process.argv;

if (!cmd || !path) {
  console.log('Uso: node test-engine.js <verify|dump|add> ruta/al/main [...]');
  process.exit(1);
}

const buffer = fs.readFileSync(path);

if (cmd === 'verify') {
  const result = engine.verifyLayout(buffer, { slot: 0 });
  if (result.ok) {
    console.log('✅ El layout documentado coincide con este save (slot A). Se puede pasar al siguiente paso (dump).');
  } else {
    console.log('❌ No coincide — NO uses este motor con este archivo todavía:');
    result.issues.forEach((i) => console.log('  -', i));
  }
  process.exit(result.ok ? 0 : 1);
}

if (cmd === 'dump') {
  const bag = engine.dumpBag(buffer, { slot: 0 });
  for (const [pouch, items] of Object.entries(bag)) {
    console.log(`\n${pouch} (${items.length} objetos distintos):`);
    items.forEach((it) => console.log(`  item_id ${it.itemId} x${it.quantity}`));
  }
  console.log('\nCompara esta lista contra lo que muestra PKHeX abriendo el mismo archivo. Si no coincide, no sigas.');
  process.exit(0);
}

if (cmd === 'add') {
  const [itemId, qty, pouch, outPath] = rest;
  if (!itemId || !qty || !pouch || !outPath) {
    console.log('Uso: node test-engine.js add ruta/al/main <itemId> <cantidad> <bolsillo> salida.bin');
    process.exit(1);
  }
  const category = pouch === 'berries' ? 'baya' : 'competitivo';
  const { buffer: out, applied, failed } = engine.applyPurchases(buffer, [
    { itemId: Number(itemId), quantity: Number(qty), category, name: `item_id ${itemId}` },
  ]);
  fs.writeFileSync(outPath, out);
  console.log('Aplicado:', applied);
  console.log('Falló:', failed);
  console.log(`\nGuardado en ${outPath}.`);
  console.log('Siguiente paso: ábrelo en PKHeX (en la PC, NO en tu consola todavía) y confirma con');
  console.log('"Verify Checksums" que no marca error, y que el objeto aparece en la bolsa correcta.');
  process.exit(0);
}

console.log('Comando desconocido:', cmd);
process.exit(1);
