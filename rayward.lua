-- ============================================================
-- rayward.lua - VAC Plugin "Rayward Intel" v1.0
-- (carga: return function(api) ... end - formato del cargador del core)
--
-- Inteligencia de cuentas 100% OPT-IN (se activa en la tab PLUGINS):
--   * NUEVA       : AccountAge < 30 dias (dato replicado - 0 HTTP)
--   * COMPRADA?   : cuenta > 365 dias con senales de recompra (badges
--                   publicos mas nuevos que la historia de la cuenta)
--                   - solo se sondea a cuentas candidatas (rate limit)
--   * ALTO RIESGO : fichada por Exploit Watcher (robloxwatcher.com,
--                   requiere API key: vac> rayward key <tu_key>)
--   * LIMPIA      : nada de lo anterior
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
        OLD_DAYS = 365,       -- > 365 d -> candidata a recompra (PGed)
        RATE     = 2,         -- segundos entre peticiones HTTP (cola FIFO)
        BACKOFF  = 10,        -- espera extra tras un 429
        QUEUE_MAX = 60,       -- tope de cola (salas enormes: se recorta)
    }
    -- Endpoint de Exploit Watcher: se APRENDE el primero que responde
    -- (la doc publica lista /api/v1/exploitwatcher/search; el parametro
    -- exacto puede variar). Autenticacion: se envian AMBOS headers y el
    -- servidor usa el que reconozca.
    local EP_CANDIDATES = {
        "https://api.robloxwatcher.com/api/v1/exploitwatcher/search?userId=%d",
        "https://robloxwatcher.com/api/v1/exploitwatcher/search?userId=%d",
        "https://api.robloxwatcher.com/api/v1/exploitwatcher/search?robloxId=%d",
        "https://api.robloxwatcher.com/api/v1/robloxwatcher/search?userId=%d",
    }
    local RBX_BADGES = "https://badges.roblox.com/v1/users/%d/badges?limit=10&sortOrder=Asc"
    local RBX_GROUPS = "https://groups.roblox.com/v2/users/%d/groups/roles"

    local cache      = {}   -- [userId] = { pending=true } | resultado final
    local alerted    = {}   -- [userId] = true (UNA alerta por sesion)
    local queue      = {}   -- FIFO de userIds pendientes
    local lastReq    = 0    -- api.clock() de la ultima peticion HTTP
    local lastStamp  = (api.raywardStamp and api.raywardStamp()) or 0
    local key, keyAt = nil, -1e9
    local epIdx      = 0    -- endpoint aprendido (0 = sin aprender)
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

    -- recorre la respuesta del watcher buscando servidores de Discord
    -- flaggeados y el rol del usuario en cada uno (tolerante a cambios)
    local function extractWatch(j)
        local out = {}
        local function walk(t, depth)
            if type(t) ~= "table" or depth > 5 then return end
            for _, v in pairs(t) do
                if type(v) == "table" then
                    local nm = v.name or v.server_name or v.guild_name
                        or v.server or v.guild or v.discord
                    local rl = v.role or v.roles or v.user_role
                    if type(nm) == "string" and #nm > 0 and #nm < 128 then
                        local role = ""
                        if type(rl) == "string" then role = rl
                        elseif type(rl) == "table" and #rl > 0 then
                            local rp = {}
                            for _, r in ipairs(rl) do
                                rp[#rp + 1] = (type(r) == "string") and r
                                    or (type(r) == "table" and tostring(r.name) or nil) or ""
                            end
                            role = table.concat(rp, ",")
                        end
                        out[#out + 1] = { name = nm, role = role }
                    end
                    walk(v, depth + 1)
                end
            end
        end
        walk(j, 1)
        return out
    end

    local function fetchJSON(url, headers)
        local okB, body = pcall(api.raywardFetch, url, "GET", headers, nil)
        lastReq = api.clock()
        if not okB or type(body) ~= "string" or #body < 2 then return nil end
        return jdec(body)
    end

    -- analisis completo de UN jugador (1-3 peticiones, ya rate-limitadas)
    local function analyze(uid, info)
        local age = tonumber(info.accountAge) or 0
        local res = { name = info.name, status = "LIMPIA", reason = "",
                      age = age, watch = false }

        -- 1) EXPLOIT WATCHER (solo con key)
        if key then
            local hdr = { ["x-api-key"] = key, ["Authorization"] = "Bearer " .. key }
            local body, code
            local first = (epIdx > 0) and epIdx or 1
            local okB, b, c = pcall(api.raywardFetch,
                string.format(EP_CANDIDATES[first], uid), "GET", hdr, nil)
            if okB then body, code = b, c end
            lastReq = api.clock()
            if not body and epIdx == 0 then
                for i = 2, #EP_CANDIDATES do
                    local okB2, b2, c2 = pcall(api.raywardFetch,
                        string.format(EP_CANDIDATES[i], uid), "GET", hdr, nil)
                    if okB2 and b2 then body, code, epIdx = b2, c2, i break end
                end
            end
            if body then
                local j = jdec(body)
                local dw = j and extractWatch(j) or nil
                if dw and #dw > 0 then
                    res.watch = true
                    res.status = "ALTO RIESGO"
                    local parts = {}
                    for i = 1, math.min(2, #dw) do
                        parts[#parts + 1] = dw[i].name
                            .. ((dw[i].role ~= "") and (" (" .. dw[i].role .. ")") or "")
                    end
                    res.reason = "Exploit Watcher: " .. table.concat(parts, " * ")
                end
            elseif code == 401 or code == 403 then
                if not keyBad then
                    keyBad = true
                    pcall(api.log, "rayward",
                        "API key rechazada (401/403) - revisala: vac> rayward key <tu_key>")
                end
            elseif code == 429 then
                lastReq = api.clock() + CFG.BACKOFF   -- backoff suave
            end
        end

        -- 2) SONDEO PGED (solo cuentas > OLD_DAYS - cuida el rate limit)
        if res.status == "LIMPIA" and age >= CFG.OLD_DAYS then
            local signals, why = 0, {}
            local bj = fetchJSON(string.format(RBX_BADGES, uid))
            if bj and type(bj.data) == "table" then
                local oldest
                for _, b in ipairs(bj.data) do
                    local d = isoDays(b.created)
                    if d and (not oldest or d < oldest) then oldest = d end
                end
                if oldest == nil then
                    signals = signals + 1
                    why[#why + 1] = "sin badges publicos"
                elseif oldest < 90 then
                    signals = signals + 2
                    why[#why + 1] = ("badge mas antiguo de hace %dd en cuenta de %dd")
                        :format(oldest, age)
                end
            end
            local gj = fetchJSON(string.format(RBX_GROUPS, uid))
            if gj and type(gj.data) == "table" and #gj.data == 0 then
                signals = signals + 1
                why[#why + 1] = "sin grupos"
            end
            if signals >= 2 then
                res.status = "COMPRADA?"
                res.reason = "posible recompra: " .. table.concat(why, " + ")
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
                if (res.status == "ALTO RIESGO" or res.status == "COMPRADA?")
                   and not alerted[uid] then
                    alerted[uid] = true
                    pcall(api.log, "rayward", string.format(
                        "ALERTA %s (#%d): %s (%dd) - %s",
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
        version = "1.0",
        desc = "Detector de cuentas nuevas, compradas (PGed) y reputacion Exploit Watcher",
        interval = 5,     -- ciclo de escaneo cada 5 s cuando esta ON
        override = true,  -- sustituye al stub registrado por el core
        run = run,
    })
end
