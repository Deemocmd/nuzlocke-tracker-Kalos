// Cliente ligero para hablar con las funciones serverless de /api, que a su
// vez usan Firebase Admin para leer/escribir en Firestore. Todo lo que antes
// vivía solo en memoria (usuarios, rutas, noticias) ahora se guarda en la
// base de datos, así que cualquier persona desde cualquier dispositivo ve lo
// mismo.

const SESSION_KEY = 'nuzlocke_session';

// Convierte un File (input type="file") a base64 puro, sin el prefijo
// "data:...;base64," que agrega FileReader. Lo usará la UI de subida de
// save (Parte 6) antes de llamar a api.applyRewards().
export function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result;
      const base64 = typeof result === 'string' ? result.split(',')[1] || '' : '';
      resolve(base64);
    };
    reader.onerror = () => reject(new Error('No se pudo leer el archivo.'));
    reader.readAsDataURL(file);
  });
}

// Dispara la descarga del save ya modificado que devuelve /api/apply-rewards.
export function downloadBase64AsFile(base64, filename) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  const blob = new Blob([bytes], { type: 'application/octet-stream' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename || 'main';
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

async function request(path, { method = 'GET', body, auth = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const session = loadSession();
    if (session && session.token) headers.Authorization = `Bearer ${session.token}`;
  }
  const res = await fetch(`/api${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch { /* respuesta vacía */ }
  if (!res.ok) {
    throw new Error(data.error || `Error de red (${res.status})`);
  }
  return data;
}

export const api = {
  loginAdmin: (password) => request('/login', { method: 'POST', body: { role: 'admin', password } }),
  loginUser: (userId, password) => request('/login', { method: 'POST', body: { role: 'user', userId, password } }),
  getUsers: () => request('/users'),
  createUser: (name, password) => request('/users', { method: 'POST', body: { name, password }, auth: true }),
  deleteUser: (id) => request(`/users?id=${encodeURIComponent(id)}`, { method: 'DELETE', auth: true }),
  updateRoute: (id, data) => request(`/route-entry?id=${encodeURIComponent(id)}`, { method: 'PUT', body: data, auth: true }),
  getNews: () => request('/news'),
  addNews: (title) => request('/news', { method: 'POST', body: { title }, auth: true }),

  giveCoins: (userId, amount, reason) => request('/coins', { method: 'POST', body: { userId, amount, reason }, auth: true }),
  getCoinHistory: (userId) => request(`/coins?userId=${encodeURIComponent(userId)}`, { auth: true }),

  addCustomRoute: (route) => request('/custom-route', { method: 'POST', body: { route }, auth: true }),
  deleteCustomRoute: (id) => request(`/custom-route?id=${encodeURIComponent(id)}`, { method: 'DELETE', auth: true }),

  getBracket: () => request('/bracket'),
  createBracket: (title, participantIds) => request('/bracket', { method: 'POST', body: { title, participantIds }, auth: true }),
  bracketSetWinner: (matchId, winnerId) => request('/bracket', { method: 'PUT', body: { action: 'setWinner', matchId, winnerId }, auth: true }),
  bracketSwap: (matchIdA, slotA, matchIdB, slotB) => request('/bracket', { method: 'PUT', body: { action: 'swap', matchIdA, slotA, matchIdB, slotB }, auth: true }),
  bracketAdvanceRound: () => request('/bracket', { method: 'PUT', body: { action: 'advanceRound' }, auth: true }),
  bracketFinish: () => request('/bracket', { method: 'PUT', body: { action: 'finish' }, auth: true }),
  resetBracket: () => request('/bracket', { method: 'DELETE', auth: true }),

  // Tienda: catálogo público (o completo si eres admin y pasas all=true).
  getShopItems: ({ all = false } = {}) => request(`/shop${all ? '?all=true' : ''}`, { auth: all }),
  createShopItem: (item) => request('/shop', { method: 'POST', body: item, auth: true }),
  updateShopItem: (id, patch) => request(`/shop?id=${encodeURIComponent(id)}`, { method: 'PUT', body: patch, auth: true }),
  deleteShopItem: (id) => request(`/shop?id=${encodeURIComponent(id)}`, { method: 'DELETE', auth: true }),

  // Compras: el jugador compra para sí mismo (quantity por defecto 1);
  // queda 'pendiente' hasta que se aplique al save (Parte 5).
  buyShopItem: (shopItemId, quantity = 1) => request('/purchases', { method: 'POST', body: { shopItemId, quantity }, auth: true }),
  getMyPurchases: (status) => request(`/purchases${status ? `?status=${encodeURIComponent(status)}` : ''}`, { auth: true }),
  getUserPurchases: (userId, status) => request(`/purchases?userId=${encodeURIComponent(userId)}${status ? `&status=${encodeURIComponent(status)}` : ''}`, { auth: true }),

  // Sube el save del jugador, el servidor aplica sus compras 'pendiente'
  // (motor de la Parte 4) y devuelve el archivo listo para reimportar.
  applyRewards: (saveBase64, filename) => request('/apply-rewards', { method: 'POST', body: { saveBase64, filename }, auth: true }),

  // Ruleta: segmentos, animación e historial persistidos en Supabase (antes
  // solo vivían en memoria del navegador y se perdían al recargar).
  getRoulette: () => request('/roulette'),
  updateRouletteConfig: (patch) => request('/roulette', { method: 'PUT', body: patch, auth: true }),
  addRouletteSpin: (entry) => request('/roulette', { method: 'POST', body: entry, auth: true }),

  getPlayoff: () => request('/playoff'),
  generatePlayoff: (size) => request('/playoff', { method: 'POST', body: { size }, auth: true }),
  playoffSetWinner: (matchId, winnerId) => request('/playoff', { method: 'PUT', body: { action: 'setWinner', matchId, winnerId }, auth: true }),
  resetPlayoff: () => request('/playoff', { method: 'DELETE', auth: true }),
};

export function saveSession(session) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
}
export function loadSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}
export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}
