// Postgres/Supabase devuelve columnas en snake_case; el frontend (src/App.jsx)
// espera el mismo shape camelCase que antes devolvía Firestore. Estos
// helpers hacen esa conversión en un solo lugar.

export function userToJson(row, routes = []) {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
    deaths: row.deaths,
    wins: row.wins,
    losses: row.losses,
    status: row.status,
    coins: row.coins ?? 0,
    createdAt: row.created_at,
    routes,
  };
}

export function routeToJson(row) {
  return {
    id: row.id,
    userId: row.user_id,
    orderIndex: row.order_index,
    route: row.route,
    pokemonName: row.pokemon_name,
    nickname: row.nickname,
    level: row.level,
    nature: row.nature,
    status: row.status,
    ability: row.ability,
    item: row.item,
    notes: row.notes,
    isCustom: row.is_custom,
  };
}

export function newsToJson(row) {
  return { id: row.id, title: row.title, excerpt: row.excerpt, createdAt: row.created_at };
}

export function coinTransactionToJson(row) {
  return {
    id: row.id,
    userId: row.user_id,
    delta: row.delta,
    reason: row.reason,
    balanceAfter: row.balance_after,
    createdAt: row.created_at,
  };
}

export function shopItemToJson(row) {
  return {
    id: row.id,
    itemId: row.item_id,
    name: row.name,
    category: row.category,
    description: row.description,
    price: row.price,
    stock: row.stock, // null = ilimitado
    active: row.active,
    createdAt: row.created_at,
  };
}

export function purchaseToJson(row) {
  return {
    id: row.id,
    userId: row.user_id,
    shopItemId: row.shop_item_id,
    itemId: row.item_id,
    itemName: row.item_name,
    quantity: row.quantity,
    pricePaid: row.price_paid,
    status: row.status,
    appliedAt: row.applied_at,
    appliedSaveFilename: row.applied_save_filename,
    createdAt: row.created_at,
  };
}

