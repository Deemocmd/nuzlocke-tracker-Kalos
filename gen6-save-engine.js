import { supabase } from './_lib/supabase.js';
import { requireAdmin, allowCors } from './_lib/auth.js';

// La ruleta se guarda como una única fila ("main"), igual que el bracket
// suizo y los playoffs. Cualquiera puede VER los segmentos/historial;
// solo el admin puede configurar segmentos/animación o registrar una
// tirada (coincide con que la pestaña "Ruleta" hoy solo la ve el admin).
const DOC_ID = 'main';
const MAX_HISTORY = 100; // evita que el historial crezca sin límite

function toJson(row) {
  return {
    segments: row.segments || [],
    history: row.history || [],
    animated: row.animated ?? true,
  };
}

export default async function handler(req, res) {
  if (allowCors(req, res)) return;

  if (req.method === 'GET') {
    try {
      const { data, error } = await supabase.from('roulette').select('*').eq('id', DOC_ID).single();
      if (error) throw error;
      res.status(200).json(toJson(data));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo cargar la ruleta.' });
    }
    return;
  }

  // PUT: reemplaza la configuración (segmentos y/o si la animación está
  // activada). El historial NO se toca acá.
  if (req.method === 'PUT') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { segments, animated } = req.body || {};
      const patch = {};
      if (segments !== undefined) {
        if (!Array.isArray(segments)) {
          res.status(400).json({ error: 'segments debe ser un array.' });
          return;
        }
        patch.segments = segments;
      }
      if (animated !== undefined) patch.animated = Boolean(animated);

      if (Object.keys(patch).length === 0) {
        res.status(400).json({ error: 'No hay cambios que guardar.' });
        return;
      }

      const { data, error } = await supabase.from('roulette').update(patch).eq('id', DOC_ID).select('*').single();
      if (error) throw error;
      res.status(200).json(toJson(data));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo guardar la configuración de la ruleta.' });
    }
    return;
  }

  // POST: agrega un resultado de tirada al historial (lo hace el admin al
  // girar la ruleta). Se guarda arriba de todo y se recorta a MAX_HISTORY.
  if (req.method === 'POST') {
    const session = requireAdmin(req, res);
    if (!session) return;

    try {
      const { label, type, time } = req.body || {};
      if (!label) {
        res.status(400).json({ error: 'Falta el resultado de la tirada.' });
        return;
      }

      const { data: current, error: readError } = await supabase
        .from('roulette').select('history').eq('id', DOC_ID).single();
      if (readError) throw readError;

      const entry = { label, type: type || 'neutro', time: time || new Date().toLocaleTimeString() };
      const nextHistory = [entry, ...(current.history || [])].slice(0, MAX_HISTORY);

      const { data, error } = await supabase
        .from('roulette').update({ history: nextHistory }).eq('id', DOC_ID).select('*').single();
      if (error) throw error;
      res.status(201).json(toJson(data));
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'No se pudo registrar la tirada.' });
    }
    return;
  }

  res.status(405).json({ error: 'Método no permitido.' });
}
