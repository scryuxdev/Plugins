-- ============================================================
-- coreplus.lua — PLUGIN "Core optimization" (v2.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #27). Si el FPS cae
-- (nivel 2+): baja los Hz de ui/core/balas/recycler y recorta los
-- buffers de LOGS/INCOME (menos memoria, menos trabajo por frame).
-- Cuando el FPS se mantiene sano 15 s seguidos, vuelve a la velocidad
-- normal solo. Nada de esto toca la deteccion: es solo rendimiento.
-- ============================================================
return function(api)
    local BASE = {
        uiHz = api.setting("uiHz"), coreHz = api.setting("coreHz"),
        bulletHz = api.setting("bulletHz"), recyclerHz = api.setting("recyclerHz"),
    }
    local low, okSince = false, 0

    api.register({
        name = "coreplus",
        version = "2.0",
        interval = 2,
        override = true,
        desc = "Hz adaptativo (ui/core/bullets) y recorte de logs cuando el FPS cae",
        run = function()
            local _, lvl = api.fps()
            if lvl >= 2 and not low then
                low = true
                okSince = 0
                api.setSetting("uiHz", 12)
                api.setSetting("coreHz", 3)
                api.setSetting("bulletHz", 8)
                api.setSetting("recyclerHz", 4)
                api.trimBuffers(150, 60)
                api.log("coreplus", "FPS bajo: modo economico (ui 12Hz, core 3Hz, logs recortados)")
            elseif low and lvl == 0 then
                if okSince == 0 then okSince = api.clock() end
                if api.clock() - okSince > 15 then
                    low = false
                    okSince = 0
                    api.setSetting("uiHz", BASE.uiHz or 30)
                    api.setSetting("coreHz", BASE.coreHz or 6)
                    api.setSetting("bulletHz", BASE.bulletHz or 15)
                    api.setSetting("recyclerHz", BASE.recyclerHz or 8)
                    api.log("coreplus", "FPS recuperado 15s: volviendo a velocidad normal")
                end
            elseif lvl >= 1 then
                okSince = 0
            end
            api.trimBuffers(250, 90)
        end,
    })
end
