-- AntiResolver 2.0 Release | t.me/penaresolv
local BUILD = "2.0-release"
local BUILD_LABEL = "2.0 Release"
local DEFAULT_SYNC_URL = "https://brilliant-semolina-d874d6.netlify.app/api/presence"
local DEFAULT_CFG_URL = "https://brilliant-semolina-d874d6.netlify.app/api/configs"
local DEFAULT_LOGO_ASSET = ""
local DEFAULT_CLIENT_KEY = ""

local localPlayer = game:GetService("Players").LocalPlayer
assert(localPlayer and type(localPlayer.UserId) == "number" and localPlayer.UserId > 0 and localPlayer.UserId % 1 == 0,
    "AntiResolver needs a signed-in local player")

local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function roundInt(n) return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5) end
local function wrap(n) return (n + 180) % 360 - 180 end
local function clampPitch(n) return math.clamp(n, -89, 89) end
local function trimStr(s) return type(s) == "string" and (s:match("^%s*(.-)%s*$") or "") or "" end
local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end
local function nowSafe()
    if type(globals) == "table" and type(globals.realtime) == "function" then
        local ok, t = pcall(globals.realtime)
        if ok and finite(t) then return t end
    end
    return os.clock and os.clock() or 0
end
local function resolveHttpRequest()
    local getters = {
        function() return request end,
        function() return http_request end,
        function() return http and http.request end,
        function() return client and client.request end,
        function() return syn and syn.request end,
    }
    for _, g in ipairs(getters) do
        local ok, fn = pcall(g)
        if ok and type(fn) == "function" then return fn end
    end
    return nil
end
local function requireAPI(lib, name)
    assert(type(lib) == "table" and type(lib[name]) == "function", "Missing API: " .. tostring(name))
end

local STATES = {"Global", "Standing", "Moving", "Slow", "Crouching", "Crouch moving", "Air", "Air crouch"}
local MODES = {"Auto", "Adaptive", "Brute-force", "Debug"}
local CLANTAG_PRESETS = {"AntiResolver", "Neverlose", "Gamesense", "Primordial", "Custom"}
local ROLL_MODES = {"Off", "Static", "Follow Inverter", "Opposite Inverter", "Jitter", "Sway"}
local FAKEPITCH_MODES = {"Off", "Down", "Up", "Zero", "Custom", "Jitter"}

local function resolverMode(value)
    if value == "Auto DT" or value == "Animation" or value == "Jitter" or value == "Native" then return "Auto" end
    return value
end

local function profileDefault()
    return {
        enabled = false,
        pitchMode = "Fixed", pitchA = -89, pitchB = 89,
        yawBase = "camera", yawOffset = 180, yawMode = "Center", amplitude = 30,
        period = 4, pitchPeriod = 4, yawPeriod = 4, desyncPeriod = 4,
        spinSpeed = 6, sequence = {-30, 30, 0},
        desyncMode = "Limits", real = -58, fake = 58,
        left = 58, right = 58, inverter = "Alternate",
        fakeLag = false, lagLimit = 4, lagVariation = 0,
        rollMode = "Off", rollAmount = 0, rollPeriod = 4,
        fakePitchMode = "Off", fakePitchA = -70, fakePitchB = 70, fakePitchOffset = 0, fakePitchPeriod = 4,
        defensive = {
            enabled = false, trigger = "Charged", duration = 4, cooldown = 16,
            pitchMode = "Jitter", pitchA = -89, pitchB = 89, yawOffset = 180,
            amplitude = 70, period = 1, shift = false, shiftTicks = 4, flush = false,
            teleport = false, rollAmount = 0, fakePitch = false,
        },
    }
end

local function defaults()
    local profiles = {}
    for _, name in ipairs(STATES) do profiles[name] = profileDefault() end
    profiles.Global.enabled = true
    return {
        resolver = {
            enabled = true, mode = "Auto", pitch = "Auto",
            bodyAfter = 3, cycleAfter = 1, safe = false, memory = 12,
            dtHold = true, dtWindowMs = 150,
            fakePitch = true, disableBuiltinBaim = true, defensiveHold = true, noAaDetect = true,
            debug = false,
        },
        builder = {
            enabled = false, slow = 6, hysteresis = 3, manualKey = "V",
            respectManual = true, showFake = false,
            profiles = profiles,
        },
        sync = {enabled = true, endpoint = "", logoAsset = "", tabBadges = true, espBadges = true, stealth = false},
        clantag = {enabled = false, preset = "AntiResolver", customText = "AntiResolver", speed = 300},
    }
end

local function member(value, choices)
    for _, allowed in ipairs(choices) do if value == allowed then return true end end
    return false
end
local function vNum(value, def, low, high, integer)
    if value == nil then return def end
    assert(finite(value) and value >= low and value <= high and (not integer or value % 1 == 0), "Invalid numeric setting")
    return value
end
local function vBool(value, def)
    if value == nil then return def end
    assert(type(value) == "boolean", "Expected boolean")
    return value
end
local function vChoice(value, def, choices)
    if value == nil then return def end
    assert(member(value, choices), "Unknown option: " .. tostring(value))
    return value
end
local function vObj(value)
    if value == nil then return {} end
    assert(type(value) == "table", "Expected table")
    return value
end

