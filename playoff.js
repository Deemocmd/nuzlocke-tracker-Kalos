import { supabase } from './_lib/supabase.js';
import { requireAdmin, requireUserOrAdmin, allowCors } from './_lib/auth.js';
import { coinTransactionToJson } from './_lib/serialize.js';

// POST  { userId, amount, reason? } — SOLO administrador. amount puede ser
//       negativo para quitar monedas. Se guarda en coin_transactions y el
//       saldo del usuario nunca baja de 0.
// GET   ?userId=... — historial de movimientos de ese participante. Un
//       usuario normal solo puede ver el suyo; el administrador puede ver
//       el de cualquiera.
export default async function handler(req, res) {
  if (allowCors(req, res)) return;

  if (req.method === 'POST') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { userId, amount, reason } = req.body || {};
      const delta = Math.round(Number(amount));

      if (!userId || !Number.isFinite(delta) || delta === 0) {
        res.status(400).json({ error: 'Indica un participante y una cantidad de monedas distinta de cero.' });
        return;
      }

      const { data, error } = await supabase.rpc('admin_adjust_coins', {
        p_user_id: userId,
        p_delta: delta,
        p_reason: reason ? String(reason).trim().slice(0, 200) : '',
      });

      if (error) {
        if (error.message?.includes('NOT_FOUND')) {
          res.status(404).json({ error: 'No se encontró al participante.' });
          return;
        }
        throw error;
      }

      res.status(200).json(data); // { userId, coins }
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudieron actualizar las monedas.' });
    }
    return;
  }

  if (req.method === 'GET') {
    const session = requireUserOrAdmin(req, res);
    if (!session) return;

    try {
      const { userId } = req.query;
      if (!userId) {
        res.status(400).json({ error: 'Falta el id del participante.' });
        return;
      }
      if (session.role !== 'admin' && session.userId !== userId) {
        res.status(403).json({ error: 'No puedes ver el historial de monedas de otro participante.' });
        return;
      }

      const { data, error } = await supabase
        .from('coin_transactions')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(30);
      if (error) throw error;

      res.status(200).json(data.map(coinTransactionToJson));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo cargar el historial de monedas.' });
    }
    return;
  }

  res.status(405).json({ error: 'Método no permitido.' });
}
