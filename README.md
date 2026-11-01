# VAC Watcher — Town (client-side, executor)

## ⬇️ ¿Qué descargar?

1. **`Script #27.lua` (v11.14)** — el script completo (lo único que ejecutas).
2. **`plugins/`** — los 3 módulos remotos: `uiplus.lua`, `infoplus.lua`, `coreplus.lua`.
   **NO se ejecutan**: se suben a tu repo de GitHub.

## 📦 Configurar el repo (una sola vez)

El script descarga los plugins con **loadstring** desde GitHub (ahorra líneas
en el core y te permite actualizar plugins sin tocar el script):

1. Repo: `https://github.com/scryuxdev/Plugins` (ya existe, rama `main`).
2. Sube los 3 archivos a la **raíz** del repo:
   - `uiplus.lua` — Mejora de interfaz
   - `infoplus.lua` — Informacion
   - `coreplus.lua` — Core optimization
3. Listo. El script intenta las ramas `main` y `master` automáticamente.

URLs que usará el core:
`https://raw.githubusercontent.com/scryuxdev/Plugins/main/uiplus.lua` (etc.)

## 🔌 Cómo funcionan las TARJETAS de plugins

- Tab **PLUGINS** = 3 TARJETAS (cards), nacen **APAGADAS por defecto**.
- **Clic en una tarjeta** → se activa (y la primera vez descarga su módulo
  desde GitHub con loadstring). Clic de nuevo → se desactiva.
- Estados del badge: `OFF` · `ON` · `CARGA...` (descargando) · `MUERTO`
  (15 errores = auto-apagado, el core nunca se tumba).
- Si GitHub falla: la tarjeta se apaga sola con error en LOGS.
- Todo lo que un plugin escribe sale como `[plugin:nombre]` en LOGS.

### Los 3 plugins
| Tarjeta | Clave | Qué hace |
|---|---|---|
| **Mejora de interfaz** | `uiplus` | 7 temas + tinte de paneles (SETTINGS → UI Tema/UI Tinte). Guarda tus cambios en `vac_ui_custom.json` y los recupera solo al reactivarla. |
| **Informacion** | `infoplus` | Más info en la card INFO del live view (observado, evidencias, última flag, FPS, flagsEver, ping) y refresco de detalles ×2. |
| **Core optimization** | `coreplus` | Si el FPS baja: modo económico (ui 12Hz, core 3Hz) + recorta logs; al recuperarse 15 s vuelve solo. |

## 🛠️ API para plugins futuros

Cada archivo del repo hace `return function(api) ... end` y recibe:
`api.register(def)` (con `override=true`), `api.setting/setSetting`,
`api.log`, `api.setHook`, `api.fps`, `api.clock`, `api.clamp`,
`api.trimBuffers`, `api.applyTheme`, `api.rebuildUI`,
`api.fileRead/fileWrite`, `api.snapshot`, `api.isEnabled`.

## v11.14 — resumen
- Plugins remotos por loadstring (GitHub `scryuxdev/Plugins`).
- Tab PLUGINS con tarjetas activables/desactivables (antes filas).
- Core sin la lógica embebida de los 3 plugins (~90 líneas ahorradas;
  los plugins ahora viven en el repo y se actualizan sin tocar el script).
- Se mantiene todo v11.13 (interfaz renovada + SIGILO) y v11.12 (fix
  `Enum.Material.Rocky`).

## Historial
`#12` v11.1 → … → `#22` v11.9 → `#23` v11.10 (radar town) → `#24` v11.11
(PPL + TRUST + FINGERPRINTS) → `#25` v11.12 (fix Rocky + plugins) →
`#26` v11.13 (interfaz renovada + sigilo) → **`#27` v11.14 (plugins remotos
por loadstring + tarjetas) — VIGENTE**.
