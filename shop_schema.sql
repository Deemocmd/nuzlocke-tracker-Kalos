// Cliente de Supabase para el NAVEGADOR. A diferencia de api/_lib/supabase.js
// (que usa la Service Role Key y solo corre en las funciones /api), este usa
// la clave "anon" pública, pensada para exponerse al cliente. Con RLS
// activado y solo la política de lectura de route_entries abierta
// (ver supabase/realtime_pokemon.sql), este cliente únicamente puede:
//   - Suscribirse a cambios en tiempo real de route_entries (los Pokémon).
// No puede leer "users" (tiene el hash de contraseña) ni escribir nada: eso
// sigue pasando solo por /api con la Service Role Key.
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  // No tiramos error para no romper el resto de la app si alguien todavía
  // no configuró estas 2 variables: simplemente no habrá tiempo real y todo
  // sigue funcionando como antes (con refrescos manuales).
  console.warn(
    '[supabaseClient] Faltan VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY: ' +
    'los cambios de Pokémon no se verán en tiempo real hasta que las agregues.'
  );
}

export const supabaseClient = url && anonKey ? createClient(url, anonKey) : null;