local function validate(inputSettings)
    local source = vObj(inputSettings)
    local result = defaults()
    local r = vObj(source.resolver)
    local b = vObj(source.builder)
    local s = vObj(source.sync)
    local c = vObj(source.clantag)

    result.sync = {
        enabled = vBool(s.enabled, true),
        endpoint = "", logoAsset = "", tabBadges = true, espBadges = true, stealth = false,
    }
    local rawMode = resolverMode(r.mode)
    result.resolver = {
        enabled = vBool(r.enabled, true),
        mode = vChoice(rawMode, "Auto", MODES),
        pitch = vChoice(r.pitch, "Auto", {"Auto", "Raw", "Off"}),
        bodyAfter = vNum(r.bodyAfter, 3, 0, 5, true),
        cycleAfter = vNum(r.cycleAfter, 1, 1, 5, true),
        safe = vBool(r.safe, false),
        memory = vNum(r.memory, 12, 3, 60, true),
        dtHold = vBool(r.dtHold, true),
        dtWindowMs = vNum(r.dtWindowMs, 150, 50, 250, true),
        fakePitch = vBool(r.fakePitch, true),
        disableBuiltinBaim = vBool(r.disableBuiltinBaim, true),
        defensiveHold = vBool(r.defensiveHold, true),
        noAaDetect = vBool(r.noAaDetect, true),
        debug = rawMode == "Debug",
    }

    result.builder.enabled = vBool(b.enabled, false)
    result.builder.slow = vNum(b.slow, 6, 0, 30)
    result.builder.hysteresis = vNum(b.hysteresis, 3, 1, 12, true)
    result.builder.respectManual = vBool(b.respectManual, true)
    result.builder.showFake = vBool(b.showFake, false)
    if b.manualKey ~= nil then
        assert(type(b.manualKey) == "string" and #b.manualKey > 0 and #b.manualKey <= 24
            and b.manualKey:match("^[A-Za-z0-9]+$"), "Invalid defensive key")
        result.builder.manualKey = b.manualKey
    end
    local profiles = vObj(b.profiles)
    for _, name in ipairs(STATES) do
        local src, dst = vObj(profiles[name]), result.builder.profiles[name]
        dst.enabled = name == "Global" or vBool(src.enabled, false)
        dst.pitchMode = vChoice(src.pitchMode, "Fixed", {"Fixed", "Jitter", "Random", "Sway", "Flick"})
        dst.pitchA = vNum(src.pitchA, -89, -89, 89)
        dst.pitchB = vNum(src.pitchB, 89, -89, 89)
        dst.yawBase = vChoice(src.yawBase, "camera", {"camera", "world"})
        dst.yawOffset = vNum(src.yawOffset, 180, -180, 180)
        dst.yawMode = vChoice(src.yawMode, "Center", {"Off", "Center", "3-Way", "5-Way", "Spin", "Random", "Sequence"})
        dst.amplitude = vNum(src.amplitude, 30, 0, 180)
        dst.period = vNum(src.period, 4, 1, 64, true)
        dst.pitchPeriod = vNum(src.pitchPeriod, dst.period, 1, 64, true)
        dst.yawPeriod = vNum(src.yawPeriod, dst.period, 1, 64, true)
        dst.desyncPeriod = vNum(src.desyncPeriod, dst.period, 1, 64, true)
        dst.desyncMode = vChoice(src.desyncMode, "Limits", {"Limits", "Explicit"})
        dst.real = vNum(src.real, -58, -86, 86)
        dst.fake = vNum(src.fake, 58, -86, 86)
        dst.spinSpeed = vNum(src.spinSpeed, 6, -30, 30)
        if src.sequence ~= nil then
            assert(type(src.sequence) == "table" and #src.sequence >= 1 and #src.sequence <= 12, "Sequence needs 1-12 angles")
            dst.sequence = {}
            for i, angle in ipairs(src.sequence) do dst.sequence[i] = vNum(angle, 0, -180, 180) end
        end
        dst.left = vNum(src.left, 58, 0, 86)
        dst.right = vNum(src.right, 58, 0, 86)
        dst.inverter = vChoice(src.inverter, "Alternate", {"Left", "Right", "Alternate"})
        dst.fakeLag = vBool(src.fakeLag, false)
        dst.lagLimit = vNum(src.lagLimit, 4, 0, 14, true)
        dst.lagVariation = vNum(src.lagVariation, 0, 0, 100)
        dst.rollMode = vChoice(src.rollMode, "Off", ROLL_MODES)
        dst.rollAmount = vNum(src.rollAmount, 0, -100, 100)
        dst.rollPeriod = vNum(src.rollPeriod, 4, 1, 64, true)
        dst.fakePitchMode = vChoice(src.fakePitchMode, "Off", FAKEPITCH_MODES)
        dst.fakePitchA = vNum(src.fakePitchA, -70, -70, 70)
        dst.fakePitchB = vNum(src.fakePitchB, 70, -70, 70)
        dst.fakePitchOffset = vNum(src.fakePitchOffset, 0, -20, 20)
        dst.fakePitchPeriod = vNum(src.fakePitchPeriod, 4, 1, 64, true)
        local d, out = vObj(src.defensive), dst.defensive
        out.enabled = vBool(d.enabled, false)
        out.trigger = vChoice(d.trigger, "Charged", {"Charged", "Manual", "On shot"})
        out.duration = vNum(d.duration, 4, 1, 16, true)
        out.cooldown = vNum(d.cooldown, 16, 0, 512, true)
        out.pitchMode = vChoice(d.pitchMode, "Jitter", {"Fixed", "Jitter", "Random"})
        out.pitchA = vNum(d.pitchA, -89, -89, 89)
        out.pitchB = vNum(d.pitchB, 89, -89, 89)
        out.yawOffset = vNum(d.yawOffset, 180, -180, 180)
        out.amplitude = vNum(d.amplitude, 70, 0, 180)
        out.period = vNum(d.period, 1, 1, 16, true)
        out.shift = vBool(d.shift, false)
        out.shiftTicks = vNum(d.shiftTicks, 4, 1, 14, true)
        out.flush = vBool(d.flush, false)
        out.teleport = vBool(d.teleport, false)
        out.rollAmount = vNum(d.rollAmount, 0, -100, 100)
        out.fakePitch = vBool(d.fakePitch, false)
    end

    result.clantag = {
        enabled = vBool(c.enabled, false),
        preset = vChoice(c.preset, "AntiResolver", CLANTAG_PRESETS),
        customText = type(c.customText) == "string" and trimStr(c.customText):sub(1, 32) or "AntiResolver",
        speed = vNum(c.speed, 300, 100, 1000, true),
    }
    if result.clantag.customText == "" then result.clantag.customText = "AntiResolver" end
    return result
end

local Store = {
    key = "antiresolver.private.v2." .. tostring(localPlayer.UserId),
    owner = tostring(localPlayer.UserId),
    cloudStatus = "Syncing...",
    cloudOk = false,
    cloudPending = false,
    maxCloudSlots = 8,
}
local library = {owner = Store.owner, version = 2, sets = {}, last = nil, autoload = nil}
local alive = true
local Resolver = {}
local Builder = {}
local Sync = {}
local Clantag = {}
local Settings = defaults()
local Options = Settings.resolver
local applySettings
local onCloudLibraryUpdated

do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    local ruMap = {
        ["й"]="q",["ц"]="w",["у"]="e",["к"]="r",["е"]="t",["н"]="y",["г"]="u",["ш"]="i",["щ"]="o",["з"]="p",["х"]="[",["ъ"]="]",
        ["ф"]="a",["ы"]="s",["в"]="d",["а"]="f",["п"]="g",["р"]="h",["о"]="j",["л"]="k",["д"]="l",["ж"]=";",["э"]="'",
        ["я"]="z",["ч"]="x",["с"]="c",["м"]="v",["и"]="b",["т"]="n",["ь"]="m",["б"]=",",["ю"]=".",["ё"]="`",
        ["Й"]="Q",["Ц"]="W",["У"]="E",["К"]="R",["Е"]="T",["Н"]="Y",["Г"]="U",["Ш"]="I",["Щ"]="O",["З"]="P",["Х"]="{",["Ъ"]="}",
        ["Ф"]="A",["Ы"]="S",["В"]="D",["А"]="F",["П"]="G",["Р"]="H",["О"]="J",["Л"]="K",["Д"]="L",["Ж"]=":",["Э"]="\"",
        ["Я"]="Z",["Ч"]="X",["С"]="C",["М"]="V",["И"]="B",["Т"]="N",["Ь"]="M",["Б"]="<",["Ю"]=">",["Ё"]="~",
    }
    Store._ruMap = ruMap

    local function validateName(name)
        assert(type(name) == "string", "Config needs a name")
        name = trimStr(name)
        local length = utf8.len(name)
        assert(length and length >= 1 and length <= 40 and not name:find("[%z\1-\31\127]"),
            "Name: 1-40 chars, no control chars")
        return name
    end
    Store.validateName = validateName

    local function difference(value, base)
        if type(value) ~= "table" then
            if value ~= base then return value end
            return nil
        end
        if value[1] ~= nil then
            if type(base) ~= "table" or #value ~= #base then return clone(value) end
            for i, v in ipairs(value) do if v ~= base[i] then return clone(value) end end
            return nil
        end
        local out = {}
        for k, v in pairs(value) do
            local orig = type(base) == "table" and base[k] or nil
            local ch = difference(v, orig)
            if ch ~= nil then out[k] = ch end
        end
        if next(out) then return out end
        return nil
    end

    function Store.normalizeLayout(text)
        return (text:gsub("[\192-\255][\128-\191]*", ruMap))
    end

    function Store.encodeSet(settings)
        return json.stringify({kind = "antiresolver", version = 2, settings = validate(settings)})
    end

    function Store.decodeSet(text)
        assert(type(text) == "string" and #text <= 131072, "JSON is too large")
        local data = json.parse(text)
        assert(type(data) == "table" and data.kind == "antiresolver" and data.version == 2 and type(data.settings) == "table",
            "Not an AntiResolver v2 config")
        return validate(data.settings), data.name ~= nil and validateName(data.name) or nil
    end

    function Store.encodeCode(settings, name)
        local text = json.stringify({
            kind = "antiresolver", version = 2,
            name = name ~= nil and validateName(name) or nil,
            settings = difference(validate(settings), defaults()) or {},
        })
        local out = {}
        for i = 1, #text, 3 do
            local a, b, c = text:byte(i, i + 2)
            b, c = b or 0, c or 0
            local n = a * 65536 + b * 256 + c
            out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
            out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
            out[#out + 1] = i + 1 <= #text and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
            out[#out + 1] = i + 2 <= #text and alphabet:sub(n % 64 + 1, n % 64 + 1) or "="
        end
        return "PR2:" .. table.concat(out)
    end

    function Store.decodeCode(code)
        assert(type(code) == "string" and #code <= 180000, "Invalid/oversized share code")
        code = trimStr(code)
        if code:sub(1, 1) ~= "{" then
            code = trimStr(code:gsub('^["\'`]+', ""):gsub('["\'`]+$', ""))
        end
        local mapped = Store.normalizeLayout(code)
        if code:sub(1, 4) ~= "PR2:" and mapped:sub(1, 4) ~= "PR2:" then
            local okRaw, valRaw, nameRaw = pcall(Store.decodeSet, code)
            if okRaw then return valRaw, nameRaw end
            return Store.decodeSet(mapped)
        end
        code = mapped:gsub("%s", "")
        local raw = code:sub(5)
        assert(#raw > 0 and #raw % 4 == 0 and raw:match("^[A-Za-z0-9_%-]*=?=?$"), "Invalid PR2 code")
        local out = {}
        for i = 1, #raw, 4 do
            local chars = {raw:sub(i, i), raw:sub(i + 1, i + 1), raw:sub(i + 2, i + 2), raw:sub(i + 3, i + 3)}
            local nums = {}
            for j, ch in ipairs(chars) do
                if ch == "=" then nums[j] = 0 else
                    local at = alphabet:find(ch, 1, true)
                    assert(at, "Invalid PR2 character")
                    nums[j] = at - 1
                end
            end
            assert(chars[1] ~= "=" and chars[2] ~= "=" and (chars[3] ~= "=" or chars[4] == "="), "Invalid padding")
            local n = nums[1] * 262144 + nums[2] * 4096 + nums[3] * 64 + nums[4]
            out[#out + 1] = string.char(math.floor(n / 65536) % 256)
            if chars[3] ~= "=" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
            if chars[4] ~= "=" then out[#out + 1] = string.char(n % 256) end
        end
        return Store.decodeSet(table.concat(out))
    end

    function Store.loadLocal()
        if type(database) ~= "table" or type(database.read) ~= "function" then return end
        local ok, raw = pcall(database.read, Store.key)
        if not ok or type(raw) ~= "table" or raw.owner ~= Store.owner or raw.version ~= 2 then return end
        local loaded = {owner = Store.owner, version = 2, sets = {}, last = nil, autoload = nil}
        local count = 0
        for name, cfg in pairs(vObj(raw.sets)) do
            local okN, cleanName = pcall(validateName, name)
            local okV, cleanCfg = pcall(validate, cfg)
            if okN and okV and loaded.sets[cleanName] == nil and count < 16 then
                count = count + 1
                loaded.sets[cleanName] = cleanCfg
            end
        end
        if type(raw.last) == "string" and loaded.sets[raw.last] then loaded.last = raw.last end
        if type(raw.autoload) == "string" and loaded.sets[raw.autoload] then loaded.autoload = raw.autoload end
        library = loaded
    end

    local function writeLocal(nextLib)
        library = clone(nextLib)
        if type(database) == "table" and type(database.write) == "function" then
            pcall(database.write, Store.key, clone(nextLib))
            if type(database.flush) == "function" then pcall(database.flush) end
        end
    end

    local cloudSaveQueued = false
    local cloudSaveInFlight = false
    local lastCloudSaveAt = 0

    local function runCloudSave()
        if not alive or cloudSaveInFlight then return end
        local reqFn = resolveHttpRequest()
        if not reqFn or type(json) ~= "table" or type(json.stringify) ~= "function" then
            Store.cloudStatus = "Local only (no HTTP)"
            return
        end
        local gap = nowSafe() - lastCloudSaveAt
        if gap < 2.2 then
            cloudSaveQueued = true
            if type(task) == "table" and type(task.delay) == "function" then
                task.delay(2.3 - gap, function()
                    if cloudSaveQueued and alive then
                        cloudSaveQueued = false
                        runCloudSave()
                    end
                end)
            end
            return
        end
        cloudSaveInFlight = true
        cloudSaveQueued = false
        lastCloudSaveAt = nowSafe()
        Store.cloudStatus = "Saving cloud..."
        local names = Store.list()
        local encodedSets = {}
        local count = 0
        for _, nm in ipairs(names) do
            if count < Store.maxCloudSlots then
                local okE, code = pcall(Store.encodeCode, library.sets[nm], nm)
                if okE and type(code) == "string" and #code <= 8192 then
                    encodedSets[nm] = code
                    count = count + 1
                end
            end
        end
        local payload = {
            action = "save",
            user_id = localPlayer.UserId,
            library = {
                sets = encodedSets,
                last = (library.last and encodedSets[library.last]) and library.last or nil,
                autoload = (library.autoload and encodedSets[library.autoload]) and library.autoload or nil,
            },
        }
        local okBody, body = pcall(json.stringify, payload)
        if not okBody or type(body) ~= "string" then
            cloudSaveInFlight = false
            Store.cloudStatus = "Encode failed"
            return
        end
        local headers = {["Content-Type"] = "application/json"}
        if DEFAULT_CLIENT_KEY ~= "" then headers["X-AR-Client"] = DEFAULT_CLIENT_KEY end
        local function work()
            local okReq, resp = pcall(reqFn, {Url = DEFAULT_CFG_URL, Method = "POST", Headers = headers, Body = body})
            cloudSaveInFlight = false
            if not alive then return end
            if okReq and type(resp) == "table" then
                local code = tonumber(resp.StatusCode or resp.status_code or resp.Status or resp.status) or 0
                local raw = resp.Body or resp.body or ""
                if code >= 200 and code < 300 then
                    local okJ, d = pcall(json.parse, raw)
                    if okJ and type(d) == "table" and d.ok then
                        Store.cloudOk = true
                        Store.cloudStatus = "Cloud synced (" .. tostring(d.count or count) .. "/" .. tostring(Store.maxCloudSlots) .. ")"
                    else
                        Store.cloudStatus = "Cloud bad JSON"
                    end
                elseif code == 429 then
                    Store.cloudStatus = "Cloud cooldown"
                    cloudSaveQueued = true
                    if type(task) == "table" and type(task.delay) == "function" then
                        task.delay(2.5, function() if cloudSaveQueued and alive then cloudSaveQueued = false; runCloudSave() end end)
                    end
                else
                    Store.cloudStatus = "Cloud HTTP " .. tostring(code)
                end
            else
                Store.cloudStatus = "Cloud offline"
            end
            if onCloudLibraryUpdated then pcall(onCloudLibraryUpdated, false) end
            if cloudSaveQueued and alive then
                cloudSaveQueued = false
                runCloudSave()
            end
        end
        if type(task) == "table" and type(task.spawn) == "function" then task.spawn(work) else pcall(work) end
    end

    function Store.cloudLoad(applyAutoload)
        local reqFn = resolveHttpRequest()
        if not reqFn or type(json) ~= "table" or type(json.stringify) ~= "function" then
            Store.cloudStatus = "Local only (no HTTP)"
            return
        end
        Store.cloudStatus = "Loading cloud..."
        local okBody, body = pcall(json.stringify, {action = "load", user_id = localPlayer.UserId})
        if not okBody or type(body) ~= "string" then return end
        local headers = {["Content-Type"] = "application/json"}
        if DEFAULT_CLIENT_KEY ~= "" then headers["X-AR-Client"] = DEFAULT_CLIENT_KEY end
        local function work()
            local okReq, resp = pcall(reqFn, {Url = DEFAULT_CFG_URL, Method = "POST", Headers = headers, Body = body})
            if not alive then return end
            if not okReq or type(resp) ~= "table" then
                Store.cloudStatus = "Cloud offline"
                if onCloudLibraryUpdated then pcall(onCloudLibraryUpdated, false) end
                return
            end
            local code = tonumber(resp.StatusCode or resp.status_code or resp.Status or resp.status) or 0
            local raw = resp.Body or resp.body or ""
            if code < 200 or code >= 300 then
                Store.cloudStatus = "Cloud HTTP " .. tostring(code)
                if onCloudLibraryUpdated then pcall(onCloudLibraryUpdated, false) end
                return
            end
            local okJ, data = pcall(json.parse, raw)
            if not okJ or type(data) ~= "table" or not data.ok or type(data.library) ~= "table" then
                Store.cloudStatus = "Cloud bad response"
                if onCloudLibraryUpdated then pcall(onCloudLibraryUpdated, false) end
                return
            end
            Store.cloudOk = true
            local remote = data.library
            local nextLib = clone(library)
            local loadedCount = 0
            if type(remote.sets) == "table" then
                for nm, encoded in pairs(remote.sets) do
                    local okN, cleanNm = pcall(validateName, nm)
                    local okD, cfgVal = pcall(Store.decodeCode, encoded)
                    if okN and okD and type(cfgVal) == "table" then
                        nextLib.sets[cleanNm] = cfgVal
                        loadedCount = loadedCount + 1
                    end
                end
            end
            if type(remote.last) == "string" and nextLib.sets[remote.last] then nextLib.last = remote.last end
            if type(remote.autoload) == "string" and nextLib.sets[remote.autoload] then nextLib.autoload = remote.autoload end
            writeLocal(nextLib)
            Store.cloudStatus = "Cloud synced (" .. tostring(#Store.list()) .. "/" .. tostring(Store.maxCloudSlots) .. ")"
            local autoApplied = false
            if applyAutoload and nextLib.autoload and nextLib.sets[nextLib.autoload] and applySettings then
                pcall(applySettings, Store.get(nextLib.autoload))
                autoApplied = true
                print("[AntiResolver] Autoloaded cloud config: " .. tostring(nextLib.autoload))
                if type(notify) == "function" then
                    pcall(notify, "AntiResolver", "Autoloaded: " .. tostring(nextLib.autoload), 2.5, false)
                end
            end
            if onCloudLibraryUpdated then pcall(onCloudLibraryUpdated, autoApplied) end
        end
        if type(task) == "table" and type(task.spawn) == "function" then task.spawn(work) else pcall(work) end
    end

    function Store.list()
        local result = {}
        for name in pairs(library.sets) do result[#result + 1] = name end
        table.sort(result)
        return result
    end

    function Store.getAutoload()
        return library.autoload
    end

    function Store.getLast()
        return library.last
    end

    function Store.get(name)
        assert(library.sets[name], "Select one of your saved configs")
        return validate(library.sets[name])
    end

    function Store.save(name, settings)
        name = validateName(name)
        local nextLib = clone(library)
        assert(nextLib.sets[name] or #Store.list() < Store.maxCloudSlots,
            "Max " .. tostring(Store.maxCloudSlots) .. " configs")
        nextLib.sets[name] = validate(settings)
        nextLib.last = name
        writeLocal(nextLib)
        runCloudSave()
        return "Saved " .. name, name
    end

    function Store.use(name)
        local cfg = Store.get(name)
        local nextLib = clone(library)
        nextLib.last = name
        writeLocal(nextLib)
        return cfg
    end

    function Store.delete(name)
        assert(library.sets[name], "Select a saved config")
        local nextLib = clone(library)
        nextLib.sets[name] = nil
        if nextLib.last == name then nextLib.last = nil end
        if nextLib.autoload == name then nextLib.autoload = nil end
        writeLocal(nextLib)
        runCloudSave()
        return "Deleted " .. name
    end

    function Store.setAutoload(name)
        local nextLib = clone(library)
        if name == nil or name == "" then
            nextLib.autoload = nil
            writeLocal(nextLib)
            runCloudSave()
            return "Autoload cleared"
        end
        assert(nextLib.sets[name], "Select a saved config")
        if nextLib.autoload == name then
            nextLib.autoload = nil
            writeLocal(nextLib)
            runCloudSave()
            return "Autoload disabled"
        end
        nextLib.autoload = name
        writeLocal(nextLib)
        runCloudSave()
        return "Autoload: " .. name
    end
end

pcall(Store.loadLocal)
if library.autoload and library.sets[library.autoload] then
    Settings = Store.get(library.autoload)
elseif library.last and library.sets[library.last] then
    Settings = Store.get(library.last)
end
Options = Settings.resolver

-- ==================== RESOLVER 2.0 ====================
do
    requireAPI(entity, "get_enemies")
    requireAPI(entity, "is_alive")
    requireAPI(entity, "get_info")
    requireAPI(entity, "get_player_angles_deg")
    requireAPI(entity, "get_player_lby_deg")
    requireAPI(plist, "get")
    requireAPI(plist, "set")
    requireAPI(rage, "get_target")
    requireAPI(globals, "tickcount")
    requireAPI(globals, "realtime")
    requireAPI(events, "on_tick")
    requireAPI(client, "set_event_callback")

    Resolver.hits = 0
    Resolver.misses = 0
    Resolver.ignored = 0
    Resolver.unknownShots = 0
    Resolver.fault = nil
    Resolver.fireEvents = 0
    Resolver.hitEvents = 0
    Resolver.missEvents = 0
    Resolver.unmatchedResults = 0
    Resolver.invalidEvents = 0
    Resolver.trackedShots = 0
    Resolver.outputLanguage = "en"
    Resolver.trace = {}
    Resolver.performance = {evaluations = 0, cached = 0}
    Resolver.results = {hits = 0, misses = 0, damage = 0, reasons = {resolver = 0, spread = 0, occlusion = 0, death = 0, unknown = 0}}
    Resolver.dt = {groups = {}, sequence = 0, completed = 0, expired = 0, stale = 0, ambiguous = 0, last = "none"}

    local keys = {"Force body yaw value", "Override yaw offset", "Force pitch value", "Override prefer body aim", "Override safe point", "Force pitch", "Force body yaw"}
    local neutral = {0, 0, 0, "-", "-", false, false}
    local bruteOffsets = {0, 58, -58, 86, -86, 35, -35}
    local bruteOffsetIds = {"brute1", "brute2", "brute3", "brute4", "brute5", "brute6", "brute7"}
    local extraOffsets = {58, -58, 86, -86, 35, -35}
    local extraOffsetIds = {"offset58", "offset-58", "offset86", "offset-86", "offset35", "offset-35"}
    local airOffsetIds = {"air58", "air-58", "air86", "air-86", "air35", "air-35"}
    local autoStrategies = {
        {name = "Adaptive", prior = 0.6},
        {name = "Brute-force", prior = 0},
        {name = "Animation", prior = 1.0},
        {name = "Jitter", prior = 1.4},
    }

    local function isResolverMissReason(r)
        return r == "resolver" or r == "desync" or r == "aa" or r:find("resolv", 1, true) ~= nil
    end

    local function readDesyncSignal(player, info, anim, yaw, lby)
        local signed = nil
        if anim and finite(anim.desync) and math.abs(anim.desync) >= 5 then
            signed = anim.desync
        elseif finite(info.desync_delta) and math.abs(info.desync_delta) >= 5 then
            signed = info.desync_delta
        end
        if not signed and type(entity.get_player_twist_deg) == "function" then
            local okT, tw = pcall(entity.get_player_twist_deg, player)
            if okT and finite(tw) and math.abs(tw) >= 5 then signed = tw end
        end
        if not signed then
            local diff = wrap(yaw - lby)
            if math.abs(diff) >= 8 then signed = diff end
        end
        if signed then
            local mag = math.clamp(math.abs(signed), 15, 86)
            return signed >= 0 and mag or -mag, mag, true
        end
        local fallbackMag = finite(info.desync_delta) and math.clamp(math.abs(info.desync_delta), 25, 86) or 58
        return fallbackMag, fallbackMag, false
    end

    local states, shots, owners, names = {}, {}, {}, {}
    local playerIdCache, playerIdCacheCount = {}, 0
    local pairIdCache = {}
    local activeMode, lastUpdateTick = nil, nil
    local zeroSeq, nextSlotIndex = 0, 0
    local savedBuiltinBaim = nil
    local lastLocalTeam, teamInit = nil, false
    local lastDtChargedAt = nil

    local function dtActive()
        return Options.dtHold == true and (Options.mode == "Auto" or Options.mode == "Adaptive" or Options.mode == "Debug")
    end

    local function readUserId(player) return player.UserId end
    local function pairId(yId, pId)
        local row = pairIdCache[yId]
        if not row then row = {}; pairIdCache[yId] = row end
        local id = row[pId]
        if not id then id = yId .. ":" .. pId; row[pId] = id end
        return id
    end

    local function playerKey(player)
        if player == nil then return nil end
        local kind = type(player)
        if kind ~= "table" and kind ~= "userdata" then return nil end
        local cached = playerIdCache[player]
        if cached ~= nil then return cached ~= false and cached or nil end
        local ok, id = pcall(readUserId, player)
        if ok and finite(id) and id > 0 and id % 1 == 0 then
            if playerIdCacheCount >= 64 then playerIdCache, playerIdCacheCount = {}, 0 end
            local key = "user:" .. tostring(id)
            playerIdCache[player] = key
            playerIdCacheCount = playerIdCacheCount + 1
            return key
        end
        return nil
    end

    local function slotKey(value)
        if finite(value) and value >= 0 and value % 1 == 0 then return "slot:" .. tostring(value) end
        if type(value) == "string" and value:match("^%d+$") then return "slot:" .. value end
        return nil
    end

    local function shotKey(value)
        if finite(value) and value % 1 == 0 then return "shot:" .. tostring(value) end
        if type(value) == "string" and value ~= "" then return "shot:" .. value end
        return nil
    end

    local function traceLine(value)
        local log = Resolver.trace
        log[#log + 1] = value
        if #log > 10 then table.remove(log, 1) end
        if Options.debug then print("[AR trace] " .. value) end
    end

    local nextBaimSyncAt = 0
    local function syncBuiltinBaim(active)
        if type(rage.get_resolver_baim_after_misses) ~= "function" or type(rage.set_resolver_baim_after_misses) ~= "function" then
            return
        end
        if active and Options.disableBuiltinBaim then
            local t = nowSafe()
            if savedBuiltinBaim == nil then
                local ok, cur = pcall(rage.get_resolver_baim_after_misses)
                savedBuiltinBaim = (ok and finite(cur)) and cur or 2
                nextBaimSyncAt = 0
            end
            if t >= nextBaimSyncAt then
                nextBaimSyncAt = t + 1.0
                local okCur, curVal = pcall(rage.get_resolver_baim_after_misses)
                if okCur and curVal ~= 0 then pcall(rage.set_resolver_baim_after_misses, 0) end
            end
        elseif savedBuiltinBaim ~= nil then
            pcall(rage.set_resolver_baim_after_misses, savedBuiltinBaim)
            savedBuiltinBaim = nil
            nextBaimSyncAt = 0
        end
    end

    local function restore(state)
        if not state.saved then return end
        for i, key in ipairs(keys) do
            local saved = state.saved[key]
            if saved == nil then saved = neutral[i] end
            pcall(plist.set, state.player, key, saved)
        end
        state.saved, state.applied = nil, nil
    end

    local function disconnectConn(conn) conn:Disconnect() end

    function Resolver.clear()
        for _, state in pairs(states) do
            restore(state)
            for _, conn in ipairs(state.connections or {}) do pcall(disconnectConn, conn) end
        end
        states, shots, owners, names = {}, {}, {}, {}
        playerIdCache, playerIdCacheCount = {}, 0
        Resolver.dt.groups = {}
        lastUpdateTick = nil
    end

    function Resolver.stop()
        syncBuiltinBaim(false)
        Resolver.clear()
    end

    function Resolver.setEnabled(value)
        Options.enabled = value == true
        if not Options.enabled then
            syncBuiltinBaim(false)
            Resolver.clear()
        end
    end

    function Resolver.setMode(value)
        value = resolverMode(value)
        Options.mode = value
        Options.debug = value == "Debug"
        Resolver.clear()
        activeMode = value
        print("[AR MODE] " .. value)
    end

    local function newState(player)
        local key = playerKey(player)
        assert(key, "Enemy Player has no usable identity")
        nextSlotIndex = nextSlotIndex + 1
        local state = {
            key = key, player = player, character = player.Character,
            history = {}, contexts = {}, consecutive = 0, lastTick = -1,
            phase = "collecting", life = 0, connections = {},
            slotIndex = nextSlotIndex, yawScratch = {}, pitchScratch = {},
            medianScratch = {}, medianDirty = true,
            calmTicks = 0, noAa = false, defUntilTick = 0,
            lastBigDelta = nil, lastBigTick = 0, stableChoice = nil,
            stableRevision = nil, stableContext = nil,
        }
        states[key] = state
        local ok, signal = pcall(function() return player.CharacterAdded end)
        if ok and signal then
            local connected, conn = pcall(function()
                return signal:Connect(function(character)
                    if not alive or states[key] ~= state then return end
                    restore(state)
                    state.life, state.character = state.life + 1, character
                    state.history, state.choice, state.dtLock = {}, nil, nil
                    state.candidateCache, state.staticSamples, state.medianDirty = nil, 0, true
                    state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
                    state.consecutive, state.lastTick = 0, -1
                    state.calmTicks, state.noAa, state.defUntilTick = 0, false, 0
                    state.stableChoice, state.stableRevision, state.stableContext = nil, nil, nil
                end)
            end)
            if connected and conn then
                state.lifecycle = true
                state.connections[#state.connections + 1] = conn
            end
        end
        return state
    end

    local function context(state, info)
        local name = info.is_in_air and "air" or (info.is_crouching and "duck" or
            ((finite(info.speed) and info.speed > 2) and "move" or "stand"))
        if not state.contexts[name] then
            state.contexts[name] = {
                scores = {}, rejected = {}, winner = nil, stage = 1,
                misses = 0, revision = 0, failedAngles = {}, decayTime = nowSafe(),
            }
        end
        return state.contexts[name], name
    end

    local function medianPitch(state)
        if not state.medianDirty and state.cachedMedian ~= nil then return state.cachedMedian end
        local history = state.history
        local values = state.medianScratch
        local n = 0
        for i = math.max(1, #history - 6), #history do
            n = n + 1
            values[n] = history[i].pitch
        end
        for i = n + 1, #values do values[i] = nil end
        if n == 0 then state.cachedMedian, state.medianDirty = 0, false; return 0 end
        table.sort(values)
        local result = (n % 2 == 1) and values[(n + 1) / 2] or ((values[n / 2] + values[n / 2 + 1]) * 0.5)
        state.cachedMedian, state.medianDirty = result, false
        return result
    end

    local function motion(history)
        local hLen = #history
        local startIdx = math.max(1, hLen - 9)
        local sx, sy, flips, changes, lastSign, pmin, pmax = 0, 0, 0, 0, 0, 89, -89
        local stepSum, absStepSum, stepCount, lastDelta = 0, 0, 0, 0
        for i = startIdx, hLen do
            local rec = history[i]
            local w = (i - startIdx + 1)
            sx = sx + (rec.yawCos or math.cos(math.rad(rec.yaw))) * w
            sy = sy + (rec.yawSin or math.sin(math.rad(rec.yaw))) * w
            pmin, pmax = math.min(pmin, rec.pitch), math.max(pmax, rec.pitch)
            if i > startIdx then
                local delta = wrap(rec.yaw - history[i - 1].yaw)
                local ad = math.abs(delta)
                if ad >= 18 then
                    local sign = delta > 0 and 1 or -1
                    if lastSign ~= 0 and sign ~= lastSign then flips = flips + 1 end
                    lastSign, changes, lastDelta = sign, changes + 1, delta
                    stepSum, absStepSum, stepCount = stepSum + delta, absStepSum + ad, stepCount + 1
                end
            end
        end
        local center
        if sx * sx + sy * sy > 0.01 then center = math.deg(math.atan2(sy, sx)) end
        local jitter = flips >= 2 and changes >= 3
        local spin = (not jitter) and flips == 0 and stepCount >= 3 and math.abs(stepSum / stepCount) >= 15
        local avgStep = stepCount > 0 and (stepSum / stepCount) or 0
        local halfAmp = (jitter and stepCount > 0) and math.min(90, (absStepSum / stepCount) * 0.5) or 0
        return jitter, center, (pmax - pmin) > 65, spin, avgStep, halfAmp, lastDelta
    end

    local function autoFeedback(ctx, strategy, hit)
        local auto = ctx.auto
        if not auto then return end
        local rec = auto.results[strategy] or {score = 0, hits = 0, misses = 0}
        auto.results[strategy] = rec
        rec.score = math.clamp(rec.score + (hit and 1 or -1.25), -4, 4)
        if hit then rec.hits = rec.hits + 1 else rec.misses = rec.misses + 1 end
        if auto.selected == strategy then auto.streak = hit and 0 or (auto.streak + 1) end
    end

    local function closeDT(group, reason)
        if group.closed then return end
        group.closed = true
        Resolver.dt.groups[group.serial] = nil
        if group.state.dtLock == group then group.state.dtLock = nil end
        for id, shot in pairs(group.members) do if shots[id] == shot then shots[id] = nil end end
        Resolver.dt.last = string.format("series=%d shots=%d results=%d %s", group.serial, group.sent, #group.results, reason)
        traceLine("DT " .. Resolver.dt.last)
    end

    local function finishDT(group)
        if group.closed then return false end
        local state = group.state
        local ctx = state.contexts[group.context]
        if not dtActive() or states[state.key] ~= state or state.life ~= group.life
            or (not state.lifecycle and state.player.Character ~= group.character)
            or not ctx or ctx.revision ~= group.revision then
            Resolver.dt.stale = Resolver.dt.stale + 1
            closeDT(group, "stale; no training")
            return false
        end
        local ts = nowSafe()
        if #group.results < group.sent then
            if ts >= group.deadline then
                Resolver.dt.expired = Resolver.dt.expired + 1
                closeDT(group, "expired")
            end
            return false
        end
        if group.sent < (group.expectedShots or 2) and ts < group.lockUntil then return false end
        local hits, misses, ignored, head, failed = 0, 0, 0, nil, nil
        for _, res in ipairs(group.results) do
            local rr = type(res.reason) == "string" and string.lower(trimStr(res.reason)) or ""
            if res.hit then
                hits = hits + 1
                if res.hitbox == "head" then head = res.shot end
            elseif isResolverMissReason(rr) then
                misses = misses + 1
                if not failed or res.hitbox ~= "head" then failed = res end
            else
                ignored = ignored + 1
            end
        end
        Resolver.hits, Resolver.misses, Resolver.ignored = Resolver.hits + hits, Resolver.misses + misses, Resolver.ignored + ignored
        if hits > 0 then
            state.consecutive, ctx.misses = 0, 0
            ctx.revision = ctx.revision + 1
            if head then
                autoFeedback(ctx, head.strategy, true)
                ctx.scores[head.id] = math.min(6, (ctx.scores[head.id] or 0) + 2.5)
                ctx.rejected[head.id] = nil
                ctx.winner = {offset = head.offset, pitch = head.pitch, time = ts}
                for i = #ctx.failedAngles, 1, -1 do
                    local f = ctx.failedAngles[i]
                    local samePitch = f.body or (f.pitch == nil and head.pitch == nil)
                        or (f.pitch ~= nil and head.pitch ~= nil and math.abs(f.pitch - head.pitch) < 12)
                    if math.abs(wrap(f.offset - head.offset)) < 14 and samePitch then table.remove(ctx.failedAngles, i) end
                end
            end
        elseif failed then
            state.consecutive, ctx.misses = state.consecutive + 1, ctx.misses + 1
            state.defUntilTick = 0
            if ctx.misses % Options.cycleAfter == 0 then
                local shot = failed.shot
                local rejectFor = math.clamp(Options.memory * 0.4, 4, 8)
                ctx.revision = ctx.revision + 1
                autoFeedback(ctx, shot.strategy, false)
                ctx.failedAngles[#ctx.failedAngles + 1] = {
                    offset = shot.offset, pitch = shot.pitch,
                    body = failed.hitbox ~= nil and failed.hitbox ~= "head",
                    expires = ts + rejectFor,
                }
                if #ctx.failedAngles > 32 then table.remove(ctx.failedAngles, 1) end
                ctx.scores[shot.id] = math.max(-12, (ctx.scores[shot.id] or 0) - 3)
                ctx.rejected[shot.id], ctx.winner = ts + rejectFor, nil
                if shot.strategy == "Brute-force" then ctx.stage = ctx.stage % #bruteOffsets + 1 end
            end
        end
        Resolver.dt.completed = Resolver.dt.completed + 1
        closeDT(group, string.format("hit=%d resolver=%d ignored=%d", hits, misses, ignored))
        return true
    end

    local function trackDT(shot, id, choice)
        local ts, state = nowSafe(), shot.state
        local weaponKey = "unavailable"
        if type(weapon) == "table" and type(weapon.get_active) == "function" then
            local ok, active = pcall(weapon.get_active)
            if ok and type(active) == "table" then weaponKey = tostring(active.id or active.name or "unavailable") end
        end
        local wLow = string.lower(weaponKey)
        local singleShot = wLow:find("ssg", 1, true) ~= nil or wLow:find("awp", 1, true) ~= nil or wLow:find("scout", 1, true) ~= nil
        local hasDtApi = type(rage) == "table" and type(rage.is_double_tap_charged) == "function"
        local dtRecent = not hasDtApi or (lastDtChargedAt ~= nil and ts - lastDtChargedAt <= 0.25)
        local expectedShots = (singleShot or not dtRecent) and 1 or 2
        local group = state.dtLock
        if not group or group.closed or group.sent >= (group.expectedShots or 2) or ts >= group.lockUntil
            or group.context ~= shot.context or group.revision ~= shot.revision or group.life ~= state.life
            or group.weapon ~= weaponKey or group.pitchMode ~= Options.pitch then
            local count, oldest = 0, nil
            for _, pending in pairs(Resolver.dt.groups) do
                count = count + 1
                if not oldest or pending.started < oldest.started then oldest = pending end
            end
            if count >= 128 then Resolver.dt.expired = Resolver.dt.expired + 1; closeDT(oldest, "cap") end
            Resolver.dt.sequence = Resolver.dt.sequence + 1
            group = {
                serial = Resolver.dt.sequence, state = state, life = state.life, character = state.character,
                context = shot.context, revision = shot.revision, choice = clone(choice), pitchMode = Options.pitch,
                weapon = weaponKey, started = ts, expectedShots = expectedShots,
                lockUntil = expectedShots > 1 and (ts + Options.dtWindowMs / 1000) or ts,
                deadline = ts + 2, sent = 0, members = {}, results = {},
            }
            Resolver.dt.groups[group.serial] = group
            state.dtLock = group
        end
        group.sent = group.sent + 1
        group.members[id], shot.dtGroup = shot, group
        traceLine(string.format("DT series=%d fire=%d/%d yaw=%.1f", group.serial, group.sent, group.expectedShots or 2, shot.yaw))
    end

    local function stableJitter(ctx, detected, center)
        local ts = nowSafe()
        local sig = ctx.jitterSignal
        if not sig then sig = {count = 0, lastSeen = -1e9, center = nil}; ctx.jitterSignal = sig end
        if detected and center then
            sig.count = math.min(8, sig.count + 1)
            sig.lastSeen, sig.center = ts, center
        elseif ts - sig.lastSeen > 0.15 then
            sig.count, sig.center = 0, nil
        end
        return sig.count >= 2 and sig.center ~= nil, sig.center
    end

    local function autoStrategy(state, ctx, name, jitter, anim)
        local ts = nowSafe()
        local auto = ctx.auto
        if not auto then auto = {selected = nil, holdUntil = 0, streak = 0, decayTime = ts, results = {}}; ctx.auto = auto end
        if ts - auto.decayTime >= 1 then
            local factor = 2 ^ (-(ts - auto.decayTime) / Options.memory)
            for _, rec in pairs(auto.results) do rec.score = rec.score * factor end
            auto.decayTime = ts
        end
        local hasAnim = anim and finite(anim.goal_feet_yaw)
        local bestName, bestScore = "Adaptive", -math.huge
        for _, item in ipairs(autoStrategies) do
            local sName = item.name
            local usable = sName == "Adaptive" or sName == "Brute-force"
                or (sName == "Animation" and hasAnim) or (sName == "Jitter" and jitter)
            if usable then
                local rec = auto.results[sName]
                local score = item.prior + (rec and rec.score or 0)
                if sName == "Brute-force" and ctx.misses >= 2 then score = score + 1.5 end
                if sName == auto.selected then score = score + 0.35 end
                if score > bestScore then bestName, bestScore = sName, score end
            end
        end
        if auto.selected and ts < auto.holdUntil and auto.streak < 2 then
            local keep = auto.selected == "Adaptive" or auto.selected == "Brute-force"
                or (auto.selected == "Animation" and hasAnim) or (auto.selected == "Jitter" and jitter)
            if keep then return auto.selected end
        end
        if auto.selected ~= bestName then
            auto.selected, auto.streak, auto.holdUntil = bestName, 0, ts + 0.6
        end
        return auto.selected
    end

    local function candidates(state, info, yaw, pitch, lby, curTick)
        local ctx, name = context(state, info)
        local elapsed = nowSafe()
        local isAir = name == "air"
        local anchorYaw = isAir and yaw or lby
        if dtActive() then
            local group = state.dtLock
            if group and not group.closed and elapsed < group.lockUntil and group.life == state.life
                and group.context == name and group.revision == ctx.revision and group.pitchMode == Options.pitch then
                local jitter, _, pitchJitter, spin = motion(state.history)
                state.phase = jitter and "jitter" or (spin and "spin" or (pitchJitter and "pitch" or "tracking"))
                state.strategy = group.choice.strategy
                return group.choice
            end
            state.dtLock = nil
        end
        if Options.defensiveHold and curTick < (state.defUntilTick or 0) and state.stableChoice
            and state.stableRevision == ctx.revision and state.stableContext == name then
            state.phase = "defensive"
            state.strategy = state.stableChoice.strategy
            return state.stableChoice
        end
        local anim
        if (Options.mode == "Auto" or Options.mode == "Debug") and type(entity.get_anim_state) == "function" then
            local okA, a = pcall(entity.get_anim_state, state.player)
            if okA and type(a) == "table" then anim = a end
        end
        local cache = state.candidateCache
        if (state.staticSamples or 0) >= 16 and cache and elapsed < cache.expires
            and cache.ctx == ctx and cache.revision == ctx.revision and cache.stage == ctx.stage
            and cache.mode == Options.mode and cache.pitchMode == Options.pitch and cache.memory == Options.memory
            and cache.yaw == yaw and cache.pitch == pitch and cache.lby == lby and cache.delta == info.desync_delta
            and cache.feet == (anim and anim.goal_feet_yaw) and cache.torso == (anim and anim.torso_yaw)
            and cache.animDesync == (anim and anim.desync)
            and cache.noAa == state.noAa and cache.fakePitch == Options.fakePitch
            and state.choice and state.choice.id == cache.choice.id then
            Resolver.performance.cached = Resolver.performance.cached + 1
            state.strategy, state.phase = cache.choice.strategy, cache.phase
            return cache.choice
        end

        Resolver.performance.evaluations = Resolver.performance.evaluations + 1
        local jitter, center, pitchJitter, spin, avgStep, halfAmp, lastDelta = motion(state.history)
        local signedDelta, absDelta, hasSign = readDesyncSignal(state.player, info, anim, yaw, lby)
        local hasAaSignal = math.abs(wrap(yaw - lby)) >= 10 or (hasSign and absDelta >= 12)
            or jitter or spin or pitchJitter or ctx.misses > 0
        local visualFakePitch = math.abs(pitch) <= 78 and not state.noAa and hasAaSignal
        local suspectFakePitch = Options.fakePitch and Options.pitch == "Auto"
            and (visualFakePitch or pitchJitter or ctx.misses >= 2)
        state.phase = jitter and "jitter" or (spin and "spin"
            or ((pitchJitter or (visualFakePitch and ctx.misses > 0)) and "pitch" or "tracking"))
        local yaws, pitches = state.yawScratch, state.pitchScratch
        local yawCount, pitchCount = 0, 0
        local function addYaw(id, angle, prior)
            angle = wrap(angle)
            for i = 1, yawCount do
                if math.abs(wrap(yaws[i].angle - angle)) < 3 then return end
            end
            yawCount = yawCount + 1
            local slot = yaws[yawCount]
            if slot then slot.id, slot.angle, slot.prior = id, angle, prior
            else yaws[yawCount] = {id = id, angle = angle, prior = prior} end
        end
        if elapsed - ctx.decayTime >= 1 then
            local factor = 2 ^ (-(elapsed - ctx.decayTime) / Options.memory)
            for id, score in pairs(ctx.scores) do ctx.scores[id] = score * factor end
            ctx.decayTime = elapsed
            if ctx.winner and elapsed - (ctx.winner.time or 0) > Options.memory * 2 then ctx.winner = nil end
        end

        local strategy = Options.mode
        if strategy == "Auto" or strategy == "Debug" then
            local stable, stableCenter = stableJitter(ctx, jitter, center)
            strategy = autoStrategy(state, ctx, name, stable, anim)
            if strategy == "Jitter" then center = stableCenter end
        end
        state.strategy = strategy

        if Options.noAaDetect and state.noAa and ctx.misses == 0 then
            addYaw("noaa", yaw, 4.5)
            addYaw("feet", lby, 3.2)
            state.strategy = "No-AA"
        elseif strategy == "Brute-force" then
            addYaw(bruteOffsetIds[ctx.stage], anchorYaw + bruteOffsets[ctx.stage], 3)
        else
            if ctx.winner then addYaw("learned", anchorYaw + ctx.winner.offset, 4.2) end
            if spin then addYaw("spin-pred", yaw + avgStep, 3.6) end
            if strategy == "Animation" and anim and finite(anim.goal_feet_yaw) then
                addYaw("anim-feet", anim.goal_feet_yaw, isAir and 2.8 or 3.5)
                if finite(anim.torso_yaw) then addYaw("anim-torso", anim.torso_yaw, 2.4) end
            end
            if jitter and center then
                if halfAmp >= 35 and lastDelta ~= 0 then
                    local nextSide = lastDelta > 0 and -halfAmp or halfAmp
                    addYaw("jit-pred", center + nextSide, strategy == "Jitter" and 3.6 or 2.8)
                    addYaw("center", center, strategy == "Jitter" and 3.1 or 2.4)
                    addYaw("jit-alt", center - nextSide, 2.2)
                else
                    addYaw("center", center, strategy == "Jitter" and 3.6 or 2.6)
                end
            end
            addYaw("feet", lby, isAir and 2.5 or 3.1)
            local mirrorYaw = wrap(yaw + wrap(yaw - lby))
            addYaw("mirror", mirrorYaw, isAir and 2.6 or 2.5)
            addYaw("delta-s", lby + signedDelta, hasSign and 2.7 or 2.2)
            addYaw("delta-o", lby - signedDelta, 2.3)
            addYaw("yaw+d", yaw + signedDelta, isAir and (hasSign and 3.0 or 2.5) or 1.9)
            addYaw("yaw-d", yaw - signedDelta, isAir and 2.6 or 1.8)
            addYaw("visual", yaw, isAir and 2.7 or 1.5)
            local highBoost = (absDelta >= 68 or isAir) and 0.45 or 0
            for i = 1, #extraOffsets do
                local off = extraOffsets[i]
                local pVal = 1.3 + ((math.abs(off) >= 80) and highBoost or 0)
                addYaw(extraOffsetIds[i], lby + off, pVal)
                if isAir then addYaw(airOffsetIds[i], yaw + off, pVal + 0.35) end
            end
        end

        local function addPitch(id, angle, prior)
            if angle ~= nil then
                for i = 1, pitchCount do
                    local pAngle = pitches[i].angle
                    if pAngle ~= nil and math.abs(pAngle - angle) < 4 then return end
                end
            end
            pitchCount = pitchCount + 1
            local slot = pitches[pitchCount]
            if slot then slot.id, slot.angle, slot.prior = id, angle, prior
            else pitches[pitchCount] = {id = id, angle = angle, prior = prior} end
        end
        if Options.pitch == "Off" then
            addPitch("off", nil, 0)
        elseif Options.pitch == "Raw" then
            addPitch("raw", pitch, 1)
        else
            if ctx.winner and ctx.winner.pitch ~= nil then addPitch("learned", ctx.winner.pitch, 2.5) end
            if suspectFakePitch and visualFakePitch and math.abs(pitch) <= 72 then
                addPitch("fp-down", -89, 2.1)
            end
            addPitch("median", medianPitch(state), pitchJitter and 1.9 or 1.5)
            addPitch("raw", pitch, 1.2)
            if suspectFakePitch then
                addPitch("fp-down", -89, visualFakePitch and 1.9 or 0.9)
                addPitch("fp-up", 89, (visualFakePitch or pitchJitter) and 1.35 or 0.25)
                addPitch("fp-zero", 0, visualFakePitch and 1.0 or 0.20)
                if visualFakePitch then
                    addPitch("fp-d70", -70, 0.85)
                    addPitch("fp-u70", 70, 0.75)
                    addPitch("fp-m20", clampPitch(pitch - 20), 0.7)
                    addPitch("fp-p20", clampPitch(pitch + 20), 0.7)
                end
            end
        end

        local bestId, bestYaw, bestPitch, bestScore = nil, nil, nil, -math.huge
        local failedAngles = ctx.failedAngles
        for i = #failedAngles, 1, -1 do
            if failedAngles[i].expires <= elapsed then table.remove(failedAngles, i) end
        end
        local choiceId = state.choice and state.choice.id
        for yi = 1, yawCount do
            local y = yaws[yi]
            local yOffset = wrap(y.angle - anchorYaw)
            for pi = 1, pitchCount do
                local p = pitches[pi]
                local id = pairId(y.id, p.id)
                local rejected = ctx.rejected[id]
                local score = y.prior + p.prior + (ctx.scores[id] or 0)
                local blocked = rejected and rejected > elapsed
                if not blocked then
                    for fi = 1, #failedAngles do
                        local failed = failedAngles[fi]
                        local samePitch = failed.body or (failed.pitch == nil and p.angle == nil)
                            or (failed.pitch ~= nil and p.angle ~= nil and math.abs(failed.pitch - p.angle) < 12)
                        if samePitch and math.abs(wrap(yOffset - failed.offset)) < 14 then
                            blocked = true; break
                        end
                    end
                end
                if blocked then score = score - 20 end
                if choiceId == id then score = score + 0.15 end
                if score > bestScore then
                    bestId, bestYaw, bestPitch, bestScore = id, y.angle, p.angle, score
                end
            end
        end

        local best = {id = bestId, yaw = bestYaw, pitch = bestPitch, context = name, lby = lby, anchorYaw = anchorYaw, strategy = state.strategy}
        state.stableChoice, state.stableRevision, state.stableContext = best, ctx.revision, name
        if (state.staticSamples or 0) >= 16 then
            local expires = math.min(elapsed + 0.2, ctx.decayTime + 1)
            if ctx.winner then expires = math.min(expires, (ctx.winner.time or 0) + Options.memory * 2) end
            for fi = 1, #failedAngles do expires = math.min(expires, failedAngles[fi].expires) end
            for _, untilT in pairs(ctx.rejected) do if untilT > elapsed then expires = math.min(expires, untilT) end end
            local nextCache = cache or {}
            nextCache.ctx, nextCache.revision, nextCache.stage = ctx, ctx.revision, ctx.stage
            nextCache.mode, nextCache.pitchMode, nextCache.memory = Options.mode, Options.pitch, Options.memory
            nextCache.yaw, nextCache.pitch, nextCache.lby, nextCache.delta = yaw, pitch, lby, info.desync_delta
            nextCache.feet, nextCache.torso, nextCache.animDesync = anim and anim.goal_feet_yaw, anim and anim.torso_yaw, anim and anim.desync
            nextCache.noAa, nextCache.fakePitch = state.noAa, Options.fakePitch
            nextCache.choice, nextCache.phase, nextCache.expires = best, state.phase, expires
            state.candidateCache = nextCache
        else
            state.candidateCache = nil
        end
        return best
    end

    local function rememberTarget()
        local ok, target = pcall(rage.get_target)
        if not ok or not target then return nil end
        if slotKey(target.slot) and playerKey(target.player) then
            owners[slotKey(target.slot)] = playerKey(target.player)
        end
        return target
    end

    local function fromEvent(value)
        if value == nil then return nil end
        local key = playerKey(value) or owners[slotKey(value)] or (type(value) == "string" and names[value])
        return key and states[key] or nil
    end

    local function applyOverride(state, key, value)
        if not state.refreshOverrides and state.applied and state.applied[key] == value then return end
        plist.set(state.player, key, value)
        state.applied = state.applied or {}
        state.applied[key] = value
    end

    local function update(forceState)
        if not alive or Resolver.fault then return end
        syncBuiltinBaim(Options.enabled)
        if not Options.enabled then
            if next(states) then Resolver.clear() end
            activeMode = nil
            return
        end
        if activeMode ~= Options.mode then Resolver.clear(); activeMode = Options.mode end
        local okTeam, curTeam = pcall(function() return localPlayer.Team end)
        if okTeam then
            if teamInit and curTeam ~= lastLocalTeam then Resolver.clear() end
            lastLocalTeam, teamInit = curTeam, true
        end
        local ts = nowSafe()
        if dtActive() then
            if type(rage) == "table" and type(rage.is_double_tap_charged) == "function" then
                local okDt, chDt = pcall(rage.is_double_tap_charged)
                if okDt and chDt then lastDtChargedAt = ts end
            end
            for _, group in pairs(Resolver.dt.groups) do finishDT(group) end
        end
        local currentTick = globals.tickcount()
        if not forceState and lastUpdateTick == currentTick then return end
        if not forceState then lastUpdateTick = currentTick end

        local seen = not forceState and {} or nil
        local activeTarget = not forceState and rememberTarget() or nil
        local activeKey = activeTarget and playerKey(activeTarget.player) or nil
        local enemies = forceState and {forceState.player} or entity.get_enemies()
        for _, player in ipairs(enemies) do
            local key = playerKey(player)
            local state = key and states[key] or nil
            if seen and key then seen[key] = true end
            if entity.is_alive(player) then
                local info = entity.get_info(player)
                if info and info.is_alive then
                    if state and not state.lifecycle and state.character ~= player.Character then
                        restore(state); state = nil
                    end
                    state = state or newState(player)
                    state.player = player
                    key = state.key
                    if seen then seen[key] = true end
                    if type(player.Name) == "string" then names[player.Name] = key end
                    if type(entity.get_player_slot) == "function" and (not state.slotRefresh or ts >= state.slotRefresh) then
                        state.slotRefresh = ts + 0.5
                        local slot = entity.get_player_slot(player)
                        if slotKey(slot) then owners[slotKey(slot)] = key end
                    end
                    if state.lastTick ~= currentTick or forceState == state then
                        local pitch, yaw = entity.get_player_angles_deg(player)
                        if finite(yaw) and finite(pitch) then
                            local wrappedYaw, samplePitch = wrap(yaw), clampPitch(pitch)
                            if state.lastRawYaw ~= nil then
                                local step = wrap(wrappedYaw - state.lastRawYaw)
                                local pitchStep = state.lastRawPitch ~= nil and math.abs(samplePitch - state.lastRawPitch) or 0
                                if pitchStep > 110 then
                                    state.defUntilTick = currentTick + 6
                                elseif math.abs(step) > 125 then
                                    if state.lastBigDelta and (step > 0) ~= (state.lastBigDelta > 0)
                                        and (currentTick - state.lastBigTick) <= 6 then
                                        state.defUntilTick = currentTick + 6
                                        state.lastBigDelta = nil
                                    else
                                        state.lastBigDelta, state.lastBigTick = step, currentTick
                                    end
                                end
                            end
                            local ctx, historyContext = context(state, info)
                            local angleChanged = state.lastRawYaw == nil or state.lastRawPitch == nil
                                or math.abs(wrap(wrappedYaw - state.lastRawYaw)) >= 2
                                or math.abs(samplePitch - state.lastRawPitch) >= 2
                            local ctxChanged = state.historyContext ~= historyContext or state.lastRevision ~= ctx.revision
                            local movingOrAir = info.is_in_air or (finite(info.speed) and info.speed > 5)
                            local due = forceState == state or key == activeKey or state.choice == nil
                                or angleChanged or ctxChanged or movingOrAir or not state.sampleTime or (ts - state.sampleTime > 0.08)
                                or ((currentTick + state.slotIndex) % 2 == 0)
                            if due then
                                local lby = entity.get_player_lby_deg(player)
                                if finite(lby) then
                                    local wrappedLby = wrap(lby)
                                    local rawDelta = math.abs(wrap(wrappedLby - wrappedYaw))
                                    local dVal = finite(info.desync_delta) and math.abs(info.desync_delta) or 0
                                    local twVal = 0
                                    if type(entity.get_player_twist_deg) == "function" then
                                        local okTw, tw = pcall(entity.get_player_twist_deg, player)
                                        if okTw and finite(tw) then twVal = math.abs(tw) end
                                    end
                                    if rawDelta < 8 and dVal < 8 and twVal < 8 and math.abs(samplePitch) <= 82 then
                                        state.calmTicks = math.min(40, (state.calmTicks or 0) + 1)
                                    else
                                        state.calmTicks = 0
                                    end
                                    state.noAa = state.calmTicks >= 20

                                    local inDef = Options.defensiveHold and currentTick < (state.defUntilTick or 0)
                                        and state.stableRevision == ctx.revision and state.stableContext == historyContext
                                    if not inDef then
                                        if state.historyContext ~= historyContext or (state.sampleTime and ts - state.sampleTime > 0.5) then
                                            state.history = {}
                                            state.staticSamples, state.candidateCache, state.medianDirty = 0, nil, true
                                        end
                                        state.historyContext, state.sampleTime = historyContext, ts
                                        state.lastRawYaw, state.lastRawPitch, state.lastRevision = wrappedYaw, samplePitch, ctx.revision
                                        if state.lastTick ~= currentTick or #state.history == 0 then
                                            local prev = state.history[#state.history]
                                            state.staticSamples = prev and prev.yaw == wrappedYaw and prev.pitch == samplePitch
                                                and math.min(16, (state.staticSamples or 0) + 1) or 1
                                            local rec = #state.history >= 16 and table.remove(state.history, 1) or {}
                                            rec.yaw, rec.pitch = wrappedYaw, samplePitch
                                            if prev and prev.yaw == wrappedYaw then
                                                rec.yawCos, rec.yawSin = prev.yawCos, prev.yawSin
                                            else
                                                rec.yawCos, rec.yawSin = math.cos(math.rad(wrappedYaw)), math.sin(math.rad(wrappedYaw))
                                            end
                                            state.history[#state.history + 1] = rec
                                            state.medianDirty = true
                                        end
                                    else
                                        state.lastRawYaw, state.lastRawPitch = wrappedYaw, samplePitch
                                    end
                                    state.lastTick = currentTick
                                    state.choice = candidates(state, info, wrappedYaw, samplePitch, wrappedLby, currentTick)
                                    if not state.saved then
                                        state.saved = {}
                                        for _, k in ipairs(keys) do state.saved[k] = plist.get(player, k) end
                                    end
                                    state.applied = state.applied or {}
                                    state.refreshOverrides = not state.overrideRefresh or ts >= state.overrideRefresh
                                    if state.refreshOverrides then state.overrideRefresh = ts + 2.0 end
                                    local ch = state.choice
                                    applyOverride(state, "Override yaw offset", 0)
                                    applyOverride(state, "Force body yaw value", ch.yaw)
                                    applyOverride(state, "Force body yaw", true)
                                    if ch.pitch ~= nil then applyOverride(state, "Force pitch value", ch.pitch) end
                                    local forcePitch = ch.pitch ~= nil
                                    if Options.pitch == "Off" then forcePitch = state.saved["Force pitch"] or false end
                                    if Options.pitch == "Off" and state.saved["Force pitch value"] ~= nil then
                                        applyOverride(state, "Force pitch value", state.saved["Force pitch value"])
                                    end
                                    applyOverride(state, "Force pitch", forcePitch)
                                    local baim = state.saved["Override prefer body aim"] or "-"
                                    if Options.bodyAfter > 0 and state.consecutive >= Options.bodyAfter then baim = "Force" end
                                    applyOverride(state, "Override prefer body aim", baim)
                                    local safe = state.saved["Override safe point"] or "-"
                                    if Options.safe and (state.phase ~= "tracking" or state.consecutive > 0 or ctx.misses > 0
                                        or dVal >= 70 or (info.is_in_air and not ctx.winner)) then
                                        safe = "Force"
                                    end
                                    applyOverride(state, "Override safe point", safe)
                                else
                                    restore(state); state.choice = nil; state.phase = "invalid angles"
                                end
                            end
                        else
                            restore(state); state.choice = nil; state.phase = "invalid angles"
                        end
                    end
                elseif state then
                    restore(state); state.history, state.choice = {}, nil; state.lastTick, state.phase = -1, "dead"
                end
            elseif state then
                restore(state); state.history, state.choice = {}, nil; state.lastTick, state.phase = -1, "dead"
            end
        end
        if seen then
            for key, state in pairs(states) do
                if not seen[key] then
                    restore(state)
                    for _, conn in ipairs(state.connections) do pcall(disconnectConn, conn) end
                    if state.player and playerIdCache[state.player] ~= nil then
                        playerIdCache[state.player] = nil
                        playerIdCacheCount = math.max(0, playerIdCacheCount - 1)
                    end
                    states[key] = nil
                end
            end
            for slot, key in pairs(owners) do if not states[key] then owners[slot] = nil end end
            for nm, key in pairs(names) do if not states[key] then names[nm] = nil end end
        end
        for id, shot in pairs(shots) do if ts - shot.time > 10 then shots[id] = nil end end
    end

    local function eventOutput(kind, event, matchedShot)
        if kind == "fire" and not Options.debug then return end
        local ru = Resolver.outputLanguage == "ru"
        local labels = ru and {fire = "ВЫСТРЕЛ", hit = "ПОПАДАНИЕ", miss = "ПРОМАХ"} or {fire = "FIRE", hit = "HIT", miss = "MISS"}
        local prefix = "[AR · " .. labels[kind] .. "] "
        if not event then return end
        local rec = matchedShot or (shotKey(event.id) and shots[shotKey(event.id)])
        local st = fromEvent(event.target) or (rec and rec.state)
        local target = st and st.player.Name
        if not target and (type(event.target) == "table" or type(event.target) == "userdata") then
            local ok, nm = pcall(function() return event.target.Name end)
            if ok then target = nm end
        end
        local parts = {tostring(target or "?")}
        local hb = event.hitbox or (rec and rec.hitbox)
        if type(hb) == "string" and hb ~= "" then parts[#parts + 1] = hb end
        if kind == "miss" then
            parts[#parts + 1] = tostring(event.reason or "unknown")
        elseif kind == "hit" then
            if finite(event.damage) then parts[#parts + 1] = tostring(event.damage) .. " dmg" end
            if finite(event.health_remaining) then parts[#parts + 1] = tostring(event.health_remaining) .. " HP" end
        end
        if Options.debug and rec then
            parts[#parts + 1] = "strat=" .. tostring(rec.strategy) .. " yaw=" .. string.format("%.0f", rec.yaw or 0)
        end
        print(prefix .. table.concat(parts, " · "))
    end

    function Resolver.onFire(event)
        rememberTarget()
        eventOutput("fire", event)
        Resolver.fireEvents = Resolver.fireEvents + 1
        if not Options.enabled then return end
        local rawID = event and event.id
        local id = shotKey(rawID)
        if not id then Resolver.invalidEvents = Resolver.invalidEvents + 1; return end
        if rawID == 0 or rawID == "0" then
            zeroSeq = zeroSeq + 1
            id = "zero:" .. tostring(zeroSeq)
        elseif dtActive() and shots[id] then
            return
        end
        local state = fromEvent(event.target)
        if not state or not state.choice or not state.saved then
            Resolver.unknownShots = Resolver.unknownShots + 1
            return
        end
        local choice = state.choice
        local count = 0
        for _ in pairs(shots) do count = count + 1 end
        if count >= 256 then
            local oldestID, oldestTime
            for sid, rec in pairs(shots) do
                if not oldestTime or rec.time < oldestTime then oldestID, oldestTime = sid, rec.time end
            end
            shots[oldestID] = nil
        end
        Resolver.trackedShots = Resolver.trackedShots + 1
        local anchor = choice.anchorYaw or choice.lby
        shots[id] = {
            state = state, character = state.character, life = state.life, time = nowSafe(),
            id = choice.id, context = choice.context, revision = state.contexts[choice.context].revision,
            offset = wrap(choice.yaw - anchor), lby = choice.lby, anchorYaw = anchor, yaw = choice.yaw, pitch = choice.pitch,
            hitbox = event.hitbox, hitchance = event.hitchance, strategy = choice.strategy,
            auto = Options.mode == "Auto" or Options.mode == "Debug",
        }
        if dtActive() then trackDT(shots[id], id, choice) end
    end

    local function matchFeedback(event)
        if not event then return nil, nil, "missing" end
        local id = shotKey(event.id)
        local nonZero = event.id ~= nil and event.id ~= 0 and event.id ~= "0"
        if nonZero and id and shots[id] then
            local target = fromEvent(event.target)
            if target and target ~= shots[id].state then return nil, nil, "mismatch" end
            return id, shots[id], "exact"
        end
        if nonZero then return id, nil, "unknown" end
        local target = fromEvent(event.target)
        if not target then return id, nil, "unmapped" end
        local found, rec, count = nil, nil, 0
        local ts = nowSafe()
        for pid, pend in pairs(shots) do
            if pend.state == target and pend.life == target.life and ts - pend.time <= 2 then
                found, rec, count = pid, pend, count + 1
            end
        end
        if count == 1 then return found, rec, "fallback" end
        if dtActive() and count > 1 then Resolver.dt.ambiguous = Resolver.dt.ambiguous + 1 end
        return id, nil, "ambiguous"
    end

    function Resolver.onFeedback(event, hit)
        if event then
            local stats = Resolver.results
            if hit then
                stats.hits = stats.hits + 1
                if finite(event.damage) and event.damage > 0 then stats.damage = stats.damage + event.damage end
            else
                stats.misses = stats.misses + 1
                local r = type(event.reason) == "string" and string.lower(trimStr(event.reason)) or "unknown"
                if r:find("death", 1, true) then r = "death" end
                if stats.reasons[r] == nil then r = "unknown" end
                stats.reasons[r] = stats.reasons[r] + 1
            end
        end
        local id, shot = matchFeedback(event)
        eventOutput(hit and "hit" or "miss", event, shot)
        if hit then Resolver.hitEvents = Resolver.hitEvents + 1 else Resolver.missEvents = Resolver.missEvents + 1 end
        if not Options.enabled or not event then return end
        if shot then shots[id] = nil end
        if not shot or nowSafe() - shot.time > 10 then
            Resolver.unmatchedResults = Resolver.unmatchedResults + 1
            return
        end
        if shot.dtGroup then
            local group = shot.dtGroup
            if group.closed then return end
            local hb = event.hitbox or shot.hitbox
            group.results[#group.results + 1] = {
                hit = hit, reason = event.reason,
                hitbox = type(hb) == "string" and string.lower(hb) or nil, shot = shot,
            }
            if finishDT(group) then update(group.state) end
            return
        end
        local state = shot.state
        if states[state.key] ~= state or state.life ~= shot.life or
            (not state.lifecycle and state.player.Character ~= shot.character) then return end
        local ctx = state.contexts[shot.context]
        if not ctx or shot.revision ~= ctx.revision then return end
        local missReason = not hit and type(event.reason) == "string" and string.lower(trimStr(event.reason)) or ""
        if hit then
            Resolver.hits = Resolver.hits + 1
            state.consecutive, ctx.misses = 0, 0
            ctx.revision = ctx.revision + 1
            if type(event.hitbox) == "string" and string.lower(event.hitbox) == "head" then
                if shot.auto then autoFeedback(ctx, shot.strategy, true) end
                ctx.scores[shot.id] = math.min(6, (ctx.scores[shot.id] or 0) + 2.5)
                ctx.rejected[shot.id] = nil
                ctx.winner = {offset = shot.offset, pitch = shot.pitch, time = nowSafe()}
                for i = #ctx.failedAngles, 1, -1 do
                    local f = ctx.failedAngles[i]
                    local samePitch = f.body or (f.pitch == nil and shot.pitch == nil)
                        or (f.pitch ~= nil and shot.pitch ~= nil and math.abs(f.pitch - shot.pitch) < 12)
                    if math.abs(wrap(f.offset - shot.offset)) < 14 and samePitch then table.remove(ctx.failedAngles, i) end
                end
            end
        elseif isResolverMissReason(missReason) then
            Resolver.misses = Resolver.misses + 1
            state.consecutive = state.consecutive + 1
            ctx.misses = ctx.misses + 1
            state.defUntilTick = 0
            if ctx.misses % Options.cycleAfter == 0 then
                local rejectFor = math.clamp(Options.memory * 0.4, 4, 8)
                ctx.revision = ctx.revision + 1
                if shot.auto then autoFeedback(ctx, shot.strategy, false) end
                local hb = event.hitbox or shot.hitbox
                ctx.failedAngles[#ctx.failedAngles + 1] = {
                    offset = shot.offset, pitch = shot.pitch,
                    body = type(hb) == "string" and string.lower(hb) ~= "head",
                    expires = nowSafe() + rejectFor,
                }
                if #ctx.failedAngles > 32 then table.remove(ctx.failedAngles, 1) end
                if shot.strategy == "Brute-force" then ctx.stage = ctx.stage % #bruteOffsets + 1 end
                ctx.scores[shot.id] = math.max(-12, (ctx.scores[shot.id] or 0) - 3)
                ctx.rejected[shot.id], ctx.winner = nowSafe() + rejectFor, nil
            end
        else
            Resolver.ignored = Resolver.ignored + 1
        end
        if hit or isResolverMissReason(missReason) then update(state) end
    end

    function Resolver.tick()
        if not alive or Resolver.fault then return end
        local ok, err = pcall(update)
        if not ok then
            Resolver.fault = tostring(err)
            Options.enabled = false
            syncBuiltinBaim(false)
            Resolver.clear()
            warn("[Resolver] Disabled after error: " .. Resolver.fault)
        end
    end

    function Resolver.status(ru)
        if Resolver.fault then return ru and "Ошибка резольвера (см. консоль)" or "Resolver error (see console)" end
        if not Options.enabled then return ru and "Резольвер выключен" or "Resolver disabled" end
        local count = 0
        for _ in pairs(states) do count = count + 1 end
        if ru then
            return string.format("%s · целей: %d · хиты: %d / миссы: %d", Options.mode, count, Resolver.hits, Resolver.misses)
        end
        return string.format("%s · targets: %d · hits: %d / misses: %d", Options.mode, count, Resolver.hits, Resolver.misses)
    end

    function Resolver.targetStatus(ru)
        local target = rememberTarget()
        local st = target and states[playerKey(target.player)] or nil
        if not st or not st.choice then return ru and "Цель: нет активной цели" or "Target: none" end
        local pStr = st.choice.pitch ~= nil and string.format("%.0f", st.choice.pitch) or "-"
        return string.format("%s · %s · yaw %.0f · pitch %s · %s",
            tostring(st.player.Name), tostring(st.strategy), st.choice.yaw, pStr, tostring(st.phase))
    end

    function Resolver.shotStatistics()
        local s = Resolver.results
        local r = s.reasons
        print(string.format("[AR STATS] hits=%d dmg=%d misses=%d (resolver=%d spread=%d occlusion=%d death=%d other=%d) DT=%s",
            s.hits, s.damage, s.misses, r.resolver, r.spread, r.occlusion, r.death, r.unknown, Resolver.dt.last))
        return "Stats printed to console"
    end

    function Resolver.diagnose()
        local count = 0
        for _ in pairs(states) do count = count + 1 end
        print(string.format("[AR DIAG] build=%s enabled=%s mode=%s dtHold=%s fakePitch=%s safe=%s targets=%d eval=%d cache=%d",
            BUILD, tostring(Options.enabled), tostring(Options.mode), tostring(Options.dtHold),
            tostring(Options.fakePitch), tostring(Options.safe), count,
            Resolver.performance.evaluations, Resolver.performance.cached))
        return "Diagnostics printed to console"
    end
end

-- ==================== AA BUILDER 2.0 (ROLL + FAKEPITCH + MANUAL) ====================
do
    Builder.owned = false
    Builder.state = nil
    Builder.profile = "Global"
    Builder.fault = nil
    Builder.requested = false
    Builder.pause = nil

    local randomMemo = {}
    local defense = nil
    local readyAt = nil
    local lastTick, epoch = nil, 0
    local candidate, candCount = nil, 0
    local lastKey, shotTick, flushRequested = false, nil, false
    local desyncModeOwned, fakeLagOwned = nil, false
    local rollOwned, fakePitchOwned, showFakeOwned = false, false, false
    local lastTeam, teamInit = nil, false
    local releaseFault, releaseRetry = nil, nil

    local function builderAPI()
        requireAPI(aa, "reset")
        requireAPI(aa, "override_pitch")
        requireAPI(aa, "override_yaw")
        requireAPI(aa, "override_yaw_offset")
        requireAPI(aa, "override_yaw_modifier")
        requireAPI(aa, "override_body_yaw")
        requireAPI(aa, "override_inverter")
        requireAPI(aa, "override_desync_limits")
        requireAPI(aa, "override_fake_lag")
        requireAPI(aa, "override_fake_lag_limit")
        requireAPI(aa, "override_fake_lag_variability")
        requireAPI(globals, "tickcount")
    end

    function Builder.release(reason)
        if Builder.owned then
            pcall(function()
                if rollOwned then
                    if type(aa.override_extended_angles) == "function" then pcall(aa.override_extended_angles, nil) end
                    if type(aa.override_extended_angles_enabled) == "function" then pcall(aa.override_extended_angles_enabled, nil) end
                end
                if fakePitchOwned then
                    if type(aa.override_fake_pitch) == "function" then pcall(aa.override_fake_pitch, nil) end
                    if type(aa.override_fake_pitch_angle) == "function" then pcall(aa.override_fake_pitch_angle, nil) end
                end
                if showFakeOwned and type(aa.override_show_fake) == "function" then
                    pcall(aa.override_show_fake, false)
                end
            end)
            local ok, err = pcall(aa.reset)
            if not ok then
                releaseFault, releaseRetry = tostring(err), nowSafe() + 1
                warn("[AR AA] Release failed: " .. releaseFault)
                return false
            end
        end
        releaseFault, releaseRetry = nil, nil
        Builder.owned, defense, Builder.requested = false, nil, false
        Builder.state, Builder.profile = nil, "Global"
        candidate, candCount, lastTick = nil, 0, nil
        randomMemo, lastKey, readyAt = {}, false, nil
        shotTick, flushRequested = nil, false
        desyncModeOwned, fakeLagOwned = nil, false
        rollOwned, fakePitchOwned, showFakeOwned = false, false, false
        Builder.pause = reason
        return true
    end

    function Builder.setEnabled(value)
        Settings.builder.enabled = value == true
        if not Settings.builder.enabled then Builder.release("disabled") else Builder.fault = nil end
    end

    function Builder.triggerManual()
        if not Settings.builder.enabled then return false end
        Builder.requested = true
        return true
    end

    function Builder.onShot()
        if Settings.builder.enabled and not Builder.fault then shotTick = globals.tickcount() end
    end

    function Builder.applyPreset(name)
        local b = Settings.builder
        b.enabled = true
        b.respectManual = true
        for _, st in ipairs(STATES) do
            b.profiles[st] = profileDefault()
        end
        b.profiles.Global.enabled = true
        if name == "Meta Roll" then
            local g = b.profiles.Global
            g.pitchMode, g.pitchA = "Fixed", -89
            g.yawMode, g.amplitude, g.yawPeriod = "Center", 26, 2
            g.desyncMode, g.left, g.right, g.inverter, g.desyncPeriod = "Limits", 86, 86, "Alternate", 3
            g.rollMode, g.rollAmount, g.rollPeriod = "Follow Inverter", 85, 3
            g.fakePitchMode, g.fakePitchA, g.fakePitchOffset = "Down", -70, 14
            g.fakeLag, g.lagLimit, g.lagVariation = true, 6, 15
            g.defensive.enabled, g.defensive.trigger, g.defensive.shift, g.defensive.flush = true, "Charged", true, true
            g.defensive.rollAmount, g.defensive.fakePitch = 100, true

            local crouch = b.profiles.Crouching
            crouch.enabled = true
            crouch.yawMode, crouch.amplitude, crouch.yawPeriod = "Center", 18, 2
            crouch.left, crouch.right, crouch.inverter = 86, 86, "Alternate"
            crouch.rollMode, crouch.rollAmount = "Opposite Inverter", 100
            crouch.fakePitchMode, crouch.fakePitchA, crouch.fakePitchOffset = "Custom", -65, -16

            local air = b.profiles.Air
            air.enabled = true
            air.yawMode, air.amplitude, air.yawPeriod = "3-Way", 42, 2
            air.left, air.right, air.inverter = 86, 86, "Alternate"
            air.rollMode, air.rollAmount, air.rollPeriod = "Jitter", 90, 2
            air.fakePitchMode, air.fakePitchA, air.fakePitchB, air.fakePitchPeriod = "Jitter", -70, 65, 2
            air.defensive.enabled, air.defensive.trigger, air.defensive.shift, air.defensive.teleport = true, "Charged", true, true
        elseif name == "Fakepitch Jitter" then
            local g = b.profiles.Global
            g.yawMode, g.amplitude, g.yawPeriod = "3-Way", 38, 2
            g.left, g.right, g.inverter, g.desyncPeriod = 72, 72, "Alternate", 2
            g.rollMode, g.rollAmount, g.rollPeriod = "Jitter", 65, 2
            g.fakePitchMode, g.fakePitchA, g.fakePitchB, g.fakePitchOffset, g.fakePitchPeriod = "Jitter", -70, 68, 18, 2
            g.fakeLag, g.lagLimit, g.lagVariation = true, 5, 20
            g.defensive.enabled, g.defensive.trigger, g.defensive.fakePitch = true, "On shot", true
        elseif name == "Defensive Tank" then
            local g = b.profiles.Global
            g.yawMode, g.amplitude, g.yawPeriod = "5-Way", 45, 2
            g.desyncMode, g.real, g.fake, g.inverter, g.desyncPeriod = "Explicit", -86, 86, "Alternate", 2
            g.rollMode, g.rollAmount, g.rollPeriod = "Sway", 100, 6
            g.fakePitchMode, g.fakePitchA, g.fakePitchB, g.fakePitchPeriod = "Jitter", -70, 70, 2
            g.fakeLag, g.lagLimit, g.lagVariation = true, 8, 25
            local d = g.defensive
            d.enabled, d.trigger, d.duration, d.cooldown = true, "Charged", 5, 14
            d.pitchMode, d.pitchA, d.pitchB, d.amplitude, d.period = "Jitter", -89, 89, 115, 1
            d.shift, d.shiftTicks, d.flush, d.teleport, d.rollAmount, d.fakePitch = true, 6, true, true, 100, true
        end
        Builder.release("preset")
        return "Applied AA preset: " .. name
    end

    local function localSnapshot()
        local ok, info = pcall(entity.get_info, 0)
        if ok and type(info) == "table" and type(info.is_alive) == "boolean" then return info end
        if type(entity.get_local_player) == "function" then
            local good, lp = pcall(entity.get_local_player)
            if good and lp then
                local ok2, snap = pcall(entity.get_info, lp)
                if ok2 and type(snap) == "table" and type(snap.is_alive) == "boolean" then return snap end
            end
        end
        return nil
    end

    local function detectState(info)
        local grounded = type(info.is_in_air) == "boolean" and not info.is_in_air
        if type(info.is_in_air) ~= "boolean" and type(movement) == "table" and type(movement.is_grounded) == "function" then
            local ok, g = pcall(movement.is_grounded, 0)
            grounded = ok and g == true
        end
        local duck = info.is_crouching == true
        if type(info.is_crouching) ~= "boolean" and type(movement) == "table" and type(movement.is_ducking) == "function" then
            local ok, d = pcall(movement.is_ducking, 0)
            duck = ok and d == true
        end
        local speed = finite(info.speed) and info.speed or 0
        if not finite(info.speed) and type(movement) == "table" and type(movement.get_speed) == "function" then
            local ok, sp = pcall(movement.get_speed, 0)
            if ok and finite(sp) then speed = sp end
        end
        if not grounded then return duck and "Air crouch" or "Air" end
        if duck then return speed > 0.4 and "Crouch moving" or "Crouching" end
        if speed <= 0.4 then return "Standing" end
        return speed <= Settings.builder.slow and "Slow" or "Moving"
    end

    local function randomStep(key, phase, low, high)
        local rec = randomMemo[key]
        if not rec or rec.phase ~= phase or rec.low ~= low or rec.high ~= high then
            rec = {phase = phase, low = low, high = high, value = low + math.random() * (high - low)}
            randomMemo[key] = rec
        end
        return rec.value
    end

    local function profilePitch(profile, elapsed, key)
        local period = math.max(1, profile.pitchPeriod or profile.period or 4)
        local phase = math.floor(elapsed / period)
        if profile.pitchMode == "Jitter" then return phase % 2 == 0 and profile.pitchA or profile.pitchB end
        if profile.pitchMode == "Random" then return randomStep(key, phase, math.min(profile.pitchA, profile.pitchB), math.max(profile.pitchA, profile.pitchB)) end
        if profile.pitchMode == "Sway" then
            local mid, amp = (profile.pitchA + profile.pitchB) * 0.5, (profile.pitchB - profile.pitchA) * 0.5
            return mid + math.sin(elapsed * math.pi / period) * amp
        end
        if profile.pitchMode == "Flick" then return elapsed % period == 0 and profile.pitchB or profile.pitchA end
        return profile.pitchA
    end

    local function yawWave(profile, elapsed)
        local period = math.max(1, profile.yawPeriod or 4)
        local phase = math.floor(elapsed / period)
        local mode, amp = profile.yawMode, profile.amplitude
        if mode == "Center" then return phase % 2 == 0 and -amp or amp end
        if mode == "3-Way" then return ({-amp, 0, amp})[phase % 3 + 1] end
        if mode == "5-Way" then return ({-amp, -amp * 0.5, 0, amp * 0.5, amp})[phase % 5 + 1] end
        if mode == "Spin" then return wrap(elapsed * profile.spinSpeed) end
        if mode == "Random" then return randomStep("yaw", phase, -amp, amp) end
        if mode == "Sequence" and #profile.sequence > 0 then return profile.sequence[phase % #profile.sequence + 1] end
        return 0
    end

    local function computeRoll(profile, elapsed, inverted)
        local mode = profile.rollMode
        local amt = math.clamp(profile.rollAmount or 0, -100, 100)
        if mode == "Off" or amt == 0 then return nil end
        if mode == "Static" then return amt end
        if mode == "Follow Inverter" then return inverted and -amt or amt end
        if mode == "Opposite Inverter" then return inverted and amt or -amt end
        local period = math.max(1, profile.rollPeriod or 4)
        if mode == "Jitter" then
            return (math.floor(elapsed / period) % 2 == 0) and amt or -amt
        end
        if mode == "Sway" then
            return roundInt(math.sin(elapsed * math.pi / period) * amt)
        end
        return nil
    end

    local function computeFakePitch(profile, elapsed)
        local mode = profile.fakePitchMode
        if mode == "Off" then return nil, nil end
        local off = math.clamp(profile.fakePitchOffset or 0, -20, 20)
        if mode == "Down" or mode == "Up" or mode == "Zero" then return mode, off end
        if mode == "Custom" then return math.clamp(profile.fakePitchA or -70, -70, 70), off end
        if mode == "Jitter" then
            local period = math.max(1, profile.fakePitchPeriod or 4)
            local val = (math.floor(elapsed / period) % 2 == 0) and (profile.fakePitchA or -70) or (profile.fakePitchB or 70)
            return math.clamp(val, -70, 70), off
        end
        return nil, nil
    end

    local function finishDefense(tick)
        if not defense then return end
        local cfg = defense.config
        defense, readyAt = nil, tick + cfg.cooldown
        if cfg.flush then flushRequested = true end
        if cfg.teleport and type(aa.force_teleport) == "function" then pcall(aa.force_teleport) end
    end

    local function builderUpdate()
        if not alive then return end
        if not Settings.builder.enabled then
            if Builder.owned then Builder.release("disabled") end
            return
        end
        local okTeam, curTeam = pcall(function() return localPlayer.Team end)
        if okTeam then
            if teamInit and curTeam ~= lastTeam then
                if Builder.owned then Builder.release("team switch") end
            end
            lastTeam, teamInit = curTeam, true
            if curTeam then
                local okTn, tn = pcall(function() return curTeam.Name end)
                if okTn and type(tn) == "string" and string.lower(tn):find("spectat", 1, true) then
                    if Builder.owned then Builder.release("spectator") end
                    Builder.pause = "spectator"
                    return
                end
            end
        end
        local info = localSnapshot()
        local inVoid = false
        pcall(function()
            local ch = localPlayer.Character
            local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head"))
            if root and root.Position and root.Position.Y < -200 then inVoid = true end
        end)
        if not info or not info.is_alive or inVoid then
            if Builder.owned then Builder.release(inVoid and "void" or "dead") end
            Builder.pause = inVoid and "void" or "dead"
            return
        end
        if not Builder.owned then
            builderAPI(); Builder.owned = true; aa.reset()
            desyncModeOwned, fakeLagOwned = nil, false
            rollOwned, fakePitchOwned, showFakeOwned = false, false, false
            randomMemo, epoch = {}, globals.tickcount()
        end
        local tick = globals.tickcount()
        if lastTick == tick then return end
        if lastTick and tick < lastTick then
            Builder.release("tick reset")
            Builder.owned, epoch = true, tick
        end
        lastTick, Builder.pause = tick, nil

        local raw = detectState(info)
        if raw == candidate then candCount = candCount + 1 else candidate, candCount = raw, 1 end
        if not Builder.state or candCount >= Settings.builder.hysteresis then Builder.state = raw end
        local stProf = Settings.builder.profiles[Builder.state]
        local profName = (stProf and stProf.enabled) and Builder.state or "Global"
        local prof = Settings.builder.profiles[profName]
        if profName ~= Builder.profile then
            if defense and not prof.defensive.enabled then finishDefense(tick) end
            Builder.profile = profName
        end

        local elapsed = tick - epoch
        local menuOpen = type(ui) == "table" and type(ui.is_menu_open) == "function" and ui.is_menu_open()
        local isTyping = type(input) == "table" and type(input.is_typing) == "function" and input.is_typing()
        local down = not menuOpen and not isTyping and type(input) == "table" and type(input.is_key_down) == "function"
            and input.is_key_down(Settings.builder.manualKey)
        local manual = Builder.requested or (down and not lastKey)
        Builder.requested, lastKey = false, down
        local shot = shotTick and tick - shotTick >= 0 and tick - shotTick <= 2
        shotTick = nil

        if defense and (tick >= defense.untilTick or not prof.defensive.enabled) then finishDefense(tick) end
        local d = prof.defensive
        if d.enabled and not defense and tick >= (readyAt or 0) then
            local trig = (d.trigger == "Manual" and manual) or (d.trigger == "On shot" and shot)
            local charged = false
            if d.trigger == "Charged" or d.shift then
                if type(rage) == "table" and type(rage.is_double_tap_charged) == "function" then
                    local okC, resC = pcall(rage.is_double_tap_charged)
                    charged = okC and resC == true
                end
            end
            if d.trigger == "Charged" then trig = charged end
            if trig and (not d.shift or charged) then
                if d.shift and type(rage) == "table" and type(rage.shift_ticks) == "function" then
                    pcall(rage.shift_ticks, d.shiftTicks)
                end
                defense = {untilTick = tick + d.duration, start = tick, config = clone(d)}
            end
        end

        local manualDir = nil
        if Settings.builder.respectManual and type(aa.is_manual) == "function" and type(aa.get_manual) == "function" then
            local okM, isMan = pcall(aa.is_manual)
            if okM and isMan then
                local okD, mDir = pcall(aa.get_manual)
                if okD and type(mDir) == "string" then manualDir = mDir end
            end
        end

        local pitch = profilePitch(prof, elapsed, "pitch")
        local yaw = prof.yawOffset + yawWave(prof, elapsed)
        local yawBase = prof.yawBase
        if manualDir == "Left" then yaw, yawBase = -90, "camera"
        elseif manualDir == "Right" then yaw, yawBase = 90, "camera"
        elseif manualDir == "Back" then yaw, yawBase = 180, "camera" end

        local inverted = prof.inverter == "Right"
            or (prof.inverter == "Alternate" and math.floor(elapsed / math.max(1, prof.desyncPeriod)) % 2 == 1)

        local rollVal = computeRoll(prof, elapsed, inverted)
        local fpVal, fpOff = computeFakePitch(prof, elapsed)

        if defense then
            local cfg, phase = defense.config, tick - defense.start
            pitch = profilePitch(cfg, phase, "def-pitch")
            yaw = cfg.yawOffset + ((math.floor(phase / math.max(1, cfg.period)) % 2 == 0) and -cfg.amplitude or cfg.amplitude)
            if cfg.rollAmount and cfg.rollAmount ~= 0 then
                rollVal = ((phase % 2 == 0) and cfg.rollAmount or -cfg.rollAmount)
            end
            if cfg.fakePitch then
                fpVal = (phase % 2 == 0) and 70 or -70
                fpOff = (phase % 2 == 0) and 20 or -20
            end
        end
        yaw = wrap(yaw)

        local flush = flushRequested
        if flush and type(aa.unchoke) == "function" then pcall(aa.unchoke) end
        local needReset = (desyncModeOwned ~= nil and desyncModeOwned ~= prof.desyncMode)
            or (not prof.fakeLag and fakeLagOwned)
        if needReset then
            aa.reset()
            desyncModeOwned, fakeLagOwned, rollOwned, fakePitchOwned, showFakeOwned = nil, false, false, false, false
        end

        aa.override_yaw_modifier("Disabled")
        aa.override_yaw_offset(0)
        aa.override_pitch(pitch)
        aa.override_yaw(yaw, yawBase)
        aa.override_body_yaw(true)
        aa.override_inverter(inverted)

        if prof.desyncMode == "Explicit" and type(aa.override_desync) == "function" then
            local sign = inverted and -1 or 1
            aa.override_desync(prof.real * sign, prof.fake * sign)
            desyncModeOwned = "Explicit"
        else
            aa.override_desync_limits(prof.left, prof.right)
            desyncModeOwned = "Limits"
        end

        if prof.fakeLag then
            aa.override_fake_lag(not flush)
            aa.override_fake_lag_limit(flush and 0 or prof.lagLimit)
            aa.override_fake_lag_variability(prof.lagVariation)
            fakeLagOwned = true
        end

        -- Roll / Extended Angles (new API)
        if rollVal ~= nil and type(aa.override_extended_angles) == "function" then
            if type(aa.override_extended_angles_enabled) == "function" then
                pcall(aa.override_extended_angles_enabled, true)
            end
            pcall(aa.override_extended_angles, math.clamp(rollVal, -100, 100))
            rollOwned = true
        elseif rollOwned then
            if type(aa.override_extended_angles) == "function" then pcall(aa.override_extended_angles, nil) end
            if type(aa.override_extended_angles_enabled) == "function" then pcall(aa.override_extended_angles_enabled, nil) end
            rollOwned = false
        end

        -- Fake Pitch Desync (new API)
        if fpVal ~= nil and type(aa.override_fake_pitch) == "function" then
            pcall(aa.override_fake_pitch, fpVal)
            if type(aa.override_fake_pitch_angle) == "function" and fpOff ~= nil then
                pcall(aa.override_fake_pitch_angle, math.clamp(fpOff, -20, 20))
            end
            fakePitchOwned = true
        elseif fakePitchOwned then
            if type(aa.override_fake_pitch) == "function" then pcall(aa.override_fake_pitch, nil) end
            if type(aa.override_fake_pitch_angle) == "function" then pcall(aa.override_fake_pitch_angle, nil) end
            fakePitchOwned = false
        end

        -- Show Fake visualizer (new API)
        if type(aa.override_show_fake) == "function" then
            if Settings.builder.showFake then
                pcall(aa.override_show_fake, true)
                showFakeOwned = true
            elseif showFakeOwned then
                pcall(aa.override_show_fake, false)
                showFakeOwned = false
            end
        end

        flushRequested = false
    end

    function Builder.tick()
        if not Settings.builder.enabled and not Builder.owned then return end
        if releaseFault then
            if nowSafe() >= (releaseRetry or 0) then Builder.release("retry") end
            return
        end
        if not alive or Builder.fault then return end
        local ok, err = pcall(builderUpdate)
        if not ok then
            Builder.fault, Settings.builder.enabled = tostring(err), false
            Builder.release("API error")
            warn("[AR AA] Disabled: " .. Builder.fault)
        end
    end

    function Builder.status(ru)
        if Builder.fault or releaseFault then return ru and "AA: ошибка API (см. консоль)" or "AA: API error (see console)" end
        if not Settings.builder.enabled then return ru and "AA: встроенный чит" or "AA: built-in cheat" end
        if not Builder.state then return ru and "AA: ожидание спавна" or "AA: waiting for character" end
        local extra = defense and (ru and " · ДЕФЕНСИВ" or " · DEFENSIVE") or ""
        return "AA: " .. tostring(Builder.state) .. " / " .. tostring(Builder.profile) .. extra
    end
end

-- ==================== SYNC (TAB + 3D ESP) ====================
do
    local syncUis = nil
    pcall(function() syncUis = game:GetService("UserInputService") end)
    local S = {
        POLL_INTERVAL = 14,
        MIN_POLL_GAP = 8.5,
        PEER_GRACE_SEC = 65,
        SCAN_INTERVAL = 0.9,
        EMPTY_SCAN_INTERVAL = 1.2,
        MAX_SCAN_NODES = 8000,
        ROLE_ORDER = {dev = 5, staff = 4, vip = 3, beta = 2, free = 1},
        ROLE_TAGS = {dev = "DEV", staff = "MOD", vip = "VIP", beta = "BETA", free = "AR"},
        SKIP_GUI_HINTS = {"arbadge", "ar_esp", "ar_textbridge", "bubblechat", "experiencechat", "killfeed", "freecam", "shop", "inventory", "mainmenu", "cinematic", "adminpanel", "antiresolver_skeet"},
        IGNORE_TEXT_ANCESTOR = {"chat", "bubblechat", "experiencechat", "killfeed", "killlog", "elimfeed", "arbadge", "ar_esp", "tooltip"},
        SCOREBOARD_HINTS = {"tab", "score", "board", "player", "roster", "list", "leader", "team"},
        gen = 0,
        inFlight = false,
        scanRunning = false,
        nextPollAt = 0,
        lastAttemptAt = 0,
        nextScanAt = 0,
        nextReposAt = 0,
        espPlayersAt = 0,
        espMyId = nil,
        espById = {},
        espActiveScratch = {},
        failCount = 0,
        lastOkAt = nil,
        storageMode = nil,
        selfRole = "free",
        statusNote = "Idle",
        peerBadges = {},
        peerSeenAt = {},
        badgeCount = 0,
        tabCount = 0,
        tabBadges = {},
        espDrawings = {},
        espBillboards = {},
        billboardBroken = false,
        cachedHttpFn = false,
        cachedPlayersSvc = false,
        loggedOnline = false,
        lastAttachSig = "",
        lastTabDown = false,
        tabPressedSignal = false,
        tabConn = nil,
        lastHttpErrLog = nil,
    }
    if syncUis then
        pcall(function()
            S.tabConn = syncUis.InputBegan:Connect(function(inp)
                if inp and inp.KeyCode == Enum.KeyCode.Tab then
                    S.tabPressedSignal = true
                    S.nextScanAt = 0
                    S.nextReposAt = 0
                end
            end)
        end)
    end
    local H = {}

    function H.roleColor(role)
        if not S.roleColors then
            S.roleColors = {
                dev = Color3.fromRGB(255, 204, 72),
                staff = Color3.fromRGB(115, 230, 175),
                vip = Color3.fromRGB(205, 130, 255),
                beta = Color3.fromRGB(120, 200, 255),
                free = Color3.fromRGB(154, 200, 47),
            }
        end
        return S.roleColors[role] or S.roleColors.free
    end

    function H.syncCfg()
        if not Settings.sync then
            Settings.sync = {enabled = true, endpoint = "", logoAsset = "", tabBadges = true, espBadges = true, stealth = false}
        end
        Settings.sync.endpoint = ""
        Settings.sync.logoAsset = ""
        Settings.sync.tabBadges = true
        Settings.sync.espBadges = true
        Settings.sync.stealth = false
        return Settings.sync
    end

    function H.effectiveAsset()
        local raw = trimStr(DEFAULT_LOGO_ASSET)
        if raw == "" then return "" end
        if raw:match("^%d+$") then return "rbxassetid://" .. raw end
        if raw:match("^rbxassetid://%d+$") or raw:match("^rbxthumb://") then return raw end
        return ""
    end

    function H.getPlayersService()
        if S.cachedPlayersSvc ~= false then return S.cachedPlayersSvc end
        local ok, svc = pcall(function() return game:GetService("Players") end)
        S.cachedPlayersSvc = (ok and svc) or nil
        return S.cachedPlayersSvc
    end

    function H.getPlayerGui()
        local svc = H.getPlayersService()
        local lp = nil
        if svc then
            local ok, p = pcall(function() return svc.LocalPlayer end)
            if ok and p then lp = p end
        end
        if not lp then lp = localPlayer end
        if not lp then return nil, lp end
        local ok, pg = pcall(function()
            return lp:FindFirstChildOfClass("PlayerGui") or lp:FindFirstChild("PlayerGui")
        end)
        return (ok and pg) or nil, lp
    end

    function H.resolveHttp()
        if S.cachedHttpFn ~= false then return S.cachedHttpFn end
        S.cachedHttpFn = resolveHttpRequest()
        return S.cachedHttpFn
    end

    function H.readSafeId(player)
        local ok, id = pcall(function() return player.UserId end)
        if ok and finite(id) and id > 0 and id % 1 == 0 then return id end
        return nil
    end

    function H.readNames(player)
        local n, d = nil, nil
        local ok1, v1 = pcall(function() return player.Name end)
        if ok1 and type(v1) == "string" and #v1 > 0 then n = v1 end
        local ok2, v2 = pcall(function() return player.DisplayName end)
        if ok2 and type(v2) == "string" and #v2 > 0 then d = v2 end
        return n, d
    end

    function H.collectPlayers()
        local _, lp = H.getPlayerGui()
        local myId = lp and H.readSafeId(lp) or nil
        local byId, peerIds, meta = {}, {}, {}
        local svc = H.getPlayersService()
        local list = nil
        if svc then
            local ok, res = pcall(function() return svc:GetPlayers() end)
            if ok and type(res) == "table" then list = res end
        end
        if not list and type(entity.get_players) == "function" then
            local ok, res = pcall(entity.get_players, false)
            if ok and type(res) == "table" then list = res end
        end
        if list then
            for _, p in ipairs(list) do
                local id = H.readSafeId(p)
                if id then
                    byId[id] = p
                    local n, d = H.readNames(p)
                    meta[id] = {name = n, display = d}
                    if id ~= myId and #peerIds < 64 then peerIds[#peerIds + 1] = id end
                end
            end
        end
        return myId, peerIds, byId, meta
    end

    function H.recountTab()
        local n = 0
        for _ in pairs(S.tabBadges) do n = n + 1 end
        S.tabCount = n
    end

    function H.removeTabEntry(id)
        local entry = S.tabBadges[id]
        if not entry then return end
        S.tabBadges[id] = nil
        if entry.conns then
            for i = 1, #entry.conns do pcall(function() entry.conns[i]:Disconnect() end) end
        end
        if entry.gui then pcall(function() entry.gui:Destroy() end) end
        H.recountTab()
    end

    function H.clearTabBadges()
        for id in pairs(S.tabBadges) do H.removeTabEntry(id) end
        S.tabBadges, S.tabCount = {}, 0
    end

    function H.destroyDraw(obj)
        if not obj then return end
        pcall(function() obj.Visible = false end)
        if type(obj.Destroy) == "function" then pcall(obj.Destroy, obj)
        elseif type(obj.Remove) == "function" then pcall(obj.Remove, obj) end
    end

    function H.clearEsp()
        for id, obj in pairs(S.espDrawings) do H.destroyDraw(obj); S.espDrawings[id] = nil end
        for id, bb in pairs(S.espBillboards) do if bb then pcall(function() bb:Destroy() end) end; S.espBillboards[id] = nil end
    end

    function H.containsHint(text, hints)
        if type(text) ~= "string" or #text == 0 then return false end
        local low = string.lower(text)
        for _, h in ipairs(hints) do if low:find(h, 1, true) then return true end end
        return false
    end

    function H.readNameSafe(inst)
        local ok, n = pcall(function() return inst.Name end)
        return (ok and type(n) == "string") and n or ""
    end

    function H.shouldSkipNode(inst)
        local low = string.lower(H.readNameSafe(inst))
        if low == "chat" then return true end
        return H.containsHint(low, S.SKIP_GUI_HINTS)
    end

    function H.isBranchVisible(inst)
        local okEn, en = pcall(function() return inst.Enabled end)
        if okEn and en == false then return false end
        local okVis, vis = pcall(function() return inst.Visible end)
        if okVis and vis == false then return false end
        return true
    end

    function H.readNodeRect(inst)
        local okS, sz = pcall(function() return inst.AbsoluteSize end)
        if not okS or not sz or sz.X < 8 or sz.Y < 8 then return nil end
        local okP, pos = pcall(function() return inst.AbsolutePosition end)
        if not okP or not pos then return sz.X, sz.Y, 0, 0 end
        if pos.X + sz.X <= 0 or pos.Y + sz.Y <= 0 then return nil end
        return sz.X, sz.Y, pos.X, pos.Y
    end

    local function isTopStop(p, playerGui)
        if not p or p == playerGui then return true end
        local n = H.readNameSafe(p)
        if n == "PlayerGui" or n == "Players" or n == "CoreGui" or n == "Workspace" then return true end
        local ok, hit = pcall(function() return p:IsA("PlayerGui") or p:IsA("Player") or p:IsA("DataModel") end)
        return ok and hit == true
    end

    function H.readRowWidth(node, playerGui)
        local cur, maxW = node, 0
        for _ = 1, 3 do
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or isTopStop(p, playerGui) then break end
            local okS, sz = pcall(function() return p.AbsoluteSize end)
            if okS and sz and sz.X >= 140 and sz.Y >= 12 and sz.Y <= 64 and sz.X > maxW then maxW = sz.X end
            cur = p
        end
        return maxW
    end

    function H.shortGuiPath(node, playerGui)
        local parts, cur = {}, node
        for _ = 1, 12 do
            if isTopStop(cur, playerGui) then break end
            table.insert(parts, 1, H.readNameSafe(cur))
            local ok, p = pcall(function() return cur.Parent end)
            if not ok then break end
            cur = p
        end
        return table.concat(parts, ".")
    end

    function H.findAncestorScoreboard(node, playerGui)
        local cur, best = node, nil
        for _ = 1, 12 do
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or isTopStop(p, playerGui) then break end
            if H.containsHint(H.readNameSafe(p), S.SCOREBOARD_HINTS) then best = p end
            cur = p
        end
        return best
    end

    function H.isLikelyRowTextNode(node, playerGui)
        local cur, hasList = node, false
        for step = 1, 10 do
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or isTopStop(p, playerGui) then break end
            local pName = H.readNameSafe(p)
            if H.containsHint(pName, S.IGNORE_TEXT_ANCESTOR) then return false end
            if H.containsHint(pName, S.SCOREBOARD_HINTS) then hasList = true end
            if not hasList and step <= 3 then
                local okS, sz = pcall(function() return p.AbsoluteSize end)
                if okS and sz and sz.X >= 100 and sz.Y >= 10 and sz.Y <= 90 then hasList = true end
            end
            if not hasList then
                local okSf, sf = pcall(function() return p:IsA("ScrollingFrame") end)
                if okSf and sf then hasList = true end
                if not hasList and step <= 5 then
                    local okC, ch = pcall(function() return p:GetChildren() end)
                    if okC and type(ch) == "table" and #ch >= 2 then
                        for _, sib in ipairs(ch) do
                            local okT, match = pcall(function()
                                if sib:IsA("UIListLayout") or sib:IsA("UIGridLayout") then return true end
                                if step <= 2 and (sib:IsA("ImageLabel") or sib:IsA("ImageButton")) then return true end
                                return false
                            end)
                            if okT and match then hasList = true; break end
                        end
                    end
                end
            end
            cur = p
        end
        return hasList
    end

    function H.wantedMap(myId)
        local wanted, count = {}, 0
        for id, role in pairs(S.peerBadges) do wanted[id] = role; count = count + 1 end
        if myId and S.ROLE_ORDER[S.selfRole] then
            if not wanted[myId] then count = count + 1 end
            wanted[myId] = S.selfRole
        end
        return wanted, count
    end

    function H.positionTextBadge(entry)
        if not entry or entry.kind ~= "text" or not entry.gui or not entry.host then return end
        local f, host, bw = entry.gui, entry.host, entry.bw or 16
        local padL = entry.padL or 0
        local hostW, tbX, clips, align = 0, 0, false, "left"
        pcall(function() if host.AbsoluteSize then hostW = host.AbsoluteSize.X end end)
        pcall(function() if host.TextBounds then tbX = host.TextBounds.X end end)
        pcall(function() clips = host.ClipsDescendants == true end)
        pcall(function()
            if host.TextXAlignment == Enum.TextXAlignment.Center then align = "center"
            elseif host.TextXAlignment == Enum.TextXAlignment.Right then align = "right" end
        end)
        local ax, ps, px = 0, 0, 0
        if tbX > 0 and align == "left" then
            px = math.floor(padL + tbX + 6)
            if clips and hostW > bw + 4 and px + bw > hostW - 2 then
                px = math.max(0, math.floor(hostW - bw - 2))
            end
            ax, ps = 0, 0
        elseif tbX > 0 and align == "center" then
            px = math.floor((hostW + tbX) * 0.5 + 6)
            if clips and hostW > bw + 4 and px + bw > hostW - 2 then
                px = math.max(0, math.floor(hostW - bw - 2))
            end
            ax, ps = 0, 0
        elseif tbX > 0 and align == "right" then
            px = math.floor(hostW - tbX - 6)
            if clips and px < bw + 2 then px = math.min(hostW, bw + 2) end
            ax, ps = 1, 0
        elseif not clips then
            ax, ps, px = 0, 1, 4
        else
            ax, ps, px = 1, 1, -2
        end
        if entry.lastAx ~= ax or entry.lastPs ~= ps or entry.lastPx ~= px then
            entry.lastAx, entry.lastPs, entry.lastPx = ax, ps, px
            pcall(function()
                f.AnchorPoint = Vector2.new(ax, 0.5)
                f.Position = UDim2.new(ps, px, 0.5, 0)
            end)
        end
    end

    local function isBadgeAlive(entry)
        if not entry or not entry.gui or not entry.host or not entry.badgeName then return false end
        local ok1, p1 = pcall(function() return entry.gui.Parent end)
        if not ok1 or p1 == nil then return false end
        local ok2, p2 = pcall(function() return entry.host.Parent end)
        if not ok2 or p2 == nil then return false end
        local ok3, found = pcall(function() return entry.host:FindFirstChild(entry.badgeName) end)
        return ok3 and found ~= nil
    end

    function H.refreshTabBadgePositions()
        for id, entry in pairs(S.tabBadges) do
            if isBadgeAlive(entry) then
                if entry.kind == "text" then H.positionTextBadge(entry) end
            else
                H.removeTabEntry(id)
                S.nextScanAt = 0
            end
        end
    end

    function H.attachTabBadge(id, host, hostKind, role, asset, score)
        local badgeName = "ARBadge_" .. tostring(id)
        local sig = tostring(role) .. "|" .. tostring(asset) .. "|" .. tostring(hostKind)
        local existing = S.tabBadges[id]
        local okSame, sameChild = pcall(function() return host:FindFirstChild(badgeName) end)
        if existing and existing.sig == sig and okSame and sameChild ~= nil and isBadgeAlive(existing) then
            if score and score > (existing.score or 0) then existing.score = score end
            if hostKind == "text" then H.positionTextBadge(existing) end
            return true
        end
        if existing and isBadgeAlive(existing) and (existing.score or 0) > (score or 0) + 80 then
            if existing.kind == "text" then H.positionTextBadge(existing) end
            return true
        end
        if existing then H.removeTabEntry(id) end
        pcall(function() local old = host:FindFirstChild(badgeName); if old then old:Destroy() end end)

        local bw = asset ~= "" and 16 or (role == "free" and 24 or 28)
        local bh = asset ~= "" and 16 or 14

        local okMake, frame = pcall(function()
            local zBase = 20
            pcall(function() if finite(host.ZIndex) then zBase = math.max(20, host.ZIndex + 15) end end)
            local color = H.roleColor(role)
            local f = Instance.new("Frame")
            f.Name = badgeName
            f.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
            f.BackgroundTransparency = 0.08
            f.BorderSizePixel = 0
            f.ZIndex = zBase
            if hostKind == "avatar" then
                f.Size = asset ~= "" and UDim2.new(0, 16, 0, 16) or UDim2.new(0, 20, 0, 13)
                f.AnchorPoint = Vector2.new(1, 1)
                f.Position = UDim2.new(1, 0, 1, 0)
            else
                f.Size = UDim2.new(0, bw, 0, bh)
                f.AnchorPoint = Vector2.new(0, 0.5)
                f.Position = UDim2.new(0, 0, 0.5, 0)
            end
            pcall(function()
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 3)
                corner.Parent = f
                local stroke = Instance.new("UIStroke")
                stroke.Thickness = 1
                stroke.Color = color
                stroke.Parent = f
            end)
            if asset ~= "" then
                local img = Instance.new("ImageLabel")
                img.Name = "Icon"
                img.Size = UDim2.new(1, 0, 1, 0)
                img.BackgroundTransparency = 1
                img.Image = asset
                img.ZIndex = zBase + 2
                pcall(function() img.ScaleType = Enum.ScaleType.Fit end)
                img.Parent = f
            else
                local lbl = Instance.new("TextLabel")
                lbl.Name = "Tag"
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = S.ROLE_TAGS[role] or "AR"
                lbl.TextColor3 = role == "free" and Color3.fromRGB(220, 245, 210) or color
                lbl.ZIndex = zBase + 2
                pcall(function() lbl.TextSize = 10 end)
                pcall(function() lbl.TextScaled = true end)
                pcall(function() lbl.Font = Enum.Font.GothamBold end)
                lbl.Parent = f
            end
            f.Parent = host
            return f
        end)
        if okMake and frame then
            local padL = 0
            pcall(function()
                local pad = host:FindFirstChildOfClass("UIPadding")
                if pad and pad.PaddingLeft then padL = pad.PaddingLeft.Offset or 0 end
            end)
            local entry = {
                gui = frame, host = host, badgeName = badgeName, sig = sig,
                kind = hostKind, role = role, bw = bw, padL = padL,
                score = score or 0, conns = {},
            }
            if hostKind == "text" then
                H.positionTextBadge(entry)
                local function repos() H.positionTextBadge(entry) end
                pcall(function() entry.conns[#entry.conns + 1] = host:GetPropertyChangedSignal("TextBounds"):Connect(repos) end)
                pcall(function() entry.conns[#entry.conns + 1] = host:GetPropertyChangedSignal("Text"):Connect(repos) end)
                pcall(function() entry.conns[#entry.conns + 1] = host:GetPropertyChangedSignal("AbsoluteSize"):Connect(repos) end)
            end
            S.tabBadges[id] = entry
            H.recountTab()
            return true
        end
        return false
    end

    function H.buildMatchIndexes(wanted, meta)
        local byAvatarId, byName, dup = {}, {}, {}
        for id in pairs(wanted) do
            byAvatarId[tostring(id)] = id
            local m = meta[id]
            if m then
                for _, kn in ipairs({m.name, m.display}) do
                    if type(kn) == "string" and #kn > 0 then
                        local low = string.lower(trimStr(kn))
                        if not dup[low] then
                            if byName[low] and byName[low] ~= id then byName[low] = nil; dup[low] = true
                            else byName[low] = id end
                        end
                    end
                end
            end
        end
        return byAvatarId, byName
    end

    local function isWordByte(b)
        if not b then return false end
        return (b >= 48 and b <= 57) or (b >= 97 and b <= 122) or b == 95
    end

    function H.matchTextToPlayer(txt, byName)
        if type(txt) ~= "string" or #txt == 0 or #txt > 512 then return nil end
        local plainTight = txt:gsub("<[^>]+>", "")
        if #plainTight == 0 or #plainTight > 110 then return nil end
        local clean = string.lower(trimStr(plainTight)):gsub("^@", "")
        if clean == "" then return nil end
        local id = byName[clean]
        if id then return id end
        local plainSpaced = txt:gsub("<[^>]+>", " "):gsub("%s+", " ")
        local cleanSp = string.lower(trimStr(plainSpaced)):gsub("^@", "")
        local stripped = trimStr(cleanSp:gsub("^%[[^%]]+%]%s*", ""):gsub("%s*%[[^%]]+%]$", ""):gsub("%s*%(you%)$", ""))
        if stripped == "" then return nil end
        id = byName[stripped]
        if id then return id end
        if stripped:find("killed", 1, true) or stripped:find("joined", 1, true) or stripped:find("left the", 1, true) then
            return nil
        end
        local sLen = #stripped
        for nm, uid in pairs(byName) do
            local nLen = #nm
            if nLen >= 2 and sLen >= nLen and sLen <= nLen + 40 then
                local sPos, ePos = stripped:find(nm, 1, true)
                if sPos then
                    local beforeB = sPos > 1 and string.byte(stripped, sPos - 1) or nil
                    local afterB = ePos < sLen and string.byte(stripped, ePos + 1) or nil
                    if (not isWordByte(beforeB) and not isWordByte(afterB))
                        or (nLen >= 4 and ePos == sLen) then
                        return uid
                    end
                end
            end
        end
        return nil
    end

    function H.scanRootForHosts(root, playerGui, byAvatarId, byName, includeHidden)
        local scoredHosts = {}
        if H.shouldSkipNode(root) or (not includeHidden and not H.isBranchVisible(root)) then return scoredHosts end
        local queue, head, visited = {root}, 1, 0
        local function recordCandidate(id, node, kind, bonus)
            local w, h, px, py
            if includeHidden then
                local okS, sz = pcall(function() return node.AbsoluteSize end)
                w, h, px, py = (okS and sz and sz.X or 16), (okS and sz and sz.Y or 16), 0, 100
            else
                w, h, px, py = H.readNodeRect(node)
                if not w then return end
            end
            if kind == "avatar" and not includeHidden and py < 65 then return end
            local sb = H.findAncestorScoreboard(node, playerGui)
            local rowW = H.readRowWidth(node, playerGui)
            local score = (sb and 200 or 0) + (rowW >= 140 and 120 or 20) + bonus
            if kind == "avatar" and py >= 65 and h >= 14 then score = score + 30 end
            local cur = scoredHosts[id]
            if not cur or score > cur.score then
                scoredHosts[id] = {node = node, kind = kind, score = score, w = w, h = h, x = px, y = py}
            end
        end
        while head <= #queue and visited < S.MAX_SCAN_NODES do
            local node = queue[head]
            head, visited = head + 1, visited + 1
            if not H.shouldSkipNode(node) and (includeHidden or H.isBranchVisible(node)) then
                local okImg, isImg = pcall(function() return node:IsA("ImageLabel") or node:IsA("ImageButton") end)
                if okImg and isImg then
                    local okSrc, src = pcall(function() return node.Image end)
                    if okSrc and type(src) == "string" and #src > 0 then
                        local low = string.lower(src)
                        local uidStr = low:match("id=(%d+)") or low:match("userid=(%d+)") or low:match("users/(%d+)")
                        if uidStr and byAvatarId[uidStr] then recordCandidate(byAvatarId[uidStr], node, "avatar", 0) end
                    end
                else
                    local okTxt, isTxt = pcall(function() return node:IsA("TextLabel") or node:IsA("TextButton") end)
                    if okTxt and isTxt then
                        local okVal, txt = pcall(function() return node.Text end)
                        if okVal then
                            local id = H.matchTextToPlayer(txt, byName)
                            if id and H.isLikelyRowTextNode(node, playerGui) then recordCandidate(id, node, "text", 80) end
                        end
                    end
                end
                local okCh, children = pcall(function() return node:GetChildren() end)
                if okCh and type(children) == "table" then
                    for _, ch in ipairs(children) do
                        if not H.shouldSkipNode(ch) and (includeHidden or H.isBranchVisible(ch)) then
                            queue[#queue + 1] = ch
                        end
                    end
                end
            end
        end
        return scoredHosts
    end

    function H.startTabScan(gen)
        if S.scanRunning then return end
        local cfg = H.syncCfg()
        if not cfg.enabled then H.clearTabBadges(); return end
        local playerGui = H.getPlayerGui()
        if not playerGui then return end
        local myId, _, _, meta = H.collectPlayers()
        local wanted, wantCount = H.wantedMap(myId)
        for id in pairs(S.tabBadges) do if not wanted[id] then H.removeTabEntry(id) end end
        if wantCount == 0 then return end
        S.scanRunning = true
        local asset = H.effectiveAsset()
        local function work()
            local okW, errW = pcall(function()
                if gen ~= S.gen or not alive then return end
                local byAvatarId, byName = H.buildMatchIndexes(wanted, meta)
                local roots, secondary = {}, {}
                local okCh, topList = pcall(function() return playerGui:GetChildren() end)
                if okCh and type(topList) == "table" then
                    for _, gui in ipairs(topList) do
                        if not H.shouldSkipNode(gui) and H.isBranchVisible(gui) then
                            if H.containsHint(H.readNameSafe(gui), S.SCOREBOARD_HINTS) then roots[#roots + 1] = gui
                            else secondary[#secondary + 1] = gui end
                        end
                    end
                    for _, gui in ipairs(secondary) do roots[#roots + 1] = gui end
                end
                local bestById = {}
                for _, root in ipairs(roots) do
                    if gen ~= S.gen or not alive then break end
                    local scored = H.scanRootForHosts(root, playerGui, byAvatarId, byName, false)
                    for k, cand in pairs(scored) do
                        local prev = bestById[k]
                        if not prev or cand.score > prev.score then bestById[k] = cand end
                    end
                end
                if gen == S.gen and alive then
                    local attachedAny, sample = false, nil
                    for id, role in pairs(wanted) do
                        local cand = bestById[id]
                        if cand then
                            if H.attachTabBadge(id, cand.node, cand.kind, role, asset, cand.score) then
                                attachedAny = true
                                if not sample or cand.score > sample.score then sample = cand end
                            end
                        else
                            local cur = S.tabBadges[id]
                            if cur then
                                if isBadgeAlive(cur) then
                                    attachedAny = true
                                else
                                    H.removeTabEntry(id)
                                end
                            end
                        end
                    end
                    if attachedAny and sample then
                        local path = H.shortGuiPath(sample.node, playerGui)
                        local sig = tostring(S.tabCount) .. "|" .. path .. "|" .. tostring(sample.kind)
                        if sig ~= S.lastAttachSig then
                            S.lastAttachSig = sig
                            print(string.format("[AR Sync] attached Tab badges: count=%d sample=%s (%s %.0fx%.0f @ %.0f,%.0f)",
                                S.tabCount, path, tostring(sample.kind), sample.w, sample.h, sample.x, sample.y))
                        end
                    end
                    S.nextScanAt = nowSafe() + (attachedAny and S.SCAN_INTERVAL or S.EMPTY_SCAN_INTERVAL)
                end
            end)
            if not okW then warn("[AR Sync] scan error: " .. tostring(errW)) end
            S.scanRunning = false
        end
        if type(task) == "table" and type(task.spawn) == "function" then task.spawn(work) else work() end
    end

    function H.startHttpPoll(reqFn)
        if S.inFlight then return end
        if type(json) ~= "table" or type(json.stringify) ~= "function" or type(json.parse) ~= "function" then
            S.statusNote = "JSON API missing"; S.nextPollAt = nowSafe() + 30; return
        end
        local myId, peerIds = H.collectPlayers()
        if not myId then S.statusNote = "Waiting for LocalPlayer"; S.nextPollAt = nowSafe() + 3; return end
        local okEnc, body = pcall(json.stringify, {user_id = myId, stealth = false, peers = peerIds})
        if not okEnc or type(body) ~= "string" then S.nextPollAt = nowSafe() + 20; return end
        local headers = {["Content-Type"] = "application/json"}
        if DEFAULT_CLIENT_KEY ~= "" then headers["X-AR-Client"] = DEFAULT_CLIENT_KEY end
        S.inFlight, S.lastAttemptAt = true, nowSafe()
        local gen = S.gen
        local function doRequest()
            local okCall, resp = pcall(reqFn, {Url = DEFAULT_SYNC_URL, Method = "POST", Headers = headers, Body = body})
            if gen ~= S.gen or not alive then S.inFlight = false; return end
            S.inFlight = false
            local t = nowSafe()
            if not okCall or type(resp) ~= "table" then
                S.failCount = S.failCount + 1
                S.statusNote = "Network error"
                S.nextPollAt = t + math.min(60, 18 + S.failCount * 10)
                return
            end
            local code = tonumber(resp.StatusCode or resp.status_code or resp.Status or resp.status) or 0
            local rawBody = resp.Body or resp.body or ""
            if code == 429 then
                S.failCount = S.failCount + 1; S.statusNote = "Rate limited"; S.nextPollAt = t + 9.0; return
            elseif code < 200 or code >= 300 then
                S.failCount = S.failCount + 1
                S.statusNote = "HTTP " .. tostring(code)
                if S.lastHttpErrLog ~= tostring(code) then S.lastHttpErrLog = tostring(code); warn("[AR Sync] HTTP " .. tostring(code)) end
                S.nextPollAt = t + math.min(60, 20 + S.failCount * 10)
                return
            end
            local okDec, data = pcall(json.parse, rawBody)
            if not okDec or type(data) ~= "table" or not data.ok then
                S.failCount = S.failCount + 1; S.statusNote = "Bad JSON"; S.nextPollAt = t + 25; return
            end
            S.failCount, S.lastHttpErrLog, S.lastOkAt = 0, nil, t
            S.storageMode = type(data.storage) == "string" and data.storage or nil
            S.selfRole = type(data.self) == "string" and data.self or "free"
            S.statusNote = "Online"
            if not S.loggedOnline then
                S.loggedOnline = true
                print(string.format("[AR Sync] online role=%s storage=%s peers=%d", tostring(S.selfRole), tostring(S.storageMode), #peerIds))
            end
            local _, _, curById = H.collectPlayers()
            local nextMap, nextCount = {}, 0
            if type(data.badges) == "table" then
                for idKey, roleVal in pairs(data.badges) do
                    local idNum = tonumber(idKey)
                    if idNum and S.ROLE_ORDER[roleVal] then
                        nextMap[idNum] = roleVal
                        S.peerSeenAt[idNum] = t
                        nextCount = nextCount + 1
                    end
                end
            end
            for idPrev, rolePrev in pairs(S.peerBadges) do
                if not nextMap[idPrev] then
                    local seen = S.peerSeenAt[idPrev] or 0
                    if curById[idPrev] and (t - seen) <= S.PEER_GRACE_SEC then
                        nextMap[idPrev] = rolePrev
                        nextCount = nextCount + 1
                    else
                        S.peerSeenAt[idPrev] = nil
                    end
                end
            end
            S.peerBadges, S.badgeCount = nextMap, nextCount
            S.espPlayersAt = 0
            S.nextPollAt = t + S.POLL_INTERVAL + math.random(0, 3)
            S.nextScanAt = 0
        end
        if type(task) == "table" and type(task.spawn) == "function" then task.spawn(doRequest) else pcall(doRequest); S.inFlight = false end
    end

    local function validWorldPos(v)
        if not v then return false end
        local ok, x, y, z = pcall(function() return v.X, v.Y, v.Z end)
        if not ok or not finite(x) or not finite(y) or not finite(z) then return false end
        if y <= -200 then return false end
        return math.abs(x) >= 0.05 or math.abs(y) >= 0.05 or math.abs(z) >= 0.05
    end

    function H.worldToScreenSafe(pos)
        if type(render) == "table" and type(render.world_to_screen) == "function" then
            local ok, x, y, vis = pcall(render.world_to_screen, pos)
            if ok and vis == true and finite(x) and finite(y) then return x, y, true end
        end
        local okCam, vec, onScreen, sw, sh = pcall(function()
            local cam = workspace and workspace.CurrentCamera
            if not cam then return nil, false, 1920, 1080 end
            local v, on = cam:WorldToViewportPoint(pos)
            local vp = cam.ViewportSize
            return v, on, vp and vp.X or 1920, vp and vp.Y or 1080
        end)
        if okCam and vec and finite(vec.X) and finite(vec.Y) and finite(vec.Z) and vec.Z > 0.1 then
            if onScreen or (vec.X >= -40 and vec.X <= sw + 40 and vec.Y >= -40 and vec.Y <= sh + 40) then
                return vec.X, vec.Y, true
            end
        end
        return nil, nil, false
    end

    function H.resolvePeerHeadPos(player)
        if type(entity) == "table" and type(entity.get_player_hitbox_position) == "function" then
            local okP, v = pcall(entity.get_player_hitbox_position, player, "head")
            if okP and validWorldPos(v) then return v end
            local okC, vc = pcall(entity.get_player_hitbox_position, player, "chest")
            if okC and validWorldPos(vc) then return vc + Vector3.new(0, 1.2, 0) end
        end
        local charPos = nil
        pcall(function()
            local ch = player.Character
            if not ch then return end
            local hp = ch:FindFirstChild("Head")
            if hp and validWorldPos(hp.Position) then charPos = hp.Position; return end
            local hrp = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
            if hrp and validWorldPos(hrp.Position) then charPos = hrp.Position + Vector3.new(0, 2.2, 0) end
        end)
        if charPos then return charPos end
        if type(entity) == "table" and type(entity.get_player_position) == "function" then
            local okE, v = pcall(entity.get_player_position, player)
            if okE and validWorldPos(v) then return v + Vector3.new(0, 2.2, 0) end
        end
        return nil
    end

    function H.isPeerAliveForEsp(player)
        local isSpec = false
        pcall(function()
            local tm = player.Team
            if tm and type(tm.Name) == "string" and string.lower(tm.Name):find("spectat", 1, true) then isSpec = true end
        end)
        if isSpec then return false end
        local humAlive = nil
        pcall(function()
            local ch = player.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and finite(hum.Health) then humAlive = hum.Health > 0 end
        end)
        local entHp = nil
        if type(entity) == "table" and type(entity.get_player_health) == "function" then
            local okH, hp = pcall(entity.get_player_health, player)
            if okH and finite(hp) then entHp = hp end
        end
        if humAlive == true or (entHp and entHp > 0) then return true end
        if humAlive == false and (not entHp or entHp <= 0) then return false end
        if entHp ~= nil and entHp <= 0 then return false end
        if type(entity) == "table" and type(entity.is_alive) == "function" then
            local okA, resA = pcall(entity.is_alive, player)
            if okA and resA == false then return false end
        end
        return true
    end

    function H.updateEsp(nowT)
        local cfg = H.syncCfg()
        if not cfg.enabled or S.badgeCount == 0 then
            if next(S.espDrawings) ~= nil then H.clearEsp() end
            return
        end
        if nowT >= S.espPlayersAt then
            S.espPlayersAt = nowT + 0.75
            local myId, _, byId = H.collectPlayers()
            S.espMyId, S.espById = myId, byId
        end
        local myId, byId = S.espMyId, S.espById
        local active = S.espActiveScratch
        for k in pairs(active) do active[k] = nil end
        for id, role in pairs(S.peerBadges) do
            local player = byId[id]
            if id ~= myId and player and H.isPeerAliveForEsp(player) then
                local headPos = H.resolvePeerHeadPos(player)
                if headPos then
                    active[id] = true
                    local sx, sy, onScreen = H.worldToScreenSafe(headPos + Vector3.new(0, 1.4, 0))
                    local lbl = S.espDrawings[id]
                    if not lbl and type(Drawing) == "table" and type(Drawing.new) == "function" then
                        local okD, obj = pcall(Drawing.new, "Text")
                        if okD and obj then
                            pcall(function() obj.Size = 13; obj.Center = true; obj.Outline = true; obj.Transparency = 1; obj.ZIndex = 45 end)
                            S.espDrawings[id] = obj; lbl = obj
                        end
                    end
                    if lbl then
                        pcall(function()
                            if onScreen and sx and sy then
                                local tag = "[" .. (S.ROLE_TAGS[role] or "AR") .. "]"
                                if lbl.Text ~= tag then lbl.Text = tag end
                                lbl.Color = H.roleColor(role)
                                lbl.Transparency = 1
                                lbl.Position = Vector2.new(math.floor(sx + 0.5), math.floor(sy - 14 + 0.5))
                                lbl.Visible = true
                            else
                                lbl.Visible = false
                            end
                        end)
                    end
                end
            end
        end
        for id, obj in pairs(S.espDrawings) do
            if not S.peerBadges[id] then
                H.destroyDraw(obj)
                S.espDrawings[id] = nil
            elseif not active[id] then
                pcall(function() obj.Visible = false end)
            end
        end
    end

    local function isTabKeyDown()
        if type(input) == "table" and type(input.is_key_down) == "function" then
            local ok, d = pcall(input.is_key_down, "Tab")
            if ok and d == true then return true end
        end
        if syncUis then
            local ok2, d2 = pcall(function() return syncUis:IsKeyDown(Enum.KeyCode.Tab) end)
            if ok2 and d2 == true then return true end
        end
        return false
    end

    function Sync.statusText(ru)
        local cfg = H.syncCfg()
        if not cfg.enabled then return ru and "Sync: выключен" or "Sync: disabled" end
        if not H.resolveHttp() then return ru and "Sync: HTTP API недоступен" or "Sync: HTTP API unavailable" end
        if S.lastOkAt then
            local roleStr = string.upper(tostring(S.selfRole or "free"))
            if ru then return string.format("Sync: онлайн (%s) · пиры: %d · Tab: %d", roleStr, S.badgeCount, S.tabCount) end
            return string.format("Sync: online (%s) · peers: %d · Tab: %d", roleStr, S.badgeCount, S.tabCount)
        end
        return "Sync: " .. tostring(S.statusNote or "Idle")
    end

    function Sync.onSettingsApplied()
        local cfg = H.syncCfg()
        S.lastAttachSig = ""
        if not cfg.enabled then
            S.peerBadges, S.peerSeenAt, S.badgeCount = {}, {}, 0
            S.statusNote = "Disabled"
            H.clearTabBadges(); H.clearEsp()
        else
            S.nextPollAt, S.nextScanAt = 0, 0
        end
    end

    function Sync.diagnose()
        local playerGui = H.getPlayerGui()
        local myId, _, _, meta = H.collectPlayers()
        local wanted, wantCount = H.wantedMap(myId)
        print(string.format("[AR Sync DIAG] status=%s role=%s wanted=%d peers=%d tab=%d lastAttach=%s",
            tostring(S.statusNote), tostring(S.selfRole), wantCount, S.badgeCount, S.tabCount, tostring(S.lastAttachSig)))
        if not playerGui then print("[AR Sync DIAG] PlayerGui=nil"); return end
        local topNames = {}
        local byAvatarId, byName = H.buildMatchIndexes(wanted, meta)
        local okCh, topList = pcall(function() return playerGui:GetChildren() end)
        if okCh and type(topList) == "table" then
            for _, gui in ipairs(topList) do
                topNames[#topNames + 1] = H.readNameSafe(gui) .. (H.isBranchVisible(gui) and "(vis)" or "(hid)")
                if not H.shouldSkipNode(gui) then
                    local scored = H.scanRootForHosts(gui, playerGui, byAvatarId, byName, true)
                    for uid, cand in pairs(scored) do
                        print(string.format("[AR Sync DIAG] match id=%s kind=%s score=%d inSb=%s path=%s",
                            tostring(uid), tostring(cand.kind), cand.score, tostring(cand.inSb), H.shortGuiPath(cand.node, playerGui)))
                    end
                end
            end
        end
        print("[AR Sync DIAG] PlayerGui: " .. table.concat(topNames, ", "))
    end

    function Sync.tick(stopped)
        if stopped or not alive then return end
        local cfg = H.syncCfg()
        if not cfg.enabled then return end
        local t = nowSafe()
        local reqFn = H.resolveHttp()
        if reqFn and not S.inFlight and t >= S.nextPollAt and (t - (S.lastAttemptAt or 0)) >= S.MIN_POLL_GAP then
            H.startHttpPoll(reqFn)
        end
        local tabDown = isTabKeyDown() or S.tabPressedSignal
        S.tabPressedSignal = false
        local tabInterval = S.tabCount == 0 and 0.20 or 0.45
        if tabDown and not S.lastTabDown then
            S.nextScanAt = math.min(S.nextScanAt, t + 0.02)
            S.nextReposAt = 0
        elseif tabDown and S.nextScanAt > t + tabInterval then
            S.nextScanAt = t + tabInterval
        end
        S.lastTabDown = tabDown
        if not S.scanRunning and t >= S.nextScanAt then
            S.nextScanAt = t + (tabDown and tabInterval or S.SCAN_INTERVAL)
            H.startTabScan(S.gen)
        end
        if tabDown and S.tabCount > 0 and t >= S.nextReposAt then
            S.nextReposAt = t + 0.06
            H.refreshTabBadgePositions()
        end
        H.updateEsp(t)
    end

    function Sync.stop()
        S.gen = S.gen + 1
        S.inFlight, S.scanRunning = false, false
        S.peerSeenAt = {}
        if S.tabConn then pcall(function() S.tabConn:Disconnect() end); S.tabConn = nil end
        H.clearTabBadges(); H.clearEsp()
    end
end

-- ==================== CLANTAG (EXACT ANIMATIONS) ====================
do
    local function buildPrimordialFrames(text)
        local orig = text
        local list = {}
        local padded = string.rep(" ", #text * 2) .. text .. string.rep(" ", #text * 2)
        for i = 1, math.floor(#padded / 1.5) do
            local sub = padded:sub(i, (i + math.floor(#orig * 2) % #padded))
            list[#list + 1] = sub
        end
        return list
    end

    local function buildTypewriterFrames(text)
        text = trimStr(text):sub(1, 32)
        if text == "" then text = "AntiResolver" end
        local f = {}
        for i = 1, #text do f[#f + 1] = text:sub(1, i) end
        for _ = 1, 4 do f[#f + 1] = text end
        for i = #text - 1, 1, -1 do f[#f + 1] = text:sub(1, i) end
        f[#f + 1] = " "
        return f
    end

    local PRESET_FRAMES = {
        AntiResolver = {
            " | ", " /\\ ", " A ", " An ", " Ant ", " Anti ", " Anti|2 ",
            " AntiR ", " AntiRe ", " AntiRes ", " AntiRes0 ", " AntiReso ",
            " AntiResol ", " AntiResolv ", " AntiResolve ",
            " AntiResolver ", " AntiResolver ", " AntiResolver ", " AntiResolver ",
            " AntiResolve ", " AntiResolv ", " AntiResol ", " AntiReso ",
            " AntiRes0 ", " AntiRes ", " AntiRe ", " AntiR ", " Anti|2 ",
            " Anti ", " Ant ", " An ", " A ", " /\\ ", " | ",
        },
        Neverlose = {
            " | ", " |\\ ", " |\\| ", " N ", " N3 ", " Ne ", " Ne\\ ", " Ne\\/ ",
            " Nev ", " Nev3 ", " Neve ", " Neve| ", " Neve|2 ", " Never|_ ",
            " Neverl ", " Neverl0 ", " Neverlo ", " Neverlo5 ", " Neverlos ",
            " Neverlos3 ", " Neverlose ", " Neverlose. ", " Neverlose.< ",
            " Neverlose.c< ", " Neverlose.cc ", " Neverlose.cc ", " Neverlose.c< ",
            " Neverlose.< ", " Neverlose.  ", " Neverlose ", " Neverlos3 ",
            " Neverlos ", " Neverlo5 ", " Neverlo ", " Neverl0 ", " Neverl ",
            " Never|_ ", " Never|2 ", " Neve|2 ", " Neve| ", " Neve ", " Nev3 ",
            " Nev ", " Ne\\/ ", " Ne ", " N3 ", " N ", " |\\| ", " |\\ ",
            " |\\| ", " |\\ ", " | ",
        },
        Gamesense = {
            "                  ", "                 g", "                ga",
            "               gam", "              game", "             games",
            "            gamese", "           gamesen", "          gamesens",
            "         gamesense", "        gamesense ", "       gamesense  ",
            "      gamesense   ", "     gamesense    ", "    gamesense     ",
            "   gamesense      ", "  gamesense       ", " gamesense        ",
            "gamesense         ", "amesense          ", "mesense           ",
            "esense            ", "sense             ", "sens              ",
            "sen               ", "se                ", "s                 ",
        },
        Primordial = buildPrimordialFrames("primordial.dev"),
    }

    local lastSig = nil
    local wasOn = false

    function Clantag.stop()
        if wasOn and type(clantag) == "table" and type(clantag.reset) == "function" then
            pcall(clantag.reset)
        end
        lastSig, wasOn = nil, false
    end

    function Clantag.apply()
        local cfg = Settings.clantag
        if not cfg or not cfg.enabled then
            if wasOn then Clantag.stop() end
            return
        end
        if type(clantag) ~= "table" or type(clantag.set_frames) ~= "function" then return end
        local preset = cfg.preset or "AntiResolver"
        local custom = trimStr(cfg.customText or "AntiResolver"):sub(1, 32)
        if custom == "" then custom = "AntiResolver" end
        local speedSec = math.clamp((tonumber(cfg.speed) or 300) / 1000, 0.08, 2.0)
        local sig = preset .. "|" .. (preset == "Custom" and custom or "") .. "|" .. tostring(speedSec)
        if sig == lastSig then return end
        lastSig, wasOn = sig, true
        local frames = preset == "Custom" and buildTypewriterFrames(custom) or (PRESET_FRAMES[preset] or PRESET_FRAMES.AntiResolver)
        pcall(clantag.set_frames, frames, speedSec)
    end
end

-- ==================== STANDALONE SKEET UI ENGINE (AUTHENTIC SKEET.LUA SCREENGUI + INPUT.* ENGINE) ====================
local SkeetUI = {}
do
    local players = game:GetService("Players")
    local hs = game:GetService("HttpService")
    local uis = nil
    pcall(function() uis = game:GetService("UserInputService") end)

    local ACCENTS = {
        ["Skeet Green"] = Color3.fromRGB(154, 200, 47),
        ["Amethyst"] = Color3.fromRGB(168, 85, 247),
        ["Cyan"] = Color3.fromRGB(64, 214, 230),
        ["Red"] = Color3.fromRGB(235, 68, 68),
        ["White"] = Color3.fromRGB(230, 230, 235),
    }
    SkeetUI.ACCENTS = ACCENTS

    local BG_DARK       = Color3.fromRGB(12, 12, 12)
    local BG_PANEL      = Color3.fromRGB(23, 23, 23)
    local BG_CTRL       = Color3.fromRGB(30, 30, 30)
    local BG_CTRL_HOV   = Color3.fromRGB(38, 38, 38)
    local BG_CTRL_ACT   = Color3.fromRGB(50, 50, 50)
    local BG_POPUP      = Color3.fromRGB(26, 26, 26)
    local BORDER_LIGHT  = Color3.fromRGB(40, 40, 40)
    local TEXT_NORM     = Color3.fromRGB(198, 198, 198)
    local TEXT_BRIGHT   = Color3.fromRGB(238, 238, 238)
    local TAB_IDLE      = Color3.fromRGB(109, 109, 109)
    local TAB_HOV       = Color3.fromRGB(204, 204, 204)
    local TAB_ACT       = Color3.fromRGB(255, 255, 255)

    local CAPTURE_KEYS = {
        "RightShift", "LeftShift", "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
        "A", "S", "D", "F", "G", "H", "J", "K", "L",
        "Z", "X", "C", "V", "B", "N", "M",
        "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        "LeftControl", "RightControl", "LeftAlt", "RightAlt", "Tab", "CapsLock", "Backquote",
        "Minus", "Equals", "LeftBracket", "RightBracket", "Semicolon", "Quote", "Comma", "Period", "Slash",
        "Escape",
    }

    local function inRect(mx, my, x, y, w, h)
        return mx >= x and mx <= x + w and my >= y and my <= y + h
    end

    local function getScreen()
        if type(render) == "table" and type(render.screen_size) == "function" then
            local ok, w, h = pcall(render.screen_size)
            if ok and finite(w) and finite(h) and w > 0 and h > 0 then return w, h end
        end
        local okC, cam = pcall(function() return workspace.CurrentCamera end)
        if okC and cam and cam.ViewportSize then return cam.ViewportSize.X, cam.ViewportSize.Y end
        return 1280, 720
    end

    local function getPointerXY()
        if type(input) == "table" then
            if type(input.get_pointer_position) == "function" then
                local ok, mx, my = pcall(input.get_pointer_position)
                if ok and finite(mx) and finite(my) then return mx, my end
            end
            if type(input.get_mouse_position) == "function" then
                local ok, mx, my = pcall(input.get_mouse_position)
                if ok and finite(mx) and finite(my) then return mx, my end
            end
        end
        if uis then
            local okU, pos = pcall(function() return uis:GetMouseLocation() end)
            if okU and pos and finite(pos.X) and finite(pos.Y) then return pos.X, pos.Y end
        end
        return 0, 0
    end

    local function pollDown()
        if type(input) == "table" then
            if type(input.is_mouse_down) == "function" then
                local ok, v = pcall(input.is_mouse_down, 1)
                if ok and v == true then return true end
            end
            if type(input.is_pointer_down) == "function" then
                local ok, v = pcall(input.is_pointer_down, 1)
                if ok and v == true then return true end
            end
            if type(input.is_held) == "function" then
                local ok, v = pcall(input.is_held, 1)
                if ok and v == true then return true end
            end
        end
        if uis then
            local okU, v = pcall(function() return uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
            if okU and v == true then return true end
        end
        return false
    end

    local function isKeyDownSafe(k)
        if type(k) ~= "string" or #k == 0 then return false end
        if type(input) == "table" and type(input.is_key_down) == "function" then
            local ok, v = pcall(input.is_key_down, k)
            if ok then return v == true end
        end
        if uis then
            local kc = Enum.KeyCode[k]
            if kc then
                local ok2, v2 = pcall(function() return uis:IsKeyDown(kc) end)
                if ok2 then return v2 == true end
            end
        end
        return false
    end

    local function isTyping()
        if uis then
            local okF, focused = pcall(function() return uis:GetFocusedTextBox() end)
            if okF and focused ~= nil then return true end
        end
        if type(input) == "table" and type(input.is_typing) == "function" then
            local ok, v = pcall(input.is_typing)
            if ok and v == true then return true end
        end
        return false
    end

    local function releaseFocusedTextBox()
        if not uis then return end
        local okF, focused = pcall(function() return uis:GetFocusedTextBox() end)
        if okF and focused then pcall(function() focused:ReleaseFocus() end) end
    end

    local function setCursor(open)
        if type(input) == "table" then
            if type(input.set_cursor_unlocked) == "function" then
                pcall(input.set_cursor_unlocked, open == true)
            elseif open and type(input.unlock_cursor) == "function" then
                pcall(input.unlock_cursor)
            elseif (not open) and type(input.lock_cursor) == "function" then
                pcall(input.lock_cursor)
            end
        end
    end

    local function getGuiParent()
        local lp = players.LocalPlayer or localPlayer
        if lp then
            local ok, pg = pcall(function()
                return lp:FindFirstChildOfClass("PlayerGui") or lp:FindFirstChild("PlayerGui") or lp:WaitForChild("PlayerGui", 3)
            end)
            if ok and pg then return pg end
        end
        local okCg, cg = pcall(function() return game:GetService("CoreGui") end)
        return (okCg and cg) or nil
    end

    local guidSeq = 0
    local function nextName()
        guidSeq = guidSeq + 1
        local ok, g = pcall(function() return hs:GenerateGUID(false) end)
        if ok and type(g) == "string" and #g > 0 then return g end
        return "ar_ui_" .. tostring(guidSeq)
    end

    local function newObj(cls, props)
        local obj = Instance.new(cls)
        local par = props.Parent
        for k, v in pairs(props) do
            if k ~= "Parent" then pcall(function() obj[k] = v end) end
        end
        if not props.Name then pcall(function() obj.Name = nextName() end) end
        if par ~= nil then obj.Parent = par end
        return obj
    end

    function SkeetUI.create(opts)
        opts = opts or {}
        local winW, winH = 658, 558
        local sw, sh = getScreen()
        local winX = opts.posX or math.max(12, math.floor((sw - winW) * 0.5))
        local winY = opts.posY or math.max(12, math.floor((sh - winH) * 0.5))
        winX = math.clamp(winX, 4, math.max(4, sw - winW))
        winY = math.clamp(winY, 4, math.max(4, sh - winH))

        local uiAlive = true
        local accentColor = ACCENTS[opts.accent] or ACCENTS["Skeet Green"]
        local accentUpdaters = {}
        local connections = {}

        local activePopup = nil
        local activeSlider = nil
        local activeScrollDrag = nil
        local dragWin = nil
        local capturingKey = nil
        local ignoreToggleUntil = 0
        local nextCursorCheck = 0
        local nextHoverAt = 0
        local prevMx, prevMy = -999, -999
        local curDotX, curDotY = -999, -999
        local prevDown = false
        local prevToggleDown = false
        local lastClickAt = -10
        local uisWheelAccum = 0
        local hoveredTabIdx = nil
        local hoveredWidget = nil
        local hoveredPopIdx = nil

        local function track(conn)
            if conn ~= nil then connections[#connections + 1] = conn end
            return conn
        end

        local function closePopup()
            if activePopup then
                local pop = activePopup
                activePopup = nil
                hoveredPopIdx = nil
                if pop.closeFn then pcall(pop.closeFn)
                else pcall(function() pop.frame:Destroy() end) end
            end
        end

        local function clearHover()
            if hoveredWidget and hoveredWidget.setHover then pcall(hoveredWidget.setHover, false) end
            hoveredWidget = nil
            if hoveredTabIdx then
                hoveredTabIdx = nil
            end
        end

        -- Exact skeet.lua ScreenGui hierarchy
        local screenGui = newObj("ScreenGui", {
            Name = "AntiResolver_SkeetUI",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 50000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Parent = getGuiParent(),
        })

        local border = newObj("Frame", {
            Active = false,
            BackgroundColor3 = Color3.fromRGB(60, 60, 60),
            BorderColor3 = BG_DARK,
            Position = UDim2.new(0, winX, 0, winY),
            Size = UDim2.new(0, winW, 0, winH),
            ZIndex = 1,
            Parent = screenGui,
        })
        -- Invisible Modal button keeps Roblox first-person cursor unlocked while menu is open
        newObj("TextButton", {
            AutoButtonColor = false,
            Active = false,
            Modal = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            Text = "",
            ZIndex = 0,
            Parent = border,
        })

        local border2 = newObj("Frame", {
            BackgroundColor3 = BORDER_LIGHT,
            BorderColor3 = BORDER_LIGHT,
            Position = UDim2.new(0, 2, 0, 2),
            Size = UDim2.new(1, -4, 1, -4),
            Parent = border,
        })
        local bg = newObj("ImageLabel", {
            BackgroundColor3 = Color3.fromRGB(20, 20, 20),
            BorderColor3 = Color3.fromRGB(60, 60, 60),
            Position = UDim2.new(0, 3, 0, 3),
            Size = UDim2.new(1, -6, 1, -6),
            Image = "rbxassetid://15453092054",
            ScaleType = Enum.ScaleType.Tile,
            TileSize = UDim2.new(0, 4, 0, 548),
            Parent = border2,
        })

        -- Exact skeet.lua top rainbow image + 1px dark shadow
        local topRainbow = newObj("ImageLabel", {
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderColor3 = BG_DARK,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 0, 2),
            ZIndex = 4,
            Image = "rbxassetid://15453122383",
            Parent = bg,
        })
        newObj("Frame", {
            BackgroundColor3 = Color3.fromRGB(6, 6, 6),
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 1),
            ZIndex = 4,
            Parent = topRainbow,
        })

        local topGap = newObj("Frame", {
            BackgroundColor3 = BG_DARK,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 4),
            Size = UDim2.new(0, 73, 0, 14),
            Parent = bg,
        })
        local topSideFix = newObj("Frame", {
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BorderSizePixel = 0,
            Position = UDim2.new(0, 73, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            Parent = topGap,
        })
        newObj("Frame", {
            BackgroundColor3 = BORDER_LIGHT,
            BorderSizePixel = 0,
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            Parent = topSideFix,
        })

        local tabHolder = newObj("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 18),
            Size = UDim2.new(0, 73, 0, 256),
            Parent = bg,
        })

        local bottomGap = newObj("Frame", {
            BackgroundColor3 = BG_DARK,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 274),
            Size = UDim2.new(0, 73, 1, -274),
            Parent = bg,
        })
        local botSideFix = newObj("Frame", {
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BorderSizePixel = 0,
            Position = UDim2.new(0, 73, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            Parent = bottomGap,
        })
        newObj("Frame", {
            BackgroundColor3 = BORDER_LIGHT,
            BorderSizePixel = 0,
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            Parent = botSideFix,
        })

        -- Crisp circular cursor dot inside the same ScreenGui (always on top of menu & popups, 1:1 with hit-test coords)
        local curDot = newObj("Frame", {
            Active = false,
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
            Position = UDim2.new(0, -50, 0, -50),
            Size = UDim2.new(0, 7, 0, 7),
            ZIndex = 200,
            Parent = screenGui,
        })
        newObj("UICorner", {CornerRadius = UDim.new(1, 0), Parent = curDot})
        newObj("UIStroke", {Color = Color3.fromRGB(0, 0, 0), Thickness = 1.2, Parent = curDot})
        accentUpdaters[#accentUpdaters + 1] = function(c) curDot.BackgroundColor3 = c end

        local win = {
            tabs = {},
            activeTab = 1,
            isOpen = true,
            toggleKey = opts.toggleKey or "RightShift",
            onTabChanged = nil,
            onPositionSaved = opts.onPositionSaved,
        }

        if uis then
            track(uis.InputChanged:Connect(function(inp)
                if not uiAlive then return end
                if inp and inp.UserInputType == Enum.UserInputType.MouseWheel then
                    uisWheelAccum = uisWheelAccum + (inp.Position and inp.Position.Z or 0)
                end
            end))
            track(uis.InputBegan:Connect(function(inp)
                if not uiAlive or not capturingKey then return end
                if inp and inp.UserInputType == Enum.UserInputType.Keyboard then
                    local kName = tostring(inp.KeyCode):gsub("^Enum%.KeyCode%.", "")
                    local target = capturingKey
                    capturingKey = nil
                    ignoreToggleUntil = nowSafe() + 0.30
                    if kName == "Escape" then target.cancel()
                    elseif kName ~= "Unknown" and kName ~= "" then target.apply(kName)
                    else target.cancel() end
                end
            end))
        end

        function win:setAccent(name)
            local c = ACCENTS[name]
            if not c then return end
            accentColor = c
            for i = 1, #accentUpdaters do pcall(accentUpdaters[i], c) end
        end

        function win:setHint() end

        function win:setOpen(open)
            open = open == true
            win.isOpen = open
            screenGui.Enabled = open
            if not open then
                closePopup()
                activeSlider = nil
                activeScrollDrag = nil
                dragWin = nil
                clearHover()
                releaseFocusedTextBox()
                if capturingKey then capturingKey.cancel(); capturingKey = nil end
            end
            setCursor(open)
        end

        function win:toggle()
            win:setOpen(not win.isOpen)
        end

        local boundKeys = {}
        local function bindToggleKey(k)
            if type(input) == "table" and type(input.on_key_press) == "function" then
                if not boundKeys[k] then
                    boundKeys[k] = true
                    input.on_key_press(k, function()
                        local now = nowSafe()
                        if not uiAlive or capturingKey or isTyping() or now < ignoreToggleUntil then return end
                        if win.toggleKey == k then
                            ignoreToggleUntil = now + 0.25
                            win:toggle()
                        end
                    end)
                end
            end
        end

        function win:setToggleKey(k)
            if type(k) == "string" and #k > 0 then
                win.toggleKey = k
                bindToggleKey(k)
            end
        end

        function win:setActiveTab(idx)
            if idx < 1 or idx > #win.tabs then return end
            closePopup()
            activeSlider = nil
            activeScrollDrag = nil
            clearHover()
            releaseFocusedTextBox()
            win.activeTab = idx
            for i = 1, #win.tabs do
                local t = win.tabs[i]
                local act = (i == idx)
                t.icon.ImageColor3 = act and TAB_ACT or TAB_IDLE
                t.lbl.TextColor3 = act and TAB_ACT or TAB_IDLE
                t.topBar.Visible = act
                t.botBar.Visible = act
                t.sideBar.Visible = not act
                t.button.BackgroundTransparency = act and 1 or 0
                t.frame.Visible = act
            end
            if win.onTabChanged then pcall(win.onTabChanged, idx) end
        end

        local function attachWidgets(sec, contentScroll)
            local function relayout()
                local curY = 0
                for i = 1, #sec.widgets do
                    local w = sec.widgets[i]
                    if w.visible then
                        w._relY = curY
                        w.root.Position = UDim2.new(0, 0, 0, curY)
                        w.root.Size = UDim2.new(1, -6, 0, w._h)
                        curY = curY + w._h + 6
                    end
                end
                sec.totalH = curY
                sec.maxScroll = math.max(0, curY - sec.viewH)
                sec.scrollY = math.clamp(sec.scrollY, 0, sec.maxScroll)
                pcall(function()
                    contentScroll.CanvasSize = UDim2.new(0, 0, 0, curY + 8)
                    contentScroll.CanvasPosition = Vector2.new(0, sec.scrollY)
                end)
                sec.lastNativeY = sec.scrollY
            end
            sec.relayout = relayout

            function sec:newLabel(text, col)
                local str = tostring(text or "")
                local h0 = (#str > 34 or str:find("\n", 1, true)) and 30 or 16
                local lbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, h0),
                    Font = Enum.Font.SourceSans,
                    Text = str,
                    TextColor3 = col or TEXT_NORM,
                    TextSize = 13,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    Parent = contentScroll,
                })
                local w = {kind = "label", root = lbl, visible = true, _h = h0, _relY = 0}
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return lbl.Text end,
                    set = function(v)
                        local nv = tostring(v or "")
                        if nv == lbl.Text then return end
                        lbl.Text = nv
                        local nh = (#nv > 34 or nv:find("\n", 1, true)) and 30 or 16
                        if nh ~= w._h then w._h = nh; relayout() end
                    end,
                    setColor = function(c) lbl.TextColor3 = c end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; lbl.Visible = vis; relayout() end
                    end,
                }
            end

            function sec:newButton(name, callback)
                local outer = newObj("Frame", {
                    Active = false,
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, -6, 0, 22),
                    Parent = contentScroll,
                })
                local inner = newObj("Frame", {
                    BackgroundColor3 = BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = outer,
                })
                local fill = newObj("Frame", {
                    BackgroundColor3 = BG_CTRL,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = inner,
                })
                local lbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Button"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 13,
                    Parent = fill,
                })
                local w = {
                    kind = "button", root = outer, visible = true, _h = 22, _relY = 0,
                    setHover = function(hov)
                        fill.BackgroundColor3 = hov and BG_CTRL_HOV or BG_CTRL
                        lbl.TextColor3 = hov and TEXT_BRIGHT or TEXT_NORM
                    end,
                    onClick = function()
                        fill.BackgroundColor3 = BG_CTRL_ACT
                        if type(task) == "table" and type(task.delay) == "function" then
                            task.delay(0.09, function() if uiAlive then fill.BackgroundColor3 = BG_CTRL end end)
                        end
                        if callback then pcall(callback) end
                    end,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    setText = function(v) lbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; outer.Visible = vis; relayout() end
                    end,
                }
            end

            function sec:newToggle(name, default, callback)
                local state = default == true
                local row = newObj("Frame", {
                    Active = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, 16),
                    Parent = contentScroll,
                })
                local boxBorder = newObj("Frame", {
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 3),
                    Size = UDim2.new(0, 10, 0, 10),
                    Parent = row,
                })
                local boxFill = newObj("Frame", {
                    BackgroundColor3 = state and accentColor or BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = boxBorder,
                })
                local lbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 18, 0, 0),
                    Size = UDim2.new(1, -18, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Toggle"),
                    TextColor3 = state and TEXT_BRIGHT or TEXT_NORM,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                local isHov = false
                local function paint()
                    boxFill.BackgroundColor3 = state and accentColor or (isHov and Color3.fromRGB(54, 54, 54) or BORDER_LIGHT)
                    lbl.TextColor3 = state and TEXT_BRIGHT or TEXT_NORM
                end
                accentUpdaters[#accentUpdaters + 1] = function() paint() end
                local function setVal(v, silent)
                    state = v == true
                    paint()
                    if not silent and callback then pcall(callback, state) end
                end
                local w = {
                    kind = "toggle", root = row, visible = true, _h = 16, _relY = 0,
                    setHover = function(hov) isHov = hov == true; paint() end,
                    onClick = function() setVal(not state, false) end,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return state end,
                    set = function(v, silent) setVal(v, silent) end,
                    setText = function(v) lbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; row.Visible = vis; relayout() end
                    end,
                }
            end

            function sec:newSlider(name, minVal, maxVal, default, suffix, callback)
                minVal = tonumber(minVal) or 0
                maxVal = tonumber(maxVal) or 100
                if maxVal <= minVal then maxVal = minVal + 1 end
                suffix = tostring(suffix or "")
                local value = roundInt(math.clamp(tonumber(default) or minVal, minVal, maxVal))

                local holder = newObj("Frame", {
                    Active = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, 28),
                    Parent = contentScroll,
                })
                local titleLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0.70, 0, 0, 14),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Slider"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = holder,
                })
                local valLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.70, 0, 0, 0),
                    Size = UDim2.new(0.30, 0, 0, 14),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(value) .. suffix,
                    TextColor3 = Color3.fromRGB(220, 220, 220),
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = holder,
                })
                local trackOuter = newObj("Frame", {
                    Active = false,
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 17),
                    Size = UDim2.new(1, 0, 0, 8),
                    Parent = holder,
                })
                local trackIn = newObj("Frame", {
                    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = trackOuter,
                })
                local fillBar = newObj("Frame", {
                    BackgroundColor3 = accentColor,
                    BorderSizePixel = 0,
                    Size = UDim2.new((value - minVal) / (maxVal - minVal), 0, 1, 0),
                    Parent = trackIn,
                })
                accentUpdaters[#accentUpdaters + 1] = function(c) fillBar.BackgroundColor3 = c end

                local function setVal(newVal, silent)
                    local nextV = roundInt(math.clamp(tonumber(newVal) or minVal, minVal, maxVal))
                    local changed = nextV ~= value
                    value = nextV
                    fillBar.Size = UDim2.new((value - minVal) / (maxVal - minVal), 0, 1, 0)
                    valLbl.Text = tostring(value) .. suffix
                    if not silent and changed and callback then pcall(callback, value) end
                end
                local function applyX(mx, trackLeft, trackWidth)
                    if trackWidth <= 0 then return end
                    local a = math.clamp((mx - trackLeft) / trackWidth, 0, 1)
                    setVal(minVal + a * (maxVal - minVal), false)
                end

                local w = {
                    kind = "slider", root = holder, visible = true, _h = 28, _relY = 0,
                    applyX = applyX,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return value end,
                    set = function(v, silent) setVal(v, silent) end,
                    setText = function(v) titleLbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; holder.Visible = vis; relayout() end
                    end,
                }
            end

            function sec:newDropdown(name, options, default, callback)
                local list = (type(options) == "table" and #options > 0) and options or {"None"}
                local selIdx = 1
                if default ~= nil then
                    for i = 1, #list do if list[i] == default then selIdx = i; break end end
                end
                local holder = newObj("Frame", {
                    Active = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, 38),
                    Parent = contentScroll,
                })
                local titleLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Dropdown"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = holder,
                })
                local box = newObj("Frame", {
                    Active = false,
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 16),
                    Size = UDim2.new(1, 0, 0, 20),
                    Parent = holder,
                })
                local boxIn = newObj("Frame", {
                    BackgroundColor3 = BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = box,
                })
                local boxFill = newObj("Frame", {
                    BackgroundColor3 = BG_CTRL,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = boxIn,
                })
                local selLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 6, 0, 0),
                    Size = UDim2.new(1, -20, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(list[selIdx]),
                    TextColor3 = TEXT_NORM,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClipsDescendants = true,
                    Parent = boxFill,
                })
                local arrowLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -14, 0, 0),
                    Size = UDim2.new(0, 12, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = "v",
                    TextColor3 = Color3.fromRGB(150, 150, 150),
                    TextSize = 11,
                    Parent = boxFill,
                })

                local myPopFrame = nil
                local function myClose()
                    if myPopFrame then pcall(function() myPopFrame:Destroy() end); myPopFrame = nil end
                    if activePopup and activePopup.owner == box then activePopup = nil; hoveredPopIdx = nil end
                    arrowLbl.Text = "v"
                end
                local function pick(idx, silent)
                    selIdx = math.clamp(idx, 1, #list)
                    selLbl.Text = tostring(list[selIdx])
                    if not silent and callback then pcall(callback, list[selIdx]) end
                end
                local function openAt(bx, by, bw)
                    local wasMine = activePopup and activePopup.owner == box
                    closePopup()
                    if wasMine then return end
                    local _, curH = getScreen()
                    local rowH = 19
                    local popH = math.min(#list * rowH + 4, 194)
                    local py = by + 21
                    if py + popH > curH - 8 then py = math.max(8, by - popH - 1) end

                    local popBorder = newObj("Frame", {
                        Active = true,
                        BackgroundColor3 = BG_DARK,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, bx, 0, py),
                        Size = UDim2.new(0, bw, 0, popH),
                        ZIndex = 60,
                        Parent = screenGui,
                    })
                    myPopFrame = popBorder
                    local popIn = newObj("Frame", {
                        BackgroundColor3 = BORDER_LIGHT,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, 1, 0, 1),
                        Size = UDim2.new(1, -2, 1, -2),
                        ZIndex = 61,
                        Parent = popBorder,
                    })
                    local popBg = newObj("ScrollingFrame", {
                        Active = true,
                        ScrollingEnabled = true,
                        BackgroundColor3 = BG_POPUP,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, 1, 0, 1),
                        Size = UDim2.new(1, -2, 1, -2),
                        CanvasSize = UDim2.new(0, 0, 0, #list * rowH),
                        ScrollBarThickness = 3,
                        ScrollBarImageColor3 = accentColor,
                        ZIndex = 62,
                        Parent = popIn,
                    })
                    local rows = {}
                    for i = 1, #list do
                        local optRow = newObj("Frame", {
                            Active = false,
                            BackgroundColor3 = BG_POPUP,
                            BorderSizePixel = 0,
                            Position = UDim2.new(0, 0, 0, (i - 1) * rowH),
                            Size = UDim2.new(1, 0, 0, rowH),
                            ZIndex = 63,
                            Parent = popBg,
                        })
                        newObj("TextLabel", {
                            BackgroundTransparency = 1,
                            Position = UDim2.new(0, 6, 0, 0),
                            Size = UDim2.new(1, -12, 1, 0),
                            Font = Enum.Font.SourceSans,
                            Text = tostring(list[i]),
                            TextColor3 = (i == selIdx) and accentColor or TEXT_NORM,
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            ZIndex = 64,
                            Parent = optRow,
                        })
                        rows[i] = optRow
                    end
                    arrowLbl.Text = "^"
                    local maxSc = math.max(0, #list * rowH - (popH - 4))
                    activePopup = {
                        owner = box, frame = popBorder, scroll = popBg,
                        x = bx, y = py, w = bw, h = popH,
                        rowH = rowH, count = #list, rows = rows,
                        scrollY = 0, lastNativeY = 0, maxScroll = maxSc,
                        armed = false, openedAt = nowSafe(),
                        pickFn = function(idx) pick(idx, false); myClose() end,
                        closeFn = myClose,
                    }
                end

                local w = {
                    kind = "dropdown", root = holder, visible = true, _h = 38, _relY = 0,
                    setHover = function(hov) boxFill.BackgroundColor3 = hov and BG_CTRL_HOV or BG_CTRL end,
                    openAt = openAt,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return list[selIdx] end,
                    set = function(v, silent)
                        for i = 1, #list do if list[i] == v then pick(i, silent); return end end
                    end,
                    setOptions = function(newOpts, newVal)
                        myClose()
                        list = (type(newOpts) == "table" and #newOpts > 0) and newOpts or {"None"}
                        selIdx = 1
                        if newVal ~= nil then
                            for i = 1, #list do if list[i] == newVal then selIdx = i; break end end
                        end
                        selLbl.Text = tostring(list[selIdx])
                    end,
                    setText = function(v) titleLbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then
                            w.visible = vis; holder.Visible = vis
                            if not vis then myClose() end
                            relayout()
                        end
                    end,
                }
            end

            function sec:newTextbox(name, placeholder, default, callback, readOnly)
                local holder = newObj("Frame", {
                    Active = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, 38),
                    Parent = contentScroll,
                })
                local titleLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 14),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Input"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = holder,
                })
                local box = newObj("Frame", {
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 0, 0, 16),
                    Size = UDim2.new(1, 0, 0, 20),
                    Parent = holder,
                })
                local boxIn = newObj("Frame", {
                    BackgroundColor3 = BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = box,
                })
                local tb = newObj("TextBox", {
                    Active = true,
                    BackgroundColor3 = Color3.fromRGB(28, 28, 28),
                    BorderSizePixel = 0,
                    ClearTextOnFocus = false,
                    TextEditable = not readOnly,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Font = Enum.Font.SourceSans,
                    PlaceholderText = tostring(placeholder or ""),
                    PlaceholderColor3 = Color3.fromRGB(115, 115, 115),
                    Text = tostring(default or ""),
                    TextColor3 = TEXT_BRIGHT,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ClipsDescendants = true,
                    Parent = boxIn,
                })
                newObj("UIPadding", {PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = tb})
                local suppress = false
                track(tb.FocusLost:Connect(function()
                    if suppress or not uiAlive then return end
                    if callback then pcall(callback, tb.Text) end
                end))
                local w = {
                    kind = "textbox", root = holder, tb = tb, readOnly = readOnly == true,
                    visible = true, _h = 38, _relY = 0,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return tb.Text end,
                    set = function(v, silent)
                        suppress = true
                        tb.Text = tostring(v or "")
                        suppress = false
                        if not silent and callback then pcall(callback, tb.Text) end
                    end,
                    setText = function(v) titleLbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; holder.Visible = vis; relayout() end
                    end,
                }
            end

            function sec:newKeybind(name, defaultKey, callback)
                local keyVal = tostring(defaultKey or "RightShift")
                local row = newObj("Frame", {
                    Active = false,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -6, 0, 20),
                    Parent = contentScroll,
                })
                local titleLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0.62, 0, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = tostring(name or "Keybind"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = row,
                })
                local btn = newObj("Frame", {
                    Active = false,
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0.62, 0, 0, 0),
                    Size = UDim2.new(0.38, 0, 0, 20),
                    Parent = row,
                })
                local btnIn = newObj("Frame", {
                    BackgroundColor3 = BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = btn,
                })
                local btnFill = newObj("Frame", {
                    BackgroundColor3 = BG_CTRL,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = btnIn,
                })
                local kLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    Font = Enum.Font.SourceSans,
                    Text = "[" .. keyVal .. "]",
                    TextColor3 = accentColor,
                    TextSize = 12,
                    Parent = btnFill,
                })
                accentUpdaters[#accentUpdaters + 1] = function(c) kLbl.TextColor3 = c end
                local w = {
                    kind = "keybind", root = row, visible = true, _h = 20, _relY = 0,
                    setHover = function(hov) btnFill.BackgroundColor3 = hov and BG_CTRL_HOV or BG_CTRL end,
                    onClick = function()
                        closePopup()
                        if capturingKey then capturingKey.cancel() end
                        kLbl.Text = "[ ... ]"
                        capturingKey = {
                            waitRelease = true,
                            apply = function(kName)
                                keyVal = kName
                                kLbl.Text = "[" .. keyVal .. "]"
                                if callback then pcall(callback, keyVal) end
                            end,
                            cancel = function() kLbl.Text = "[" .. keyVal .. "]" end,
                        }
                    end,
                }
                sec.widgets[#sec.widgets + 1] = w
                relayout()
                return {
                    get = function() return keyVal end,
                    set = function(v, silent)
                        keyVal = tostring(v or "RightShift")
                        kLbl.Text = "[" .. keyVal .. "]"
                        if not silent and callback then pcall(callback, keyVal) end
                    end,
                    setText = function(v) titleLbl.Text = tostring(v or "") end,
                    setVisible = function(vis)
                        vis = vis == true
                        if vis ~= w.visible then w.visible = vis; row.Visible = vis; relayout() end
                    end,
                }
            end
        end

        function win:addTab(label, iconAsset)
            local idx = #win.tabs + 1
            local btn = newObj("Frame", {
                Active = false,
                BackgroundColor3 = BG_DARK,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, (idx - 1) * 64),
                Size = UDim2.new(0, 73, 0, 64),
                Parent = tabHolder,
            })
            local botBar = newObj("Frame", {
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 1, 0),
                Size = UDim2.new(1, 0, 0, 1),
                Visible = false,
                ZIndex = 3,
                Parent = btn,
            })
            newObj("Frame", {
                BackgroundColor3 = BORDER_LIGHT,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, -1),
                Size = UDim2.new(1, 2, 1, 0),
                ZIndex = 3,
                Parent = botBar,
            })
            local topBar = newObj("Frame", {
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, -1),
                Size = UDim2.new(1, 0, 0, 1),
                Visible = false,
                ZIndex = 3,
                Parent = btn,
            })
            newObj("Frame", {
                BackgroundColor3 = BORDER_LIGHT,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0, 1),
                Size = UDim2.new(1, 2, 1, 0),
                ZIndex = 3,
                Parent = topBar,
            })
            local sideBar = newObj("Frame", {
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BorderSizePixel = 0,
                Position = UDim2.new(0, 73, 0, 0),
                Size = UDim2.new(0, 1, 1, 0),
                Parent = btn,
            })
            newObj("Frame", {
                BackgroundColor3 = BORDER_LIGHT,
                BorderSizePixel = 0,
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0, 1, 1, 0),
                Parent = sideBar,
            })
            local icon = newObj("ImageLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0.5, -20, 0, 6),
                Size = UDim2.new(0, 40, 0, 40),
                Image = iconAsset or "",
                ImageColor3 = TAB_IDLE,
                ScaleType = Enum.ScaleType.Fit,
                Parent = btn,
            })
            local lbl = newObj("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 2, 0, 47),
                Size = UDim2.new(1, -4, 0, 14),
                Font = Enum.Font.SourceSans,
                Text = tostring(label or "Tab"),
                TextColor3 = TAB_IDLE,
                TextSize = 11,
                Parent = btn,
            })
            local frame = newObj("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 96, 0, 23),
                Size = UDim2.new(0, 532, 0, 506),
                Visible = false,
                Parent = bg,
            })

            local totalTabH = idx * 64
            tabHolder.Size = UDim2.new(0, 73, 0, totalTabH)
            bottomGap.Position = UDim2.new(0, 0, 0, 18 + totalTabH)
            bottomGap.Size = UDim2.new(0, 73, 1, -(18 + totalTabH))

            local tabObj = {
                idx = idx, button = btn, icon = icon, lbl = lbl,
                topBar = topBar, botBar = botBar, sideBar = sideBar,
                frame = frame, sections = {}, colY = {left = 0, right = 0},
            }
            tabObj.setLabel = function(text) lbl.Text = tostring(text or "") end

            function tabObj:newSection(secName, side, scale)
                local hScale = math.clamp(tonumber(scale) or 1.0, 0.2, 1.0)
                local isRight = string.lower(tostring(side or "left")) == "right"
                local yFrac = isRight and tabObj.colY.right or tabObj.colY.left
                if isRight then tabObj.colY.right = yFrac + hScale else tabObj.colY.left = yFrac + hScale end

                local secRelX = isRight and 275 or 0
                local secRelY = math.floor(yFrac * 506)
                local secW = 257
                local secH = math.floor(hScale * 506) - 9

                local secFrame = newObj("Frame", {
                    Active = false,
                    BackgroundColor3 = BG_DARK,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, secRelX, 0, secRelY),
                    Size = UDim2.new(0, secW, 0, secH),
                    Parent = frame,
                })
                local inside = newObj("Frame", {
                    BackgroundColor3 = BORDER_LIGHT,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = secFrame,
                })
                local inside2 = newObj("Frame", {
                    BackgroundColor3 = BG_PANEL,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0, 1, 0, 1),
                    Size = UDim2.new(1, -2, 1, -2),
                    Parent = inside,
                })
                local titleLbl = newObj("TextLabel", {
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 3),
                    Size = UDim2.new(1, -20, 0, 16),
                    Font = Enum.Font.SourceSansBold,
                    Text = tostring(secName or "Section"),
                    TextColor3 = TEXT_NORM,
                    TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = inside2,
                })
                local viewW = (secW - 4) - 14
                local viewH = (secH - 4) - 28
                local scroll = newObj("ScrollingFrame", {
                    Active = true,
                    ScrollingEnabled = true,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ClipsDescendants = true,
                    Position = UDim2.new(0, 10, 0, 22),
                    Size = UDim2.new(0, viewW, 0, viewH),
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ScrollBarThickness = 3,
                    ScrollBarImageColor3 = accentColor,
                    Parent = inside2,
                })
                accentUpdaters[#accentUpdaters + 1] = function(c) scroll.ScrollBarImageColor3 = c end
                local secObj = {
                    frame = secFrame, scroll = scroll,
                    relX = secRelX, relY = secRelY, w = secW, h = secH,
                    viewOffX = 12, viewOffY = 24, viewW = viewW, viewH = viewH,
                    scrollY = 0, lastNativeY = 0, totalH = 0, maxScroll = 0,
                    widgets = {},
                    setTitle = function(v) titleLbl.Text = tostring(v or "") end,
                }
                attachWidgets(secObj, scroll)
                tabObj.sections[#tabObj.sections + 1] = secObj
                return secObj
            end

            win.tabs[idx] = tabObj
            if idx == 1 then win:setActiveTab(1) end
            return tabObj
        end

        local function syncSectionScroll(sec)
            local okN, ny = pcall(function() return sec.scroll.CanvasPosition.Y end)
            if okN and finite(ny) and math.abs(ny - sec.lastNativeY) >= 1 then
                sec.scrollY = math.clamp(ny, 0, sec.maxScroll)
                sec.lastNativeY = sec.scrollY
                closePopup()
            end
        end

        local function setSectionScroll(sec, ny)
            local clamped = math.clamp(ny, 0, sec.maxScroll)
            if math.abs(clamped - sec.scrollY) < 0.5 then return end
            sec.scrollY = clamped
            sec.lastNativeY = clamped
            pcall(function() sec.scroll.CanvasPosition = Vector2.new(0, clamped) end)
            closePopup()
        end

        local function stepKeyCapture(now)
            if not capturingKey then return end
            local anyDown, picked = false, nil
            for i = 1, #CAPTURE_KEYS do
                local k = CAPTURE_KEYS[i]
                if isKeyDownSafe(k) then
                    anyDown = true
                    if not picked then picked = k end
                end
            end
            if capturingKey.waitRelease then
                if not anyDown then capturingKey.waitRelease = false end
            elseif picked then
                local target = capturingKey
                capturingKey = nil
                ignoreToggleUntil = now + 0.30
                if picked == "Escape" then target.cancel() else target.apply(picked) end
            end
        end

        local function updateHover(mx, my)
            -- Popup hover
            if activePopup then
                local pop = activePopup
                local newPop = nil
                if inRect(mx, my, pop.x + 2, pop.y + 2, pop.w - 4, pop.h - 4) then
                    local okN, ny = pcall(function() return pop.scroll.CanvasPosition.Y end)
                    if okN and finite(ny) then pop.scrollY = ny end
                    local idx = math.floor((my - (pop.y + 2) + pop.scrollY) / pop.rowH) + 1
                    if idx >= 1 and idx <= pop.count then newPop = idx end
                end
                if newPop ~= hoveredPopIdx then
                    if hoveredPopIdx and pop.rows[hoveredPopIdx] then pop.rows[hoveredPopIdx].BackgroundColor3 = BG_POPUP end
                    hoveredPopIdx = newPop
                    if newPop and pop.rows[newPop] then pop.rows[newPop].BackgroundColor3 = BG_CTRL_HOV end
                end
                return
            end

            -- Tabs hover
            local bgX, bgY = winX + 5, winY + 5
            local newTab = nil
            for i = 1, #win.tabs do
                if win.activeTab ~= i and inRect(mx, my, bgX, bgY + 18 + (i - 1) * 64, 73, 64) then
                    newTab = i; break
                end
            end
            if newTab ~= hoveredTabIdx then
                if hoveredTabIdx and win.tabs[hoveredTabIdx] and win.activeTab ~= hoveredTabIdx then
                    win.tabs[hoveredTabIdx].icon.ImageColor3 = TAB_IDLE
                    win.tabs[hoveredTabIdx].lbl.TextColor3 = TAB_IDLE
                end
                hoveredTabIdx = newTab
                if newTab and win.tabs[newTab] then
                    win.tabs[newTab].icon.ImageColor3 = TAB_HOV
                    win.tabs[newTab].lbl.TextColor3 = TAB_HOV
                end
            end

            -- Active tab widget hover
            local newW = nil
            local at = win.tabs[win.activeTab]
            if at then
                local tfX, tfY = bgX + 96, bgY + 23
                for s = 1, #at.sections do
                    local sec = at.sections[s]
                    local vx = tfX + sec.relX + sec.viewOffX
                    local vy = tfY + sec.relY + sec.viewOffY
                    if inRect(mx, my, vx, vy, sec.viewW - 6, sec.viewH) then
                        local localY = (my - vy) + sec.scrollY
                        for k = 1, #sec.widgets do
                            local w = sec.widgets[k]
                            if w.visible and w.setHover and localY >= w._relY and localY <= w._relY + w._h then
                                newW = w; break
                            end
                        end
                        break
                    end
                end
            end
            if newW ~= hoveredWidget then
                if hoveredWidget and hoveredWidget.setHover then hoveredWidget.setHover(false) end
                hoveredWidget = newW
                if newW and newW.setHover then newW.setHover(true) end
            end
        end

        function win:step()
            if not uiAlive then return end
            local now = nowSafe()

            if win.isOpen then stepKeyCapture(now) end

            local tkDown = isKeyDownSafe(win.toggleKey)
            if tkDown and not prevToggleDown then
                if not capturingKey and not isTyping() and now >= ignoreToggleUntil then
                    ignoreToggleUntil = now + 0.25
                    win:toggle()
                end
            end
            prevToggleDown = tkDown

            if not win.isOpen then
                prevDown = false
                uisWheelAccum = 0
                return
            end

            if now >= nextCursorCheck then
                nextCursorCheck = now + 0.25
                if type(input) == "table" and type(input.is_cursor_unlocked) == "function" and type(input.set_cursor_unlocked) == "function" then
                    local okC, unl = pcall(input.is_cursor_unlocked)
                    if okC and unl == false then pcall(input.set_cursor_unlocked, true) end
                end
            end

            local mx, my = getPointerXY()
            local cx, cy = math.floor(mx - 3.5 + 0.5), math.floor(my - 3.5 + 0.5)
            if cx ~= curDotX or cy ~= curDotY then
                curDotX, curDotY = cx, cy
                curDot.Position = UDim2.new(0, cx, 0, cy)
            end

            local downNow = pollDown()
            local apiJust = false
            if type(input) == "table" and type(input.is_just_pressed) == "function" then
                local okJ, vJ = pcall(input.is_just_pressed, 1)
                if okJ and vJ == true then apiJust = true end
            end
            local justPressed = (downNow and not prevDown) or (apiJust and not prevDown)
            prevDown = downNow

            local wheel = 0
            if type(input) == "table" and type(input.get_mouse_wheel_delta) == "function" then
                local okW, wd = pcall(input.get_mouse_wheel_delta)
                if okW and finite(wd) and wd ~= 0 then wheel = wd end
            end
            if wheel == 0 and uisWheelAccum ~= 0 then wheel = uisWheelAccum end
            uisWheelAccum = 0

            if not downNow then
                activeSlider = nil
                activeScrollDrag = nil
                if dragWin then
                    dragWin = nil
                    if win.onPositionSaved then pcall(win.onPositionSaved, winX, winY) end
                end
                if activePopup and not activePopup.armed and (now - activePopup.openedAt) >= 0.05 then
                    activePopup.armed = true
                end
            end

            -- Active drags
            if activeSlider and downNow then
                activeSlider.applyX(mx, activeSlider.x, activeSlider.w)
                return
            elseif activeScrollDrag and downNow then
                local sd = activeScrollDrag
                local f = math.clamp((my - sd.vy) / math.max(1, sd.vh), 0, 1)
                setSectionScroll(sd.sec, f * sd.sec.maxScroll)
                return
            elseif dragWin and downNow then
                local curW, curH = getScreen()
                local nx = math.clamp(dragWin.wx + (mx - dragWin.sx), 0, math.max(0, curW - winW))
                local ny = math.clamp(dragWin.wy + (my - dragWin.sy), 0, math.max(0, curH - winH))
                if nx ~= winX or ny ~= winY then
                    winX, winY = nx, ny
                    border.Position = UDim2.new(0, winX, 0, winY)
                end
                return
            end

            -- Sync native scroll & handle wheel / keyboard scroll
            local bgX, bgY = winX + 5, winY + 5
            local tfX, tfY = bgX + 96, bgY + 23
            local at = win.tabs[win.activeTab]
            if activePopup then
                if wheel ~= 0 and activePopup.maxScroll > 0 and inRect(mx, my, activePopup.x, activePopup.y, activePopup.w, activePopup.h) then
                    activePopup.scrollY = math.clamp(activePopup.scrollY - wheel * 30, 0, activePopup.maxScroll)
                    pcall(function() activePopup.scroll.CanvasPosition = Vector2.new(0, activePopup.scrollY) end)
                end
            elseif at then
                for s = 1, #at.sections do
                    local sec = at.sections[s]
                    syncSectionScroll(sec)
                    if sec.maxScroll > 0 then
                        local sx, sy = tfX + sec.relX, tfY + sec.relY
                        if inRect(mx, my, sx, sy, sec.w, sec.h) then
                            if wheel ~= 0 then setSectionScroll(sec, sec.scrollY - wheel * 36) end
                            if isKeyDownSafe("Down") then setSectionScroll(sec, sec.scrollY + 8) end
                            if isKeyDownSafe("Up") then setSectionScroll(sec, sec.scrollY - 8) end
                        end
                    end
                end
            end

            -- Throttled hover update when mouse moves
            if (mx ~= prevMx or my ~= prevMy) and now >= nextHoverAt then
                prevMx, prevMy = mx, my
                nextHoverAt = now + 0.04
                updateHover(mx, my)
            end

            -- Click handling (pure exact-math hit-testing in ScreenGui coords)
            if not justPressed or (now - lastClickAt) < 0.11 then return end

            -- 1. Active dropdown popup has top priority
            if activePopup then
                if activePopup.armed then
                    local pop = activePopup
                    if inRect(mx, my, pop.x + 2, pop.y + 2, pop.w - 4, pop.h - 4) then
                        local okN, ny = pcall(function() return pop.scroll.CanvasPosition.Y end)
                        if okN and finite(ny) then pop.scrollY = ny end
                        local idx = math.floor((my - (pop.y + 2) + pop.scrollY) / pop.rowH) + 1
                        if idx >= 1 and idx <= pop.count then
                            lastClickAt = now
                            pop.pickFn(idx)
                            return
                        end
                    end
                    closePopup()
                    lastClickAt = now
                end
                return
            end

            -- 2. Sidebar tabs (exact 73x64 slots at bgX, bgY + 18 + (i-1)*64)
            for i = 1, #win.tabs do
                if inRect(mx, my, bgX, bgY + 18 + (i - 1) * 64, 73, 64) then
                    lastClickAt = now
                    if win.activeTab ~= i then win:setActiveTab(i) end
                    return
                end
            end

            -- 3. Active tab sections & widgets
            local clickedInsideScroll = false
            if at then
                for s = 1, #at.sections do
                    local sec = at.sections[s]
                    local vx = tfX + sec.relX + sec.viewOffX
                    local vy = tfY + sec.relY + sec.viewOffY
                    if inRect(mx, my, vx, vy, sec.viewW, sec.viewH) then
                        clickedInsideScroll = true
                        -- Scrollbar drag zone (right 10px when scrollable)
                        if sec.maxScroll > 0 and mx >= vx + sec.viewW - 10 then
                            activeScrollDrag = {sec = sec, vy = vy, vh = sec.viewH}
                            local f = math.clamp((my - vy) / math.max(1, sec.viewH), 0, 1)
                            setSectionScroll(sec, f * sec.maxScroll)
                            lastClickAt = now
                            return
                        end
                        local localY = (my - vy) + sec.scrollY
                        local itemW = sec.viewW - 6
                        for k = 1, #sec.widgets do
                            local w = sec.widgets[k]
                            if w.visible and localY >= w._relY and localY <= w._relY + w._h then
                                if w.kind == "textbox" then
                                    if localY >= w._relY + 14 then
                                        lastClickAt = now
                                        if w.readOnly and type(setclipboard) == "function" and #w.tb.Text > 0 then
                                            pcall(setclipboard, w.tb.Text)
                                        end
                                        local okF, curF = pcall(function() return uis and uis:GetFocusedTextBox() end)
                                        if not (okF and curF == w.tb) then
                                            pcall(function() w.tb:CaptureFocus() end)
                                        end
                                        return
                                    end
                                elseif w.kind == "slider" then
                                    if localY >= w._relY + 12 then
                                        releaseFocusedTextBox()
                                        activeSlider = {applyX = w.applyX, x = vx + 1, w = itemW - 2}
                                        w.applyX(mx, vx + 1, itemW - 2)
                                        lastClickAt = now
                                        return
                                    end
                                elseif w.kind == "dropdown" then
                                    if localY >= w._relY + 14 then
                                        releaseFocusedTextBox()
                                        local boxScreenY = vy + (w._relY - sec.scrollY) + 16
                                        w.openAt(vx, boxScreenY, itemW)
                                        lastClickAt = now
                                        return
                                    end
                                elseif w.onClick then
                                    releaseFocusedTextBox()
                                    lastClickAt = now
                                    w.onClick()
                                    return
                                end
                            end
                        end
                        releaseFocusedTextBox()
                        return
                    end
                end
            end

            -- 4. Window dragging (anywhere on window frame/top/sidebar/section headers outside scroll areas)
            if not clickedInsideScroll and inRect(mx, my, winX, winY, winW, winH) then
                releaseFocusedTextBox()
                dragWin = {sx = mx, sy = my, wx = winX, wy = winY}
                lastClickAt = now
            end
        end

        function win:destroy()
            uiAlive = false
            closePopup()
            activeSlider = nil
            activeScrollDrag = nil
            dragWin = nil
            releaseFocusedTextBox()
            setCursor(false)
            for i = 1, #connections do pcall(function() connections[i]:Disconnect() end) end
            connections = {}
            pcall(function() screenGui:Destroy() end)
        end

        bindToggleKey(win.toggleKey)
        setCursor(true)
        return win
    end
end

-- ==================== APP WIRING & LOCALIZATION ====================
do
    local uiPrefKey = "antiresolver.ui.v2." .. tostring(localPlayer.UserId)
    local uiPrefs = {language = "en", accent = "Skeet Green", toggleKey = "RightShift", posX = nil, posY = nil}
    if type(database) == "table" and type(database.read) == "function" then
        local ok, p = pcall(database.read, uiPrefKey)
        if ok and type(p) == "table" then
            if p.language == "en" or p.language == "ru" then uiPrefs.language = p.language end
            if type(p.accent) == "string" and SkeetUI.ACCENTS[p.accent] then uiPrefs.accent = p.accent end
            if type(p.toggleKey) == "string" and #p.toggleKey > 0 then uiPrefs.toggleKey = p.toggleKey end
            if finite(p.posX) and finite(p.posY) then uiPrefs.posX, uiPrefs.posY = p.posX, p.posY end
        end
    end
    local function savePrefs()
        if type(database) == "table" and type(database.write) == "function" then
            pcall(database.write, uiPrefKey, uiPrefs)
            if type(database.flush) == "function" then pcall(database.flush) end
        end
    end

    local RU = {
        ["Resolver"] = "Резольвер",
        ["Anti-Aim"] = "Антиаимы",
        ["Misc"] = "Разное",
        ["Configs"] = "Конфиги",
        ["Core"] = "Основное",
        ["Smart & Status"] = "Умная логика и статус",
        ["Enable Resolver"] = "Включить резольвер",
        ["Mode"] = "Режим",
        ["DT series hold"] = "Удержание угла в DT",
        ["DT window"] = "Окно серии DT",
        ["Pitch mode"] = "Обработка pitch",
        ["Fakepitch counter"] = "Контр Fake Pitch",
        ["Safe points"] = "Безопасные точки (Roll)",
        ["Body aim after misses"] = "BAim после промахов",
        ["Cycle after misses"] = "Смена угла после промахов",
        ["Memory half-life"] = "Память обучения",
        ["Disable built-in BAim"] = "Выкл. встроенный BAim",
        ["Hold on defensive flick"] = "Фикс enemy defensive",
        ["No-AA legit detect"] = "Детект No-AA / легитов",
        ["Reset opponent data"] = "Сбросить обучение",
        ["Shot statistics"] = "Статистика выстрелов",
        ["Print diagnostics"] = "Диагностика в консоль",
        ["State & Presets"] = "Состояние и пресеты",
        ["Angles · Roll · FakePitch"] = "Углы · Roll · FakePitch",
        ["Enable AA Builder"] = "Включить AA Builder",
        ["Edit state"] = "Состояние",
        ["Use own state profile"] = "Свой профиль состояния",
        ["Edit section"] = "Секция",
        ["Respect Manual AA"] = "Уважать Manual AA",
        ["Show Fake ghost"] = "Показывать Show Fake",
        ["Slow speed threshold"] = "Порог медл. шага",
        ["State delay"] = "Задержка смены",
        ["Defensive key"] = "Клавиша дефенсива",
        ["Trigger defensive now"] = "Запустить дефенсив",
        ["Copy from state"] = "Копировать из",
        ["Copy profile"] = "Скопировать профиль",
        ["Preset: Meta Roll"] = "Пресет: Meta Roll",
        ["Preset: Fakepitch Jitter"] = "Пресет: Fakepitch Jitter",
        ["Preset: Defensive Tank"] = "Пресет: Defensive Tank",
        ["Pitch A"] = "Наклон A",
        ["Pitch B"] = "Наклон B",
        ["Pitch step"] = "Шаг pitch",
        ["Yaw base"] = "База yaw",
        ["Yaw offset"] = "Смещение yaw",
        ["Yaw modifier"] = "Режим yaw",
        ["Yaw amplitude"] = "Амплитуда yaw",
        ["Yaw step"] = "Шаг yaw",
        ["Spin speed"] = "Скорость спина",
        ["Sequence angles"] = "Углы (через запятую)",
        ["Apply sequence"] = "Применить углы",
        ["Roll / Extended mode"] = "Режим Roll / Extended",
        ["Roll amount"] = "Сила Roll",
        ["Roll step"] = "Шаг Roll",
        ["Fake Pitch mode"] = "Режим Fake Pitch",
        ["Fake Pitch A"] = "Fake Pitch A",
        ["Fake Pitch B"] = "Fake Pitch B",
        ["Fake Pitch offset"] = "Смещение Fake Pitch",
        ["Fake Pitch step"] = "Шаг Fake Pitch",
        ["Desync mode"] = "Режим desync",
        ["Left desync"] = "Desync слева",
        ["Right desync"] = "Desync справа",
        ["Real angle"] = "Реальный угол",
        ["Fake angle"] = "Фейковый угол",
        ["Inverter"] = "Инвертер",
        ["Desync step"] = "Шаг desync",
        ["Fake Lag"] = "Фейклаг",
        ["Choke limit"] = "Лимит тиков",
        ["Choke variability"] = "Разброс",
        ["Defensive enabled"] = "Дефенсив включён",
        ["Defensive trigger"] = "Активация",
        ["Duration"] = "Длительность",
        ["Cooldown"] = "Перезарядка",
        ["Def pitch mode"] = "Деф. режим pitch",
        ["Def pitch A"] = "Деф. pitch A",
        ["Def pitch B"] = "Деф. pitch B",
        ["Def yaw offset"] = "Деф. yaw",
        ["Def yaw amp"] = "Деф. амплитуда",
        ["Def step"] = "Деф. шаг",
        ["Def Roll"] = "Деф. Roll",
        ["Def Fake Pitch"] = "Деф. Fake Pitch",
        ["Tick shift (DT)"] = "Сдвиг тиков (DT)",
        ["Shift ticks"] = "Тиков сдвига",
        ["Flush choke at end"] = "Сброс в конце",
        ["Force Teleport"] = "Force Teleport",
        ["Sync & Clantag"] = "Синк и Клантег",
        ["Menu & Theme"] = "Меню и тема",
        ["Sync"] = "Синк",
        ["Enable Clantag"] = "Включить клантег",
        ["Clantag preset"] = "Клантег",
        ["Custom clantag"] = "Свой клантег",
        ["Animation speed"] = "Скорость анимации",
        ["Language"] = "Язык",
        ["Accent color"] = "Цвет акцента",
        ["Menu key"] = "Клавиша меню",
        ["Cloud Configs"] = "Облачные конфиги",
        ["Share & Import"] = "Обмен и импорт",
        ["Saved configs"] = "Сохранённые конфиги",
        ["Config name"] = "Название конфига",
        ["Save"] = "Сохранить",
        ["Load"] = "Загрузить",
        ["Toggle Autoload"] = "Автозагрузка (вкл/выкл)",
        ["Delete"] = "Удалить",
        ["Sync from Cloud"] = "Обновить из облака",
        ["Reveal / Hide code"] = "Показать / скрыть код",
        ["Share code"] = "Код для друга",
        ["Import code"] = "Код для импорта (RU автофикс)",
        ["Import config"] = "Импортировать",
    }

    local function isRu() return uiPrefs.language == "ru" end
    local function T(key) return (isRu() and RU[key]) or key end
    Resolver.outputLanguage = uiPrefs.language

    local locEntries = {}
    local function regLoc(obj, key, method)
        locEntries[#locEntries + 1] = {obj = obj, key = key, method = method or "setText"}
        return obj
    end
    local function refreshLocalization()
        Resolver.outputLanguage = uiPrefs.language
        for i = 1, #locEntries do
            local e = locEntries[i]
            if e.obj and e.obj[e.method] then pcall(e.obj[e.method], T(e.key)) end
        end
        if refreshCfgUI then pcall(refreshCfgUI) end
    end

    local win = SkeetUI.create({
        accent = uiPrefs.accent,
        toggleKey = uiPrefs.toggleKey,
        posX = uiPrefs.posX,
        posY = uiPrefs.posY,
        onPositionSaved = function(px, py)
            uiPrefs.posX, uiPrefs.posY = px, py
            savePrefs()
        end,
    })

    local function toast(msg)
        print("[AntiResolver] " .. tostring(msg))
        if type(notify) == "function" then pcall(notify, "AntiResolver 2.0", tostring(msg), 2.5, false) end
    end

    -- 4 Skeet Sidebar Tabs (verified Skeet icons from skeet.lua)
    local tabRes = win:addTab(T("Resolver"), "rbxassetid://15453302474")
    local tabAA  = win:addTab(T("Anti-Aim"), "rbxassetid://15453313321")
    local tabMsc = win:addTab(T("Misc"),     "rbxassetid://15453354931")
    local tabCfg = win:addTab(T("Configs"),  "rbxassetid://15453359751")
    regLoc(tabRes, "Resolver", "setLabel")
    regLoc(tabAA, "Anti-Aim", "setLabel")
    regLoc(tabMsc, "Misc", "setLabel")
    regLoc(tabCfg, "Configs", "setLabel")

    local W = {}
    local editState = "Global"
    local editSection = "Normal"
    local copySource = "Global"
    local selectedCfg = Store.getAutoload() or Store.getLast() or Store.list()[1]
    local shareCode = ""

    local syncAllWidgets, syncAAVisibility, refreshCfgUI

    -- ===== TAB 1: RESOLVER =====
    do
        local sL = tabRes:newSection(T("Core"), "Left", 1.0)
        local sR = tabRes:newSection(T("Smart & Status"), "Right", 1.0)
        regLoc(sL, "Core", "setTitle")
        regLoc(sR, "Smart & Status", "setTitle")

        W.rEnabled = regLoc(sL:newToggle(T("Enable Resolver"), Options.enabled, function(v) Resolver.setEnabled(v) end), "Enable Resolver")
        W.rMode = regLoc(sL:newDropdown(T("Mode"), MODES, Options.mode, function(v)
            Resolver.setMode(v)
            if W.rDtWin then W.rDtWin.setVisible(Options.dtHold and v ~= "Brute-force") end
        end), "Mode")
        W.rDtHold = regLoc(sL:newToggle(T("DT series hold"), Options.dtHold, function(v)
            Options.dtHold = v
            if W.rDtWin then W.rDtWin.setVisible(v and Options.mode ~= "Brute-force") end
        end), "DT series hold")
        W.rDtWin = regLoc(sL:newSlider(T("DT window"), 50, 250, Options.dtWindowMs, " ms", function(v) Options.dtWindowMs = v end), "DT window")
        W.rPitch = regLoc(sL:newDropdown(T("Pitch mode"), {"Auto", "Raw", "Off"}, Options.pitch, function(v) Options.pitch = v end), "Pitch mode")
        W.rFakePitch = regLoc(sL:newToggle(T("Fakepitch counter"), Options.fakePitch, function(v) Options.fakePitch = v end), "Fakepitch counter")
        W.rSafe = regLoc(sL:newToggle(T("Safe points"), Options.safe, function(v) Options.safe = v end), "Safe points")
        W.rBodyAfter = regLoc(sL:newSlider(T("Body aim after misses"), 0, 5, Options.bodyAfter, "", function(v) Options.bodyAfter = v end), "Body aim after misses")
        W.rCycleAfter = regLoc(sL:newSlider(T("Cycle after misses"), 1, 5, Options.cycleAfter, "", function(v) Options.cycleAfter = v end), "Cycle after misses")
        W.rMemory = regLoc(sL:newSlider(T("Memory half-life"), 3, 60, Options.memory, " s", function(v) Options.memory = v end), "Memory half-life")

        W.rNoBuiltinBaim = regLoc(sR:newToggle(T("Disable built-in BAim"), Options.disableBuiltinBaim, function(v) Options.disableBuiltinBaim = v end), "Disable built-in BAim")
        W.rDefHold = regLoc(sR:newToggle(T("Hold on defensive flick"), Options.defensiveHold, function(v) Options.defensiveHold = v end), "Hold on defensive flick")
        W.rNoAa = regLoc(sR:newToggle(T("No-AA legit detect"), Options.noAaDetect, function(v) Options.noAaDetect = v end), "No-AA legit detect")
        W.rStatusLbl = sR:newLabel(Resolver.status(isRu()))
        W.rTargetLbl = sR:newLabel(Resolver.targetStatus(isRu()))
        regLoc(sR:newButton(T("Reset opponent data"), function() Resolver.clear(); toast("Opponent data cleared") end), "Reset opponent data")
        regLoc(sR:newButton(T("Shot statistics"), function() toast(Resolver.shotStatistics()) end), "Shot statistics")
        regLoc(sR:newButton(T("Print diagnostics"), function()
            local msg = Resolver.diagnose()
            pcall(Sync.diagnose)
            toast(msg)
        end), "Print diagnostics")
    end

    -- ===== TAB 2: ANTI-AIM (AA BUILDER 2.0) =====
    local function curProf() return Settings.builder.profiles[editState] end
    local function curDef() return curProf().defensive end
    local function seqToStr(seq)
        local t = {}
        for i = 1, #seq do t[i] = tostring(seq[i]) end
        return table.concat(t, ", ")
    end

    do
        local sL = tabAA:newSection(T("State & Presets"), "Left", 1.0)
        local sR = tabAA:newSection(T("Angles · Roll · FakePitch"), "Right", 1.0)
        regLoc(sL, "State & Presets", "setTitle")
        regLoc(sR, "Angles · Roll · FakePitch", "setTitle")

        W.bEnabled = regLoc(sL:newToggle(T("Enable AA Builder"), Settings.builder.enabled, function(v) Builder.setEnabled(v) end), "Enable AA Builder")
        W.bState = regLoc(sL:newDropdown(T("Edit state"), STATES, editState, function(v) editState = v; syncAllWidgets() end), "Edit state")
        W.bOwn = regLoc(sL:newToggle(T("Use own state profile"), curProf().enabled, function(v) curProf().enabled = v; syncAAVisibility() end), "Use own state profile")
        W.bSec = regLoc(sL:newDropdown(T("Edit section"), {"Normal", "Defensive"}, editSection, function(v) editSection = v; syncAAVisibility() end), "Edit section")
        W.bRespectMan = regLoc(sL:newToggle(T("Respect Manual AA"), Settings.builder.respectManual, function(v) Settings.builder.respectManual = v end), "Respect Manual AA")
        W.bShowFake = regLoc(sL:newToggle(T("Show Fake ghost"), Settings.builder.showFake, function(v) Settings.builder.showFake = v end), "Show Fake ghost")
        W.bSlow = regLoc(sL:newSlider(T("Slow speed threshold"), 0, 30, Settings.builder.slow, "", function(v) Settings.builder.slow = v end), "Slow speed threshold")
        W.bHyst = regLoc(sL:newSlider(T("State delay"), 1, 12, Settings.builder.hysteresis, " t", function(v) Settings.builder.hysteresis = v end), "State delay")
        W.bDefKey = regLoc(sL:newKeybind(T("Defensive key"), Settings.builder.manualKey, function(k) Settings.builder.manualKey = k end), "Defensive key")
        regLoc(sL:newButton(T("Trigger defensive now"), function()
            if Builder.triggerManual() then toast("Defensive triggered") else toast("Enable AA Builder first") end
        end), "Trigger defensive now")
        W.bCopyFrom = regLoc(sL:newDropdown(T("Copy from state"), STATES, copySource, function(v) copySource = v end), "Copy from state")
        regLoc(sL:newButton(T("Copy profile"), function()
            Settings.builder.profiles[editState] = clone(Settings.builder.profiles[copySource])
            if editState == "Global" then curProf().enabled = true end
            Builder.release("copy")
            syncAllWidgets()
            toast("Copied " .. copySource .. " -> " .. editState)
        end), "Copy profile")
        regLoc(sL:newButton(T("Preset: Meta Roll"), function() toast(Builder.applyPreset("Meta Roll")); syncAllWidgets() end), "Preset: Meta Roll")
        regLoc(sL:newButton(T("Preset: Fakepitch Jitter"), function() toast(Builder.applyPreset("Fakepitch Jitter")); syncAllWidgets() end), "Preset: Fakepitch Jitter")
        regLoc(sL:newButton(T("Preset: Defensive Tank"), function() toast(Builder.applyPreset("Defensive Tank")); syncAllWidgets() end), "Preset: Defensive Tank")
        W.bStatusLbl = sL:newLabel(Builder.status(isRu()))

        -- Right: Normal controls
        W.pPitchMode = regLoc(sR:newDropdown(T("Pitch mode"), {"Fixed", "Jitter", "Random", "Sway", "Flick"}, curProf().pitchMode, function(v) curProf().pitchMode = v; syncAAVisibility() end), "Pitch mode")
        W.pPitchA = regLoc(sR:newSlider(T("Pitch A"), -89, 89, curProf().pitchA, "°", function(v) curProf().pitchA = v end), "Pitch A")
        W.pPitchB = regLoc(sR:newSlider(T("Pitch B"), -89, 89, curProf().pitchB, "°", function(v) curProf().pitchB = v end), "Pitch B")
        W.pPitchStep = regLoc(sR:newSlider(T("Pitch step"), 1, 64, curProf().pitchPeriod, " t", function(v) curProf().pitchPeriod = v end), "Pitch step")

        W.pYawBase = regLoc(sR:newDropdown(T("Yaw base"), {"camera", "world"}, curProf().yawBase, function(v) curProf().yawBase = v end), "Yaw base")
        W.pYawOff = regLoc(sR:newSlider(T("Yaw offset"), -180, 180, curProf().yawOffset, "°", function(v) curProf().yawOffset = v end), "Yaw offset")
        W.pYawMode = regLoc(sR:newDropdown(T("Yaw modifier"), {"Off", "Center", "3-Way", "5-Way", "Spin", "Random", "Sequence"}, curProf().yawMode, function(v) curProf().yawMode = v; syncAAVisibility() end), "Yaw modifier")
        W.pYawAmp = regLoc(sR:newSlider(T("Yaw amplitude"), 0, 180, curProf().amplitude, "°", function(v) curProf().amplitude = v end), "Yaw amplitude")
        W.pYawStep = regLoc(sR:newSlider(T("Yaw step"), 1, 64, curProf().yawPeriod, " t", function(v) curProf().yawPeriod = v end), "Yaw step")
        W.pSpin = regLoc(sR:newSlider(T("Spin speed"), -30, 30, curProf().spinSpeed, "°", function(v) curProf().spinSpeed = v end), "Spin speed")
        W.pSeqBox = regLoc(sR:newTextbox(T("Sequence angles"), "-30, 30, 0", seqToStr(curProf().sequence)), "Sequence angles")
        W.pSeqBtn = regLoc(sR:newButton(T("Apply sequence"), function()
            local list = {}
            for tok in string.gmatch(W.pSeqBox.get(), "[^,]+") do
                local n = tonumber(trimStr(tok))
                if n and finite(n) and #list < 12 then list[#list + 1] = math.clamp(n, -180, 180) end
            end
            if #list > 0 then curProf().sequence = list; W.pSeqBox.set(seqToStr(list), true); toast("Sequence updated")
            else toast("Invalid angles") end
        end), "Apply sequence")

        W.pRollMode = regLoc(sR:newDropdown(T("Roll / Extended mode"), ROLL_MODES, curProf().rollMode, function(v) curProf().rollMode = v; syncAAVisibility() end), "Roll / Extended mode")
        W.pRollAmt = regLoc(sR:newSlider(T("Roll amount"), -100, 100, curProf().rollAmount, "%", function(v) curProf().rollAmount = v end), "Roll amount")
        W.pRollStep = regLoc(sR:newSlider(T("Roll step"), 1, 64, curProf().rollPeriod, " t", function(v) curProf().rollPeriod = v end), "Roll step")

        W.pFpMode = regLoc(sR:newDropdown(T("Fake Pitch mode"), FAKEPITCH_MODES, curProf().fakePitchMode, function(v) curProf().fakePitchMode = v; syncAAVisibility() end), "Fake Pitch mode")
        W.pFpA = regLoc(sR:newSlider(T("Fake Pitch A"), -70, 70, curProf().fakePitchA, "°", function(v) curProf().fakePitchA = v end), "Fake Pitch A")
        W.pFpB = regLoc(sR:newSlider(T("Fake Pitch B"), -70, 70, curProf().fakePitchB, "°", function(v) curProf().fakePitchB = v end), "Fake Pitch B")
        W.pFpOff = regLoc(sR:newSlider(T("Fake Pitch offset"), -20, 20, curProf().fakePitchOffset, "°", function(v) curProf().fakePitchOffset = v end), "Fake Pitch offset")
        W.pFpStep = regLoc(sR:newSlider(T("Fake Pitch step"), 1, 64, curProf().fakePitchPeriod, " t", function(v) curProf().fakePitchPeriod = v end), "Fake Pitch step")

        W.pDesMode = regLoc(sR:newDropdown(T("Desync mode"), {"Limits", "Explicit"}, curProf().desyncMode, function(v) curProf().desyncMode = v; syncAAVisibility() end), "Desync mode")
        W.pLeft = regLoc(sR:newSlider(T("Left desync"), 0, 86, curProf().left, "°", function(v) curProf().left = v end), "Left desync")
        W.pRight = regLoc(sR:newSlider(T("Right desync"), 0, 86, curProf().right, "°", function(v) curProf().right = v end), "Right desync")
        W.pReal = regLoc(sR:newSlider(T("Real angle"), -86, 86, curProf().real, "°", function(v) curProf().real = v end), "Real angle")
        W.pFake = regLoc(sR:newSlider(T("Fake angle"), -86, 86, curProf().fake, "°", function(v) curProf().fake = v end), "Fake angle")
        W.pInv = regLoc(sR:newDropdown(T("Inverter"), {"Left", "Right", "Alternate"}, curProf().inverter, function(v) curProf().inverter = v; syncAAVisibility() end), "Inverter")
        W.pDesStep = regLoc(sR:newSlider(T("Desync step"), 1, 64, curProf().desyncPeriod, " t", function(v) curProf().desyncPeriod = v end), "Desync step")

        W.pLag = regLoc(sR:newToggle(T("Fake Lag"), curProf().fakeLag, function(v) curProf().fakeLag = v; syncAAVisibility() end), "Fake Lag")
        W.pLagLim = regLoc(sR:newSlider(T("Choke limit"), 0, 14, curProf().lagLimit, " t", function(v) curProf().lagLimit = v end), "Choke limit")
        W.pLagVar = regLoc(sR:newSlider(T("Choke variability"), 0, 100, curProf().lagVariation, "%", function(v) curProf().lagVariation = v end), "Choke variability")

        -- Right: Defensive controls
        W.dEn = regLoc(sR:newToggle(T("Defensive enabled"), curDef().enabled, function(v) curDef().enabled = v end), "Defensive enabled")
        W.dTrig = regLoc(sR:newDropdown(T("Defensive trigger"), {"Charged", "Manual", "On shot"}, curDef().trigger, function(v) curDef().trigger = v end), "Defensive trigger")
        W.dDur = regLoc(sR:newSlider(T("Duration"), 1, 16, curDef().duration, " t", function(v) curDef().duration = v end), "Duration")
        W.dCd = regLoc(sR:newSlider(T("Cooldown"), 0, 512, curDef().cooldown, " t", function(v) curDef().cooldown = v end), "Cooldown")
        W.dPM = regLoc(sR:newDropdown(T("Def pitch mode"), {"Fixed", "Jitter", "Random"}, curDef().pitchMode, function(v) curDef().pitchMode = v; syncAAVisibility() end), "Def pitch mode")
        W.dPA = regLoc(sR:newSlider(T("Def pitch A"), -89, 89, curDef().pitchA, "°", function(v) curDef().pitchA = v end), "Def pitch A")
        W.dPB = regLoc(sR:newSlider(T("Def pitch B"), -89, 89, curDef().pitchB, "°", function(v) curDef().pitchB = v end), "Def pitch B")
        W.dYO = regLoc(sR:newSlider(T("Def yaw offset"), -180, 180, curDef().yawOffset, "°", function(v) curDef().yawOffset = v end), "Def yaw offset")
        W.dYA = regLoc(sR:newSlider(T("Def yaw amp"), 0, 180, curDef().amplitude, "°", function(v) curDef().amplitude = v end), "Def yaw amp")
        W.dPer = regLoc(sR:newSlider(T("Def step"), 1, 16, curDef().period, " t", function(v) curDef().period = v end), "Def step")
        W.dRoll = regLoc(sR:newSlider(T("Def Roll"), -100, 100, curDef().rollAmount, "%", function(v) curDef().rollAmount = v end), "Def Roll")
        W.dFP = regLoc(sR:newToggle(T("Def Fake Pitch"), curDef().fakePitch, function(v) curDef().fakePitch = v end), "Def Fake Pitch")
        W.dShift = regLoc(sR:newToggle(T("Tick shift (DT)"), curDef().shift, function(v) curDef().shift = v; syncAAVisibility() end), "Tick shift (DT)")
        W.dShiftT = regLoc(sR:newSlider(T("Shift ticks"), 1, 14, curDef().shiftTicks, " t", function(v) curDef().shiftTicks = v end), "Shift ticks")
        W.dFlush = regLoc(sR:newToggle(T("Flush choke at end"), curDef().flush, function(v) curDef().flush = v end), "Flush choke at end")
        W.dTp = regLoc(sR:newToggle(T("Force Teleport"), curDef().teleport, function(v) curDef().teleport = v end), "Force Teleport")
    end

    -- ===== TAB 3: MISC (SYNC + CLANTAG + MENU) =====
    do
        local sL = tabMsc:newSection(T("Sync & Clantag"), "Left", 1.0)
        local sR = tabMsc:newSection(T("Menu & Theme"), "Right", 1.0)
        regLoc(sL, "Sync & Clantag", "setTitle")
        regLoc(sR, "Menu & Theme", "setTitle")

        W.mSync = regLoc(sL:newToggle(T("Sync"), Settings.sync.enabled ~= false, function(v)
            Settings.sync.enabled = v
            Sync.onSettingsApplied()
        end), "Sync")
        W.mSyncLbl = sL:newLabel(Sync.statusText(isRu()))

        W.mCtEn = regLoc(sL:newToggle(T("Enable Clantag"), Settings.clantag.enabled, function(v)
            Settings.clantag.enabled = v
            Clantag.apply()
        end), "Enable Clantag")
        W.mCtPreset = regLoc(sL:newDropdown(T("Clantag preset"), CLANTAG_PRESETS, Settings.clantag.preset, function(v)
            Settings.clantag.preset = v
            W.mCtCustom.setVisible(v == "Custom")
            Clantag.apply()
        end), "Clantag preset")
        W.mCtCustom = regLoc(sL:newTextbox(T("Custom clantag"), "AntiResolver", Settings.clantag.customText, function(v)
            local clean = trimStr(v):sub(1, 32)
            Settings.clantag.customText = clean ~= "" and clean or "AntiResolver"
            Clantag.apply()
        end), "Custom clantag")
        W.mCtSpeed = regLoc(sL:newSlider(T("Animation speed"), 100, 1000, Settings.clantag.speed, " ms", function(v)
            Settings.clantag.speed = v
            Clantag.apply()
        end), "Animation speed")

        W.mLang = regLoc(sR:newDropdown(T("Language"), {"English", "Русский"}, isRu() and "Русский" or "English", function(v)
            uiPrefs.language = (v == "Русский") and "ru" or "en"
            savePrefs()
            refreshLocalization()
        end), "Language")
        W.mAccent = regLoc(sR:newDropdown(T("Accent color"), {"Skeet Green", "Amethyst", "Cyan", "Red", "White"}, uiPrefs.accent, function(v)
            uiPrefs.accent = v
            win:setAccent(v)
            savePrefs()
        end), "Accent color")
        W.mMenuKey = regLoc(sR:newKeybind(T("Menu key"), uiPrefs.toggleKey, function(k)
            uiPrefs.toggleKey = k
            win:setToggleKey(k)
            savePrefs()
        end), "Menu key")
        sR:newLabel("AntiResolver " .. BUILD_LABEL .. " · t.me/penaresolv")
    end

    -- ===== TAB 4: CONFIGS (CLOUD DB + AUTOLOAD + ANTI-LEAK) =====
    do
        local sL = tabCfg:newSection(T("Cloud Configs"), "Left", 1.0)
        local sR = tabCfg:newSection(T("Share & Import"), "Right", 1.0)
        regLoc(sL, "Cloud Configs", "setTitle")
        regLoc(sR, "Share & Import", "setTitle")

        W.cStatusLbl = sL:newLabel(Store.cloudStatus)
        W.cAutoLbl = sL:newLabel("Autoload: none")
        W.cPicker = regLoc(sL:newDropdown(T("Saved configs"), {"(empty)"}, "(empty)", function(v)
            if v ~= "(empty)" then
                selectedCfg = v
                W.cNameBox.set(v, true)
                shareCode = ""
                W.cShareBox.set("", true)
                W.cShareBox.setVisible(false)
            end
        end), "Saved configs")
        W.cNameBox = regLoc(sL:newTextbox(T("Config name"), "Main", selectedCfg or "Main"), "Config name")

        regLoc(sL:newButton(T("Save"), function()
            local ok, msg, nm = pcall(Store.save, W.cNameBox.get(), Settings)
            if ok then
                selectedCfg, shareCode = nm, ""
                W.cShareBox.set("", true); W.cShareBox.setVisible(false)
                refreshCfgUI(); toast(msg)
            else toast(msg) end
        end), "Save")

        regLoc(sL:newButton(T("Load"), function()
            local ok, cfgOrErr = pcall(Store.use, selectedCfg)
            if ok then
                shareCode = ""
                W.cShareBox.set("", true); W.cShareBox.setVisible(false)
                applySettings(cfgOrErr)
                toast("Loaded " .. tostring(selectedCfg))
            else toast(cfgOrErr) end
        end), "Load")

        regLoc(sL:newButton(T("Toggle Autoload"), function()
            local ok, msg = pcall(Store.setAutoload, selectedCfg)
            refreshCfgUI(); toast(msg)
        end), "Toggle Autoload")

        regLoc(sL:newButton(T("Delete"), function()
            local ok, msg = pcall(Store.delete, selectedCfg)
            if ok then
                selectedCfg, shareCode = Store.list()[1], ""
                W.cShareBox.set("", true); W.cShareBox.setVisible(false)
                refreshCfgUI(); toast(msg)
            else toast(msg) end
        end), "Delete")

        regLoc(sL:newButton(T("Sync from Cloud"), function()
            Store.cloudLoad(false)
            toast("Refreshing cloud configs...")
        end), "Sync from Cloud")

        regLoc(sR:newButton(T("Reveal / Hide code"), function()
            if shareCode ~= "" then
                shareCode = ""
                W.cShareBox.set("", true); W.cShareBox.setVisible(false)
                toast("Share code hidden")
                return
            end
            local ok, code = pcall(function() return Store.encodeCode(Store.get(selectedCfg), selectedCfg) end)
            if ok and code then
                shareCode = code
                W.cShareBox.set(shareCode, true)
                W.cShareBox.setVisible(true)
                local copied = type(setclipboard) == "function" and pcall(setclipboard, shareCode)
                toast(copied and "Code copied to clipboard" or "Share code revealed")
            else toast("Select a saved config first") end
        end), "Reveal / Hide code")

        W.cShareBox = regLoc(sR:newTextbox(T("Share code"), "", "", nil, true), "Share code")
        W.cShareBox.setVisible(false)

        W.cImportBox = regLoc(sR:newTextbox(T("Import code"), "PR2:...", ""), "Import code")
        regLoc(sR:newButton(T("Import config"), function()
            local ok, val, encName = pcall(Store.decodeCode, W.cImportBox.get())
            if not ok then toast("Import failed: " .. tostring(val)); return end
            local base = trimStr(W.cNameBox.get())
            if base == "" or base == selectedCfg then base = encName or "Imported" end
            local okN, cleanBase = pcall(Store.validateName, base)
            base = okN and cleanBase or "Imported"
            local nm, suf = base, 1
            while library.sets[nm] do suf = suf + 1; nm = base:sub(1, 34) .. " (" .. tostring(suf) .. ")" end
            local okS, msg = pcall(Store.save, nm, val)
            if okS then
                selectedCfg, shareCode = nm, ""
                W.cShareBox.set("", true); W.cShareBox.setVisible(false)
                W.cImportBox.set("", true)
                applySettings(val)
                refreshCfgUI()
                toast("Imported: " .. nm)
            else toast(msg) end
        end), "Import config")
    end

    win.onTabChanged = function(idx)
        if idx ~= 4 and shareCode ~= "" then
            shareCode = ""
            W.cShareBox.set("", true)
            W.cShareBox.setVisible(false)
        end
    end

    syncAAVisibility = function()
        local p = curProf()
        local d = curDef()
        local own = editState == "Global" or p.enabled
        local isNorm = own and editSection == "Normal"
        local isDef = own and editSection == "Defensive"
        W.bOwn.setVisible(editState ~= "Global")

        W.pPitchMode.setVisible(isNorm)
        W.pPitchA.setVisible(isNorm)
        W.pPitchB.setVisible(isNorm and p.pitchMode ~= "Fixed")
        W.pPitchStep.setVisible(isNorm and p.pitchMode ~= "Fixed")

        W.pYawBase.setVisible(isNorm)
        W.pYawOff.setVisible(isNorm)
        W.pYawMode.setVisible(isNorm)
        W.pYawAmp.setVisible(isNorm and p.yawMode ~= "Off" and p.yawMode ~= "Spin" and p.yawMode ~= "Sequence")
        W.pYawStep.setVisible(isNorm and p.yawMode ~= "Off" and p.yawMode ~= "Spin")
        W.pSpin.setVisible(isNorm and p.yawMode == "Spin")
        W.pSeqBox.setVisible(isNorm and p.yawMode == "Sequence")
        W.pSeqBtn.setVisible(isNorm and p.yawMode == "Sequence")

        W.pRollMode.setVisible(isNorm)
        W.pRollAmt.setVisible(isNorm and p.rollMode ~= "Off")
        W.pRollStep.setVisible(isNorm and (p.rollMode == "Jitter" or p.rollMode == "Sway"))

        W.pFpMode.setVisible(isNorm)
        W.pFpA.setVisible(isNorm and (p.fakePitchMode == "Custom" or p.fakePitchMode == "Jitter"))
        W.pFpB.setVisible(isNorm and p.fakePitchMode == "Jitter")
        W.pFpOff.setVisible(isNorm and p.fakePitchMode ~= "Off")
        W.pFpStep.setVisible(isNorm and p.fakePitchMode == "Jitter")

        W.pDesMode.setVisible(isNorm)
        W.pLeft.setVisible(isNorm and p.desyncMode == "Limits")
        W.pRight.setVisible(isNorm and p.desyncMode == "Limits")
        W.pReal.setVisible(isNorm and p.desyncMode == "Explicit")
        W.pFake.setVisible(isNorm and p.desyncMode == "Explicit")
        W.pInv.setVisible(isNorm)
        W.pDesStep.setVisible(isNorm and p.inverter == "Alternate")

        W.pLag.setVisible(isNorm)
        W.pLagLim.setVisible(isNorm and p.fakeLag)
        W.pLagVar.setVisible(isNorm and p.fakeLag)

        W.dEn.setVisible(isDef)
        W.dTrig.setVisible(isDef)
        W.dDur.setVisible(isDef)
        W.dCd.setVisible(isDef)
        W.dPM.setVisible(isDef)
        W.dPA.setVisible(isDef)
        W.dPB.setVisible(isDef and d.pitchMode ~= "Fixed")
        W.dYO.setVisible(isDef)
        W.dYA.setVisible(isDef)
        W.dPer.setVisible(isDef)
        W.dRoll.setVisible(isDef)
        W.dFP.setVisible(isDef)
        W.dShift.setVisible(isDef)
        W.dShiftT.setVisible(isDef and d.shift)
        W.dFlush.setVisible(isDef)
        W.dTp.setVisible(isDef)
    end

    refreshCfgUI = function()
        local names = Store.list()
        local opts = #names > 0 and names or {"(empty)"}
        if not selectedCfg or not library.sets[selectedCfg] then selectedCfg = names[1] end
        W.cPicker.setOptions(opts, selectedCfg or "(empty)")
        W.cStatusLbl.set(Store.cloudStatus)
        local autoNm = Store.getAutoload()
        W.cAutoLbl.set((isRu() and "Автозагрузка: " or "Autoload: ") .. tostring(autoNm or (isRu() and "выкл" or "none")))
    end

    syncAllWidgets = function()
        W.rEnabled.set(Options.enabled, true)
        W.rMode.set(Options.mode, true)
        W.rDtHold.set(Options.dtHold, true)
        W.rDtWin.set(Options.dtWindowMs, true)
        W.rDtWin.setVisible(Options.dtHold and Options.mode ~= "Brute-force")
        W.rPitch.set(Options.pitch, true)
        W.rFakePitch.set(Options.fakePitch, true)
        W.rSafe.set(Options.safe, true)
        W.rBodyAfter.set(Options.bodyAfter, true)
        W.rCycleAfter.set(Options.cycleAfter, true)
        W.rMemory.set(Options.memory, true)
        W.rNoBuiltinBaim.set(Options.disableBuiltinBaim, true)
        W.rDefHold.set(Options.defensiveHold, true)
        W.rNoAa.set(Options.noAaDetect, true)

        local b, p, d = Settings.builder, curProf(), curDef()
        W.bEnabled.set(b.enabled, true)
        W.bOwn.set(p.enabled, true)
        W.bRespectMan.set(b.respectManual, true)
        W.bShowFake.set(b.showFake, true)
        W.bSlow.set(b.slow, true)
        W.bHyst.set(b.hysteresis, true)
        W.bDefKey.set(b.manualKey, true)

        W.pPitchMode.set(p.pitchMode, true); W.pPitchA.set(p.pitchA, true); W.pPitchB.set(p.pitchB, true); W.pPitchStep.set(p.pitchPeriod, true)
        W.pYawBase.set(p.yawBase, true); W.pYawOff.set(p.yawOffset, true); W.pYawMode.set(p.yawMode, true)
        W.pYawAmp.set(p.amplitude, true); W.pYawStep.set(p.yawPeriod, true); W.pSpin.set(p.spinSpeed, true)
        W.pSeqBox.set(seqToStr(p.sequence), true)
        W.pRollMode.set(p.rollMode, true); W.pRollAmt.set(p.rollAmount, true); W.pRollStep.set(p.rollPeriod, true)
        W.pFpMode.set(p.fakePitchMode, true); W.pFpA.set(p.fakePitchA, true); W.pFpB.set(p.fakePitchB, true)
        W.pFpOff.set(p.fakePitchOffset, true); W.pFpStep.set(p.fakePitchPeriod, true)
        W.pDesMode.set(p.desyncMode, true); W.pLeft.set(p.left, true); W.pRight.set(p.right, true)
        W.pReal.set(p.real, true); W.pFake.set(p.fake, true); W.pInv.set(p.inverter, true); W.pDesStep.set(p.desyncPeriod, true)
        W.pLag.set(p.fakeLag, true); W.pLagLim.set(p.lagLimit, true); W.pLagVar.set(p.lagVariation, true)

        W.dEn.set(d.enabled, true); W.dTrig.set(d.trigger, true); W.dDur.set(d.duration, true); W.dCd.set(d.cooldown, true)
        W.dPM.set(d.pitchMode, true); W.dPA.set(d.pitchA, true); W.dPB.set(d.pitchB, true)
        W.dYO.set(d.yawOffset, true); W.dYA.set(d.amplitude, true); W.dPer.set(d.period, true)
        W.dRoll.set(d.rollAmount, true); W.dFP.set(d.fakePitch, true)
        W.dShift.set(d.shift, true); W.dShiftT.set(d.shiftTicks, true); W.dFlush.set(d.flush, true); W.dTp.set(d.teleport, true)

        W.mSync.set(Settings.sync.enabled ~= false, true)
        W.mCtEn.set(Settings.clantag.enabled, true)
        W.mCtPreset.set(Settings.clantag.preset, true)
        W.mCtCustom.set(Settings.clantag.customText, true)
        W.mCtCustom.setVisible(Settings.clantag.preset == "Custom")
        W.mCtSpeed.set(Settings.clantag.speed, true)

        syncAAVisibility()
        refreshCfgUI()
    end

    applySettings = function(nextSettings)
        nextSettings = validate(nextSettings)
        Resolver.clear()
        Builder.release("config applied")
        Settings = nextSettings
        Options = Settings.resolver
        Resolver.fault, Builder.fault = nil, nil
        Sync.onSettingsApplied()
        Clantag.apply()
        syncAllWidgets()
    end

    onCloudLibraryUpdated = function(autoApplied)
        refreshCfgUI()
        if autoApplied then syncAllWidgets() end
    end

    -- Optional 1-button quick toggle inside native SynUI (helpful on mobile / 60% keyboards without Insert)
    pcall(function()
        if type(menu) == "table" and type(menu.new_tab) == "function" then
            local fallbackTab = menu.new_tab("AntiResolver", "rbxassetid://10734975692")
            local fSec = fallbackTab:new_section("AntiResolver " .. BUILD_LABEL, "Left")
            fSec:new_label("Standalone Skeet UI (" .. uiPrefs.toggleKey .. ")")
            fSec:new_button("Open / Close Skeet Menu", function() win:toggle() end)
        end
    end)

    syncAllWidgets()
    Clantag.apply()
    Store.cloudLoad(true)

    local function normalizeEvent(kind, e, hitbox, extra)
        if type(e) ~= "table" then
            local out = {target = e, hitbox = hitbox}
            if kind == "hit" then out.damage = extra else out.reason = extra end
            return out
        end
        return e
    end

    local lifeConn = nil
    pcall(function() lifeConn = localPlayer.CharacterAdded:Connect(function() Builder.release("respawn") end) end)

    events.on_tick(function()
        if alive then
            Resolver.tick()
            Builder.tick()
        end
    end)

    client.set_event_callback("aim_fire", function(e)
        if not alive then return end
        if e then Builder.onShot() end
        pcall(Resolver.onFire, e)
    end)
    client.set_event_callback("aim_hit", function(e, hb, dmg)
        if not alive then return end
        pcall(Resolver.onFeedback, normalizeEvent("hit", e, hb, dmg), true)
    end)
    client.set_event_callback("aim_miss", function(e, hb, reason)
        if not alive then return end
        pcall(Resolver.onFeedback, normalizeEvent("miss", e, hb, reason), false)
    end)

    local nextUiTick = 0
    client.set_event_callback("paint", function()
        if not alive then return end
        pcall(win.step, win)
        Sync.tick(false)
        local t = nowSafe()
        if t < nextUiTick then return end
        nextUiTick = t + 0.25
        if win.isOpen then
            local ru = isRu()
            W.rStatusLbl.set(Resolver.status(ru))
            W.rTargetLbl.set(Resolver.targetStatus(ru))
            W.bStatusLbl.set(Builder.status(ru))
            W.mSyncLbl.set(Sync.statusText(ru))
            W.cStatusLbl.set(Store.cloudStatus)
        end
    end)

    client.set_event_callback("shutdown", function()
        if not alive then return end
        alive = false
        if lifeConn then pcall(function() lifeConn:Disconnect() end) end
        Builder.release("shutdown")
        Resolver.stop()
        Sync.stop()
        Clantag.stop()
        win:destroy()
    end)
end

print("[AR BUILD] " .. BUILD .. " · AntiResolver " .. BUILD_LABEL .. " · Skeet UI · modules=resolver+aa2+clantag+sync+cloudcfg · schema=2")
