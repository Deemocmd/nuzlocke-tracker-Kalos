import { useEffect, useState } from 'react';

const cache = new Map();

// Cualquier nombre de Pokémon vale (no solo los de una lista fija de
// encuentros): buscamos el sprite en la PokeAPI pública según lo que
// escriba la persona, con un pequeño debounce y caché en memoria.
export function usePokemonSprite(name) {
  const [sprite, setSprite] = useState(null);

  useEffect(() => {
    const clean = String(name || '').trim().toLowerCase();
    if (!clean) {
      setSprite(null);
      return undefined;
    }
    if (cache.has(clean)) {
      setSprite(cache.get(clean));
      return undefined;
    }
    let cancelled = false;
    const timer = setTimeout(async () => {
      try {
        const res = await fetch(`https://pokeapi.co/api/v2/pokemon/${encodeURIComponent(clean)}`);
        if (!res.ok) throw new Error('not found');
        const data = await res.json();
        const url = (data.sprites && data.sprites.front_default) || null;
        cache.set(clean, url);
        if (!cancelled) setSprite(url);
      } catch {
        cache.set(clean, null);
        if (!cancelled) setSprite(null);
      }
    }, 400);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [name]);

  return sprite;
}

const evolutionCache = new Map();

// Busca, dentro del árbol de una cadena evolutiva de la PokeAPI, el nodo
// correspondiente a una especie concreta (comparando por nombre).
function findSpeciesNode(chainNode, targetName) {
  if (!chainNode) return null;
  if (chainNode.species.name === targetName) return chainNode;
  for (const child of chainNode.evolves_to || []) {
    const found = findSpeciesNode(child, targetName);
    if (found) return found;
  }
  return null;
}

// Dado el nombre de un Pokémon, devuelve la lista de nombres a los que
// puede evolucionar directamente (normalmente 0 o 1, pero puede haber más
// de una opción en evoluciones ramificadas como Eevee). Con caché en
// memoria igual que el sprite.
export function usePokemonEvolutions(name) {
  const [options, setOptions] = useState([]);

  useEffect(() => {
    const clean = String(name || '').trim().toLowerCase();
    if (!clean) {
      setOptions([]);
      return undefined;
    }
    if (evolutionCache.has(clean)) {
      setOptions(evolutionCache.get(clean));
      return undefined;
    }
    let cancelled = false;
    const timer = setTimeout(async () => {
      try {
        const speciesRes = await fetch(`https://pokeapi.co/api/v2/pokemon-species/${encodeURIComponent(clean)}`);
        if (!speciesRes.ok) throw new Error('species not found');
        const species = await speciesRes.json();
        const chainRes = await fetch(species.evolution_chain.url);
        if (!chainRes.ok) throw new Error('chain not found');
        const chainData = await chainRes.json();
        const node = findSpeciesNode(chainData.chain, clean);
        const nextNames = node ? (node.evolves_to || []).map((n) => n.species.name) : [];
        evolutionCache.set(clean, nextNames);
        if (!cancelled) setOptions(nextNames);
      } catch {
        evolutionCache.set(clean, []);
        if (!cancelled) setOptions([]);
      }
    }, 400);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [name]);

  return options;
}
