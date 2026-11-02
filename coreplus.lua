-- ============================================================
-- coreplus.lua -- PLUGIN "Core optimization" (v3.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #36, core v11.23).
-- Si el FPS cae (nivel 2+): baja core/recycler a ritmo economico y
-- recorta los buffers de LOGS/INCOME (menos memoria, menos trabajo).
-- Cuando el FPS se mantiene sano 15 s seguidos, vuelve a la velocidad
-- normal solo. Nada de esto toca la deteccion: es solo rendimiento.
-- v3.0 (alineado al core v11.23) -- por que cambia respecto a v2.0:
--   * TURBO manda: si api.turbo() esta caliente (sospechoso con score,
--     live view, espectateo o cola de balas) NO entra en economico y,
--     si ya estaba en economico, recupera al instante. Ver a un
--     cheater jamas se puede volver mas lento porque baje el FPS.
--   * Ya no escribe bulletHz: desde v11.18 el worker de balas usa
--     presupuesto por tick + conexiones de evento y ese ajuste esta
--     MUERTO (escribirlo no hacia nada y el log lo prometia).
--   * Ya no escribe uiHz: el core fuerza uiHz por nivel de FPS
--     (15/10/6/4) y en nivel 2+ el valor del ajuste se ignora.
--   * Fallbacks alineados a los defaults reales del core (coreHz 5,
--     recyclerHz 10) por si api.setting devuelve nil.
-- ============================================================
return function(api)
    local BASE = {
        coreHz = api.setting("coreHz") or 5,
        recyclerHz = api.setting("recyclerHz") or 10,
    }
    local low, okSince = false, 0

    local function modoNormal()
        api.setSetting("coreHz", BASE.coreHz)
        api.setSetting("recyclerHz", BASE.recyclerHz)
    end

    api.register({
        name = "coreplus",
        version = "3.0",
        interval = 2,
        override = true,
        desc = "Hz economico (core/recycler) y recorte de logs cuando el FPS cae; nunca durante TURBO",
        run = function()
            local _, lvl = api.fps()
            local hot = api.turbo()
            if hot then
                -- v3.0: TURBO manda -- la observacion va primero.
                if low then
                    low = false
                    okSince = 0
                    modoNormal()
                    api.log("coreplus", "TURBO activo: economico cancelado (la observacion va primero)")
                end
            elseif lvl >= 2 and not low then
                low = true
                okSince = 0
                api.setSetting("coreHz", 3)
                api.setSetting("recyclerHz", 4)
                api.trimBuffers(150, 60)
                api.log("coreplus", "FPS bajo: modo economico (core 3Hz, recycler 4Hz, logs recortados)")
            elseif low and lvl == 0 then
                if okSince == 0 then okSince = api.clock() end
                if api.clock() - okSince > 15 then
                    low = false
                    okSince = 0
                    modoNormal()
                    api.log("coreplus", "FPS recuperado 15s: volviendo a velocidad normal")
                end
            elseif lvl >= 1 then
                okSince = 0
            end
            api.trimBuffers(250, 90)
        end,
    })
end
