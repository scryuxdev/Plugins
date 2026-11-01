-- ============================================================
-- uiplus.lua — PLUGIN "Mejora de interfaz" (v2.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #27). El archivo
-- devuelve una funcion que recibe la API del nucleo:
--   api.register(def)      -> registra/actualiza este plugin
--   api.setting(k)         -> lee un ajuste del core (solo lectura)
--   api.log(nombre, texto) -> escribe en LOGS como [plugin:nombre]
--   api.applyTheme()       -> recalcula la paleta (COL)
--   api.rebuildUI()        -> reconstruye la GUI con el tema nuevo
--   api.fileWrite/read     -> escritura/lectura segura de archivos
-- Personaliza UI Tema (1-7) y UI Tinte (0-30) en SETTINGS y PERSISTE
-- en vac_ui_custom.json: al reactivar la tarjeta en otra sesion, tus
-- cambios vuelven solos.
-- ============================================================
return function(api)
    local HS = game:GetService("HttpService")
    local FILE = "vac_ui_custom.json"
    local applied = { theme = nil, tint = nil }

    local function guardar(th, ti)
        return api.fileWrite(FILE, HS:JSONEncode({ uiTheme = th, uiTint = ti }))
    end

    api.register({
        name = "uiplus",
        version = "2.0",
        interval = 0.5,
        override = true,
        desc = "Temas + tinte de la interfaz, guardado en vac_ui_custom.json",
        run = function()
            local th = tonumber(api.setting("uiTheme")) or 1
            local ti = api.clamp(tonumber(api.setting("uiTint")) or 0, 0, 30)
            if th ~= applied.theme or ti ~= applied.tint then
                local primero = (applied.theme == nil)
                applied.theme, applied.tint = th, ti
                local okF = guardar(th, ti)
                api.log("uiplus", ("tema %d, tinte %d aplicados%s"):format(
                    th, ti, okF and " y guardados en " .. FILE or " (sin writefile: solo esta sesion)"))
                if primero then
                    api.log("uiplus", "activo: personaliza en SETTINGS -> UI Tema / UI Tinte (se guarda solo)")
                end
                api.applyTheme()
                api.rebuildUI()
            end
        end,
    })
end
