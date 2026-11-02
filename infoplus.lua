-- ============================================================
-- infoplus.lua -- PLUGIN "Informacion" (v3.0, remoto)
-- Repo: https://github.com/scryuxdev/Plugins
-- ------------------------------------------------------------
-- Se carga con loadstring desde el core (Script #36, core v11.23).
-- Anyade lineas a la card INFO del live view via api.setHook("info", fn)
-- y el core ya refresca los detalles el doble de rapido cuando esta
-- activo (FN.detailGap consulta isEnabled("infoplus")).
-- Campos que recibe el hook: d (datos del jugador observado),
-- lines (tabla de lineas RichText de la card) y dm (color hex).
-- v3.0 (alineado al core v11.23) -- por que cambia respecto a v2.0:
--   * TURBO (v11.22) via api.turbo(): HOT = los workers van al doble
--     de ritmo porque hay actividad caliente (sospechoso, live view,
--     espectateo o cola de balas). Antes esta senal no existia.
--   * SEC (v11.21) via api.sec(): trampas de conducta / camara. Solo
--     avisa cuando algo va MAL (en la tab PRIV ya esta el detalle).
--   * PPL (v11.11) del observado (d._ppl): aceleracion pico, vy+
--     sostenido, glide y teleports a 10 Hz -- la fisica por estado.
--   * QUITA el ping: el core ya lo muestra en su linea 2 (HP/Ping/Dist)
--     -- estaba duplicado desde siempre.
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
        local hot = api.turbo()
        lines[#lines + 1] = ("<font color='%s'>Info+</font> observado %dm   evidencias %d   ultima %s"):format(
            dm, seenMin, evN, evLast)
        lines[#lines + 1] = ("<font color='%s'>Info+</font> FPS %d (nivel %d)   flagsEver %d   turbo %s"):format(
            dm, fps, lvl, fev, hot and "HOT" or "idle")
        -- v3.0: fisica por estado del observado (solo si hay algo que mostrar)
        local ppl = d._ppl
        if ppl and ((ppl.acc or 0) > 0 or (ppl.up or 0) > 0
            or (ppl.glide or 0) > 0 or (ppl.tele or 0) > 0) then
            lines[#lines + 1] = ("<font color='%s'>Info+</font> PPL acc %.0f st/s2   vy+ %.2fs   glide %.2fs   tele %d"):format(
                dm, ppl.acc or 0, ppl.up or 0, ppl.glide or 0, ppl.tele or 0)
        end
        -- v3.0: SEC solo si algo va mal (hooks alterados o camara tocada)
        local sec = api.sec()
        if sec and ((not sec.hooksOK) or sec.camTampered) then
            lines[#lines + 1] = ("<font color='#ff5a5a'>Info+ SEC</font> hooks %s   camara %s"):format(
                sec.hooksOK and "OK" or "ALTERADOS", sec.camTampered and "ALTERADA" or "OK")
        end
    end)

    api.register({
        name = "infoplus",
        version = "3.0",
        override = true,
        desc = "Card INFO ampliada: TURBO, SEC, PPL, evidencias, FPS; refresco de detalles x2",
    })
end
