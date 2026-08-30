import { supabase } from './_lib/supabase.js';
import { requireUserOrAdmin, allowCors } from './_lib/auth.js';
import { purchaseToJson } from './_lib/serialize.js';

// POST { shopItemId, quantity? } — el usuario logueado compra para sí mismo.
//      Llama a purchase_shop_item(), que descuenta monedas y crea la fila
//      en estado 'pendiente'. Un admin puede comprar "para" otro usuario
//      pasando también userId (útil para regalar algo puntual).
// GET  ?userId=...&status=pendiente — historial de compras. Un jugador solo
//      puede ver las suyas; el admin puede ver las de cualquiera, o de
//      todos si no manda userId (así arma el lote a aplicar en la Parte 5).
export default async function handler(req, res) {
  if (allowCors(req, res)) return;

  if (req.method === 'POST') {
    const session = requireUserOrAdmin(req, res);
    if (!session) return;

    try {
      const { shopItemId, quantity, userId } = req.body || {};
      const qty = quantity === undefined || quantity === null || quantity === '' ? 1 : Math.round(Number(quantity));

      if (!shopItemId || !Number.isFinite(qty) || qty < 1) {
        res.status(400).json({ error: 'Indica el objeto a comprar y una cantidad válida.' });
        return;
      }

      // Un jugador solo compra para sí mismo; solo el admin puede indicar
      // un userId distinto (p.ej. para regalar monedas ya gastadas en algo).
      const targetUserId = session.role === 'admin' && userId ? userId : session.userId;
      if (!targetUserId) {
        res.status(400).json({ error: 'No se pudo determinar el participante que compra.' });
        return;
      }

      const { data, error } = await supabase.rpc('purchase_shop_item', {
        p_user_id: targetUserId,
        p_shop_item_id: shopItemId,
        p_quantity: qty,
      });

      if (error) {
        const map = {
          USER_NOT_FOUND: [404, 'No se encontró al participante.'],
          ITEM_NOT_FOUND: [404, 'No se encontró el objeto en la tienda.'],
          ITEM_INACTIVE: [409, 'Ese objeto ya no está disponible en la tienda.'],
          OUT_OF_STOCK: [409, 'No queda stock suficiente de ese objeto.'],
          INSUFFICIENT_COINS: [402, 'No tienes monedas suficientes para esta compra.'],
          INVALID_QUANTITY: [400, 'Cantidad inválida.'],
        };
        const hit = Object.keys(map).find((code) => error.message?.includes(code));
        if (hit) {
          const [status, msg] = map[hit];
          res.status(status).json({ error: msg });
          return;
        }
        throw error;
      }

      res.status(201).json(data); // { purchaseId, coins }
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo completar la compra.' });
    }
    return;
  }

  if (req.method === 'GET') {
    const session = requireUserOrAdmin(req, res);
    if (!session) return;

    try {
      const { userId, status } = req.query;

      if (session.role !== 'admin' && userId && userId !== session.userId) {
        res.status(403).json({ error: 'No puedes ver las compras de otro participante.' });
        return;
      }

      let query = supabase.from('purchases').select('*').order('created_at', { ascending: false });

      // Un jugador normal siempre queda acotado a lo suyo, sin importar
      // qué mande en la query; el admin puede filtrar por userId o ver todo.
      const effectiveUserId = session.role === 'admin' ? userId : session.userId;
      if (effectiveUserId) query = query.eq('user_id', effectiveUserId);
      if (status) query = query.eq('status', status);

      const { data, error } = await query;
      if (error) throw error;

      res.status(200).json(data.map(purchaseToJson));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo cargar el historial de compras.' });
    }
    return;
  }

  res.status(405).json({ error: 'Método no permitido.' });
}
