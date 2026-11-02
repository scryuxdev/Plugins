-- ============================================================
-- uiplus.lua -- PLUGIN "Mejora de interfaz" (v3.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #36, core v11.23).
-- El archivo devuelve una funcion que recibe la API del nucleo:
--   api.register(def)      -> registra/actualiza este plugin
--   api.setting(k)         -> lee un ajuste del core (solo lectura)
--   api.log(nombre, texto) -> escribe en LOGS como [plugin:nombre]
--   api.applyTheme()       -> recalcula la paleta (COL)
--   api.rebuildUI()        -> reconstruye la GUI con el tema nuevo
--   api.fileWrite/read     -> escritura/lectura segura de archivos
-- Personaliza UI Tema (1-7) y UI Tinte (0-30) en SETTINGS y PERSISTE
-- en vac_ui_custom.json: al reactivar la tarjeta en otra sesion, tus
-- cambios vuelven solos.
-- v3.0 (alineado al core v11.23) -- por que cambia respecto a v2.0:
--   * Clamp defensivo ANTES de aplicar y guardar: tema 1-7 y tinte
--     0-30 con floor (un valor 2.5, negativo o NaN no deja la paleta
--     a medias ni guarda basura en el JSON).
--   * Aviso UNA sola vez si el valor en SETTINGS estaba fuera de
--     rango (antes un valor raro se aplicaba en silencio o el core
--     caia al tema 1 sin explicar por que).
-- ============================================================
return function(api)
    local HS = game:GetService("HttpService")
    local FILE = "vac_ui_custom.json"
    local applied = { theme = nil, tint = nil }
    local warned = { theme = false, tint = false }

    local function guardar(th, ti)
        return api.fileWrite(FILE, HS:JSONEncode({ uiTheme = th, uiTint = ti }))
    end

    api.register({
        name = "uiplus",
        version = "3.0",
        interval = 0.5,
        override = true,
        desc = "Temas + tinte de la interfaz (clamp 1-7 / 0-30), guardado en vac_ui_custom.json",
        run = function()
            local rawTh = tonumber(api.setting("uiTheme"))
            local rawTi = tonumber(api.setting("uiTint"))
            local th = api.clamp(math.floor(rawTh or 1), 1, 7)
            local ti = api.clamp(math.floor(rawTi or 0), 0, 30)
            if rawTh and (rawTh < 1 or rawTh > 7 or rawTh ~= rawTh) and not warned.theme then
                warned.theme = true
                api.log("uiplus", ("uiTheme fuera de rango (%s): aplicando 1-7"):format(tostring(rawTh)))
            end
            if rawTi and (rawTi < 0 or rawTi > 30 or rawTi ~= rawTi) and not warned.tint then
                warned.tint = true
                api.log("uiplus", ("uiTint fuera de rango (%s): aplicando 0-30"):format(tostring(rawTi)))
            end
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
