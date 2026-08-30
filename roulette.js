import { supabase } from './_lib/supabase.js';
import { requireAdmin, readSession, allowCors } from './_lib/auth.js';
import { shopItemToJson } from './_lib/serialize.js';

// GET    — catálogo. Sin sesión o sesión de jugador: solo objetos activos.
//          Con sesión de admin y ?all=true: también los desactivados (para
//          poder reactivarlos/editarlos desde el panel).
// POST   { itemId, name, category, description, price, stock } — SOLO admin.
// PUT    ?id=... { name?, category?, description?, price?, stock?, active? }
//          — SOLO admin. Editar un objeto existente (p.ej. desactivarlo).
// DELETE ?id=... — SOLO admin. Borra el objeto del catálogo. Si ya tiene
//          compras asociadas, mejor usar PUT { active: false } en vez de
//          borrar, para no perder el historial de purchases.
export default async function handler(req, res) {
  if (allowCors(req, res)) return;

  if (req.method === 'GET') {
    try {
      const session = readSession(req);
      const wantsAll = req.query.all === 'true' && session?.role === 'admin';

      let query = supabase.from('shop_items').select('*').order('category').order('name');
      if (!wantsAll) query = query.eq('active', true);

      const { data, error } = await query;
      if (error) throw error;

      res.status(200).json(data.map(shopItemToJson));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo cargar el catálogo de la tienda.' });
    }
    return;
  }

  if (req.method === 'POST') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { itemId, name, category, description, price, stock } = req.body || {};
      const trimmedName = String(name || '').trim();
      const numericItemId = Number(itemId);
      const numericPrice = Number(price);

      if (!trimmedName || !Number.isFinite(numericItemId) || !Number.isFinite(numericPrice) || numericPrice <= 0) {
        res.status(400).json({ error: 'Indica al menos nombre, item_id del juego y un precio válido (> 0).' });
        return;
      }

      const { data, error } = await supabase
        .from('shop_items')
        .insert({
          item_id: numericItemId,
          name: trimmedName,
          category: category ? String(category) : 'competitivo',
          description: description ? String(description) : '',
          price: Math.round(numericPrice),
          stock: stock === '' || stock === undefined || stock === null ? null : Math.max(0, Math.round(Number(stock))),
        })
        .select('*')
        .single();

      if (error) {
        if (error.code === '23505') {
          res.status(409).json({ error: 'Ya existe un objeto con ese nombre en la tienda.' });
          return;
        }
        throw error;
      }

      res.status(201).json(shopItemToJson(data));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo crear el objeto.' });
    }
    return;
  }

  if (req.method === 'PUT') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { id } = req.query;
      if (!id) {
        res.status(400).json({ error: 'Falta el id del objeto.' });
        return;
      }

      const { name, category, description, price, stock, active } = req.body || {};
      const patch = {};
      if (name !== undefined) patch.name = String(name).trim();
      if (category !== undefined) patch.category = String(category);
      if (description !== undefined) patch.description = String(description);
      if (price !== undefined) {
        const numericPrice = Number(price);
        if (!Number.isFinite(numericPrice) || numericPrice <= 0) {
          res.status(400).json({ error: 'El precio debe ser un número mayor a 0.' });
          return;
        }
        patch.price = Math.round(numericPrice);
      }
      if (stock !== undefined) {
        patch.stock = stock === '' || stock === null ? null : Math.max(0, Math.round(Number(stock)));
      }
      if (active !== undefined) patch.active = Boolean(active);

      if (Object.keys(patch).length === 0) {
        res.status(400).json({ error: 'No hay cambios que guardar.' });
        return;
      }

      const { data, error } = await supabase
        .from('shop_items').update(patch).eq('id', id).select('*').single();
      if (error) throw error;
      if (!data) {
        res.status(404).json({ error: 'No se encontró el objeto.' });
        return;
      }

      res.status(200).json(shopItemToJson(data));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo actualizar el objeto.' });
    }
    return;
  }

  if (req.method === 'DELETE') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { id } = req.query;
      if (!id) {
        res.status(400).json({ error: 'Falta el id del objeto.' });
        return;
      }
      const { error } = await supabase.from('shop_items').delete().eq('id', id);
      if (error) throw error;
      res.status(200).json({ ok: true });
    } catch (err) {
      console.error(err);
      // La causa más probable es una foreign key: ya hay compras que
      // apuntan a este objeto. En ese caso conviene desactivarlo (PUT
      // { active: false }) en vez de borrarlo.
      res.status(500).json({ error: 'No se pudo borrar el objeto (¿ya tiene compras asociadas? prueba desactivarlo en vez de borrarlo).' });
    }
    return;
  }

  res.status(405).json({ error: 'Método no permitido.' });
}
