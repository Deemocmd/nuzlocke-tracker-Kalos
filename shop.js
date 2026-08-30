import { supabase } from './_lib/supabase.js';
import { requireUserOrAdmin, allowCors } from './_lib/auth.js';
import { purchaseToJson } from './_lib/serialize.js';
import { applyPurchases } from '../save-engine/gen6-save-engine.js';

// POST { saveBase64, filename?, userId? }
// - saveBase64: el archivo "main" completo, codificado en base64.
// - filename: opcional, solo para guardar referencia en purchases.applied_save_filename.
// - userId: SOLO admin. Permite aplicar las compras de OTRO jugador (por si
//   sube el save por él). Un jugador normal siempre aplica sobre sí mismo.
//
// Flujo:
//   1. Busca las compras 'pendiente' del jugador (con la categoría del
//      objeto, para saber a qué bolsillo va cada una).
//   2. Si no hay ninguna, responde sin tocar el archivo.
//   3. Llama al motor (Parte 4). Si el save no pasa la verificación de
//      layout, NO se marca nada como aplicado — se corta ahí, para no
//      dejar a un jugador con compras "perdidas" por un save que no pudo
//      procesarse.
//   4. Lo que sí se pudo escribir se marca 'aplicada' en Supabase. Lo que
//      no entró (p.ej. bolsillo lleno) queda 'pendiente' para la próxima.
//   5. Devuelve el archivo modificado en base64 para que el jugador lo
//      baje y lo reimporte con Checkpoint/JKSM.
export default async function handler(req, res) {
  if (allowCors(req, res)) return;

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Método no permitido.' });
    return;
  }

  const session = requireUserOrAdmin(req, res);
  if (!session) return;

  try {
    const { saveBase64, filename, userId } = req.body || {};

    if (!saveBase64 || typeof saveBase64 !== 'string') {
      res.status(400).json({ error: 'Falta el archivo del save (saveBase64).' });
      return;
    }

    const targetUserId = session.role === 'admin' && userId ? userId : session.userId;
    if (!targetUserId) {
      res.status(400).json({ error: 'No se pudo determinar el jugador.' });
      return;
    }

    let inputBuffer;
    try {
      inputBuffer = Buffer.from(saveBase64, 'base64');
    } catch {
      res.status(400).json({ error: 'El archivo recibido no es un base64 válido.' });
      return;
    }

    // Trae las compras pendientes con la categoría de su objeto (para saber
    // el bolsillo). El join funciona porque purchases.shop_item_id
    // referencia shop_items(id).
    const { data: pending, error: fetchError } = await supabase
      .from('purchases')
      .select('*, shop_items(category)')
      .eq('user_id', targetUserId)
      .eq('status', 'pendiente')
      .order('created_at', { ascending: true });

    if (fetchError) throw fetchError;

    if (!pending || pending.length === 0) {
      res.status(200).json({ applied: [], failed: [], message: 'No hay compras pendientes para este jugador.' });
      return;
    }

    const purchasesForEngine = pending.map((p) => ({
      purchaseId: p.id,
      itemId: p.item_id,
      quantity: p.quantity,
      category: p.shop_items?.category || 'objeto',
      name: p.item_name,
    }));

    let engineResult;
    try {
      engineResult = applyPurchases(inputBuffer, purchasesForEngine);
    } catch (engineError) {
      // El motor rechazó el archivo (tamaño raro, checksum no coincide,
      // etc.) — no se toca ninguna compra, todas siguen 'pendiente'.
      console.error('Motor de save rechazó el archivo:', engineError);
      res.status(422).json({
        error:
          'No se pudo procesar este archivo de save. Verifica que sea el "main" exportado con Checkpoint/JKSM de una partida de Pokémon X/Y. ' +
          (engineError?.message || ''),
      });
      return;
    }

    const appliedIds = engineResult.applied.map((a) => a.purchaseId);
    const failedIds = engineResult.failed.map((f) => f.purchaseId);

    if (appliedIds.length > 0) {
      const { error: updateError } = await supabase
        .from('purchases')
        .update({
          status: 'aplicada',
          applied_at: new Date().toISOString(),
          applied_save_filename: filename || null,
        })
        .in('id', appliedIds);
      if (updateError) throw updateError;
    }

    let updatedRows = [];
    if (appliedIds.length > 0 || failedIds.length > 0) {
      const { data, error } = await supabase
        .from('purchases')
        .select('*')
        .in('id', [...appliedIds, ...failedIds]);
      if (error) throw error;
      updatedRows = data;
    }

    res.status(200).json({
      saveBase64: engineResult.buffer.toString('base64'),
      applied: updatedRows.filter((r) => appliedIds.includes(r.id)).map(purchaseToJson),
      failed: engineResult.failed.map((f) => ({
        purchaseId: f.purchaseId,
        itemName: f.name,
        reason: f.reason, // p.ej. 'POUCH_FULL'
      })),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'No se pudieron aplicar las recompensas al save.' });
  }
}
