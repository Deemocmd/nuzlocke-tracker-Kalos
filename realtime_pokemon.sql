import { useState, useEffect, useMemo, useRef } from 'react';
import {
  Home, Users, Swords, Trophy, Dices, ScrollText,
  BarChart3, ShieldCheck, UserCircle, Menu, X, Search,
  Skull, Clock, Flame, Newspaper, ChevronDown, Plus,
  Shuffle, Move, Trash2, Archive, Sparkles, Coins, Minus, History, ShoppingBag,
  Upload, Download, AlertTriangle,
} from 'lucide-react';
import { api, saveSession, loadSession, clearSession, fileToBase64, downloadBase64AsFile } from './api.js';
import { supabaseClient } from './supabaseClient.js';
import { usePokemonSprite, usePokemonEvolutions } from './usePokemonSprite.js';
import { KALOS_LOCATIONS, USER_COLOR_POOL, STATUSES, NATURES } from '../shared/constants.js';

/* ==============================================================================
   Los datos de participantes, fichas Nuzlocke y noticias ya NO viven en
   memoria: se leen y escriben en Firestore a través de Firebase Admin (ver
   carpeta /api). Este archivo solo pinta la interfaz y llama a src/api.js.
================================================================================ */

const ROULETTE_SEGMENTS = [
  { id: 1, label: 'Perdona una muerte', type: 'premio', pct: 15 },
  { id: 2, label: '+1 muerte', type: 'castigo', pct: 12 },
  { id: 3, label: 'Objeto gratis', type: 'premio', pct: 13 },
  { id: 4, label: 'Pierdes tu objeto', type: 'castigo', pct: 12 },
  { id: 5, label: 'Revive 1 Pokémon', type: 'premio', pct: 8 },
  { id: 6, label: 'Repite la ronda', type: 'castigo', pct: 12 },
  { id: 7, label: 'Doble captura', type: 'premio', pct: 13 },
  { id: 8, label: 'Sin efecto', type: 'neutro', pct: 15 },
];

/* ---------- Bracket de eliminación directa · 32 participantes ---------- */

const BRACKET_ROUND_LABEL_POOL = ['Dieciseisavos', 'Octavos', 'Cuartos', 'Semifinal', 'Final'];
const BRACKET_ROUND_COLORS = ['#dc2626', '#ea580c', '#f59e0b', '#eab308', '#facc15'];
// Un cuadro de playoffs puede tener menos de 5 rondas (ej: 8 u 16
// participantes en vez de 32) — tomamos las últimas N etiquetas del pool
// para que siempre termine en "Final".
function bracketRoundLabels(roundCount) {
  return BRACKET_ROUND_LABEL_POOL.slice(BRACKET_ROUND_LABEL_POOL.length - roundCount);
}

const STATUS_STYLES = {
  Vivo: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
  Muerto: 'bg-red-500/10 text-red-400 border-red-500/30',
  Caja: 'bg-sky-500/10 text-sky-400 border-sky-500/30',
  Equipo: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
};

const MAX_DEATHS = 30; // el Nuzlocke termina cuando se llega a este número de muertes

const NAV_ITEMS = [
  { key: 'inicio', label: 'Inicio', icon: Home },
  { key: 'participantes', label: 'Participantes', icon: Users },
  { key: 'bracket', label: 'Bracket', icon: Swords },
  { key: 'playoffs', label: 'Playoffs', icon: Trophy },
  { key: 'torneo-suizo', label: 'Torneo Oficial', icon: Shuffle },
  { key: 'tienda', label: 'Tienda', icon: ShoppingBag },
  { key: 'ruleta', label: 'Ruleta', icon: Dices },
  { key: 'normas', label: 'Normas', icon: ScrollText },
  { key: 'estadisticas', label: 'Estadísticas', icon: BarChart3 },
  { key: 'admin', label: 'Administrador', icon: ShieldCheck },
  { key: 'perfil', label: 'Mi Perfil', icon: UserCircle },
];

const VIEW_TITLES = {
  inicio: 'Inicio', participantes: 'Participantes', bracket: 'Bracket', playoffs: 'Playoffs',
  'torneo-suizo': 'Torneo Oficial',
  tienda: 'Tienda', ruleta: 'Ruleta', normas: 'Normas', estadisticas: 'Estadísticas',
  admin: 'Administrador', perfil: 'Mi Perfil',
};

/* Sistema de usuarios: Administrador (único, con contraseña de entorno) ·
   Usuario (cada jugador, con su propia contraseña) — ambos guardados en
   Firestore vía Firebase Admin, ver /api/login.js. */

const DEFAULT_RULES_MD = `# Normas del Torneo Nuzlocke Championship

## Reglas de captura

1. Solo puedes capturar el primer Pokémon que aparezca en cada ruta; si huye o el encuentro falla, esa ruta queda vacía para siempre.
2. Todo Pokémon debilitado en combate se considera muerto y debe transferirse a la Caja de difuntos.
3. Los apodos son obligatorios para cada captura.
4. No se permite el uso de objetos curativos fuera de los Centros Pokémon durante los combates de torneo.

## Formato de combate

- Los combates de clasificación se juegan a formato VGC, dobles, con la Regulation vigente.
- Todo resultado debe ser confirmado por ambos jugadores y validado por un administrador antes de reflejarse en el bracket.
- Los BYES se asignan automáticamente cuando el número de inscritos no llega a 32.

## Restricciones por fase

| Fase | Curación en combate | Objetos permitidos |
| --- | --- | --- |
| Fase de grupos | No | Todos excepto Restos |
| Playoffs | No | Objetos de combate estándar |
| Final | No | A discreción del administrador |

Este editor admite **negrita**, *cursiva*, listas, tablas, imágenes (\`![alt](url)\`) y vídeos (\`!video[alt](url)\`).
`;

/* ============================== HOOKS Y HELPERS ============================== */

function useCountdown(targetDate) {
  const [timeLeft, setTimeLeft] = useState(() => targetDate.getTime() - Date.now());
  useEffect(() => {
    const id = setInterval(() => setTimeLeft(targetDate.getTime() - Date.now()), 1000);
    return () => clearInterval(id);
  }, [targetDate]);
  const clamped = Math.max(0, timeLeft);
  return {
    days: Math.floor(clamped / 86400000),
    hours: Math.floor((clamped / 3600000) % 24),
    minutes: Math.floor((clamped / 60000) % 60),
    seconds: Math.floor((clamped / 1000) % 60),
  };
}

const inputClass = 'bg-gray-800 border border-gray-700 rounded-lg px-2.5 py-1.5 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-500 transition-shadow';

/* ---------- Mini-parser de Markdown para la sección de Normas ----------
   Admite: encabezados (#, ##, ###), negrita/cursiva, listas con y sin
   numerar, tablas, imágenes ![alt](url) y vídeos !video[alt](url). */

function renderInline(text, keyPrefix) {
  const parts = String(text).split(/(\*\*[^*]+\*\*|\*[^*]+\*)/g).filter((p) => p !== '');
  return parts.map((part, idx) => {
    const key = `${keyPrefix}-${idx}`;
    if (/^\*\*[^*]+\*\*$/.test(part)) return <strong key={key} className="text-gray-100 font-semibold">{part.slice(2, -2)}</strong>;
    if (/^\*[^*]+\*$/.test(part)) return <em key={key} className="text-gray-300">{part.slice(1, -1)}</em>;
    return <span key={key}>{part}</span>;
  });
}

function parseMarkdown(md) {
  const lines = String(md || '').split('\n');
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }

    if (line.includes('|') && lines[i + 1] && /^[\s|:-]+$/.test(lines[i + 1]) && lines[i + 1].includes('-')) {
      const header = line.split('|').map((c) => c.trim()).filter(Boolean);
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].includes('|')) {
        rows.push(lines[i].split('|').map((c) => c.trim()).filter(Boolean));
        i++;
      }
      blocks.push({ type: 'table', header, rows });
      continue;
    }

    const vidMatch = line.match(/^!video\[(.*?)\]\((.*?)\)\s*$/);
    if (vidMatch) { blocks.push({ type: 'video', alt: vidMatch[1], src: vidMatch[2] }); i++; continue; }

    const imgMatch = line.match(/^!\[(.*?)\]\((.*?)\)\s*$/);
    if (imgMatch) { blocks.push({ type: 'image', alt: imgMatch[1], src: imgMatch[2] }); i++; continue; }

    const hMatch = line.match(/^(#{1,3})\s+(.*)$/);
    if (hMatch) { blocks.push({ type: 'heading', level: hMatch[1].length, text: hMatch[2] }); i++; continue; }

    if (/^\s*-\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) { items.push(lines[i].replace(/^\s*-\s+/, '')); i++; }
      blocks.push({ type: 'ul', items });
      continue;
    }

    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) { items.push(lines[i].replace(/^\s*\d+\.\s+/, '')); i++; }
      blocks.push({ type: 'ol', items });
      continue;
    }

    const para = [line];
    i++;
    while (i < lines.length && lines[i].trim() && !/^#{1,3}\s/.test(lines[i]) && !/^\s*-\s+/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i]) && !lines[i].includes('|') && !/^!/.test(lines[i])) {
      para.push(lines[i]);
      i++;
    }
    blocks.push({ type: 'p', text: para.join(' ') });
  }
  return blocks;
}

