-- ============================================================
-- infoplus.lua — PLUGIN "Informacion" (v2.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #27). Anyade lineas
-- a la card INFO del live view via api.setHook("info", fn) y el core
-- ya refresca los detalles el doble de rapido cuando esta activo
-- (FN.detailGap consulta isEnabled("infoplus")).
-- Campos que recibe el hook: d (datos del jugador observado),
-- lines (tabla de lineas RichText de la card) y dm (color hex).
-- ============================================================
return function(api)
    api.setHook("info", function(d, lines, dm)
        local ahora = api.clock()
        local seenMin = math.floor((ahora - (d.firstSeen or ahora)) / 60)
        local evN = d.evidence and #d.evidence or 0
        local evLast = "-"
        if d.evidence and evN > 0 then
            evLast = tostring(d.evidence[evN].type or "?")
        end
        local fev = 0
        if d.flagsEver then
            for _ in pairs(d.flagsEver) do fev = fev + 1 end
        end
        local fps, lvl = api.fps()
        lines[#lines + 1] = ("<font color='%s'>Info+</font> observado %dm   evidencias %d   ultima %s"):format(
            dm, seenMin, evN, evLast)
        lines[#lines + 1] = ("<font color='%s'>Info+</font> FPS %d (nivel %d)   flagsEver %d   ping %dms"):format(
            dm, fps, lvl, fev, d.ping or 0)
    end)

    api.register({
        name = "infoplus",
        version = "2.0",
        override = true,
        desc = "Mas info en la card INFO (observado, evidencias, FPS, ping) y refresco x2",
    })
end
