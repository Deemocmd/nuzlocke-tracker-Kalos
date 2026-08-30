// Constantes compartidas entre el frontend (src/App.jsx) y las funciones
// serverless (api/*). Vivir en un solo sitio evita que la ficha Nuzlocke que
// se crea en el backend y la que se pinta en pantalla se desincronicen.

export const KALOS_LOCATIONS = [
  // Tramo inicial y medallas 1-2
  'Pueblo Boceto', 'Ruta 2 (Vía Avance)', 'Bosque de Novarte', 'Ruta 3 (Senda Abierta)',
  'Ruta 22 (Vía Desvío)', 'Ruta 4 (Vía Parterre)', 'Ciudad Luminalia', 'Ruta 5 (Vía Versalles)',
  'Ruta 6 (Camino del Palacio)', 'Palacio Cénit', 'Ruta 7 (Paseo de los Ríos)',
  'Gruta Tierraunida', 'Ruta 8 (Muralla de la Costa)', 'Pueblo Petroglifo',
  'Ruta 9 (Paso de los Pinchos)', 'Cueva Brillante', 'Ciudad Relieve',
  // Tramo intermedio y medallas 3-5
  'Ruta 10 (Senda Menhir)', 'Ruta 11 (Senda Espejo)', 'Cueva Reflejos', 'Ciudad Yantra',
  'Torre Maestra', 'Ruta 12 (Vía Forraje)', 'Ciudad Témpera', 'Ruta 13 (Páramo de Luminalia)',
  'Ruta 14 (Senda Romántica)', 'Ciudad Romantis',
  // Tramo final y medallas 6-8
  'Ruta 15 (Senda Hoja Caduca)', 'Hotel Desolación', 'Ruta 16 (Senda Melancolía)',
  'Ruta 17 (Vía Mamoswine)', 'Caverna Helada', 'Ruta 18 (Senda del Valle)', 'Cueva Desenlace',
  'Pueblo Mosaico', 'Ruta 19 (Senda Gran Valle)', 'Ruta 20 (Bosque de los Errabundos)',
  'Villa Pokémon', 'Ruta 21 (Última Senda)', 'Calle Victoria',
  // Áreas post-game / opcionales
  'Mazmorra Rara', 'Estancia Vacua',
];

export const USER_COLOR_POOL = [
  'bg-red-600', 'bg-amber-500', 'bg-emerald-600', 'bg-indigo-600', 'bg-pink-600',
  'bg-cyan-600', 'bg-orange-600', 'bg-violet-600', 'bg-lime-600', 'bg-teal-600',
  'bg-fuchsia-600', 'bg-sky-600',
];

export const STATUSES = ['Vivo', 'Muerto', 'Caja', 'Equipo'];
export const NATURES = [
  'Fuerte', 'Huraña', 'Audaz', 'Firme', 'Pícara',
  'Osada', 'Dócil', 'Plácida', 'Agitada', 'Floja',
  'Miedosa', 'Activa', 'Seria', 'Alegre', 'Ingenua',
  'Modesta', 'Afable', 'Mansa', 'Tímida', 'Alocada',
  'Serena', 'Amable', 'Grosera', 'Cauta', 'Rara',
];