function MarkdownView({ markdown }) {
  const blocks = useMemo(() => parseMarkdown(markdown), [markdown]);
  return (
    <div className="space-y-4">
      {blocks.map((b, i) => {
        if (b.type === 'heading') {
          const Tag = b.level === 1 ? 'h2' : b.level === 2 ? 'h3' : 'h4';
          const sizeClass = b.level === 1 ? 'text-xl' : b.level === 2 ? 'text-lg' : 'text-base';
          return <Tag key={i} className={`font-display font-bold text-white tracking-wide ${sizeClass}`}>{renderInline(b.text, `h${i}`)}</Tag>;
        }
        if (b.type === 'p') return <p key={i} className="text-sm text-gray-300 leading-relaxed">{renderInline(b.text, `p${i}`)}</p>;
        if (b.type === 'ul') return (
          <ul key={i} className="list-disc list-inside text-sm text-gray-300 space-y-1.5">
            {b.items.map((it, j) => <li key={j}>{renderInline(it, `ul${i}-${j}`)}</li>)}
          </ul>
        );
        if (b.type === 'ol') return (
          <ol key={i} className="list-decimal list-inside text-sm text-gray-300 space-y-1.5">
            {b.items.map((it, j) => <li key={j}>{renderInline(it, `ol${i}-${j}`)}</li>)}
          </ol>
        );
        if (b.type === 'table') return (
          <div key={i} className="overflow-x-auto">
            <table className="w-full text-sm border border-gray-800 rounded-lg overflow-hidden">
              <thead>
                <tr className="bg-gray-800/60 text-left text-gray-400">
                  {b.header.map((h, j) => <th key={j} className="py-2 px-3 font-medium border-b border-gray-800">{h}</th>)}
                </tr>
              </thead>
              <tbody>
                {b.rows.map((row, j) => (
                  <tr key={j} className="border-b border-gray-900 last:border-0 hover:bg-gray-900/40">
                    {row.map((cell, k) => <td key={k} className="py-2 px-3 text-gray-300">{cell}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
        if (b.type === 'image') return (
          <img key={i} src={b.src} alt={b.alt} className="max-w-full rounded-lg border border-gray-800" />
        );
        if (b.type === 'video') {
          const isEmbed = /youtube\.com|youtu\.be/.test(b.src);
          return isEmbed
            ? <iframe key={i} src={b.src} title={b.alt} className="w-full aspect-video rounded-lg border border-gray-800" allowFullScreen />
            : <video key={i} src={b.src} controls className="w-full rounded-lg border border-gray-800" />;
        }
        return null;
      })}
    </div>
  );
}

/* ============================== COMPONENTES BASE ============================== */

// -----------------------------------------------------------------------
// Sistema de animación global. Un solo lugar para las fuentes y los
// keyframes que usa toda la app — se monta tanto en el login como en el
// shell principal (son árboles de React separados). Respeta
// prefers-reduced-motion: si el usuario lo pide, se desactivan las
// animaciones decorativas (las de utilidad, como el spinner, quedan).
// -----------------------------------------------------------------------
function GlobalStyles() {
  return (
    <style>{`
      @import url('https://fonts.googleapis.com/css2?family=Rajdhani:wght@500;600;700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@500;600&display=swap');
      .font-display { font-family: 'Rajdhani', sans-serif; }
      .font-mono-data { font-family: 'JetBrains Mono', monospace; }

      @keyframes fadeInUp { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
      @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
      @keyframes scaleIn { from { opacity: 0; transform: scale(0.94); } to { opacity: 1; transform: scale(1); } }
      @keyframes slideInLeft { from { opacity: 0; transform: translateX(-10px); } to { opacity: 1; transform: translateX(0); } }
      @keyframes pokeSpin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      @keyframes shimmer { 0% { background-position: -200% 0; } 100% { background-position: 200% 0; } }

      .animate-fade-in-up { animation: fadeInUp 0.5s cubic-bezier(0.16,1,0.3,1) both; }
      .animate-fade-in { animation: fadeIn 0.35s ease both; }
      .animate-scale-in { animation: scaleIn 0.35s cubic-bezier(0.16,1,0.3,1) both; }
      .animate-slide-in-left { animation: slideInLeft 0.4s cubic-bezier(0.16,1,0.3,1) both; }
      .animate-poke-spin { animation: pokeSpin 0.9s linear infinite; }
      .shimmer-bg { background: linear-gradient(90deg, rgba(255,255,255,0.03) 25%, rgba(255,255,255,0.08) 37%, rgba(255,255,255,0.03) 63%); background-size: 400% 100%; animation: shimmer 1.6s ease infinite; }

      .hover-lift { transition: transform 0.25s cubic-bezier(0.16,1,0.3,1), border-color 0.25s ease, box-shadow 0.25s ease; }
      .hover-lift:hover { transform: translateY(-3px); border-color: rgba(37,99,235,0.5); box-shadow: 0 10px 28px -10px rgba(0,0,0,0.55); }

      .press-feedback { transition: transform 0.15s ease; }
      .press-feedback:active { transform: scale(0.96); }

      @media (prefers-reduced-motion: reduce) {
        .animate-fade-in-up, .animate-fade-in, .animate-scale-in, .animate-slide-in-left, .shimmer-bg { animation: none !important; }
        .hover-lift, .hover-lift:hover, .press-feedback, .press-feedback:active { transition: none !important; transform: none !important; }
        * { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
      }
    `}</style>
  );
}

// Cuenta de 0 (o del valor anterior) hasta `value` con un ease-out suave.
// Se usa en los números de estadísticas para que un cambio real (ronda
// jugada, participante nuevo) se note en vez de aparecer de golpe.
function AnimatedCounter({ value, duration = 700 }) {
  const numericTarget = Number(value);
  const isNumeric = Number.isFinite(numericTarget);
  const [display, setDisplay] = useState(isNumeric ? numericTarget : 0);
  const fromRef = useRef(isNumeric ? numericTarget : 0);

  useEffect(() => {
    if (!isNumeric) return undefined;
    const from = fromRef.current;
    const to = numericTarget;
    if (from === to) return undefined;
    const start = performance.now();
    let raf;
    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      setDisplay(Math.round(from + (to - from) * eased));
      if (progress < 1) {
        raf = requestAnimationFrame(tick);
      } else {
        fromRef.current = to;
      }
    }
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  return <>{isNumeric ? display : value}</>;
}

function Panel({ className = '', style, children }) {
  return (
    <div className={`bg-gray-900/70 border border-gray-800 rounded-2xl p-4 md:p-5 animate-fade-in-up ${className}`} style={style}>
      {children}
    </div>
  );
}

function LoadingState({ label = 'Cargando…' }) {
  return (
    <div className="flex items-center gap-2 text-sm text-gray-600">
      <PokeballIcon className="w-4 h-4 animate-poke-spin" />
      {label}
    </div>
  );
}

function StatusBadge({ status }) {
  return (
    <span className={`text-xs font-semibold px-2 py-1 rounded-full border whitespace-nowrap ${STATUS_STYLES[status] || 'bg-gray-500/10 text-gray-400 border-gray-500/30'}`}>
      {status}
    </span>
  );
}


function Avatar({ name, color, size = 'w-6 h-6' }) {
  return (
    <span className={`${size} rounded-full ${color} flex items-center justify-center text-xs font-bold text-white shrink-0`}>
      {name[0]}
    </span>
  );
}

function PokeballIcon({ className = 'w-6 h-6' }) {
  return (
    <svg viewBox="0 0 40 40" className={className} aria-hidden="true">
      <circle cx="20" cy="20" r="18" fill="#fff" stroke="#111827" strokeWidth="2" />
      <path d="M2 20a18 18 0 0 1 36 0z" fill="#2563eb" stroke="#111827" strokeWidth="2" />
      <line x1="2" y1="20" x2="38" y2="20" stroke="#111827" strokeWidth="2.5" />
      <circle cx="20" cy="20" r="6.5" fill="#fff" stroke="#111827" strokeWidth="2.5" />
      <circle cx="20" cy="20" r="2.5" fill="#111827" />
    </svg>
  );
}

/* ============================== SIDEBAR ============================== */

function SidebarNav({ active, onSelect, open, onClose, items, onHome }) {
  return (
    <>
      {open && <div className="fixed inset-0 bg-black/70 z-40 md:hidden" onClick={onClose} />}
      <aside className={`fixed md:static inset-y-0 left-0 z-50 w-64 bg-gray-950 border-r border-gray-800 flex flex-col transform transition-transform duration-300 ${open ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0`}>
        <div className="flex items-center justify-between px-5 py-5 border-b border-gray-800">
          <button type="button" onClick={onHome} title="Volver a Inicio" className="flex items-center gap-2.5 group">
            <PokeballIcon className="w-9 h-9 group-hover:rotate-12 transition-transform duration-300 animate-scale-in" />
            <span className="font-display font-bold text-white tracking-wide text-lg leading-none text-left">NUZLOCKE<br /><span className="text-xs font-sans font-normal text-gray-500 tracking-widest">TOURNAMENT HUB</span></span>
          </button>
          <button type="button" onClick={onClose} className="md:hidden text-gray-500 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>
        <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">
          {items.map((item, i) => {
            const Icon = item.icon;
            const isActive = active === item.key;
            return (
              <button
                type="button"
                key={item.key}
                onClick={() => { onSelect(item.key); onClose(); }}
                style={{ animationDelay: `${i * 35}ms` }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors animate-slide-in-left group ${isActive ? 'bg-blue-600/15 text-blue-400 border border-blue-800/50' : 'text-gray-400 hover:bg-gray-900 hover:text-gray-200 border border-transparent'}`}
              >
                <Icon className={`w-4 h-4 transition-transform duration-200 ${isActive ? '' : 'group-hover:scale-110 group-hover:-translate-y-px'}`} />
                {item.label}
              </button>
            );
          })}
        </nav>
        <div className="px-5 py-4 border-t border-gray-800 text-xs text-gray-600">Vista previa de diseño</div>
      </aside>
    </>
  );
}

/* ============================== INICIO ============================== */

function HomeView({ news, onNavigate, users }) {
  const clasificacion = [...users].sort((a, b) => b.wins - a.wins || a.deaths - b.deaths).slice(0, 5);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[['Participantes', users.length, Users], ['Ronda actual', '—', Swords], ['Combates jugados', users.reduce((a, u) => a + u.wins + u.losses, 0), Flame], ['Eliminados', users.filter((u) => u.status === 'Eliminado').length, Skull]].map(([label, val, Icon], i) => (
          <Panel key={label} className="flex items-center gap-3 hover-lift" style={{ animationDelay: `${i * 60}ms` }}>
            <Icon className="w-7 h-7 text-blue-500 shrink-0" />
            <div>
              <div className="font-display text-xl font-bold text-white leading-none"><AnimatedCounter value={val} /></div>
              <div className="text-xs text-gray-500 mt-1">{label}</div>
            </div>
          </Panel>
        ))}
      </div>

      <Panel>
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><Trophy className="w-4 h-4 text-amber-400" /> Clasificación</h3>
        {clasificacion.length === 0 ? (
          <p className="text-sm text-gray-600">Todavía no hay participantes. Un administrador puede darlos de alta desde el panel de Administrador.</p>
        ) : (
          <div className="space-y-2">
            {clasificacion.map((p, i) => (
              <div key={p.id} className="flex items-center justify-between text-sm bg-gray-800/40 rounded-lg px-3 py-2 animate-fade-in-up" style={{ animationDelay: `${i * 50}ms` }}>
                <div className="flex items-center gap-2.5">
                  <span className="font-mono-data text-gray-600 w-4">{i + 1}</span>
                  <Avatar name={p.name} color={p.color} />
                  <span className="text-gray-200">{p.name}</span>
                </div>
                <span className="font-mono-data text-gray-400">{p.wins}-{p.losses}</span>
              </div>
            ))}
          </div>
        )}
      </Panel>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Panel>
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-white font-semibold flex items-center gap-2"><Newspaper className="w-4 h-4 text-amber-400" /> Noticias</h3>
            <button type="button" onClick={() => onNavigate && onNavigate('admin')} className="text-xs text-gray-500 hover:text-gray-300">Gestionar</button>
          </div>
          <div className="space-y-3">
            {news.length === 0 ? (
              <p className="text-sm text-gray-600">Aún no hay noticias publicadas.</p>
            ) : news.map((n) => (
              <div key={n.id} className="bg-gray-800/40 rounded-lg px-3 py-2.5">
                <div className="flex items-center justify-between gap-2 mb-1">
                  <span className="text-sm font-semibold text-gray-100">{n.title}</span>
                  <span className="text-xs text-gray-600 font-mono-data shrink-0">
                    {n.createdAt ? new Date(n.createdAt).toLocaleDateString() : ''}
                  </span>
                </div>
                <p className="text-xs text-gray-500 leading-relaxed">{n.excerpt}</p>
              </div>
            ))}
          </div>
        </Panel>

        <Panel>
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-white font-semibold flex items-center gap-2"><ScrollText className="w-4 h-4 text-blue-400" /> Normas del torneo</h3>
            <button type="button" onClick={() => onNavigate && onNavigate('normas')} className="text-xs text-gray-500 hover:text-gray-300">Ver todo</button>
          </div>
          <p className="text-sm text-gray-500 leading-relaxed">Consulta las reglas de captura, formato de combate y restricciones por fase antes de tu próxima ronda.</p>
          <button type="button" onClick={() => onNavigate && onNavigate('perfil')} className="mt-4 flex items-center gap-1.5 text-xs font-semibold text-amber-400 hover:text-amber-300">
            <UserCircle className="w-3.5 h-3.5" /> Ir a mi ficha Nuzlocke
          </button>
        </Panel>
      </div>
    </div>
  );
}

/* ============================== PARTICIPANTES ============================== */

function ParticipantsView({ users }) {
  if (users.length === 0) {
    return (
      <Panel className="flex flex-col items-center justify-center gap-2 py-14 text-gray-600 border-dashed">
        <Users className="w-8 h-8" />
        <span className="text-sm">Todavía no hay participantes registrados.</span>
        <span className="text-xs text-gray-700">Un administrador puede añadirlos desde el panel de Administrador.</span>
      </Panel>
    );
  }
  return (
    <div className="space-y-4">
      <Panel><p className="text-sm text-gray-400">Roster completo del torneo · {users.length} participantes registrados</p></Panel>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {users.map((p, i) => (
          <Panel key={p.id} className="flex flex-col gap-3 hover-lift" style={{ animationDelay: `${i * 45}ms` }}>
            <div className="flex items-center gap-3">
              <Avatar name={p.name} color={p.color} size="w-12 h-12 text-lg" />
              <div>
                <div className="font-semibold text-white">{p.name}</div>
                <div className={`text-xs ${p.status === 'Eliminado' ? 'text-red-500' : 'text-emerald-500'}`}>{p.status}</div>
              </div>
            </div>
            <div>
              <div className="flex justify-between text-xs text-gray-500 mb-1">
                <span>Muertes</span><span className="font-mono-data">{p.deaths}/{MAX_DEATHS}</span>
              </div>
              <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
                <div className="h-full bg-gradient-to-r from-red-700 to-red-500 rounded-full" style={{ width: `${Math.min(100, (p.deaths / MAX_DEATHS) * 100)}%` }} />
              </div>
            </div>
            <div className="text-sm text-gray-400">Récord: <span className="font-mono-data text-gray-200 font-semibold">{p.wins}-{p.losses}</span></div>
          </Panel>
        ))}
      </div>
    </div>
  );
}

/* ============================== BRACKET (FASE DE GRUPOS) ============================== */

function GroupStandingsView({ users }) {
  const sorted = [...users].sort((a, b) => b.wins - a.wins || a.deaths - b.deaths);
  return (
    <div className="space-y-4">
      <Panel>
        <h2 className="font-display text-xl font-bold text-white mb-1 tracking-wide">FASE DE GRUPOS</h2>
        <p className="text-sm text-gray-500">Clasificación por récord y menos muertes registradas como desempate.</p>
      </Panel>
      {sorted.length === 0 ? (
        <Panel className="text-center py-10 text-sm text-gray-600">Sin participantes todavía.</Panel>
      ) : (
        <Panel className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-gray-500 border-b border-gray-800">
                <th className="py-2 pr-4 font-medium">#</th>
                <th className="py-2 pr-4 font-medium">Jugador</th>
                <th className="py-2 pr-4 font-medium">Récord</th>
                <th className="py-2 pr-4 font-medium">Muertes</th>
                <th className="py-2 pr-4 font-medium">Estado</th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((p, i) => (
                <tr key={p.id} className="border-b border-gray-900 hover:bg-gray-900/40 transition-colors animate-fade-in-up" style={{ animationDelay: `${i * 30}ms` }}>
                  <td className="py-2.5 pr-4 font-mono-data text-gray-600">{i + 1}</td>
                  <td className="py-2.5 pr-4 text-gray-200 font-medium">{p.name}</td>
                  <td className="py-2.5 pr-4 font-mono-data text-gray-400">{p.wins}-{p.losses}</td>
                  <td className="py-2.5 pr-4 font-mono-data text-gray-400">{p.deaths}/{MAX_DEATHS}</td>
                  <td className="py-2.5 pr-4"><StatusBadge status={p.status === 'Eliminado' ? 'Muerto' : 'Vivo'} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </Panel>
      )}
    </div>
  );
}

/* ============================== PLAYOFFS · BRACKET DE 32 ============================== */

const BRACKET_SLOT_HEIGHT = 88;

function BracketSlot({ player, isWinner, hoveredName, onHover, onClick, clickable }) {
  if (player === undefined) {
    return <div className="flex items-center px-2.5 py-2 rounded-lg border border-dashed border-gray-800 text-xs text-gray-700 italic h-[34px]">Por determinar</div>;
  }
  if (player === null) {
    return <div className="flex items-center px-2.5 py-2 rounded-lg border border-dashed border-gray-800 text-xs text-gray-600 h-[34px]">BYE</div>;
  }
  const highlighted = hoveredName === player.name;
  return (
    <button
      type="button"
      disabled={!clickable}
      onClick={onClick}
      onMouseEnter={() => onHover(player.name)}
      onMouseLeave={() => onHover(null)}
      className={`w-full flex items-center gap-2 px-2.5 py-2 rounded-lg border text-sm font-mono-data transition-all h-[34px] ${
        isWinner ? 'border-amber-400 bg-amber-500/10 text-amber-300 font-semibold' : 'border-gray-700 bg-gray-800/60 text-gray-300'
      } ${clickable ? 'hover:border-gray-500 hover:scale-[1.02] active:scale-95 cursor-pointer' : 'cursor-default'} ${highlighted ? 'ring-2 ring-amber-400/70' : ''}`}
    >
      <Avatar name={player.name} color={player.color} />
      <span className="truncate">{player.name}</span>
      {isWinner && <Trophy className="w-3.5 h-3.5 text-amber-400 ml-auto shrink-0 animate-scale-in" />}
    </button>
  );
}

function BracketMatchCard({ match, roundIndex, matchIndex, color, hoveredName, onHover, onSetWinner, cardRef, editable }) {
  const clickable = editable && Boolean(match.p1 && match.p2);
  return (
    <div ref={cardRef} className="flex flex-col gap-1 bg-gray-900/70 border rounded-xl p-1.5" style={{ borderColor: `${color}55`, width: 192 }}>
      <BracketSlot player={match.p1} isWinner={Boolean(match.winner && match.p1 && match.winner.name === match.p1.name)} hoveredName={hoveredName} onHover={onHover} clickable={clickable} onClick={() => onSetWinner(roundIndex, matchIndex, match.p1)} />
      <BracketSlot player={match.p2} isWinner={Boolean(match.winner && match.p2 && match.winner.name === match.p2.name)} hoveredName={hoveredName} onHover={onHover} clickable={clickable} onClick={() => onSetWinner(roundIndex, matchIndex, match.p2)} />
    </div>
  );
}

function BracketLines({ lines, hoveredName }) {
  const pathRefs = useRef({}).current;
  useEffect(() => {
    Object.values(pathRefs).forEach((el) => {
      if (!el) return;
      const len = el.getTotalLength();
      el.style.strokeDasharray = `${len}`;
      el.style.strokeDashoffset = `${len}`;
      requestAnimationFrame(() => {
        el.style.transition = 'stroke-dashoffset 700ms ease';
        el.style.strokeDashoffset = '0';
      });
    });
  }, [lines]);

  return (
    <svg className="absolute inset-0 pointer-events-none" style={{ overflow: 'visible' }} width="100%" height="100%">
      {lines.map((line) => {
        const active = hoveredName && line.players.includes(hoveredName);
        return (
          <path
            key={line.key}
            ref={(el) => { pathRefs[line.key] = el; }}
            d={line.d}
            fill="none"
            stroke={active ? '#f59e0b' : '#374151'}
            strokeWidth={active ? 2.5 : 1.5}
            className="transition-colors duration-200"
          />
        );
      })}
    </svg>
  );
}

function Bracket32View({ role, playoff, loading, swissStatus, onGenerate, onSetWinner, onReset }) {
  const isAdmin = role === 'Administrador';
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [hoveredName, setHoveredName] = useState(null);
  const [lines, setLines] = useState([]);
  const containerRef = useRef(null);
  const cardRefs = useRef({}).current;

  const participantMap = useMemo(
    () => Object.fromEntries((playoff?.participants || []).map((p) => [p.id, p])),
    [playoff],
  );
  // Traduce los ids guardados en el backend a objetos {id, name, color}
  // conservando la distinción entre "BYE" (null) y "todavía no definido"
  // (undefined), igual que hacía el armado local anterior.
  function resolve(id) {
    if (id === undefined) return undefined;
    if (id === null) return null;
    return participantMap[id] || { id, name: '???', color: '#6b7280' };
  }
  const displayRounds = useMemo(
    () => (playoff?.rounds || []).map((round) => round.map((m) => ({
      id: m.id, p1: resolve(m.p1), p2: resolve(m.p2), winner: resolve(m.winner),
    }))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [playoff],
  );

  function setCardRef(key) { return (el) => { cardRefs[key] = el; }; }

  async function handleGenerate() {
    setBusy(true);
    setError('');
    try {
      await onGenerate();
    } catch (err) {
      setError(err.message || 'No se pudo generar el cuadro de playoffs.');
    } finally {
      setBusy(false);
    }
  }

  async function handleReset() {
    if (!window.confirm('Esto borra el cuadro de playoffs actual por completo. ¿Continuar?')) return;
    setBusy(true);
    setError('');
    try {
      await onReset();
    } catch (err) {
      setError(err.message || 'No se pudo reiniciar los playoffs.');
    } finally {
      setBusy(false);
    }
  }

  async function handleSetWinner(roundIndex, matchIndex, player) {
    if (!isAdmin || !player) return;
    const matchId = displayRounds[roundIndex][matchIndex].id;
    setError('');
    try {
      await onSetWinner(matchId, player.id);
    } catch (err) {
      setError(err.message || 'No se pudo guardar el resultado.');
    }
  }

  useEffect(() => {
    function computeLines() {
      if (!containerRef.current || displayRounds.length === 0) return;
      const containerRect = containerRef.current.getBoundingClientRect();
      const next = [];
      for (let r = 0; r < displayRounds.length - 1; r++) {
        displayRounds[r].forEach((m, i) => {
          const srcEl = cardRefs[`${r}-${i}`];
          const tgtEl = cardRefs[`${r + 1}-${Math.floor(i / 2)}`];
          if (!srcEl || !tgtEl) return;
          const s = srcEl.getBoundingClientRect();
          const t = tgtEl.getBoundingClientRect();
          const x1 = s.right - containerRect.left;
          const y1 = s.top + s.height / 2 - containerRect.top;
          const x2 = t.left - containerRect.left;
          const y2 = t.top + t.height / 2 - containerRect.top;
          const midX = x1 + (x2 - x1) / 2;
          next.push({
            key: `${r}-${i}`,
            d: `M${x1},${y1} H${midX} V${y2} H${x2}`,
            players: [m.p1 && m.p1.name, m.p2 && m.p2.name, m.winner && m.winner.name].filter(Boolean),
          });
        });
      }
      setLines(next);
    }
    computeLines();
    window.addEventListener('resize', computeLines);
    return () => window.removeEventListener('resize', computeLines);
  }, [displayRounds, cardRefs]);

  if (loading) {
    return <Panel><LoadingState /></Panel>;
  }

  if (!playoff) {
    return (
      <div className="space-y-4">
        <Panel className="flex flex-col items-center justify-center gap-3 py-14 text-gray-600 border-dashed text-center">
          <Trophy className="w-8 h-8" />
          {swissStatus === 'finished' ? (
            <>
              <span className="text-sm">El Torneo Oficial ya finalizó — todavía no se generó el cuadro de playoffs.</span>
              {isAdmin ? (
                <>
                  <span className="text-xs text-gray-700 max-w-md">Se arma solo, tomando la clasificación final del Torneo Oficial (mejor récord primero, menos muertes como desempate) y sembrándola en un cuadro de eliminación directa.</span>
                  {error && <p className="text-xs text-red-400">{error}</p>}
                  <button type="button" onClick={handleGenerate} disabled={busy} className="flex items-center gap-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors">
                    <Trophy className="w-4 h-4" /> Generar playoffs
                  </button>
                </>
              ) : (
                <span className="text-xs text-gray-700">El administrador todavía no generó los playoffs.</span>
              )}
            </>
          ) : (
            <span className="text-sm">Los playoffs se generan automáticamente en cuanto el administrador finalice el Torneo Oficial (sección "Torneo Oficial").</span>
          )}
        </Panel>
      </div>
    );
  }

  const roundLabels = bracketRoundLabels(displayRounds.length);
  const slotCount = displayRounds[0]?.length * 2 || 0;
  const champion = displayRounds[displayRounds.length - 1][0]?.winner;
  const colHeight = (slotCount / 2) * BRACKET_SLOT_HEIGHT;

  return (
    <div className="space-y-4">
      <Panel>
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
          <div>
            <h2 className="font-display text-xl font-bold text-white flex items-center gap-2 tracking-wide"><Trophy className="w-5 h-5 text-amber-400" /> PLAYOFFS · CUADRO DE {slotCount}</h2>
            <p className="text-sm text-gray-500 mt-1">
              Eliminación directa a partido único · sembrado con la clasificación final del Torneo Oficial.
              {isAdmin ? ' Toca un jugador para avanzarlo de ronda.' : ' Solo el administrador puede cargar resultados aquí.'}
            </p>
          </div>
          <div className="flex items-center gap-2">
            {champion && (
              <div className="flex items-center gap-2 bg-amber-500/10 border border-amber-500/30 rounded-lg px-3 py-2 animate-scale-in">
                <Trophy className="w-5 h-5 text-amber-400" />
                <div>
                  <div className="text-[10px] text-amber-500 uppercase tracking-wider">Campeón</div>
                  <div className="text-sm font-semibold text-amber-300">{champion.name}</div>
                </div>
              </div>
            )}
            {isAdmin && (
              <div className="flex items-center gap-2">
                <button type="button" onClick={handleGenerate} disabled={busy} className="text-xs text-amber-400 hover:text-amber-300 disabled:opacity-50 px-2 press-feedback">Regenerar</button>
                <button type="button" onClick={handleReset} disabled={busy} className="text-xs text-red-400 hover:text-red-300 disabled:opacity-50 px-2 press-feedback">Reiniciar</button>
              </div>
            )}
          </div>
        </div>
        {error && <p className="text-xs text-red-400 mt-2 animate-fade-in-up">{error}</p>}
      </Panel>

      <Panel className="overflow-x-auto">
        <div ref={containerRef} className="relative inline-flex gap-10 min-w-full" style={{ minHeight: colHeight + 40 }}>
          <BracketLines lines={lines} hoveredName={hoveredName} />
          {displayRounds.map((round, ri) => (
            <div key={ri} className="flex flex-col shrink-0" style={{ width: 192 }}>
              <div className="text-center mb-3">
                <span className="text-xs font-bold uppercase tracking-wider font-mono-data" style={{ color: BRACKET_ROUND_COLORS[ri] }}>{roundLabels[ri]}</span>
              </div>
              <div className="flex flex-col justify-around flex-1" style={{ height: colHeight }}>
                {round.map((m, mi) => (
                  <BracketMatchCard
                    key={m.id}
                    match={m}
                    roundIndex={ri}
                    matchIndex={mi}
                    color={BRACKET_ROUND_COLORS[ri]}
                    hoveredName={hoveredName}
                    onHover={setHoveredName}
                    onSetWinner={handleSetWinner}
                    cardRef={setCardRef(`${ri}-${mi}`)}
                    editable={isAdmin}
                  />
                ))}
              </div>
            </div>
          ))}
          {champion && (
            <div className="flex flex-col justify-center shrink-0" style={{ width: 160 }}>
              <div className="flex flex-col items-center gap-2 bg-gradient-to-b from-amber-500/15 to-transparent border border-amber-500/40 rounded-xl p-4 animate-scale-in hover-lift">
                <Trophy className="w-8 h-8 text-amber-400" />
                <Avatar name={champion.name} color={champion.color} size="w-10 h-10 text-base" />
                <span className="text-sm font-semibold text-amber-300 text-center">{champion.name}</span>
              </div>
            </div>
          )}
        </div>
      </Panel>
    </div>
  );
}

/* ============================== TORNEO OFICIAL (BRACKET SUIZO) ============================== */

function computeSwissRecords(bracket) {
  const records = {};
  (bracket.participantIds || []).forEach((id) => { records[id] = { wins: 0, losses: 0 }; });
  (bracket.rounds || []).forEach((round) => {
    round.matches.forEach((m) => {
      if (!m.winner) return;
      const loser = m.winner === m.playerA ? m.playerB : m.playerA;
      if (records[m.winner]) records[m.winner].wins += 1;
      if (loser && records[loser]) records[loser].losses += 1;
    });
  });
  return records;
}

function SwissParticipantChip({ userId, userMap, isWinner, isMoveSource, dimmed }) {
  const u = userId ? userMap[userId] : null;
  if (!userId) {
    return <div className="flex items-center px-2 py-1.5 rounded-lg border border-dashed border-gray-800 text-xs text-gray-600 h-[32px]">BYE</div>;
  }
  if (!u) {
    return <div className="flex items-center px-2 py-1.5 rounded-lg border border-dashed border-gray-800 text-xs text-gray-700 italic h-[32px]">Desconocido</div>;
  }
  return (
    <div className={`flex items-center gap-1.5 px-2 py-1.5 rounded-lg border text-xs font-mono-data h-[32px] transition-all ${
      isWinner ? 'border-amber-400 bg-amber-500/10 text-amber-300 font-semibold' : 'border-gray-700 bg-gray-800/60 text-gray-300'
    } ${isMoveSource ? 'ring-2 ring-sky-400' : ''} ${dimmed ? 'opacity-40' : ''}`}
    >
      <Avatar name={u.name} color={u.color} size="w-5 h-5" />
      <span className="truncate flex-1">{u.name}</span>
      {isWinner && <Trophy className="w-3 h-3 text-amber-400 shrink-0 animate-scale-in" />}
    </div>
  );
}

function SwissMatchCard({ match, userMap, editable, onSetWinner, moveSource, onMoveClick }) {
  const clickableResult = editable && match.playerA && match.playerB;
  return (
    <div className="flex flex-col gap-1 bg-gray-900/70 border border-gray-800 rounded-xl p-1.5" style={{ width: 190 }}>
      {['playerA', 'playerB'].map((slot) => {
        const playerId = match[slot];
        const isSrc = moveSource && moveSource.matchId === match.id && moveSource.slot === slot;
        return (
          <div key={slot} className="flex items-center gap-1">
            <div className="flex-1">
              <SwissParticipantChip userId={playerId} userMap={userMap} isWinner={Boolean(match.winner && match.winner === playerId)} isMoveSource={isSrc} />
            </div>
            {editable && (
              <div className="flex flex-col gap-0.5 shrink-0">
                <button
                  type="button"
                  title="Marcar como ganador"
                  disabled={!clickableResult}
                  onClick={() => onSetWinner(match.id, match.winner === playerId ? null : playerId)}
                  className={`p-1 rounded border press-feedback ${clickableResult ? 'border-gray-700 text-gray-400 hover:text-amber-400 hover:border-amber-500' : 'border-gray-900 text-gray-800 cursor-not-allowed'}`}
                >
                  <Trophy className="w-3 h-3" />
                </button>
                <button
                  type="button"
                  title="Mover a otro combate"
                  onClick={() => onMoveClick(match.id, slot, playerId)}
                  className={`p-1 rounded border press-feedback ${isSrc ? 'border-sky-400 text-sky-300' : 'border-gray-700 text-gray-400 hover:text-sky-400 hover:border-sky-500'}`}
                >
                  <Move className="w-3 h-3" />
                </button>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function SwissBracketView({ users, role, bracket, loading, onCreate, onSetWinner, onSwap, onAdvanceRound, onFinish, onReset, playoff, onGeneratePlayoff, onGoToPlayoffs }) {
  const isAdmin = role === 'Administrador';
  const userMap = useMemo(() => Object.fromEntries(users.map((u) => [u.id, u])), [users]);

  const [selected, setSelected] = useState([]);
  const [title, setTitle] = useState('Torneo Oficial');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [moveSource, setMoveSource] = useState(null);

  function toggleSelected(id) {
    setSelected((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function handleCreate() {
    if (selected.length < 2) { setError('Selecciona al menos 2 participantes.'); return; }
    setBusy(true);
    setError('');
    try {
      await onCreate(title, selected);
      setSelected([]);
    } catch (err) {
      setError(err.message || 'No se pudo crear el torneo.');
    } finally {
      setBusy(false);
    }
  }

  async function handleSetWinner(matchId, winnerId) {
    setError('');
    try {
      await onSetWinner(matchId, winnerId);
    } catch (err) {
      setError(err.message || 'No se pudo guardar el resultado.');
    }
  }

  function handleMoveClick(matchId, slot, playerId) {
    if (!moveSource) {
      setMoveSource({ matchId, slot, playerId });
      return;
    }
    if (moveSource.matchId === matchId && moveSource.slot === slot) {
      setMoveSource(null);
      return;
    }
    const src = moveSource;
    setMoveSource(null);
    onSwap(src.matchId, src.slot, matchId, slot).catch((err) => setError(err.message || 'No se pudo mover al jugador.'));
  }

  async function handleAdvance() {
    setBusy(true);
    setError('');
    try {
      await onAdvanceRound();
    } catch (err) {
      setError(err.message || 'No se pudo generar la siguiente fecha.');
    } finally {
      setBusy(false);
    }
  }

  async function handleFinish() {
    setBusy(true);
    setError('');
    try {
      await onFinish();
    } catch (err) {
      setError(err.message || 'No se pudo finalizar el torneo.');
    } finally {
      setBusy(false);
    }
  }

  async function handleReset() {
    if (!window.confirm('Esto borra el torneo actual por completo. ¿Continuar?')) return;
    setBusy(true);
    setError('');
    try {
      await onReset();
      setSelected([]);
    } catch (err) {
      setError(err.message || 'No se pudo reiniciar el torneo.');
    } finally {
      setBusy(false);
    }
  }

  async function handleGeneratePlayoffs() {
    setBusy(true);
    setError('');
    try {
      await onGeneratePlayoff();
      if (onGoToPlayoffs) onGoToPlayoffs();
    } catch (err) {
      setError(err.message || 'No se pudo generar el cuadro de playoffs.');
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return <Panel><LoadingState /></Panel>;
  }

  if (!bracket) {
    if (!isAdmin) {
      return (
        <Panel className="flex flex-col items-center justify-center gap-2 py-14 text-gray-600 border-dashed">
          <Shuffle className="w-8 h-8" />
          <span className="text-sm">El administrador todavía no inició el Torneo Oficial.</span>
        </Panel>
      );
    }
    return (
      <div className="space-y-4">
        <Panel>
          <h2 className="font-display text-xl font-bold text-white flex items-center gap-2 tracking-wide"><Shuffle className="w-5 h-5 text-amber-400" /> TORNEO OFICIAL · SISTEMA SUIZO</h2>
          <p className="text-sm text-gray-500 mt-1">Elige quiénes participan. La Fecha 1 se empareja al azar; desde la Fecha 2, cada participante enfrenta rivales con su mismo récord — igual que en un torneo suizo real.</p>
        </Panel>
        <Panel>
          <h3 className="text-white font-semibold mb-3">Configurar torneo</h3>
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Título del torneo" className={`${inputClass} w-full mb-3`} />
          {users.length === 0 ? (
            <p className="text-sm text-gray-600">Todavía no hay participantes creados.</p>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 mb-3">
              {users.map((u) => (
                <button
                  type="button"
                  key={u.id}
                  onClick={() => toggleSelected(u.id)}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border text-sm transition-colors press-feedback ${selected.includes(u.id) ? 'bg-blue-600/20 border-blue-500 text-blue-300' : 'bg-gray-800/60 border-gray-700 text-gray-400 hover:text-gray-200'}`}
                >
                  <Avatar name={u.name} color={u.color} />
                  {u.name}
                </button>
              ))}
            </div>
          )}
          {error && <p className="text-xs text-red-400 mb-2">{error}</p>}
          <button
            type="button"
            onClick={handleCreate}
            disabled={busy || selected.length < 2}
            className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors press-feedback"
          >
            <Shuffle className="w-4 h-4" /> Iniciar torneo ({selected.length} seleccionados)
          </button>
        </Panel>
      </div>
    );
  }

  const records = computeSwissRecords(bracket);
  const currentRound = bracket.rounds[bracket.rounds.length - 1];
  const currentRoundComplete = currentRound.matches.every((m) => m.isBye || m.winner);
  const standings = [...bracket.participantIds].sort((a, b) => {
    const ra = records[a] || { wins: 0, losses: 0 };
    const rb = records[b] || { wins: 0, losses: 0 };
    if (ra.wins !== rb.wins) return rb.wins - ra.wins;
    return ra.losses - rb.losses;
  });

  const finalGroups = new Map();
  if (bracket.status === 'finished') {
    standings.forEach((id) => {
      const r = records[id] || { wins: 0, losses: 0 };
      const key = `${r.wins}-${r.losses}`;
      if (!finalGroups.has(key)) finalGroups.set(key, []);
      finalGroups.get(key).push(id);
    });
  }

  return (
    <div className="space-y-4">
      <Panel>
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
          <div>
            <h2 className="font-display text-xl font-bold text-white flex items-center gap-2 tracking-wide"><Shuffle className="w-5 h-5 text-amber-400" /> {bracket.title.toUpperCase()}</h2>
            <p className="text-sm text-gray-500 mt-1">
              {bracket.participantIds.length} participantes · {bracket.rounds.length} fecha{bracket.rounds.length === 1 ? '' : 's'} jugada{bracket.rounds.length === 1 ? '' : 's'}
              {bracket.status === 'finished' ? ' · Torneo finalizado' : ''}
            </p>
          </div>
          {isAdmin && (
            <div className="flex flex-wrap items-center gap-2">
              {bracket.status === 'active' && (
                <button type="button" onClick={handleAdvance} disabled={busy || !currentRoundComplete} className="flex items-center gap-1.5 bg-amber-600 hover:bg-amber-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors press-feedback">
                  Generar siguiente fecha
                </button>
              )}
              {bracket.status === 'active' && (
                <button type="button" onClick={handleFinish} disabled={busy || !currentRoundComplete} className="flex items-center gap-1.5 bg-emerald-700 hover:bg-emerald-600 disabled:opacity-40 disabled:cursor-not-allowed text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors press-feedback">
                  <Trophy className="w-3.5 h-3.5" /> Finalizar torneo
                </button>
              )}
              <button type="button" onClick={handleReset} disabled={busy} className="text-xs text-red-400 hover:text-red-300 disabled:opacity-50 px-2 press-feedback">Reiniciar</button>
            </div>
          )}
        </div>
        {isAdmin && (
          <p className="text-xs text-gray-600 mt-3">
            Usa el trofeo <Trophy className="w-3 h-3 inline text-gray-500" /> para marcar al ganador de un combate, y la flecha <Move className="w-3 h-3 inline text-gray-500" /> para mover a un jugador a cualquier otro puesto: tócala una vez sobre el jugador de origen, y otra vez sobre el puesto destino.
          </p>
        )}
        {error && <p className="text-xs text-red-400 mt-2">{error}</p>}
      </Panel>

      <Panel className="overflow-x-auto">
        <div className="flex gap-6 min-w-full">
          {bracket.rounds.map((round, ri) => (
            <div key={ri} className="flex flex-col gap-2 shrink-0" style={{ width: 190 }}>
              <div className="text-center mb-1">
                <span className="text-xs font-bold uppercase tracking-wider font-mono-data text-amber-400">{round.label}</span>
              </div>
              {round.matches.map((m) => (
                <SwissMatchCard
                  key={m.id}
                  match={m}
                  userMap={userMap}
                  editable={isAdmin && bracket.status === 'active'}
                  onSetWinner={handleSetWinner}
                  moveSource={moveSource}
                  onMoveClick={handleMoveClick}
                />
              ))}
            </div>
          ))}
        </div>
      </Panel>

      <Panel>
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><BarChart3 className="w-4 h-4 text-amber-400" /> Tabla de posiciones</h3>
        <div className="space-y-1.5">
          {standings.map((id, i) => {
            const u = userMap[id];
            const r = records[id] || { wins: 0, losses: 0 };
            if (!u) return null;
            return (
              <div key={id} className="flex items-center gap-2.5 bg-gray-800/40 rounded-lg px-3 py-1.5 animate-fade-in-up" style={{ animationDelay: `${i * 30}ms` }}>
                <Avatar name={u.name} color={u.color} />
                <span className="text-sm text-gray-200 flex-1 truncate">{u.name}</span>
                <span className="font-mono-data text-sm text-gray-400">{r.wins}-{r.losses}</span>
              </div>
            );
          })}
        </div>
      </Panel>

      {bracket.status === 'finished' && (
        <Panel className="border-amber-800/60 bg-amber-950/10">
          <h3 className="text-amber-300 font-semibold mb-3 flex items-center gap-2"><Trophy className="w-4 h-4" /> Clasificación final</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {[...finalGroups.entries()].map(([record, ids], i) => (
              <div key={record} className="bg-gray-900/60 border border-gray-800 rounded-xl p-3 hover-lift animate-fade-in-up" style={{ animationDelay: `${i * 60}ms` }}>
                <div className="text-xs font-mono-data text-amber-400 mb-2">Récord {record}</div>
                <div className="space-y-1">
                  {ids.map((id) => {
                    const u = userMap[id];
                    if (!u) return null;
                    return (
                      <div key={id} className="flex items-center gap-2 text-sm text-gray-300">
                        <Avatar name={u.name} color={u.color} size="w-5 h-5" />
                        {u.name}
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
          {isAdmin && (
            <div className="mt-4 pt-4 border-t border-amber-900/40 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <p className="text-xs text-gray-500 max-w-md">
                {playoff
                  ? 'Ya se generó el cuadro de playoffs a partir de esta clasificación. Podés volver a generarlo si cambiaste algún resultado.'
                  : 'Con esta clasificación final ya se puede armar el cuadro de eliminación directa (Playoffs): se siembra solo, mejor récord primero y menos muertes como desempate.'}
              </p>
              <button
                type="button"
                onClick={handleGeneratePlayoffs}
                disabled={busy}
                className="flex items-center justify-center gap-1.5 bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white text-xs font-semibold px-4 py-2 rounded-lg transition-colors shrink-0 press-feedback"
              >
                <Trophy className="w-3.5 h-3.5" /> {playoff ? 'Regenerar playoffs' : 'Generar playoffs con esta clasificación'}
              </button>
            </div>
          )}
        </Panel>
      )}
    </div>
  );
}

/* ============================== RULETA ============================== */

const ROULETTE_COLORS = { premio: '#f59e0b', castigo: '#dc2626', neutro: '#4b5563' };

function segmentAngles(segments) {
  const total = segments.reduce((a, s) => a + Number(s.pct || 0), 0) || 1;
  let acc = 0;
  return segments.map((s) => {
    const sweep = (Number(s.pct || 0) / total) * 360;
    const entry = { ...s, start: acc, sweep };
    acc += sweep;
    return entry;
  });
}

function pickWeighted(segments) {
  const total = segments.reduce((a, s) => a + Number(s.pct || 0), 0) || 1;
  let r = Math.random() * total;
  for (const s of segments) {
    if (r < Number(s.pct || 0)) return s;
    r -= Number(s.pct || 0);
  }
  return segments[segments.length - 1];
}

function RouletteView({ role, segments, onSegmentsChange, animated, onAnimatedChange, history, onSpinResult }) {
  const isAdmin = role === 'Administrador';
  const [angle, setAngle] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const [result, setResult] = useState(null);
  const [configOpen, setConfigOpen] = useState(false);
  const withAngles = useMemo(() => segmentAngles(segments), [segments]);
  const totalPct = segments.reduce((a, s) => a + Number(s.pct || 0), 0);
  const duration = animated ? 4000 : 150;

  function spin() {
    if (spinning) return;
    setSpinning(true);
    setResult(null);
    const chosen = pickWeighted(segments);
    const chosenWithAngle = withAngles.find((s) => s.id === chosen.id);
    const target = 360 - chosenWithAngle.start - chosenWithAngle.sweep / 2;
    const finalAngle = angle - (angle % 360) + 5 * 360 + target;
    setAngle(finalAngle);
    setTimeout(() => {
      setSpinning(false);
      setResult(chosen);
      onSpinResult({ ...chosen, time: new Date().toLocaleTimeString() });
    }, duration);
  }

  function updateSegment(id, patch) {
    onSegmentsChange(segments.map((s) => (s.id === id ? { ...s, ...patch } : s)));
  }
  function removeSegment(id) {
    onSegmentsChange(segments.filter((s) => s.id !== id));
  }
  function addSegment() {
    const nextId = Math.max(0, ...segments.map((s) => s.id)) + 1;
    onSegmentsChange([...segments, { id: nextId, label: 'Nuevo premio', type: 'premio', pct: 5 }]);
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Panel className="flex flex-col items-center gap-6 py-8">
          <div className="relative w-64 h-64">
            <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-0 h-0 border-l-8 border-r-8 border-b-8 border-l-transparent border-r-transparent border-b-amber-400 z-10" />
            <svg viewBox="0 0 200 200" className="w-full h-full" style={{ transform: `rotate(${angle}deg)`, transition: `transform ${duration}ms cubic-bezier(0.15,0.65,0.15,1)` }}>
              {withAngles.map((s) => {
                const start = s.start;
                const end = s.start + s.sweep;
                const x1 = 100 + 95 * Math.cos((Math.PI * (start - 90)) / 180);
                const y1 = 100 + 95 * Math.sin((Math.PI * (start - 90)) / 180);
                const x2 = 100 + 95 * Math.cos((Math.PI * (end - 90)) / 180);
                const y2 = 100 + 95 * Math.sin((Math.PI * (end - 90)) / 180);
                const large = s.sweep > 180 ? 1 : 0;
                return <path key={s.id} d={`M100,100 L${x1},${y1} A95,95 0 ${large} 1 ${x2},${y2} Z`} fill={ROULETTE_COLORS[s.type]} stroke="#000" strokeWidth="1" opacity="0.88" />;
              })}
              <circle cx="100" cy="100" r="18" fill="#111827" stroke="#f59e0b" strokeWidth="2" />
            </svg>
          </div>
          <button type="button" onClick={spin} disabled={spinning} className="bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-semibold px-6 py-2.5 rounded-lg transition-colors press-feedback">
            {spinning ? 'Girando…' : 'Girar ruleta'}
          </button>
          {result && !spinning && (
            <div className="text-center animate-scale-in">
              <div className="text-xs text-gray-500 uppercase tracking-wider">Resultado</div>
              <div className={`font-display text-lg font-bold ${result.type === 'premio' ? 'text-amber-400' : result.type === 'castigo' ? 'text-red-400' : 'text-gray-400'}`}>{result.label}</div>
            </div>
          )}
          {isAdmin && (
            <label className="flex items-center gap-2 text-xs text-gray-400 cursor-pointer select-none">
              <input type="checkbox" checked={animated} onChange={(e) => onAnimatedChange(e.target.checked)} className="accent-blue-600" />
              Animación de giro activada
            </label>
          )}
        </Panel>

        <Panel>
          <h3 className="text-white font-semibold mb-3">Historial de tiradas</h3>
          {history.length === 0 ? (
            <p className="text-sm text-gray-600">Aún no hay tiradas registradas.</p>
          ) : (
            <div className="space-y-2 max-h-64 overflow-y-auto pr-1">
              {history.map((h, i) => (
                <div key={i} className="flex items-center justify-between text-sm bg-gray-800/40 rounded-lg px-3 py-2 animate-fade-in-up" style={{ animationDelay: `${Math.min(i, 10) * 30}ms` }}>
                  <span className={h.type === 'premio' ? 'text-amber-400' : h.type === 'castigo' ? 'text-red-400' : 'text-gray-400'}>{h.label}</span>
                  <span className="font-mono-data text-gray-600 text-xs">{h.time}</span>
                </div>
              ))}
            </div>
          )}
          <p className="text-xs text-gray-600 mt-4">{isAdmin ? 'Como administrador puedes configurar premios, castigos y porcentajes abajo.' : 'Los administradores pueden configurar premios, castigos y porcentajes desde su panel.'}</p>
        </Panel>
      </div>

      {isAdmin && (
        <Panel>
          <button type="button" onClick={() => setConfigOpen((o) => !o)} className="w-full flex items-center justify-between text-white font-semibold">
            <span className="flex items-center gap-2"><Dices className="w-4 h-4 text-amber-400" /> Configurar premios y castigos</span>
            <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform ${configOpen ? 'rotate-180' : ''}`} />
          </button>
          {configOpen && (
            <div className="mt-4 space-y-2 animate-fade-in-up">
              {segments.map((s, i) => (
                <div key={s.id} className="flex flex-wrap items-center gap-2 bg-gray-800/40 rounded-lg px-3 py-2 animate-fade-in-up" style={{ animationDelay: `${i * 30}ms` }}>
                  <input value={s.label} onChange={(e) => updateSegment(s.id, { label: e.target.value })} className={`${inputClass} flex-1 min-w-[10rem]`} />
                  <select value={s.type} onChange={(e) => updateSegment(s.id, { type: e.target.value })} className={inputClass}>
                    <option value="premio">Premio</option>
                    <option value="castigo">Castigo</option>
                    <option value="neutro">Neutro</option>
                  </select>
                  <div className="flex items-center gap-1">
                    <input type="number" min="0" max="100" value={s.pct} onChange={(e) => updateSegment(s.id, { pct: Number(e.target.value) })} className={`${inputClass} w-16`} />
                    <span className="text-xs text-gray-500">%</span>
                  </div>
                  <button type="button" onClick={() => removeSegment(s.id)} className="text-xs text-red-400 hover:text-red-300 px-2">Eliminar</button>
                </div>
              ))}
              <div className="flex items-center justify-between pt-1">
                <button type="button" onClick={addSegment} className="flex items-center gap-1.5 text-xs font-semibold text-amber-400 hover:text-amber-300">
                  <Plus className="w-3.5 h-3.5" /> Añadir segmento
                </button>
                <span className={`text-xs font-mono-data ${totalPct === 100 ? 'text-emerald-400' : 'text-red-400'}`}>Total: {totalPct}% {totalPct !== 100 && '(debería sumar 100%)'}</span>
              </div>
            </div>
          )}
        </Panel>
      )}
    </div>
  );
}

/* ============================== NORMAS ============================== */

function RulesView({ role, content, onSave }) {
  const isAdmin = role === 'Administrador';
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(content);

  useEffect(() => { if (!editing) setDraft(content); }, [content, editing]);

  function startEditing() { setDraft(content); setEditing(true); }
  function save() { onSave(draft); setEditing(false); }
  function cancel() { setDraft(content); setEditing(false); }

  return (
    <div className="space-y-4">
      <Panel>
        <div className="flex items-center justify-between mb-4 gap-2">
          <h2 className="text-white font-semibold">Normas del Torneo</h2>
          {isAdmin && (
            editing ? (
              <div className="flex items-center gap-2 animate-fade-in-up">
                <button type="button" onClick={cancel} className="text-xs text-gray-400 hover:text-gray-200 px-3 py-1.5 press-feedback">Cancelar</button>
                <button type="button" onClick={save} className="bg-blue-600 hover:bg-blue-500 text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors press-feedback">Guardar normas</button>
              </div>
            ) : (
              <button type="button" onClick={startEditing} className="text-xs font-semibold text-amber-400 hover:text-amber-300 press-feedback">Editar normas</button>
            )
          )}
        </div>

        {editing ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 animate-fade-in-up">
            <div>
              <span className="text-xs text-gray-600 uppercase tracking-wider">Editor Markdown</span>
              <textarea
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                rows={18}
                className={`${inputClass} w-full mt-1.5 font-mono-data text-xs leading-relaxed resize-y`}
              />
              <p className="text-xs text-gray-600 mt-1.5">Admite listas, tablas, negrita/cursiva, imágenes <code className="text-gray-500">![alt](url)</code> y vídeos <code className="text-gray-500">!video[alt](url)</code>.</p>
            </div>
            <div>
              <span className="text-xs text-gray-600 uppercase tracking-wider">Vista previa</span>
              <div className="mt-1.5 bg-gray-950/50 border border-gray-800 rounded-lg p-4 max-h-[28rem] overflow-y-auto">
                <MarkdownView markdown={draft} />
              </div>
            </div>
          </div>
        ) : (
          <MarkdownView markdown={content} />
        )}
      </Panel>
    </div>
  );
}

/* ============================== ESTADÍSTICAS ============================== */

function UsageBarChart({ data }) {
  const max = Math.max(...data.map((d) => d.usos));
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    const raf = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(raf);
  }, []);
  return (
    <div className="flex items-end gap-4 h-44">
      {data.map((d, i) => (
        <div key={d.name} className="flex-1 flex flex-col items-center gap-2 group">
          <span className="font-mono-data text-xs text-gray-400"><AnimatedCounter value={d.usos} /></span>
          <div className="w-full h-32 bg-gray-800 rounded-t-md flex items-end overflow-hidden">
            <div
              className="w-full bg-gradient-to-t from-red-700 to-amber-500 rounded-t-md transition-all duration-700 group-hover:brightness-110"
              style={{ height: mounted ? `${(d.usos / max) * 100}%` : '0%', transitionDelay: `${i * 80}ms` }}
            />
          </div>
          <span className="text-xs text-gray-500 text-center">{d.name}</span>
        </div>
      ))}
    </div>
  );
}

function StatsView({ users }) {
  if (users.length === 0) {
    return (
      <Panel className="flex flex-col items-center justify-center gap-2 py-14 text-gray-600 border-dashed">
        <BarChart3 className="w-8 h-8" />
        <span className="text-sm">Sin datos todavía — añade participantes para ver estadísticas.</span>
      </Panel>
    );
  }

  const maxDeaths = Math.max(...users.map((p) => p.deaths));
  const minDeaths = Math.min(...users.map((p) => p.deaths));
  const mostDeaths = users.find((p) => p.deaths === maxDeaths);
  const leastDeaths = users.find((p) => p.deaths === minDeaths);
  const totalWins = users.reduce((a, p) => a + p.wins, 0);
  const totalLosses = users.reduce((a, p) => a + p.losses, 0);
  const winrate = totalWins + totalLosses > 0 ? Math.round((totalWins / (totalWins + totalLosses)) * 100) : 0;

  const usageCount = {};
  users.forEach((u) => u.routes.forEach((r) => {
    if (!r.pokemonName) return;
    const key = r.pokemonName.trim();
    if (!key) return;
    usageCount[key] = (usageCount[key] || 0) + 1;
  }));
  const usageData = Object.entries(usageCount)
    .map(([name, usos]) => ({ name, usos }))
    .sort((a, b) => b.usos - a.usos)
    .slice(0, 5);

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Panel className="hover-lift"><div className="text-xs text-gray-500 mb-1">Menos muertes</div><div className="font-semibold text-emerald-400">{leastDeaths?.name} · <span className="font-mono-data">{minDeaths}/{MAX_DEATHS}</span></div></Panel>
        <Panel className="hover-lift" style={{ animationDelay: '60ms' }}><div className="text-xs text-gray-500 mb-1">Más muertes</div><div className="font-semibold text-red-400">{mostDeaths?.name} · <span className="font-mono-data">{maxDeaths}/{MAX_DEATHS}</span></div></Panel>
        <Panel className="hover-lift" style={{ animationDelay: '120ms' }}><div className="text-xs text-gray-500 mb-1">Winrate global</div><div className="font-mono-data font-semibold text-amber-400"><AnimatedCounter value={winrate} />%</div></Panel>
      </div>
      <Panel>
        <h3 className="text-white font-semibold mb-4">Pokémon más utilizados</h3>
        {usageData.length === 0 ? <p className="text-sm text-gray-600">Aún no se ha registrado ninguna captura.</p> : <UsageBarChart data={usageData} />}
      </Panel>
      <Panel><p className="text-sm text-gray-500">Panel completo en construcción: naturalezas y habilidades más comunes, rutas con más bajas, comparador de jugadores.</p></Panel>
    </div>
  );
}

/* ============================== ADMINISTRADOR (STUB) ============================== */

const ADMIN_CATEGORIES = [
  {
    label: 'Torneo',
    items: [
      { label: 'Editar resultados', icon: Swords },
      { label: 'Crear combates', icon: Swords },
      { label: 'Abrir / cerrar rondas', icon: Clock },
    ],
  },
  {
    label: 'Datos de juego',
    items: [
      { label: 'Editar Pokémon y capturas', icon: Search },
      { label: 'Editar estadísticas', icon: BarChart3 },
    ],
  },
  {
    label: 'Contenido',
    items: [
      { label: 'Registro de auditoría', icon: ShieldCheck },
    ],
  },
];

function CoinControls({ user, onGiveCoins }) {
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [localError, setLocalError] = useState('');
  const [history, setHistory] = useState(null);
  const [showHistory, setShowHistory] = useState(false);

  async function apply(sign) {
    const n = Math.abs(Number(amount));
    if (!n || Number.isNaN(n)) { setLocalError('Escribe una cantidad de monedas.'); return; }
    setBusy(true);
    setLocalError('');
    try {
      await onGiveCoins(user.id, sign * n, reason.trim());
      setAmount('');
      setReason('');
      if (showHistory) loadHistory();
    } catch (err) {
      setLocalError(err.message || 'No se pudo actualizar el saldo.');
    } finally {
      setBusy(false);
    }
  }

  async function loadHistory() {
    try {
      const data = await api.getCoinHistory(user.id);
      setHistory(data);
    } catch {
      setHistory([]);
    }
  }

  function toggleHistory() {
    setShowHistory((v) => !v);
    if (!history) loadHistory();
  }

  return (
    <div className="flex flex-col gap-2 bg-gray-800/40 rounded-lg px-3 py-2 hover-lift">
      <div className="flex items-center gap-2.5">
        <Avatar name={user.name} color={user.color} />
        <span className="text-sm text-gray-200 flex-1 truncate">{user.name}</span>
        <span className="flex items-center gap-1 text-xs font-mono-data text-amber-300 bg-amber-950/40 border border-amber-800/40 rounded-full px-2 py-0.5">
          <Coins className="w-3 h-3" /> <AnimatedCounter value={user.coins ?? 0} />
        </span>
        <button type="button" onClick={toggleHistory} title="Ver historial de monedas" className="text-gray-500 hover:text-amber-300 hover:scale-110 active:scale-90 transition-transform duration-150">
          <History className="w-4 h-4" />
        </button>
      </div>
      <div className="flex flex-wrap items-center gap-1.5">
        <input
          type="number"
          min="0"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="Cantidad"
          className={`${inputClass} w-24`}
        />
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Motivo (opcional)"
          className={`${inputClass} flex-1 min-w-[8rem]`}
        />
        <button type="button" disabled={busy} onClick={() => apply(1)} className="flex items-center gap-1 bg-emerald-700/80 hover:bg-emerald-600 text-white text-xs font-semibold px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50 press-feedback">
          <Plus className="w-3.5 h-3.5" /> Dar
        </button>
        <button type="button" disabled={busy} onClick={() => apply(-1)} className="flex items-center gap-1 bg-red-800/80 hover:bg-red-700 text-white text-xs font-semibold px-2.5 py-1.5 rounded-lg transition-colors disabled:opacity-50 press-feedback">
          <Minus className="w-3.5 h-3.5" /> Quitar
        </button>
      </div>
      {localError && <p className="text-xs text-red-400 animate-fade-in-up">{localError}</p>}
      {showHistory && (
        <div className="mt-1 border-t border-gray-800 pt-2 animate-fade-in-up">
          {history === null ? (
            <LoadingState label="Cargando historial…" />
          ) : history.length === 0 ? (
            <p className="text-xs text-gray-600">Sin movimientos todavía.</p>
          ) : (
            <ul className="space-y-1 max-h-32 overflow-y-auto">
              {history.map((h, i) => (
                <li key={h.id} className="text-[11px] text-gray-500 flex items-center justify-between gap-2 animate-fade-in-up" style={{ animationDelay: `${Math.min(i, 8) * 25}ms` }}>
                  <span className={h.delta > 0 ? 'text-emerald-400' : 'text-red-400'}>
                    {h.delta > 0 ? '+' : ''}{h.delta} {h.reason && `— ${h.reason}`}
                  </span>
                  <span className="text-gray-600 shrink-0">{new Date(h.createdAt).toLocaleDateString()}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function AdminStub({ news, onAddNews, users, onAddUser, onDeleteUser, onGiveCoins }) {
  const [draftTitle, setDraftTitle] = useState('');
  const [newName, setNewName] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submitNews() {
    if (!draftTitle.trim()) return;
    try {
      await onAddNews(draftTitle.trim());
      setDraftTitle('');
    } catch (err) {
      setError(err.message || 'No se pudo publicar la noticia.');
    }
  }

  async function submitUser() {
    const name = newName.trim();
    if (!name || !newPassword) { setError('Escribe un nombre y una contraseña.'); return; }
    if (users.some((u) => u.name.toLowerCase() === name.toLowerCase())) { setError('Ya existe un participante con ese nombre.'); return; }
    setBusy(true);
    setError('');
    try {
      await onAddUser({ name, password: newPassword });
      setNewName('');
      setNewPassword('');
    } catch (err) {
      setError(err.message || 'No se pudo crear el participante.');
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(id) {
    try {
      await onDeleteUser(id);
    } catch (err) {
      setError(err.message || 'No se pudo eliminar el participante.');
    }
  }

  return (
    <div className="space-y-4">
      <Panel className="border-amber-900/50 bg-amber-950/10">
        <p className="text-sm text-amber-400 flex items-center gap-2"><ShieldCheck className="w-4 h-4" /> Panel visible solo para el perfil de Administrador.</p>
      </Panel>

      <Panel>
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><Users className="w-4 h-4 text-amber-400" /> Añadir participante</h3>
        <p className="text-xs text-gray-500 mb-3">Al crearlo recibe automáticamente su ficha Nuzlocke con las {KALOS_LOCATIONS.length} zonas de Kalos, lista para rellenar. Pásale el nombre y la contraseña para que inicie sesión.</p>
        <div className="flex flex-col sm:flex-row gap-2 mb-2">
          <input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Nombre de usuario…" className={`${inputClass} flex-1`} />
          <input value={newPassword} onChange={(e) => setNewPassword(e.target.value)} placeholder="Contraseña…" className={`${inputClass} sm:w-48`} />
          <button type="button" onClick={submitUser} className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors shrink-0 press-feedback">
            <Plus className="w-4 h-4" /> Crear
          </button>
        </div>
        {error && <p className="text-xs text-red-400 mb-2 animate-fade-in-up">{error}</p>}

        {users.length === 0 ? (
          <p className="text-sm text-gray-600 mt-2">Aún no has añadido a nadie.</p>
        ) : (
          <div className="space-y-2 mt-3">
            {users.map((u, i) => (
              <div key={u.id} className="flex items-center gap-2.5 bg-gray-800/40 rounded-lg px-3 py-2 hover-lift animate-fade-in-up" style={{ animationDelay: `${i * 30}ms` }}>
                <Avatar name={u.name} color={u.color} />
                <span className="text-sm text-gray-200 flex-1 truncate">{u.name}</span>
                <button type="button" onClick={() => handleDelete(u.id)} className="text-xs text-red-400 hover:text-red-300 px-2 press-feedback">Eliminar</button>
              </div>
            ))}
          </div>
        )}
      </Panel>

      <Panel>
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><Coins className="w-4 h-4 text-amber-400" /> Monedas</h3>
        <p className="text-xs text-gray-500 mb-3">Dale o quítale monedas a cualquier participante. Queda guardado en Supabase con fecha y motivo, así que cada jugador ve su saldo desde cualquier dispositivo.</p>
        {users.length === 0 ? (
          <p className="text-sm text-gray-600">Todavía no hay participantes.</p>
        ) : (
          <div className="space-y-2">
            {users.map((u, i) => (
              <div key={u.id} className="animate-fade-in-up" style={{ animationDelay: `${i * 30}ms` }}>
                <CoinControls user={u} onGiveCoins={onGiveCoins} />
              </div>
            ))}
          </div>
        )}
      </Panel>

      <Panel>
        <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><Newspaper className="w-4 h-4 text-amber-400" /> Publicar noticia</h3>
        <div className="flex flex-col sm:flex-row gap-2 mb-3">
          <input
            value={draftTitle}
            onChange={(e) => setDraftTitle(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submitNews()}
            placeholder="Título de la noticia…"
            className={`${inputClass} flex-1`}
          />
          <button type="button" onClick={submitNews} className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors shrink-0 press-feedback">
            <Plus className="w-4 h-4" /> Publicar
          </button>
        </div>
        <p className="text-xs text-gray-600">Esto sí es funcional — pruébalo y luego mira Inicio, aparece arriba del todo.</p>
      </Panel>

      {ADMIN_CATEGORIES.map((cat, ci) => (
        <Panel key={cat.label} style={{ animationDelay: `${ci * 40}ms` }}>
          <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">{cat.label}</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            {cat.items.map((a) => {
              const Icon = a.icon;
              return (
                <div key={a.label} className="flex items-center gap-2.5 bg-gray-800/40 border border-gray-800 rounded-lg px-3 py-2.5 opacity-70 transition-opacity hover:opacity-90">
                  <Icon className="w-4 h-4 text-gray-500 shrink-0" />
                  <span className="text-sm text-gray-400">{a.label}</span>
                </div>
              );
            })}
          </div>
        </Panel>
      ))}

      <p className="text-xs text-gray-600">Las secciones de abajo son solo referencia visual — todavía no están conectadas a la base de datos.</p>
    </div>
  );
}

/* ============================== TIENDA ============================== */
/* Nivel 1: el jugador compra con sus monedas -> queda "pendiente" en
   Supabase (tabla purchases, ver /api/purchases.js). Todavía no se aplica
   sola al save — eso llega en la Parte 4/5 (motor + endpoint de subida). */

const SHOP_CATEGORY_LABELS = { competitivo: 'Objetos competitivos', baya: 'Bayas', objeto: 'Objetos' };
const PURCHASE_STATUS_LABELS = { pendiente: 'Pendiente', aplicada: 'Aplicada', cancelada: 'Cancelada' };
const PURCHASE_STATUS_STYLES = {
  pendiente: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
  aplicada: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
  cancelada: 'bg-gray-500/10 text-gray-500 border-gray-500/30',
};

function ShopItemCard({ item, coins, onBuy }) {
  const [qty, setQty] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const outOfStock = item.stock !== null && item.stock <= 0;
  const canAfford = coins >= item.price * qty;

  async function handleBuy() {
    setBusy(true);
    setError('');
    try {
      await onBuy(item.id, qty);
      setQty(1);
    } catch (err) {
      setError(err.message || 'No se pudo comprar.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-2 bg-gray-800/40 border border-gray-800 rounded-xl p-3 hover-lift">
      <div className="flex items-start justify-between gap-2">
        <p className="text-sm font-semibold text-gray-100">{item.name}</p>
        <span className="flex items-center gap-1 text-xs font-mono-data text-amber-300 bg-amber-950/40 border border-amber-800/40 rounded-full px-2 py-0.5 shrink-0">
          <Coins className="w-3 h-3" /> {item.price}
        </span>
      </div>
      {item.description && <p className="text-xs text-gray-500">{item.description}</p>}
      <div className="flex items-center justify-between gap-2 mt-1">
        <span className="text-[11px] text-gray-600">{item.stock === null ? 'Stock ilimitado' : `Quedan ${item.stock}`}</span>
        <div className="flex items-center gap-1.5">
          <input
            type="number" min="1" value={qty}
            onChange={(e) => setQty(Math.max(1, Number(e.target.value) || 1))}
            className={`${inputClass} w-14 text-center`}
          />
          <button
            type="button" disabled={busy || outOfStock || !canAfford} onClick={handleBuy}
            className="flex items-center gap-1 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors whitespace-nowrap press-feedback"
          >
            {busy ? 'Comprando…' : outOfStock ? 'Agotado' : !canAfford ? 'Sin monedas' : 'Comprar'}
          </button>
        </div>
      </div>
      {error && <p className="text-[11px] text-red-400 animate-fade-in-up">{error}</p>}
    </div>
  );
}

function MyPurchasesPanel({ purchases, loading }) {
  return (
    <Panel>
      <h3 className="text-white font-semibold mb-1 flex items-center gap-2"><History className="w-4 h-4 text-amber-400" /> Mis compras</h3>
      <p className="text-xs text-gray-500 mb-3">Quedan "Pendiente" hasta que subas tu save y el sistema las aplique automáticamente (próxima parte).</p>
      {loading ? (
        <LoadingState />
      ) : purchases.length === 0 ? (
        <p className="text-sm text-gray-600">Todavía no has comprado nada.</p>
      ) : (
        <div className="space-y-1.5">
          {purchases.map((p, i) => (
            <div key={p.id} className="flex items-center justify-between gap-2 bg-gray-800/40 rounded-lg px-3 py-2 animate-fade-in-up" style={{ animationDelay: `${Math.min(i, 10) * 30}ms` }}>
              <div className="min-w-0">
                <p className="text-sm text-gray-200 truncate">{p.itemName}{p.quantity > 1 && ` ×${p.quantity}`}</p>
                <p className="text-[11px] text-gray-600">{new Date(p.createdAt).toLocaleDateString()}</p>
              </div>
              <span className={`text-xs font-semibold px-2 py-1 rounded-full border whitespace-nowrap shrink-0 transition-colors ${PURCHASE_STATUS_STYLES[p.status] || PURCHASE_STATUS_STYLES.cancelada}`}>
                {PURCHASE_STATUS_LABELS[p.status] || p.status}
              </span>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function AdminAddShopItemForm({ onCreate }) {
  const blank = { itemId: '', name: '', category: 'competitivo', description: '', price: '', stock: '' };
  const [form, setForm] = useState(blank);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  function update(field, value) { setForm((f) => ({ ...f, [field]: value })); }

  async function submit() {
    setError('');
    if (!form.name.trim() || form.itemId === '' || form.price === '') {
      setError('Completa al menos nombre, item_id del juego y precio.');
      return;
    }
    setBusy(true);
    try {
      await onCreate({
        itemId: Number(form.itemId),
        name: form.name.trim(),
        category: form.category,
        description: form.description.trim(),
        price: Number(form.price),
        stock: form.stock === '' ? null : Number(form.stock),
      });
      setForm(blank);
    } catch (err) {
      setError(err.message || 'No se pudo crear el objeto.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        <input value={form.itemId} onChange={(e) => update('itemId', e.target.value)} placeholder="item_id (juego)" type="number" className={inputClass} />
        <input value={form.name} onChange={(e) => update('name', e.target.value)} placeholder="Nombre" className={`${inputClass} col-span-2 sm:col-span-1`} />
        <select value={form.category} onChange={(e) => update('category', e.target.value)} className={inputClass}>
          <option value="competitivo">Competitivo</option>
          <option value="baya">Baya</option>
          <option value="objeto">Objeto</option>
        </select>
        <input value={form.price} onChange={(e) => update('price', e.target.value)} placeholder="Precio" type="number" className={inputClass} />
      </div>
      <div className="flex flex-col sm:flex-row gap-2">
        <input value={form.description} onChange={(e) => update('description', e.target.value)} placeholder="Descripción (opcional)" className={`${inputClass} flex-1`} />
        <input value={form.stock} onChange={(e) => update('stock', e.target.value)} placeholder="Stock (vacío = ilimitado)" type="number" className={`${inputClass} sm:w-48`} />
        <button type="button" disabled={busy} onClick={submit} className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors shrink-0 press-feedback">
          <Plus className="w-4 h-4" /> Añadir
        </button>
      </div>
      {error && <p className="text-xs text-red-400 animate-fade-in-up">{error}</p>}
    </div>
  );
}

function AdminShopItemRow({ item, onUpdate, onDelete }) {
  const [price, setPrice] = useState(item.price);
  const [stock, setStock] = useState(item.stock ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function saveChanges() {
    setBusy(true);
    setError('');
    try {
      await onUpdate(item.id, { price: Number(price), stock: stock === '' ? null : Number(stock) });
    } catch (err) {
      setError(err.message || 'No se pudo guardar.');
    } finally {
      setBusy(false);
    }
  }

  async function toggleActive() {
    setBusy(true);
    setError('');
    try {
      await onUpdate(item.id, { active: !item.active });
    } catch (err) {
      setError(err.message || 'No se pudo cambiar el estado.');
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    setBusy(true);
    setError('');
    try {
      await onDelete(item.id);
    } catch (err) {
      setError(err.message || 'No se pudo borrar.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={`flex flex-col gap-1.5 bg-gray-800/40 rounded-lg px-3 py-2 transition-opacity duration-300 ${!item.active ? 'opacity-50' : ''}`}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-gray-200 flex-1 min-w-[8rem] truncate">{item.name}</span>
        <span className="text-[11px] text-gray-600 font-mono-data shrink-0">#{item.itemId}</span>
        <input type="number" value={price} onChange={(e) => setPrice(e.target.value)} className={`${inputClass} w-20`} title="Precio" />
        <input type="number" value={stock} onChange={(e) => setStock(e.target.value)} placeholder="∞" className={`${inputClass} w-20`} title="Stock" />
        <button type="button" disabled={busy} onClick={saveChanges} className="text-xs text-emerald-400 hover:text-emerald-300 px-2 disabled:opacity-50 press-feedback">Guardar</button>
        <button type="button" disabled={busy} onClick={toggleActive} className="text-xs text-amber-400 hover:text-amber-300 px-2 disabled:opacity-50 press-feedback">{item.active ? 'Desactivar' : 'Activar'}</button>
        <button type="button" disabled={busy} onClick={handleDelete} className="text-xs text-red-400 hover:text-red-300 px-2 disabled:opacity-50 press-feedback">Borrar</button>
      </div>
      {error && <p className="text-[11px] text-red-400 animate-fade-in-up">{error}</p>}
    </div>
  );
}

function PendingPurchasesQueue({ purchases, loading, users }) {
  const nameById = useMemo(() => Object.fromEntries(users.map((u) => [u.id, u.name])), [users]);
  return (
    <Panel>
      <h3 className="text-white font-semibold mb-1 flex items-center gap-2"><History className="w-4 h-4 text-amber-400" /> Compras pendientes de aplicar</h3>
      <p className="text-xs text-gray-500 mb-3">De todos los participantes. Se aplicarán automáticamente al save cuando el jugador lo suba (próxima parte) — por ahora es solo lectura.</p>
      {loading ? (
        <LoadingState />
      ) : purchases.length === 0 ? (
        <p className="text-sm text-gray-600">No hay compras pendientes.</p>
      ) : (
        <div className="space-y-1.5">
          {purchases.map((p, i) => (
            <div key={p.id} className="flex items-center justify-between gap-2 bg-gray-800/40 rounded-lg px-3 py-2 animate-fade-in-up" style={{ animationDelay: `${Math.min(i, 10) * 30}ms` }}>
              <span className="text-sm text-gray-200 truncate">{nameById[p.userId] || '—'} · {p.itemName}{p.quantity > 1 && ` ×${p.quantity}`}</span>
              <span className="text-[11px] text-gray-600 shrink-0">{new Date(p.createdAt).toLocaleDateString()}</span>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function ShopView({ role, session, ownUser, users, onCoinsChange }) {
  const isAdmin = role === 'Administrador';
  const [items, setItems] = useState([]);
  const [loadingItems, setLoadingItems] = useState(true);
  const [purchases, setPurchases] = useState([]);
  const [loadingPurchases, setLoadingPurchases] = useState(true);
  const [shopError, setShopError] = useState('');

  async function refreshItems() {
    setLoadingItems(true);
    try {
      const data = await api.getShopItems({ all: isAdmin });
      setItems(data);
    } catch (err) {
      setShopError(err.message || 'No se pudo cargar la tienda.');
    } finally {
      setLoadingItems(false);
    }
  }

  // Reutiliza el mismo endpoint para dos casos: un jugador siempre ve solo
  // lo suyo (el backend lo acota por su sesión); el admin, al no mandar
  // userId, ve TODAS las compras — filtradas a 'pendiente' para armar la
  // cola de la próxima parte.
  async function refreshPurchases() {
    setLoadingPurchases(true);
    try {
      const data = await api.getMyPurchases(isAdmin ? 'pendiente' : undefined);
      setPurchases(data);
    } catch {
      setPurchases([]);
    } finally {
      setLoadingPurchases(false);
    }
  }

  useEffect(() => {
    refreshItems();
    refreshPurchases();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAdmin]);

  async function handleBuy(shopItemId, quantity) {
    const result = await api.buyShopItem(shopItemId, quantity);
    onCoinsChange(session.userId, result.coins);
    await Promise.all([refreshItems(), refreshPurchases()]);
  }

  async function handleCreateItem(payload) {
    await api.createShopItem(payload);
    await refreshItems();
  }

  async function handleUpdateItem(id, patch) {
    await api.updateShopItem(id, patch);
    await refreshItems();
  }

  async function handleDeleteItem(id) {
    await api.deleteShopItem(id);
    await refreshItems();
  }

  const grouped = useMemo(() => {
    const map = {};
    for (const it of items) (map[it.category] ||= []).push(it);
    return map;
  }, [items]);

  return (
    <div className="space-y-4">
      {shopError && (
        <Panel className="border-red-900/50 bg-red-950/10">
          <p className="text-sm text-red-400">{shopError}</p>
        </Panel>
      )}

      {isAdmin ? (
        <>
          <Panel>
            <h3 className="text-white font-semibold mb-1 flex items-center gap-2"><ShoppingBag className="w-4 h-4 text-amber-400" /> Añadir objeto a la tienda</h3>
            <p className="text-xs text-gray-500 mb-3">El item_id debe ser el ID real del objeto en el juego (verifícalo contra PKHeX) — se usará para escribirlo en el save en la Parte 4.</p>
            <AdminAddShopItemForm onCreate={handleCreateItem} />
          </Panel>
          <Panel>
            <h3 className="text-white font-semibold mb-3 flex items-center gap-2"><Coins className="w-4 h-4 text-amber-400" /> Catálogo ({items.length})</h3>
            {loadingItems ? (
              <LoadingState />
            ) : items.length === 0 ? (
              <p className="text-sm text-gray-600">Todavía no hay objetos en la tienda.</p>
            ) : (
              <div className="space-y-1.5">
                {items.map((it) => (
                  <AdminShopItemRow key={it.id} item={it} onUpdate={handleUpdateItem} onDelete={handleDeleteItem} />
                ))}
              </div>
            )}
          </Panel>
          <PendingPurchasesQueue purchases={purchases} loading={loadingPurchases} users={users} />
        </>
      ) : (
        <>
          <Panel className="border-amber-900/50 bg-amber-950/10">
            <p className="text-sm text-amber-300 flex items-center gap-2 flex-wrap">
              <Coins className="w-4 h-4 shrink-0" />
              Tienes <span className="font-mono-data"><AnimatedCounter value={ownUser?.coins ?? 0} /></span> monedas. Lo que compres queda pendiente hasta que subas tu save (próxima parte).
            </p>
          </Panel>
          {loadingItems ? (
            <LoadingState label="Cargando tienda…" />
          ) : items.length === 0 ? (
            <Panel><p className="text-sm text-gray-600">Todavía no hay objetos en la tienda.</p></Panel>
          ) : (
            Object.entries(grouped).map(([cat, list]) => (
              <Panel key={cat}>
                <h3 className="text-white font-semibold mb-3">{SHOP_CATEGORY_LABELS[cat] || cat}</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {list.map((item, i) => (
                    <div key={item.id} className="animate-fade-in-up" style={{ animationDelay: `${i * 40}ms` }}>
                      <ShopItemCard item={item} coins={ownUser?.coins ?? 0} onBuy={handleBuy} />
                    </div>
                  ))}
                </div>
              </Panel>
            ))
          )}
          <ApplySaveCard onApplied={refreshPurchases} />
          <MyPurchasesPanel purchases={purchases} loading={loadingPurchases} />
        </>
      )}
    </div>
  );
}

function ApplySaveCard({ onApplied }) {
  const [file, setFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState(null); // { saveBase64, applied, failed, message, filename }

  function handleFileChange(e) {
    const chosen = e.target.files?.[0] || null;
    setFile(chosen);
    setError('');
    setResult(null);
  }

  async function handleApply() {
    if (!file) {
      setError('Elige primero tu archivo "main".');
      return;
    }
    setBusy(true);
    setError('');
    setResult(null);
    try {
      const base64 = await fileToBase64(file);
      const response = await api.applyRewards(base64, file.name);
      setResult({ ...response, filename: file.name });
      if (response.saveBase64) {
        downloadBase64AsFile(response.saveBase64, file.name);
      }
      if (onApplied) onApplied();
    } catch (err) {
      setError(err.message || 'No se pudo procesar el save.');
    } finally {
      setBusy(false);
    }
  }

  function handleDownloadAgain() {
    if (result?.saveBase64) downloadBase64AsFile(result.saveBase64, result.filename);
  }

  return (
    <Panel className="border-amber-900/40">
      <h3 className="text-white font-semibold mb-1 flex items-center gap-2">
        <Upload className="w-4 h-4 text-amber-400" /> Aplicar mis compras al save
      </h3>
      <p className="text-xs text-gray-500 mb-3">
        Sube tu archivo <span className="font-mono-data text-gray-400">main</span> (el que exporta Checkpoint o JKSM desde tu consola).
        El sistema añade automáticamente todos los objetos que tengas pendientes y te devuelve el archivo listo para reimportar. No se envía nada a tu consola: es solo subir y bajar un archivo.
      </p>

      <div className="flex flex-col sm:flex-row gap-2 items-start sm:items-center">
        <input
          type="file"
          onChange={handleFileChange}
          className="text-xs text-gray-400 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:bg-gray-800 file:text-gray-300 file:text-xs hover:file:bg-gray-700 file:cursor-pointer cursor-pointer"
        />
        <button
          type="button"
          disabled={busy || !file}
          onClick={handleApply}
          className="flex items-center gap-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-xs font-semibold px-4 py-1.5 rounded-lg transition-colors shrink-0 press-feedback"
        >
          {busy ? <PokeballIcon className="w-3.5 h-3.5 animate-poke-spin" /> : <Upload className="w-3.5 h-3.5" />}
          {busy ? 'Procesando…' : 'Aplicar y descargar'}
        </button>
      </div>

      {error && (
        <div className="flex items-start gap-2 mt-3 bg-red-950/30 border border-red-900/50 rounded-lg px-3 py-2 animate-fade-in-up">
          <AlertTriangle className="w-4 h-4 text-red-400 shrink-0 mt-0.5" />
          <p className="text-xs text-red-300">{error}</p>
        </div>
      )}

      {result && (
        <div className="mt-3 space-y-2 animate-fade-in-up">
          {result.message && <p className="text-xs text-gray-500">{result.message}</p>}
          {result.applied?.length > 0 && (
            <div className="bg-emerald-950/20 border border-emerald-900/40 rounded-lg px-3 py-2 animate-scale-in">
              <p className="text-xs text-emerald-400 font-semibold mb-1">Aplicado ✓ — se descargó tu save actualizado:</p>
              <ul className="text-xs text-gray-300 space-y-0.5">
                {result.applied.map((p) => (
                  <li key={p.id}>{p.itemName}{p.quantity > 1 && ` ×${p.quantity}`}</li>
                ))}
              </ul>
              <button type="button" onClick={handleDownloadAgain} className="text-[11px] text-amber-400 hover:text-amber-300 mt-1.5 flex items-center gap-1">
                <Download className="w-3 h-3" /> Descargar de nuevo
              </button>
            </div>
          )}
          {result.failed?.length > 0 && (
            <div className="bg-amber-950/20 border border-amber-900/40 rounded-lg px-3 py-2">
              <p className="text-xs text-amber-400 font-semibold mb-1">No se pudieron aplicar (quedan pendientes):</p>
              <ul className="text-xs text-gray-300 space-y-0.5">
                {result.failed.map((f) => (
                  <li key={f.purchaseId}>{f.itemName} — {f.reason === 'POUCH_FULL' ? 'el bolsillo está lleno' : f.reason}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      <div className="mt-4 pt-3 border-t border-gray-800/60">
        <p className="text-[11px] text-gray-600 font-semibold mb-1">Cómo reimportarlo:</p>
        <ol className="text-[11px] text-gray-500 space-y-0.5 list-decimal list-inside">
          <li>Descarga el archivo con el botón de arriba (se llama igual que tu "main" original).</li>
          <li>Abre Checkpoint (3DS) o JKSM y reemplaza el save de tu partida por este archivo.</li>
          <li>Arranca el juego — tus objetos ya deberían estar en la bolsa.</li>
        </ol>
      </div>
    </Panel>
  );
}

/* ============================== MI PERFIL — REGISTRO NUZLOCKE ============================== */

function PokemonGalleryCard({ data }) {
  const sprite = usePokemonSprite(data.pokemonName);
  return (
    <div className="flex flex-col items-center text-center bg-gray-900/60 border border-gray-800 rounded-xl p-3 gap-1.5 hover-lift">
      <div className="w-14 h-14 rounded-lg bg-gray-800 border border-gray-700 flex items-center justify-center overflow-hidden shrink-0">
        {sprite ? <img src={sprite} alt={data.pokemonName} className="w-11 h-11 object-contain" /> : <span className="text-gray-600 text-xs">?</span>}
      </div>
      <span className="text-sm font-semibold text-gray-200 truncate max-w-full">{data.nickname || data.pokemonName || 'Sin nombre'}</span>
      {data.nickname && data.pokemonName && (
        <span className="text-[11px] text-gray-500 truncate max-w-full">{data.pokemonName}</span>
      )}
      <span className="text-[11px] text-gray-600 truncate max-w-full">{data.route}</span>
      {data.level != null && <span className="text-[11px] font-mono-data text-gray-500">Nv. {data.level}</span>}
    </div>
  );
}

function PokemonGallerySection({ title, icon, routes, emptyText, accentClass }) {
  const Icon = icon;
  return (
    <Panel className="border-dashed border-gray-700">
      <h4 className={`text-sm font-semibold mb-3 flex items-center gap-2 ${accentClass}`}>
        <Icon className="w-4 h-4" /> {title} <span className="text-xs text-gray-600 font-normal">({routes.length})</span>
      </h4>
      {routes.length === 0 ? (
        <p className="text-xs text-gray-600 text-center py-4">{emptyText}</p>
      ) : (
        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-2.5">
          {routes.map((r, i) => (
            <div key={r.id} className="animate-fade-in-up" style={{ animationDelay: `${Math.min(i, 12) * 30}ms` }}>
              <PokemonGalleryCard data={r} />
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
}

function capitalize(name) {
  return name ? name.charAt(0).toUpperCase() + name.slice(1) : name;
}

function RouteCard({ data, onChange, onDelete }) {
  const sprite = usePokemonSprite(data.pokemonName);
  const evolutions = usePokemonEvolutions(data.pokemonName);
  const [showEvoPicker, setShowEvoPicker] = useState(false);

  function handleEvolveClick() {
    if (evolutions.length === 1) {
      onChange({ ...data, pokemonName: capitalize(evolutions[0]) });
    } else if (evolutions.length > 1) {
      setShowEvoPicker((v) => !v);
    }
  }

  function handlePickEvolution(name) {
    onChange({ ...data, pokemonName: capitalize(name) });
    setShowEvoPicker(false);
  }

  return (
    <div className="flex flex-col md:flex-row md:items-center gap-2.5 bg-gray-900/60 border border-gray-800 rounded-xl p-3 hover:border-blue-900/60 hover-lift animate-fade-in-up">
      <div className="flex items-center gap-3 md:w-40 shrink-0">
        <div className="w-11 h-11 rounded-lg bg-gray-800 border border-gray-700 flex items-center justify-center overflow-hidden shrink-0">
          {sprite ? <img src={sprite} alt={data.pokemonName} className="w-9 h-9 object-contain" /> : <span className="text-gray-600 text-xs">?</span>}
        </div>
        <span className="text-sm font-semibold text-gray-200 flex items-center gap-1.5">
          {data.route}
          {data.isCustom && <span className="text-[9px] uppercase tracking-wider text-amber-500 border border-amber-700/50 rounded px-1">Extra</span>}
        </span>
      </div>

      <div className="relative flex items-center gap-1 md:w-32">
        <input
          value={data.pokemonName ?? ''}
          onChange={(e) => onChange({ ...data, pokemonName: e.target.value })}
          placeholder="Nombre del Pokémon…"
          className={`${inputClass} w-full`}
        />
        {evolutions.length > 0 && (
          <button
            type="button"
            onClick={handleEvolveClick}
            title={evolutions.length === 1 ? `Evolucionar a ${capitalize(evolutions[0])}` : 'Elegir evolución'}
            className="shrink-0 text-amber-400 hover:text-amber-300 transition-colors hover:scale-110 active:scale-90 duration-150"
          >
            <Sparkles className="w-4 h-4" />
          </button>
        )}
        {showEvoPicker && evolutions.length > 1 && (
          <div className="absolute z-10 top-full left-0 mt-1 bg-gray-900 border border-gray-700 rounded-lg shadow-lg py-1 min-w-max animate-scale-in" style={{ transformOrigin: 'top left' }}>
            {evolutions.map((name) => (
              <button
                key={name}
                type="button"
                onClick={() => handlePickEvolution(name)}
                className="block w-full text-left px-3 py-1.5 text-xs text-gray-300 hover:bg-gray-800 hover:text-amber-300 whitespace-nowrap"
              >
                {capitalize(name)}
              </button>
            ))}
          </div>
        )}
      </div>

      <input value={data.nickname} onChange={(e) => onChange({ ...data, nickname: e.target.value })} placeholder="Apodo" className={`${inputClass} md:w-24`} />

      <select value={data.status} onChange={(e) => onChange({ ...data, status: e.target.value })} className={`${inputClass} md:w-24`}>
        {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
      </select>

      <select value={data.nature} onChange={(e) => onChange({ ...data, nature: e.target.value })} className={`${inputClass} md:w-28`}>
        <option value="">Naturaleza</option>
        {NATURES.map((n) => <option key={n} value={n}>{n}</option>)}
      </select>

      <input value={data.ability} onChange={(e) => onChange({ ...data, ability: e.target.value })} placeholder="Habilidad" className={`${inputClass} md:w-24`} />
      <input value={data.item} onChange={(e) => onChange({ ...data, item: e.target.value })} placeholder="Objeto" className={`${inputClass} md:w-20`} />
      <input type="number" min="1" max="100" value={data.level ?? ''} onChange={(e) => onChange({ ...data, level: e.target.value ? Number(e.target.value) : null })} placeholder="Nv" className={`${inputClass} md:w-14`} />
      <input value={data.notes} onChange={(e) => onChange({ ...data, notes: e.target.value })} placeholder="Observaciones" className={`${inputClass} flex-1 min-w-0`} />

      <StatusBadge status={data.status} />
      {data.isCustom && onDelete && (
        <button type="button" onClick={onDelete} title="Eliminar esta fila" className="text-gray-600 hover:text-red-400 shrink-0 hover:scale-110 active:scale-90 transition-transform duration-150">
          <Trash2 className="w-4 h-4" />
        </button>
      )}
    </div>
  );
}

function TrackerView({ users, role, session, onRouteChange, onAddCustomRoute, onDeleteCustomRoute }) {
  const isAdmin = role === 'Administrador';
  const [activeId, setActiveId] = useState(() => (isAdmin ? (users[0] && users[0].id) : session.userId));
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('Todos');
  const [lastChanged, setLastChanged] = useState(null);
  const [newRouteName, setNewRouteName] = useState('');
  const [customBusy, setCustomBusy] = useState(false);
  const [customError, setCustomError] = useState('');

  const activeUser = users.find((u) => u.id === activeId) || (isAdmin ? users[0] : users.find((u) => u.id === session.userId));
  const isOwnProfile = !isAdmin && activeUser && activeUser.id === session.userId;

  useEffect(() => {
    if (!lastChanged) return undefined;
    const t = setTimeout(() => setLastChanged(null), 600);
    return () => clearTimeout(t);
  }, [lastChanged]);

  if (!activeUser) {
    return (
      <Panel className="flex flex-col items-center justify-center gap-2 py-14 text-gray-600 border-dashed">
        <ScrollText className="w-8 h-8" />
        <span className="text-sm">{isAdmin ? 'Aún no hay participantes — créalos desde el panel de Administrador.' : 'Tu ficha todavía no se ha generado. Avisa a un administrador.'}</span>
      </Panel>
    );
  }

  const deaths = activeUser.deaths;
  const routes = activeUser.routes;

  function handleRouteChange(routeId, newData) {
    const old = routes.find((r) => r.id === routeId);
    if (old && old.status !== newData.status) {
      if (newData.status === 'Muerto' && old.status !== 'Muerto') setLastChanged('down');
      else if (old.status === 'Muerto' && newData.status !== 'Muerto') setLastChanged('up');
    }
    onRouteChange(activeUser.id, routeId, newData);
  }

  async function handleAddCustomRoute() {
    const name = newRouteName.trim();
    if (!name) return;
    setCustomBusy(true);
    setCustomError('');
    try {
      await onAddCustomRoute(name);
      setNewRouteName('');
    } catch (err) {
      setCustomError(err.message || 'No se pudo agregar la fila.');
    } finally {
      setCustomBusy(false);
    }
  }

  async function handleDeleteCustomRoute(routeId) {
    try {
      await onDeleteCustomRoute(routeId);
    } catch (err) {
      setCustomError(err.message || 'No se pudo eliminar la fila.');
    }
  }

  const filtered = routes.filter((r) => {
    const matchesSearch = !search
      || r.route.toLowerCase().includes(search.toLowerCase())
      || (r.pokemonName && r.pokemonName.toLowerCase().includes(search.toLowerCase()));
    const matchesStatus = statusFilter === 'Todos' || r.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  const completed = routes.filter((r) => r.pokemonName && r.pokemonName.trim()).length;
  const isPulsing = lastChanged !== null;

  return (
    <div className="space-y-5">
      {isAdmin && users.length > 1 && (
        <div className="flex flex-wrap items-center gap-2">
          {users.map((p, i) => (
            <button
              type="button"
              key={p.id}
              onClick={() => setActiveId(p.id)}
              style={{ animationDelay: `${i * 30}ms` }}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-full border text-sm transition-colors press-feedback animate-fade-in-up ${activeId === p.id ? 'bg-blue-600/20 border-blue-500 text-blue-300' : 'bg-gray-800/60 border-gray-700 text-gray-400 hover:text-gray-200'}`}
            >
              <Avatar name={p.name} color={p.color} />
              {p.name}
            </button>
          ))}
        </div>
      )}

      <Panel>
        <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-5">
          <div className="md:w-96">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-semibold text-gray-300 flex items-center gap-1.5">
                <Skull className="w-4 h-4 text-red-500" /> Muertes
              </span>
              <span className={`font-mono-data text-sm text-gray-400 transition-transform duration-300 ${isPulsing ? 'scale-125 text-red-400' : 'scale-100'}`}>{deaths} / {MAX_DEATHS}</span>
            </div>
            <div className="h-3 max-w-xs bg-gray-800 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full bg-gradient-to-r from-red-700 to-red-500 transition-all duration-500"
                style={{ width: `${Math.min(100, (deaths / MAX_DEATHS) * 100)}%` }}
              />
            </div>
            {deaths >= MAX_DEATHS && (
              <div className="mt-3 inline-flex items-center gap-2 bg-red-950/60 border border-red-800 rounded-lg px-3 py-2 text-red-400 text-sm font-semibold animate-pulse">
                <Skull className="w-4 h-4" /> Jugador eliminado
              </div>
            )}
          </div>
          <div className="md:w-56 md:shrink-0 flex flex-col gap-3">
            <div>
              <div className="flex items-center justify-between text-xs text-gray-500 mb-1">
                <span>Progreso Nuzlocke</span><span className="font-mono-data">{completed}/{routes.length}</span>
              </div>
              <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
                <div className="h-full bg-gradient-to-r from-amber-500 to-blue-500 transition-all duration-700" style={{ width: `${routes.length ? (completed / routes.length) * 100 : 0}%` }} />
              </div>
            </div>
            <div className="flex items-center gap-2 bg-amber-950/30 border border-amber-800/40 rounded-lg px-3 py-2 self-start hover-lift">
              <Coins className="w-4 h-4 text-amber-400" />
              <span className="text-sm font-mono-data text-amber-300"><AnimatedCounter value={activeUser.coins ?? 0} /></span>
              <span className="text-xs text-gray-500">monedas</span>
            </div>
          </div>
        </div>
      </Panel>

      <div className="flex flex-col sm:flex-row gap-2">
        <div className="relative flex-1">
          <Search className="w-4 h-4 text-gray-600 absolute left-3 top-1/2 -translate-y-1/2" />

          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar por ruta o Pokémon…" className={`${inputClass} w-full pl-9`} />
        </div>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className={inputClass}>
          <option>Todos</option>
          {STATUSES.map((s) => <option key={s}>{s}</option>)}
        </select>
      </div>

      <div className="space-y-2">
        {filtered.map((r) => (
          <RouteCard
            key={r.id}
            data={r}
            onChange={(newData) => handleRouteChange(r.id, newData)}
            onDelete={isOwnProfile && r.isCustom ? () => handleDeleteCustomRoute(r.id) : undefined}
          />
        ))}
        {filtered.length === 0 && <p className="text-sm text-gray-600 text-center py-6">Sin resultados para este filtro.</p>}
      </div>

      <PokemonGallerySection
        title="Cementerio"
        icon={Skull}
        routes={routes.filter((r) => r.status === 'Muerto')}
        emptyText="Todavía no hay ningún Pokémon caído."
        accentClass="text-red-400"
      />

      <PokemonGallerySection
        title="Caja"
        icon={Archive}
        routes={routes.filter((r) => r.status === 'Caja')}
        emptyText="La caja está vacía por ahora."
        accentClass="text-sky-400"
      />

      {isOwnProfile && (
        <Panel className="border-dashed border-gray-700">
          <h4 className="text-sm font-semibold text-gray-300 mb-2 flex items-center gap-2"><Plus className="w-4 h-4 text-amber-400" /> Agregar una fila propia</h4>
          <p className="text-xs text-gray-600 mb-3">Además de tus {KALOS_LOCATIONS.length} rutas fijas, puedes agregarte todas las filas extra que quieras (por ejemplo, un encuentro especial o un evento) y borrarlas cuando quieras.</p>
          <div className="flex flex-col sm:flex-row gap-2">
            <input
              value={newRouteName}
              onChange={(e) => setNewRouteName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAddCustomRoute()}
              placeholder="Nombre de la fila (ej. Evento especial)…"
              className={`${inputClass} flex-1`}
            />
            <button
              type="button"
              onClick={handleAddCustomRoute}
              disabled={customBusy || !newRouteName.trim()}
              className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors shrink-0 press-feedback"
            >
              <Plus className="w-4 h-4" /> Agregar
            </button>
          </div>
          {customError && <p className="text-xs text-red-400 mt-2 animate-fade-in-up">{customError}</p>}
        </Panel>
      )}

      {isAdmin && (
        <p className="text-xs text-gray-600 text-center">
          El cuadro para agregar filas propias solo lo ve cada jugador cuando entra con su propia sesión, no el administrador viendo la ficha ajena.
        </p>
      )}
    </div>
  );
}

/* ============================== LOGIN ============================== */

function LoginView({ users, loadingUsers, onAdminLogin, onUserLogin }) {
  const [tab, setTab] = useState('jugador');
  const [password, setPassword] = useState('');
  const [selectedUserId, setSelectedUserId] = useState(users[0] ? users[0].id : '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!selectedUserId && users[0]) setSelectedUserId(users[0].id);
  }, [users, selectedUserId]);

  async function submit(e) {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      if (tab === 'admin') {
        const ok = await onAdminLogin(password);
        if (!ok) setError('Contraseña de administrador incorrecta.');
        return;
      }
      if (!selectedUserId) { setError('Todavía no hay participantes creados. Pide a un administrador que te añada.'); return; }
      const ok = await onUserLogin(selectedUserId, password);
      if (!ok) setError('Contraseña incorrecta.');
    } catch (err) {
      setError(err.message || 'No se pudo iniciar sesión. Inténtalo de nuevo.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen bg-black flex items-center justify-center p-4" style={{ fontFamily: "'Inter', sans-serif" }}>
      <GlobalStyles />
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-6 animate-fade-in-up">
          <PokeballIcon className="w-14 h-14 mb-3 animate-scale-in" />
          <h1 className="font-display text-2xl font-bold text-white tracking-wide">NUZLOCKE TOURNAMENT HUB</h1>
          <p className="text-xs text-gray-500 mt-1">Inicia sesión para entrar al torneo — funciona desde cualquier dispositivo</p>
        </div>

        <div className="flex bg-gray-900 border border-gray-800 rounded-lg p-1 mb-4 animate-fade-in-up" style={{ animationDelay: '80ms' }}>
          {[['jugador', 'Jugador'], ['admin', 'Administrador']].map(([key, label]) => (
            <button
              type="button"
              key={key}
              onClick={() => { setTab(key); setError(''); }}
              className={`flex-1 text-sm font-medium py-1.5 rounded-md transition-colors press-feedback ${tab === key ? 'bg-blue-600 text-white' : 'text-gray-400 hover:text-gray-200'}`}
            >
              {label}
            </button>
          ))}
        </div>

        <form onSubmit={submit} className="bg-gray-900/70 border border-gray-800 rounded-2xl p-5 space-y-3 animate-fade-in-up" style={{ animationDelay: '150ms' }}>
          {tab === 'jugador' && (
            loadingUsers ? (
              <p className="text-sm text-gray-500">Cargando participantes…</p>
            ) : users.length === 0 ? (
              <p className="text-sm text-gray-500">Todavía no hay participantes registrados. Pide a un administrador que te añada desde su panel.</p>
            ) : (
              <select value={selectedUserId} onChange={(e) => setSelectedUserId(e.target.value)} className={`${inputClass} w-full`}>
                {users.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
              </select>
            )
          )}
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Contraseña"
            className={`${inputClass} w-full`}
          />
          {error && <p className="text-xs text-red-400 animate-fade-in-up">{error}</p>}
          <button type="submit" disabled={busy} className="w-full flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-60 text-white font-semibold py-2 rounded-lg transition-colors press-feedback">
            {busy && <PokeballIcon className="w-4 h-4 animate-poke-spin" />}
            {busy ? 'Entrando…' : 'Entrar'}
          </button>
        </form>
      </div>
    </div>
  );
}

/* ============================== APP ============================== */

export default function App() {
  const [session, setSession] = useState(null);
  const [sessionChecked, setSessionChecked] = useState(false);
  const [view, setView] = useState('inicio');
  const [navOpen, setNavOpen] = useState(false);
  const [news, setNews] = useState([]);
  const [users, setUsers] = useState([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [globalError, setGlobalError] = useState('');
  const [rulesContent, setRulesContent] = useState(DEFAULT_RULES_MD);
  const [rouletteSegments, setRouletteSegments] = useState(ROULETTE_SEGMENTS);
  const [rouletteAnimated, setRouletteAnimated] = useState(true);
  const [rouletteHistory, setRouletteHistory] = useState([]);
  const [loadingRoulette, setLoadingRoulette] = useState(true);
  const [bracket, setBracket] = useState(null);
  const [loadingBracket, setLoadingBracket] = useState(true);
  const [playoff, setPlayoff] = useState(null);
  const [loadingPlayoff, setLoadingPlayoff] = useState(true);
  const targetDate = useMemo(() => new Date(Date.now() + 1000 * 60 * 60 * 24 * 14), []);
  const countdown = useCountdown(targetDate);

  const role = session ? (session.type === 'admin' ? 'Administrador' : 'Usuario') : null;
  const visibleNavItems = useMemo(
    () => NAV_ITEMS.filter((item) => {
      if (item.key === 'admin') return role === 'Administrador';
      if (item.key === 'ruleta') return role === 'Administrador';
      return true;
    }),
    [role],
  );

  // Trae la lista de participantes (con sus fichas Nuzlocke) desde Postgres.
  async function refreshUsers() {
    try {
      const data = await api.getUsers();
      setUsers(data);
    } catch (err) {
      setGlobalError(err.message || 'No se pudo conectar con la base de datos.');
    } finally {
      setLoadingUsers(false);
    }
  }

  async function refreshNews() {
    try {
      const data = await api.getNews();
      setNews(data);
    } catch {
      // Si falla, simplemente no mostramos noticias — no es crítico.
    }
  }

  async function refreshBracket() {
    try {
      const data = await api.getBracket();
      setBracket(data);
    } catch {
      // Si falla, se muestra como "aún no hay torneo" — no es crítico.
    } finally {
      setLoadingBracket(false);
    }
  }

  async function refreshPlayoff() {
    try {
      const data = await api.getPlayoff();
      setPlayoff(data);
    } catch {
      // Si falla, se muestra como "aún no hay playoffs" — no es crítico.
    } finally {
      setLoadingPlayoff(false);
    }
  }

  // La ruleta ahora vive en Supabase (antes solo en memoria del navegador):
  // esto trae los segmentos, la animación y el historial ya guardados.
  async function refreshRoulette() {
    try {
      const data = await api.getRoulette();
      setRouletteSegments(data.segments?.length ? data.segments : ROULETTE_SEGMENTS);
      setRouletteAnimated(data.animated ?? true);
      setRouletteHistory(data.history || []);
    } catch {
      // Si falla, se queda con los valores por defecto — no es crítico.
    } finally {
      setLoadingRoulette(false);
    }
  }

  // Al montar: recupera la sesión guardada en este dispositivo (si existe) y
  // carga usuarios/noticias desde la base de datos vía Firestore.
  useEffect(() => {
    const saved = loadSession();
    if (saved) setSession(saved);
    setSessionChecked(true);
    refreshUsers();
    refreshNews();
    refreshBracket();
    refreshPlayoff();
    refreshRoulette();
  }, []);

  // Tiempo real: cualquier Pokémon que cambie (el propio o el de otro
  // participante, desde cualquier dispositivo) llega aquí por WebSocket vía
  // Supabase Realtime y se refleja al instante, sin recargar la página.
  useEffect(() => {
    if (!supabaseClient) return undefined; // faltan las env vars VITE_SUPABASE_*

    function mapRow(row) {
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

    const channel = supabaseClient
      .channel('route_entries_realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'route_entries' },
        (payload) => {
          if (payload.eventType === 'DELETE') {
            const deletedId = payload.old?.id;
            setUsers((prev) => prev.map((u) => ({
              ...u,
              routes: u.routes.filter((r) => r.id !== deletedId),
            })));
            return;
          }

          const mapped = mapRow(payload.new);
          setUsers((prev) => prev.map((u) => {
            if (u.id !== mapped.userId) return u;
            const exists = u.routes.some((r) => r.id === mapped.id);
            const routes = exists
              ? u.routes.map((r) => (r.id === mapped.id ? mapped : r))
              : [...u.routes, mapped].sort((a, b) => a.orderIndex - b.orderIndex);
            return { ...u, routes };
          }));

          // Si el estado cruzó hacia/desde "Muerto", el contador de muertes
          // del participante también cambió en la base de datos: /api/users
          // ya filtra la contraseña, así que lo usamos para traer el número
          // actualizado (no exponemos la tabla "users" a Realtime).
          const oldStatus = payload.old?.status;
          if (payload.eventType === 'UPDATE' && oldStatus !== mapped.status &&
              (oldStatus === 'Muerto' || mapped.status === 'Muerto')) {
            refreshUsers();
          }
        },
      )
      .subscribe();

    return () => {
      supabaseClient.removeChannel(channel);
    };
  }, []);

  useEffect(() => {
    if (view === 'admin' && role !== 'Administrador') setView('inicio');
    if (view === 'ruleta' && role !== 'Administrador') setView('inicio');
  }, [role, view]);

  async function handleAdminLogin(password) {
    const res = await api.loginAdmin(password);
    const newSession = { type: 'admin', token: res.token };
    saveSession(newSession);
    setSession(newSession);
    return true;
  }

  async function handleUserLogin(userId, password) {
    const res = await api.loginUser(userId, password);
    const newSession = { type: 'user', userId: res.userId, token: res.token };
    saveSession(newSession);
    setSession(newSession);
    return true;
  }

  function logout() {
    clearSession();
    setSession(null);
    setView('inicio');
  }

  async function addUser({ name, password }) {
    await api.createUser(name, password);
    await refreshUsers();
  }

  async function deleteUser(id) {
    await api.deleteUser(id);
    await refreshUsers();
  }

  // Da (amount > 0) o quita (amount < 0) monedas a un participante. Se
  // guarda en Supabase (tabla coin_transactions) vía /api/coins, así que
  // persiste igual que muertes, victorias, etc.
  async function giveCoins(userId, amount, reason) {
    const result = await api.giveCoins(userId, amount, reason);
    setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, coins: result.coins } : u)));
    return result;
  }

  // Actualización optimista: refleja el cambio al instante en pantalla y lo
  // guarda en segundo plano; si el contador de muertes del jugador cambia
  // (por una captura marcada como "Muerto"), se sincroniza con el servidor.
  async function updateUserRoute(userId, routeId, newData) {
    setUsers((prev) => prev.map((u) => {
      if (u.id !== userId) return u;
      return { ...u, routes: u.routes.map((r) => (r.id === routeId ? { ...r, ...newData } : r)) };
    }));
    try {
      const result = await api.updateRoute(routeId, newData);
      if (result.user) {
        setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, deaths: result.user.deaths } : u)));
      }
    } catch (err) {
      setGlobalError(err.message || 'No se pudo guardar el cambio en la base de datos.');
      refreshUsers();
    }
  }

  async function addNews(title) {
    await api.addNews(title);
    await refreshNews();
  }

  async function addCustomRoute(routeName) {
    await api.addCustomRoute(routeName);
    await refreshUsers();
  }

  async function deleteCustomRoute(id) {
    await api.deleteCustomRoute(id);
    await refreshUsers();
  }

  async function createBracket(title, participantIds) {
    await api.createBracket(title, participantIds);
    await refreshBracket();
  }

  async function bracketSetWinner(matchId, winnerId) {
    await api.bracketSetWinner(matchId, winnerId);
    await refreshBracket();
  }

  async function bracketSwap(matchIdA, slotA, matchIdB, slotB) {
    await api.bracketSwap(matchIdA, slotA, matchIdB, slotB);
    await refreshBracket();
  }

  async function bracketAdvanceRound() {
    await api.bracketAdvanceRound();
    await refreshBracket();
  }

  async function bracketFinish() {
    await api.bracketFinish();
    await refreshBracket();
  }

  async function resetBracket() {
    await api.resetBracket();
    await refreshBracket();
  }

  async function generatePlayoff() {
    await api.generatePlayoff();
    await refreshPlayoff();
  }

  async function playoffSetWinner(matchId, winnerId) {
    await api.playoffSetWinner(matchId, winnerId);
    await refreshPlayoff();
  }

  async function resetPlayoff() {
    await api.resetPlayoff();
    await refreshPlayoff();
  }

  // La tienda descuenta monedas en el servidor (purchase_shop_item) y
  // devuelve el saldo nuevo; esto solo refleja ese saldo en pantalla, igual
  // que hace giveCoins cuando el admin da/quita monedas.
  function syncCoins(userId, coins) {
    setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, coins } : u)));
  }

  // La ruleta persiste en Supabase: se actualiza al instante en pantalla y
  // se guarda en segundo plano; si falla, se resincroniza con el servidor.
  async function addRouletteResult(entry) {
    setRouletteHistory((prev) => [entry, ...prev].slice(0, 100));
    try {
      const data = await api.addRouletteSpin(entry);
      setRouletteHistory(data.history || []);
    } catch (err) {
      setGlobalError(err.message || 'No se pudo guardar la tirada de la ruleta.');
    }
  }

  async function updateRouletteSegments(nextSegments) {
    setRouletteSegments(nextSegments);
    try {
      await api.updateRouletteConfig({ segments: nextSegments });
    } catch (err) {
      setGlobalError(err.message || 'No se pudo guardar la configuración de la ruleta.');
      refreshRoulette();
    }
  }

  async function updateRouletteAnimated(nextAnimated) {
    setRouletteAnimated(nextAnimated);
    try {
      await api.updateRouletteConfig({ animated: nextAnimated });
    } catch (err) {
      setGlobalError(err.message || 'No se pudo guardar la configuración de la ruleta.');
      refreshRoulette();
    }
  }

  // Intento de resolución de credenciales cuidando el estado de carga: no
  // mostramos el login hasta comprobar si ya había una sesión guardada.
  if (!sessionChecked) return null;

  if (!session) {
    return <LoginView users={users} loadingUsers={loadingUsers} onAdminLogin={handleAdminLogin} onUserLogin={handleUserLogin} />;
  }

  const ownUser = session.type === 'user' ? users.find((u) => u.id === session.userId) : null;
  const displayName = session.type === 'admin' ? 'Administrador' : (ownUser || {}).name || '—';
  const displayColor = session.type === 'admin' ? 'bg-blue-600' : (ownUser || {}).color || 'bg-gray-600';

  return (
    <>
      <GlobalStyles />
      <div className="min-h-screen bg-black text-gray-100 flex" style={{ fontFamily: "'Inter', sans-serif" }}>
        <SidebarNav active={view} onSelect={setView} open={navOpen} onClose={() => setNavOpen(false)} items={visibleNavItems} onHome={() => setView('inicio')} />
        <div className="flex-1 flex flex-col min-w-0">
          <header className="flex items-center justify-between px-4 md:px-8 py-4 border-b border-gray-800 bg-gray-950/80 backdrop-blur-sm sticky top-0 z-30">
            <div className="flex items-center gap-3">
              <button type="button" onClick={() => setNavOpen(true)} className="md:hidden text-gray-400 hover:text-white">
                <Menu className="w-5 h-5" />
              </button>
              <button type="button" onClick={() => setView('inicio')} title="Volver a Inicio" className="md:hidden">
                <PokeballIcon className="w-6 h-6" />
              </button>
              <h1 key={view} className="font-display text-lg font-bold text-white tracking-wide animate-fade-in">{VIEW_TITLES[view]}</h1>
            </div>
            <div className="flex items-center gap-3 md:gap-4">
              <div className="hidden sm:flex items-center gap-2 text-xs text-gray-500 font-mono-data">
                <Clock className="w-4 h-4" />
                {String(countdown.days).padStart(2, '0')}d {String(countdown.hours).padStart(2, '0')}h para la siguiente ronda
              </div>
              {ownUser && (
                <div className="hidden sm:flex items-center gap-1.5 bg-amber-950/30 border border-amber-800/40 rounded-full pl-2 pr-2.5 py-1.5 hover-lift">
                  <Coins className="w-3.5 h-3.5 text-amber-400" />
                  <span className="text-xs font-mono-data text-amber-300"><AnimatedCounter value={ownUser.coins ?? 0} /></span>
                </div>
              )}
              <div className="flex items-center gap-2 bg-gray-900 border border-gray-800 rounded-full pl-1.5 pr-2.5 py-1.5">
                <Avatar name={displayName} color={displayColor} />
                <span className="hidden md:block text-xs text-gray-300 font-medium">{displayName}</span>
                <span className="hidden md:block text-xs text-gray-600">·</span>
                <span className="text-xs text-amber-400 font-medium">{role}</span>
              </div>
              <button type="button" onClick={logout} className="text-xs text-gray-500 hover:text-red-400 font-medium press-feedback">Cerrar sesión</button>
            </div>
          </header>
          <main className="flex-1 p-4 md:p-8 max-w-6xl w-full mx-auto">
            {globalError && (
              <div className="mb-4 bg-red-950/60 border border-red-800 rounded-lg px-4 py-2.5 text-sm text-red-300 flex items-center justify-between gap-3 animate-fade-in-up">
                <span>{globalError}</span>
                <button type="button" onClick={() => setGlobalError('')} className="text-red-400 hover:text-red-200"><X className="w-4 h-4" /></button>
              </div>
            )}
            {view === 'inicio' && (
              <div key={view} className="animate-fade-in-up"><HomeView countdown={countdown} news={news} onNavigate={setView} users={users} /></div>
            )}
            {view === 'participantes' && <div key={view} className="animate-fade-in-up"><ParticipantsView users={users} /></div>}
            {view === 'bracket' && <div key={view} className="animate-fade-in-up"><GroupStandingsView users={users} /></div>}
            {view === 'playoffs' && (
              <div key={view} className="animate-fade-in-up">
                <Bracket32View
                  role={role}
                  playoff={playoff}
                  loading={loadingPlayoff}
                  swissStatus={bracket ? bracket.status : null}
                  onGenerate={generatePlayoff}
                  onSetWinner={playoffSetWinner}
                  onReset={resetPlayoff}
                />
              </div>
            )}
            {view === 'torneo-suizo' && (
              <div key={view} className="animate-fade-in-up">
                <SwissBracketView
                  users={users}
                  role={role}
                  bracket={bracket}
                  loading={loadingBracket}
                  onCreate={createBracket}
                  onSetWinner={bracketSetWinner}
                  onSwap={bracketSwap}
                  onAdvanceRound={bracketAdvanceRound}
                  onFinish={bracketFinish}
                  onReset={resetBracket}
                  playoff={playoff}
                  onGeneratePlayoff={generatePlayoff}
                  onGoToPlayoffs={() => setView('playoffs')}
                />
              </div>
            )}
            {view === 'tienda' && (
              <div key={view} className="animate-fade-in-up">
                <ShopView role={role} session={session} ownUser={ownUser} users={users} onCoinsChange={syncCoins} />
              </div>
            )}
            {view === 'ruleta' && role === 'Administrador' && (
              <div key={view} className="animate-fade-in-up">
                <RouletteView
                  role={role}
                  segments={rouletteSegments}
                  onSegmentsChange={updateRouletteSegments}
                  animated={rouletteAnimated}
                  onAnimatedChange={updateRouletteAnimated}
                  history={rouletteHistory}
                  onSpinResult={addRouletteResult}
                />
              </div>
            )}
            {view === 'normas' && <div key={view} className="animate-fade-in-up"><RulesView role={role} content={rulesContent} onSave={setRulesContent} /></div>}
            {view === 'estadisticas' && <div key={view} className="animate-fade-in-up"><StatsView users={users} /></div>}
            {view === 'admin' && role === 'Administrador' && (
              <div key={view} className="animate-fade-in-up">
                <AdminStub news={news} onAddNews={addNews} users={users} onAddUser={addUser} onDeleteUser={deleteUser} onGiveCoins={giveCoins} />
              </div>
            )}
            {view === 'perfil' && (
              <div key={view} className="animate-fade-in-up">
                <TrackerView
                  users={users}
                  role={role}
                  session={session}
                  onRouteChange={updateUserRoute}
                  onAddCustomRoute={addCustomRoute}
                  onDeleteCustomRoute={deleteCustomRoute}
                />
              </div>
            )}
          </main>
        </div>
      </div>
    </>
  );
}
