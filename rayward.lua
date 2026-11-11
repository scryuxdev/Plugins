-- ============================================================
-- rayward.lua - VAC Plugin "Rayward Intel" v1.1
-- (carga: return function(api) ... end - formato del cargador del core)
--
-- Inteligencia de cuentas 100% OPT-IN (se activa en la tab PLUGINS):
--   * ALTO RIESGO : fichada por Exploit Watcher (inyecciones severas
--                   registradas; requiere API key EW_: vac> rayward key <k>)
--   * REVISAR     : edad replicada no coincide con la fuente oficial
--                   (users.roblox.com) o cuenta marcada baneada — dato
--                   para el operador, NO prueba de nada
--   * NUEVA       : AccountAge < 30 dias (dato replicado - 0 HTTP)
--   * LIMPIA      : nada de lo anterior
--
-- v1.1 (auto-mejora ronda #94): los 4 endpoints adivinados de la v1.0
--   se sustituyen por el ESQUEMA REAL documentado (OpenAPI v1.4.0):
--     GET https://api.robloxwatcher.com/api/v1/exploitwatcher/roblox/search/{robloxId}
--     auth: header X-API-Key (o Bearer) · key con prefijo EW_
--     resp: { flagged, totalInjections, totalGamesInjected,
--             injectedGames[{name,lastInjection}], discordAccounts[{id,flagged}] }
--   Y el CAMBIO DE PRIVACIDAD de Roblox (23-03-2026): el endpoint publico
--   de badges exige auth ahora (401) -> la heuristica "badge antiguo en
--   cuenta vieja" murio y "sin badges" ya NO es senal (privacidad
--   normal). Politica CERO FP: nada inventado, solo la fuente oficial.
--
-- Politica CERO falsos positivos: NUNCA suma score ni auto-acusa.
-- Pinta la pestana Rayward y avisa UNA vez por jugador; el operador
-- decide (LiveCam, vigilancia, reporte).
--
-- Red: SOLO via api.raywardFetch (ACL estricta del core). Cola FIFO de
-- 1 peticion cada 2 s + cache por userId: sin martillear la API ni
-- quemar la cuota diaria de la key (nunca 429 por repetir).
-- ============================================================
return function(api)
    local CFG = {
        NEW_DAYS = 30,        -- < 30 d  -> cuenta nueva/desechable
        OLD_DAYS = 365,       -- > 365 d -> candidata a verificacion
        RATE     = 2,         -- segundos entre peticiones HTTP (cola FIFO)
        BACKOFF  = 10,        -- espera extra tras un 429
        QUEUE_MAX = 60,       -- tope de cola (salas enormes: se recorta)
    }
    -- v1.1: endpoints UNICOS, tal cual el esquema OpenAPI oficial
    -- (api.robloxwatcher.com, produccion; auth por header). users.roblox.com
    -- ya estaba en la ACL del core y sigue publico (verificado in vivo).
    local EP_WATCHER = "https://api.robloxwatcher.com/api/v1/exploitwatcher/roblox/search/%d"
    local RBX_USER   = "https://users.roblox.com/v1/users/%d"

    local cache      = {}   -- [userId] = { pending=true } | resultado final
    local alerted    = {}   -- [userId] = true (UNA alerta por sesion)
    local queue      = {}   -- FIFO de userIds pendientes
    local lastReq    = 0    -- api.clock() de la ultima peticion HTTP
    local lastStamp  = (api.raywardStamp and api.raywardStamp()) or 0
    local key, keyAt = nil, -1e9
    local keyBad     = false

    -- key: la lee del SU archivo (ACL vac_plug_rayward_*); refresco cada
    -- 60 s para cogerla sin reiniciar si la pegas despues por terminal.
    local function loadKey()
        local ok, k = pcall(api.fileRead, "vac_plug_rayward_key.txt")
        if ok and type(k) == "string" then
            k = k:match("^%s*(.-)%s*$")
            if k and #k >= 8 then key = k return end
        end
        key = nil
    end

    local function jdec(s)
        local ok, j = pcall(function()
            return game:GetService("HttpService"):JSONDecode(s)
        end)
        if ok then return j end
        return nil
    end

    -- dias desde una fecha ISO de Roblox ("2019-03-12T...") hasta ahora
    local function isoDays(iso)
        if type(iso) ~= "string" or #iso < 10 then return nil end
        local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if not y then return nil end
        local okT, t = pcall(os.time, { year = tonumber(y), month = tonumber(m),
            day = tonumber(d), hour = 12 })
        if not okT or not t then return nil end
        return math.floor((os.time() - t) / 86400)
    end

    -- v1.1: parse del ESQUEMA DOCUMENTADO de Exploit Watcher (tolerante a
    -- campos ausentes; nada se inventa: si el campo no viene, no se usa).
    local function parseWatch(j)
        if type(j) ~= "table" then return nil end
        local out = { flagged = (j.flagged == true),
                      inj = tonumber(j.totalInjections) or 0,
                      games = tonumber(j.totalGamesInjected) or 0,
                      names = {}, discs = {} }
        if type(j.injectedGames) == "table" then
            for _, g in ipairs(j.injectedGames) do
                if type(g) == "table" and type(g.name) == "string"
                   and #g.name > 0 and #out.names < 2 then
                    local last = isoDays(tostring(g.lastInjection or ""))
                    out.names[#out.names + 1] = g.name
                        .. ((last and last > 0) and (" (hace " .. last .. "d)") or "")
                end
            end
        end
        if type(j.discordAccounts) == "table" then
            for _, da in ipairs(j.discordAccounts) do
                if type(da) == "table" and da.flagged == true and #out.discs < 2 then
                    out.discs[#out.discs + 1] = tostring(da.id or "")
                end
            end
        end
        return out
    end

    local function fetchJSON(url, headers)
        local okB, body = pcall(api.raywardFetch, url, "GET", headers, nil)
        lastReq = api.clock()
        if not okB or type(body) ~= "string" or #body < 2 then return nil end
        return jdec(body)
    end

    -- analisis completo de UN jugador (1-2 peticiones, ya rate-limitadas)
    local function analyze(uid, info)
        local age = tonumber(info.accountAge) or 0
        local res = { name = info.name, status = "LIMPIA", reason = "",
                      age = age, watch = false }

        -- 1) EXPLOIT WATCHER (solo con key; endpoint documentado unico)
        if key then
            local hdr = { ["X-API-Key"] = key, ["Authorization"] = "Bearer " .. key }
            local okB, body, code = pcall(api.raywardFetch,
                string.format(EP_WATCHER, uid), "GET", hdr, nil)
            lastReq = api.clock()
            if okB and type(body) == "string" then
                local w = parseWatch(jdec(body))
                if w and w.flagged then
                    res.watch = true
                    res.status = "ALTO RIESGO"
                    local det = ("inyecto %d vez/veces en %d juego(s)"):format(w.inj, w.games)
                    if #w.names > 0 then
                        det = det .. " (" .. table.concat(w.names, ", ") .. ")"
                    end
                    if #w.discs > 0 then det = det .. " - discord ligado fichado" end
                    res.reason = "Exploit Watcher: " .. det
                    local dl = {}
                    for _, did in ipairs(w.discs) do
                        dl[#dl + 1] = { name = "Discord " .. did, role = "ligado fichado" }
                    end
                    if #dl > 0 then res.discords = dl end
                elseif w and (w.inj > 0 or w.games > 0) then
                    -- historial presente pero sin flag severo: dato, no senal
                    res.reason = ("historial del watcher: %d inyeccion(es) registradas, sin flag severo")
                        :format(w.inj)
                end
            elseif code == 401 or code == 403 then
                if not keyBad then
                    keyBad = true
                    pcall(api.log, "rayward",
                        "API key rechazada (401/403) - las keys Exploit Watcher empiezan por EW_: revisala: vac> rayward key <tu_key>")
                end
            elseif code == 429 then
                lastReq = api.clock() + CFG.BACKOFF   -- backoff suave
            end
        end

        -- 2) VERIFICACION DE CUENTA (solo candidatas > OLD_DAYS):
        --    users.roblox.com es la fuente oficial y sigue publica.
        --    (los badges publicos murieron con la privacidad 2026-03:
        --    NO se inventan senales debiles — politica cero FP)
        if res.status == "LIMPIA" and age >= CFG.OLD_DAYS then
            local uj = fetchJSON(string.format(RBX_USER, uid))
            if uj and type(uj.created) == "string" then
                local rd = isoDays(uj.created)
                if rd and rd > 0 and math.abs(rd - age) > 45 then
                    res.status = "REVISAR"
                    res.reason = ("edad replicada %dd, fuente oficial %dd - no coinciden")
                        :format(age, rd)
                end
                if uj.isBanned == true and res.status == "LIMPIA" then
                    res.status = "REVISAR"
                    res.reason = "cuenta marcada baneada en users.roblox.com"
                end
            end
        end

        -- 3) NUEVA (local - 0 HTTP, dato replicado)
        if res.status == "LIMPIA" and age > 0 and age < CFG.NEW_DAYS then
            res.status = "NUEVA"
            res.reason = ("cuenta de %d dias"):format(age)
        end
        return res
    end

    local function run()
        local now = api.clock()

        -- `rayward scan` (terminal): limpia cache y cola para re-escanear
        local stamp = (api.raywardStamp and api.raywardStamp()) or 0
        if stamp ~= lastStamp then
            lastStamp = stamp
            cache, alerted, queue = {}, {}, {}
        end

        -- key fresca cada 60 s (por si la pegan despues por terminal)
        if now - keyAt > 60 then
            keyAt = now
            loadKey()
        end

        local okP, players = pcall(api.getPlayersInfo)
        if not okP or type(players) ~= "table" then return end

        local present = {}
        for _, inf in ipairs(players) do
            if type(inf) == "table" and inf.userId then
                present[inf.userId] = inf
                if not cache[inf.userId] then
                    cache[inf.userId] = { pending = true }
                    queue[#queue + 1] = inf.userId
                end
            end
        end
        -- los que salieron: fuera del cache y de la cola
        for uid in pairs(cache) do
            if not present[uid] then
                cache[uid] = nil
                alerted[uid] = nil
            end
        end
        local nq = {}
        for _, uid in ipairs(queue) do
            if present[uid] and cache[uid] and cache[uid].pending then
                nq[#nq + 1] = uid
            end
        end
        queue = nq
        while #queue > CFG.QUEUE_MAX do table.remove(queue, 1) end

        -- UNA peticion por tick como maximo (FIFO, gate RATE)
        if #queue > 0 and (now - lastReq) >= CFG.RATE then
            local uid = table.remove(queue, 1)
            local inf = present[uid]
            local okA, res = pcall(analyze, uid, inf)
            if okA and type(res) == "table" then
                cache[uid] = res
                pcall(api.setRaywardResult, uid, res)
                if (res.status == "ALTO RIESGO" or res.status == "REVISAR")
                   and not alerted[uid] then
                    alerted[uid] = true
                    pcall(api.log, "rayward", string.format(
                        "AVISO %s (#%d): %s (%dd) - %s",
                        tostring(inf.name), uid, res.status,
                        tonumber(inf.accountAge) or 0,
                        res.reason ~= "" and res.reason or "sin detalle"))
                end
            else
                cache[uid] = { name = inf and inf.name or tostring(uid),
                    status = "S/D", reason = "error de analisis",
                    age = (inf and inf.accountAge) or 0 }
            end
        end
    end

    api.register({
        name = "rayward",
        version = "1.1",
        desc = "Intel de cuentas: nuevas, fichadas por Exploit Watcher (API real v1.4) y verificacion users.roblox.com",
        interval = 5,     -- ciclo de escaneo cada 5 s cuando esta ON
        override = true,  -- sustituye al stub registrado por el core
        run = run,
    })
end
