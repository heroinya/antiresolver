-- AntiResolver Beta 1.3 | t.me/penaresolv
local BUILD = "1.3-beta"
local localPlayer = game:GetService("Players").LocalPlayer
assert(localPlayer and type(localPlayer.UserId) == "number" and localPlayer.UserId > 0 and localPlayer.UserId % 1 == 0, "AntiResolver needs a signed-in local player")
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local STATES = {"Global", "Standing", "Moving", "Slow", "Crouching", "Crouch moving", "Air", "Air crouch"}
local MODES = {"Auto", "Auto DT", "Adaptive", "Brute-force", "Debug"}
local function resolverMode(value)
    if value == "Animation" or value == "Jitter" or value == "Native" then return "Auto" end
    return value
end
local function profileDefault()
    return {
        enabled = false, pitchMode = "Fixed", pitchA = -89, pitchB = 89,
        yawBase = "camera", yawOffset = 180, yawMode = "Center", amplitude = 30,
        period = 4, pitchPeriod = 4, yawPeriod = 4, desyncPeriod = 4,
        spinSpeed = 6, sequence = {-30, 30, 0}, desyncMode = "Limits", real = -58, fake = 58,
        left = 58, right = 58, inverter = "Alternate", fakeLag = false, lagLimit = 4, lagVariation = 0,
        defensive = {enabled = false, trigger = "Charged", duration = 4, cooldown = 16,
            pitchMode = "Jitter", pitchA = -89, pitchB = 89, yawOffset = 180,
            amplitude = 70, period = 1, shift = false, shiftTicks = 4, flush = false},
    }
end
local function defaults()
    local profiles = {}
    for _, name in ipairs(STATES) do profiles[name] = profileDefault() end
    profiles.Global.enabled = true
    return {
        resolver = {enabled = true, mode = "Auto", pitch = "Auto", bodyAfter = 3, cycleAfter = 1,
            safe = false, memory = 12, dtWindowMs = 150, debug = false},
        builder = {enabled = false, slow = 6, hysteresis = 3, manualKey = "V", profiles = profiles},
        sync = {enabled = true, endpoint = "", logoAsset = "", tabBadges = true, espBadges = true, stealth = false},
    }
end
local Sync = {}
local function member(value, choices)
    for _, allowed in ipairs(choices) do if value == allowed then return true end end
    return false
end
local function number(value, default, low, high, integer)
    if value == nil then return default end
    assert(finite(value) and value >= low and value <= high and (not integer or value % 1 == 0), "Invalid numeric setting")
    return value
end
local function boolean(value, default)
    if value == nil then return default end
    assert(type(value) == "boolean", "Expected true/false")
    return value
end
local function choice(value, default, choices)
    if value == nil then return default end
    assert(member(value, choices), "Unknown mode: " .. tostring(value))
    return value
end
local function object(value)
    if value == nil then return {} end
    assert(type(value) == "table", "Expected settings object")
    return value
end
local function validate(inputSettings)
    local source = object(inputSettings)
    local result = defaults()
    local r, b = object(source.resolver), object(source.builder)
    local s = object(source.sync)
    result.sync = {
        enabled = boolean(s.enabled, true),
        endpoint = type(s.endpoint) == "string" and (s.endpoint:match("^%s*(.-)%s*$") or ""):sub(1, 200) or "",
        logoAsset = type(s.logoAsset) == "string" and (s.logoAsset:match("^%s*(.-)%s*$") or ""):sub(1, 120) or "",
        tabBadges = boolean(s.tabBadges, true),
        espBadges = boolean(s.espBadges, true),
        stealth = boolean(s.stealth, false),
    }
    result.resolver = {
        enabled = boolean(r.enabled, true), mode = choice(resolverMode(r.mode), "Auto", MODES),
        pitch = choice(r.pitch, "Auto", {"Auto", "Raw", "Off"}),
        bodyAfter = number(r.bodyAfter, 3, 0, 5, true), cycleAfter = number(r.cycleAfter, 1, 1, 5, true),
        safe = boolean(r.safe, false), memory = number(r.memory, 12, 3, 60, true),
        dtWindowMs = number(r.dtWindowMs, 150, 50, 250, true), debug = resolverMode(r.mode) == "Debug",
    }
    result.builder.enabled = boolean(b.enabled, false)
    result.builder.slow = number(b.slow, 6, 0, 30)
    result.builder.hysteresis = number(b.hysteresis, 3, 1, 12, true)
    if b.manualKey ~= nil then
        assert(type(b.manualKey) == "string" and #b.manualKey > 0 and #b.manualKey <= 24
            and b.manualKey:match("^[A-Za-z0-9]+$"), "Invalid defensive key")
        result.builder.manualKey = b.manualKey
    end
    local profiles = object(b.profiles)
    for _, name in ipairs(STATES) do
        local src, dst = object(profiles[name]), result.builder.profiles[name]
        dst.enabled = name == "Global" or boolean(src.enabled, false)
        dst.pitchMode = choice(src.pitchMode, "Fixed", {"Fixed", "Jitter", "Random", "Sway", "Flick"})
        dst.pitchA = number(src.pitchA, -89, -89, 89)
        dst.pitchB = number(src.pitchB, 89, -89, 89)
        dst.yawBase = choice(src.yawBase, "camera", {"camera", "world"})
        dst.yawOffset = number(src.yawOffset, 180, -180, 180)
        dst.yawMode = choice(src.yawMode, "Center", {"Off", "Center", "3-Way", "5-Way", "Spin", "Random", "Sequence"})
        dst.amplitude = number(src.amplitude, 30, 0, 180)
        dst.period = number(src.period, 4, 1, 64, true)
        dst.pitchPeriod = number(src.pitchPeriod, dst.period, 1, 64, true)
        dst.yawPeriod = number(src.yawPeriod, dst.period, 1, 64, true)
        dst.desyncPeriod = number(src.desyncPeriod, dst.period, 1, 64, true)
        dst.desyncMode = choice(src.desyncMode, "Limits", {"Limits", "Explicit"})
        dst.real, dst.fake = number(src.real, -58, -86, 86), number(src.fake, 58, -86, 86)
        dst.spinSpeed = number(src.spinSpeed, 6, -30, 30)
        if src.sequence ~= nil then
            assert(type(src.sequence) == "table" and #src.sequence >= 1 and #src.sequence <= 12, "Sequence needs 1–12 angles")
            dst.sequence = {}
            for i, angle in ipairs(src.sequence) do dst.sequence[i] = number(angle, 0, -180, 180) end
        end
        dst.left, dst.right = number(src.left, 58, 0, 86), number(src.right, 58, 0, 86)
        dst.inverter = choice(src.inverter, "Alternate", {"Left", "Right", "Alternate"})
        dst.fakeLag = boolean(src.fakeLag, false)
        dst.lagLimit = number(src.lagLimit, 4, 0, 14, true)
        dst.lagVariation = number(src.lagVariation, 0, 0, 100)
        local d, out = object(src.defensive), dst.defensive
        out.enabled = boolean(d.enabled, false)
        out.trigger = choice(d.trigger, "Charged", {"Charged", "Manual", "On shot"})
        out.duration = number(d.duration, 4, 1, 16, true)
        out.cooldown = number(d.cooldown, 16, 0, 512, true)
        out.pitchMode = choice(d.pitchMode, "Jitter", {"Fixed", "Jitter", "Random"})
        out.pitchA, out.pitchB = number(d.pitchA, -89, -89, 89), number(d.pitchB, 89, -89, 89)
        out.yawOffset, out.amplitude = number(d.yawOffset, 180, -180, 180), number(d.amplitude, 70, 0, 180)
        out.period = number(d.period, 1, 1, 16, true)
        out.shift = boolean(d.shift, false)
        out.shiftTicks = number(d.shiftTicks, 4, 1, 14, true)
        out.flush = boolean(d.flush, false)
    end
    return result
end


local Store = {key = "antiresolver.private.v2." .. tostring(localPlayer.UserId), owner = tostring(localPlayer.UserId)}
local library = {owner = Store.owner, version = 2, sets = {}, last = nil}
local startupNote
local function validateName(name)
    assert(type(name) == "string", "Set needs a name")
    name = name:match("^%s*(.-)%s*$")
    local length = utf8.len(name)
    assert(length and length >= 1 and length <= 40 and not name:find("[%z\1-\31\127]"), "Name: 1–40 characters, no control characters")
    return name
end
function Store.load()
    assert(type(database) == "table" and type(database.read) == "function" and type(database.write) == "function", "Personal database unavailable")
    local raw = database.read(Store.key)
    if raw == nil then return end
    assert(type(raw) == "table" and raw.owner == Store.owner and raw.version == 2, "Personal store owner/version mismatch")
    local loaded = {owner = Store.owner, version = 2, sets = {}}
    local count = 0
    for name, settings in pairs(object(raw.sets)) do
        name = validateName(name)
        count = count + 1
        assert(count <= 32, "Personal store has too many sets")
        assert(loaded.sets[name] == nil, "Duplicate normalized set name")
        loaded.sets[name] = validate(settings)
    end
    if type(raw.last) == "string" and loaded.sets[raw.last] then loaded.last = raw.last end
    library = loaded
end
function Store.commit(nextLibrary)
    assert(not Store.problem, Store.problem)
    assert(nextLibrary.owner == Store.owner, "Cannot write another account's sets")
    database.write(Store.key, clone(nextLibrary))
    library = clone(nextLibrary)
    if type(database.flush) == "function" then
        local ok, err = pcall(database.flush)
        if not ok then return "Saved in session memory; flush failed: " .. tostring(err) end
    end
    return "Saved to your session store"
end
function Store.list()
    local result = {}
    for name in pairs(library.sets) do result[#result + 1] = name end
    table.sort(result)
    return result
end
function Store.save(name, settings)
    name = validateName(name)
    local nextLibrary = clone(library)
    assert(nextLibrary.sets[name] or #Store.list() < 32, "Maximum 32 personal sets")
    nextLibrary.sets[name] = validate(settings)
    nextLibrary.last = name
    return Store.commit(nextLibrary), name
end
function Store.get(name)
    assert(library.sets[name], "Select one of your saved sets")
    return validate(library.sets[name])
end
function Store.use(name)
    local settings = Store.get(name)
    local nextLibrary = clone(library)
    nextLibrary.last = name
    Store.commit(nextLibrary)
    return settings
end
function Store.rename(oldName, newName)
    assert(library.sets[oldName], "Select a saved set")
    newName = validateName(newName)
    if oldName == newName then return "Name unchanged", newName end
    assert(not library.sets[newName], "That name already exists")
    local nextLibrary = clone(library)
    nextLibrary.sets[newName], nextLibrary.sets[oldName] = nextLibrary.sets[oldName], nil
    if nextLibrary.last == oldName then nextLibrary.last = newName end
    return Store.commit(nextLibrary), newName
end
function Store.delete(name)
    assert(library.sets[name], "Select a saved set")
    local nextLibrary = clone(library)
    nextLibrary.sets[name] = nil
    if nextLibrary.last == name then nextLibrary.last = nil end
    return Store.commit(nextLibrary)
end
function Store.encodeSet(settings)
    return json.stringify({kind = "antiresolver", version = 2, settings = validate(settings)})
end
function Store.decodeSet(text)
    assert(type(text) == "string" and #text <= 131072, "JSON is too large")
    local data = json.parse(text)
    assert(type(data) == "table" and data.kind == "antiresolver" and data.version == 2 and type(data.settings) == "table", "Not an AntiResolver v2 set")
    return validate(data.settings), data.name ~= nil and validateName(data.name) or nil
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function difference(value, base)
    if type(value) ~= "table" then if value ~= base then return value end; return nil end
    if value[1] ~= nil then
        if type(base) ~= "table" or #value ~= #base then return clone(value) end
        for i,v in ipairs(value) do if v ~= base[i] then return clone(value) end end
        return nil
    end
    local out = {}
    for key,v in pairs(value) do
        local original
        if type(base)=="table" then original=base[key] end
        local changed = difference(v, original)
        if changed ~= nil then out[key]=changed end
    end
    if next(out) then return out end
    return nil
end
function Store.encodeCode(settings, name)
    local text=json.stringify({kind="antiresolver",version=2,name=name ~= nil and validateName(name) or nil,
        settings=difference(validate(settings),defaults()) or {}})
    local out={}
    for i=1,#text,3 do
        local a,b,c=text:byte(i,i+2);b=b or 0;c=c or 0
        local n=a*65536+b*256+c
        out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
        out[#out+1]=alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
        out[#out+1]=i+1<=#text and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "="
        out[#out+1]=i+2<=#text and alphabet:sub(n%64+1,n%64+1) or "="
    end
    return "PR2:" .. table.concat(out)
end
function Store.decodeCode(code)
    assert(type(code)=="string" and #code<=180000,"Invalid/oversized share code")
    code=code:match("^%s*(.-)%s*$")
    if code:sub(1,4)~="PR2:" then return Store.decodeSet(code) end
    code=code:gsub("%s","")
    local raw=code:sub(5)
    assert(#raw>0 and #raw%4==0 and raw:match("^[A-Za-z0-9_%-]*=?=?$"),"Invalid PR2 code")
    local out={}
    for i=1,#raw,4 do
        local chars={raw:sub(i,i),raw:sub(i+1,i+1),raw:sub(i+2,i+2),raw:sub(i+3,i+3)}
        local nums={}
        for j,ch in ipairs(chars) do
            if ch=="=" then nums[j]=0 else
                local at=alphabet:find(ch,1,true);assert(at,"Invalid PR2 character");nums[j]=at-1
            end
        end
        assert(chars[1]~="=" and chars[2]~="=" and (chars[3]~="=" or chars[4]=="="),"Invalid padding")
        local n=nums[1]*262144+nums[2]*4096+nums[3]*64+nums[4]
        out[#out+1]=string.char(math.floor(n/65536)%256)
        if chars[3]~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
        if chars[4]~="=" then out[#out+1]=string.char(n%256) end
    end
    return Store.decodeSet(table.concat(out))
end
local loaded, loadError = pcall(Store.load)
if not loaded then Store.problem = tostring(loadError); startupNote = "Personal sets unavailable: " .. tostring(loadError); warn("[AntiResolver] " .. startupNote) end
local Settings = library.last and Store.get(library.last) or defaults()
local Options = Settings.resolver
local applySettings


local function requireAPI(library, name)
    assert(type(library) == "table" and type(library[name]) == "function",
        "Penablox API missing: " .. name)
end
for _, name in ipairs({"get_enemies", "is_alive", "get_info", "get_player_angles_deg", "get_player_lby_deg"}) do
    requireAPI(entity, name)
end
for _, name in ipairs({"get", "set"}) do requireAPI(plist, name) end
requireAPI(client, "set_event_callback")
requireAPI(rage, "get_target")
requireAPI(events, "on_tick")
requireAPI(globals, "tickcount")
requireAPI(globals, "realtime")

local Resolver = {hits = 0, misses = 0, ignored = 0, unknownShots = 0, fault = nil, fireEvents = 0, hitEvents = 0, missEvents = 0, unmatchedResults = 0, invalidEvents = 0, trackedShots = 0, trace = {}}
Resolver.results = {hits = 0, misses = 0, damage = 0, reasons = {resolver = 0, spread = 0, occlusion = 0, death = 0, unknown = 0}}
Resolver.dt = {groups = {}, sequence = 0, completed = 0, expired = 0, stale = 0, ambiguous = 0}
Resolver.performance = {evaluations = 0, cached = 0}
local states, shots, owners, names = {}, {}, {}, {}
local alive = true
local now = function() return globals.realtime() end
local function wrap(n) return (n + 180) % 360 - 180 end
local function clampPitch(n) return math.clamp(n, -89, 89) end
local keys = {"Force body yaw value", "Override yaw offset", "Force pitch value", "Override prefer body aim", "Override safe point", "Force pitch", "Force body yaw"}
local neutral = {0, 0, 0, "-", "-", false, false}
local lastUpdateTick
local activeMode
local zeroSeq = 0
local nextSlotIndex = 0
local playerIdCache, playerIdCacheCount = {}, 0
local pairIdCache = {}
local function readUserId(player) return player.UserId end
local function pairId(yId, pId)
    local row = pairIdCache[yId]
    if not row then row = {}; pairIdCache[yId] = row end
    local id = row[pId]
    if not id then id = yId .. ":" .. pId; row[pId] = id end
    return id
end
local function playerKey(player)
    if player == nil or (type(player) ~= "table" and type(player) ~= "userdata") then return nil end
    local cached = playerIdCache[player]
    if cached ~= nil then return cached end
    local ok, id = pcall(readUserId, player)
    if ok and finite(id) and id > 0 and id % 1 == 0 then
        local key = "user:" .. tostring(id)
        if playerIdCacheCount >= 64 then playerIdCache, playerIdCacheCount = {}, 0 end
        playerIdCache[player] = key
        playerIdCacheCount = playerIdCacheCount + 1
        return key
    end
    return player
end
local function stateForPlayer(player)
    local key = playerKey(player)
    return key and states[key] or nil
end
local function slotKey(value)
    if type(value) == "string" and value:match("^%d+$") then value = tonumber(value) end
    if finite(value) and value % 1 == 0 then return "slot:" .. tostring(value) end
    return nil
end
local function shotKey(value)
    if type(value) == "string" and value:match("^%d+$") then value = tonumber(value) end
    if finite(value) or (type(value) == "string" and #value > 0) then return "shot:" .. tostring(value) end
    return nil
end
local function traceLine(value)
    local log = Resolver.trace
    log[#log + 1] = value
    if #log > 8 then table.remove(log, 1) end
    if Options.debug then print("[AR trace] " .. value) end
end
local function restore(state)
    if not state.saved then return end
    for i, key in ipairs(keys) do
        local saved = state.saved[key]
        if saved == nil then saved = neutral[i] end
        local ok, err = pcall(plist.set, state.player, key, saved)
        if not ok then warn("[Resolver] Restore failed: " .. key .. ": " .. tostring(err)) end
    end
    state.saved, state.applied = nil, nil
end
local function disconnectConn(connection) connection:Disconnect() end
function Resolver.clear()
    for _, state in pairs(states) do
        restore(state)
        for _, connection in ipairs(state.connections or {}) do pcall(disconnectConn, connection) end
    end
    states, shots, owners, names = {}, {}, {}, {}
    playerIdCache, playerIdCacheCount = {}, 0
    Resolver.dt.groups = {}
    lastUpdateTick = nil
end
function Resolver.stop()
    alive = false
    Resolver.clear()
end
function Resolver.setEnabled(value)
    Options.enabled = value
    if not value then Resolver.clear() end
end
local function newState(player)
    local key = playerKey(player)
    assert(key, "Enemy Player has no usable identity")
    nextSlotIndex = nextSlotIndex + 1
    local state = {key = key, player = player, character = player.Character, history = {},
        contexts = {}, consecutive = 0, lastTick = -1, phase = "collecting", life = 0, connections = {},
        slotIndex = nextSlotIndex, yawScratch = {}, pitchScratch = {}, medianScratch = {}, medianDirty = true}
    states[key] = state
    
    local ok, signal = pcall(function() return player.CharacterAdded end)
    if ok and signal then
        local connected, connection = pcall(function()
            return signal:Connect(function(character)
                if not alive or states[key] ~= state then return end
                restore(state)
                state.life, state.character = state.life + 1, character
                state.history, state.choice, state.dtLock = {}, nil, nil
                state.candidateCache, state.staticSamples, state.medianDirty = nil, 0, true
                state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
                state.consecutive, state.lastTick = 0, -1
            end)
        end)
        if connected and connection then
            state.lifecycle = true
            state.connections[#state.connections + 1] = connection
        end
    end
    return state
end
local function context(state, info)
    local name = info.is_in_air and "air" or (info.is_crouching and "duck" or
        ((finite(info.speed) and info.speed > 2) and "move" or "stand"))
    if not state.contexts[name] then
        state.contexts[name] = {scores = {}, rejected = {}, winner = nil, stage = 1, misses = 0, revision = 0, failedAngles = {}, decayTime = now()}
    end
    return state.contexts[name], name
end
local function medianPitch(state)
    if not state.medianDirty and state.cachedMedian ~= nil then return state.cachedMedian end
    local history = state.history
    local values = state.medianScratch
    local n = 0
    for i = math.max(1, #history - 11), #history do
        n = n + 1
        values[n] = history[i].pitch
    end
    for i = n + 1, #values do values[i] = nil end
    if n == 0 then state.cachedMedian, state.medianDirty = 0, false; return 0 end
    table.sort(values)
    local result
    if n % 2 == 1 then result = values[(n + 1) / 2]
    else result = (values[n / 2] + values[n / 2 + 1]) * 0.5 end
    state.cachedMedian, state.medianDirty = result, false
    return result
end
local function motion(history)
    local sx, sy, flips, changes, lastSign, pmin, pmax = 0, 0, 0, 0, 0, 89, -89
    for i, record in ipairs(history) do
        sx = sx + (record.yawCos or math.cos(math.rad(record.yaw)))
        sy = sy + (record.yawSin or math.sin(math.rad(record.yaw)))
        pmin, pmax = math.min(pmin, record.pitch), math.max(pmax, record.pitch)
        if i > 1 then
            local delta = wrap(record.yaw - history[i - 1].yaw)
            if math.abs(delta) >= 25 then
                local sign = delta > 0 and 1 or -1
                if lastSign ~= 0 and sign ~= lastSign then flips = flips + 1 end
                lastSign, changes = sign, changes + 1
            end
        end
    end
    local center
    if sx * sx + sy * sy > 0.01 then center = math.deg(math.atan2(sy, sx)) end
    return flips >= 3 and changes >= 4, center, pmax - pmin > 70
end
local function autoFeedback(ctx, strategy, hit)
    local auto = ctx.auto
    if not auto then return end
    local record = auto.results[strategy] or {score = 0, hits = 0, misses = 0}
    auto.results[strategy] = record
    record.score = math.clamp(record.score + (hit and 1 or -1.25), -4, 4)
    if hit then record.hits = record.hits + 1 else record.misses = record.misses + 1 end
    if auto.selected == strategy then auto.streak = hit and 0 or auto.streak + 1 end
end
function Resolver.closeDT(group, reason)
    if group.closed then return end
    group.closed = true
    Resolver.dt.groups[group.serial] = nil
    if group.state.dtLock == group then group.state.dtLock = nil end
    for id, shot in pairs(group.members) do if shots[id] == shot then shots[id] = nil end end
    Resolver.dt.last = string.format("series=%d shots=%d results=%d %s", group.serial, group.sent, #group.results, reason)
    traceLine("DT " .. Resolver.dt.last)
end
function Resolver.finishDT(group)
    if group.closed then return false end
    local state = group.state
    local ctx = state.contexts[group.context]
    if Options.mode ~= "Auto DT" or states[state.key] ~= state or state.life ~= group.life
        or (not state.lifecycle and state.player.Character ~= group.character)
        or not ctx or ctx.revision ~= group.revision then
        Resolver.dt.stale = Resolver.dt.stale + 1
        Resolver.closeDT(group, "stale; no training")
        return false
    end
    local timestamp = now()
    if #group.results < group.sent then
        if timestamp >= group.deadline then
            Resolver.dt.expired = Resolver.dt.expired + 1
            Resolver.closeDT(group, "missing or ambiguous results; no training")
        end
        return false
    end
    if group.sent < 2 and timestamp < group.lockUntil then return false end
    local hits, misses, ignored, head, failed = 0, 0, 0, nil, nil
    for _, result in ipairs(group.results) do
        if result.hit then
            hits = hits + 1
            if result.hitbox == "head" then head = result.shot end
        elseif result.reason == "resolver" then
            misses = misses + 1
            if not failed or result.hitbox ~= "head" then failed = result end
        else ignored = ignored + 1 end
    end
    Resolver.hits, Resolver.misses, Resolver.ignored = Resolver.hits+hits, Resolver.misses+misses, Resolver.ignored+ignored
    if hits > 0 then
        state.consecutive, ctx.misses = 0, 0
        ctx.revision = ctx.revision + 1
        if head then
            autoFeedback(ctx, head.strategy, true)
            ctx.scores[head.id] = math.min(6, (ctx.scores[head.id] or 0)+2)
            ctx.rejected[head.id] = nil
            ctx.winner = {offset = head.offset, pitch = head.pitch, time = timestamp}
            for i=#ctx.failedAngles,1,-1 do
                local f=ctx.failedAngles[i]
                local samePitch = f.body or (f.pitch == nil and head.pitch == nil)
                    or (f.pitch ~= nil and head.pitch ~= nil and math.abs(f.pitch - head.pitch) < 2)
                if math.abs(wrap(f.offset-head.offset))<2 and samePitch then table.remove(ctx.failedAngles,i) end
            end
        end
    elseif failed then
        state.consecutive, ctx.misses = state.consecutive+1, ctx.misses+1
        if ctx.misses % Options.cycleAfter == 0 then
            local shot = failed.shot
            ctx.revision = ctx.revision+1
            autoFeedback(ctx, shot.strategy, false)
            ctx.failedAngles[#ctx.failedAngles+1] = {offset=shot.offset,pitch=shot.pitch,
                body=failed.hitbox~=nil and failed.hitbox~="head",expires=timestamp+3}
            if #ctx.failedAngles>32 then table.remove(ctx.failedAngles,1) end
            ctx.scores[shot.id] = math.max(-12,(ctx.scores[shot.id] or 0)-3)
            ctx.rejected[shot.id], ctx.winner = timestamp+3, nil
            if shot.strategy=="Brute-force" then ctx.stage=ctx.stage%5+1 end
        end
    end
    Resolver.dt.completed = Resolver.dt.completed+1
    Resolver.closeDT(group, string.format("hit=%d resolver=%d ignored=%d; one series update",hits,misses,ignored))
    return true
end
function Resolver.trackDT(shot, id, choice)
    local timestamp, state = now(), shot.state
    local weaponKey = "unavailable"
    if type(weapon)=="table" and type(weapon.get_active)=="function" then
        local ok, active = pcall(weapon.get_active)
        if ok and type(active)=="table" then weaponKey=tostring(active.id or active.name or "unavailable") end
    end
    local group = state.dtLock
    if not group or group.closed or group.sent>=2 or timestamp>=group.lockUntil
        or group.context~=shot.context or group.revision~=shot.revision or group.life~=state.life
        or group.weapon~=weaponKey or group.pitchMode~=Options.pitch then
        local count, oldest = 0, nil
        for _, pending in pairs(Resolver.dt.groups) do
            count=count+1
            if not oldest or pending.started<oldest.started then oldest=pending end
        end
        if count>=128 then
            Resolver.dt.expired=Resolver.dt.expired+1
            Resolver.closeDT(oldest,"capacity limit; no training")
        end
        Resolver.dt.sequence=Resolver.dt.sequence+1
        group={serial=Resolver.dt.sequence,state=state,life=state.life,character=state.character,
            context=shot.context,revision=shot.revision,choice=clone(choice),pitchMode=Options.pitch,
            weapon=weaponKey,started=timestamp,lockUntil=timestamp+Options.dtWindowMs/1000,
            deadline=timestamp+2,sent=0,members={},results={}}
        Resolver.dt.groups[group.serial]=group
        state.dtLock=group
    end
    group.sent=group.sent+1
    group.members[id], shot.dtGroup = shot, group
    traceLine(string.format("DT series=%d fire=%d/%d yaw=%.1f pitch=%s",group.serial,group.sent,2,shot.yaw,tostring(shot.pitch)))
end
local autoStrategies = {{name = "Adaptive", prior = 0.6}, {name = "Brute-force", prior = 0},
    {name = "Animation", prior = 1}, {name = "Jitter", prior = 1.4}}
local function autoStrategy(state, ctx, name, jitter, anim)
    local timestamp = now()
    if not ctx.auto then ctx.auto = {results = {}, streak = 0, decayTime = timestamp, holdUntil = 0} end
    local auto = ctx.auto
    local elapsed = timestamp - auto.decayTime
    if elapsed >= 1 then
        local factor = 2 ^ (-elapsed / Options.memory)
        for _, record in pairs(auto.results) do record.score = record.score * factor end
        auto.decayTime = timestamp
    end
    local hasAnimation = anim and finite(anim.goal_feet_yaw)
    local best, bestScore, currentScore = nil, -math.huge, nil
    local rotate = auto.streak >= 2
    for _, entry in ipairs(autoStrategies) do
        if (entry.name ~= "Animation" or hasAnimation) and (entry.name ~= "Jitter" or jitter) then
        local record = auto.results[entry.name]
        local score = entry.prior + (record and record.score or 0)
        if entry.name == auto.selected then currentScore = score end
        if (not rotate or entry.name ~= auto.selected) and score > bestScore then
            best, bestScore = entry.name, score
        end
        end
    end
    local previous = auto.selected
    if not previous or currentScore == nil or rotate
        or (timestamp >= auto.holdUntil and bestScore > currentScore + 0.75) then
        auto.selected, auto.streak, auto.holdUntil = best, 0, timestamp + 0.75
        if previous and previous ~= best and Options.debug then
            print("[AR · AUTO] " .. tostring(state.player.Name) .. " · " .. name .. " · " .. previous .. " -> " .. best)
        end
    end
    return auto.selected
end
local function stableJitter(ctx, detected, center)
    local timestamp = now()
    local signal = ctx.jitterSignal
    if not signal then signal = {}; ctx.jitterSignal = signal end
    if detected and finite(center) then
        signal.since = signal.since or timestamp
        signal.lastSeen, signal.center = timestamp, center
        if timestamp-signal.since >= 0.08 then signal.confirmed = true end
    else
        signal.since = nil
        if not signal.lastSeen or timestamp-signal.lastSeen > 0.15 then signal.confirmed = false end
    end
    return signal.confirmed == true, signal.center
end
local bruteOffsets = {0, 58, -58, 86, -86}
local bruteOffsetIds = {"brute1", "brute2", "brute3", "brute4", "brute5"}
local extraOffsets = {58, -58, 86, -86}
local extraOffsetIds = {"offset58", "offset-58", "offset86", "offset-86"}
local function candidates(state, info, yaw, pitch, lby)
    local ctx, name = context(state, info)
    local elapsed = now()
    if Options.mode == "Auto DT" then
        local group = state.dtLock
        if group and not group.closed and elapsed < group.lockUntil and group.life == state.life
            and group.context == name and group.revision == ctx.revision and group.pitchMode == Options.pitch then
            local jitter, _, pitchJitter = motion(state.history)
            state.phase = jitter and "jitter" or (pitchJitter and "pitch" or "tracking")
            state.strategy = group.choice.strategy
            return group.choice
        end
        state.dtLock = nil
    end
    local anim
    if (Options.mode == "Auto" or Options.mode == "Auto DT" or Options.mode == "Debug") and type(entity.get_anim_state) == "function" then anim = entity.get_anim_state(state.player) end
    local cache = state.candidateCache
    if (state.staticSamples or 0) >= 16 and cache and elapsed < cache.expires
        and cache.ctx == ctx and cache.revision == ctx.revision and cache.stage == ctx.stage
        and cache.mode == Options.mode and cache.pitchMode == Options.pitch and cache.memory == Options.memory
        and cache.yaw == yaw and cache.pitch == pitch and cache.lby == lby and cache.delta == info.desync_delta
        and cache.feet == (anim and anim.goal_feet_yaw) and cache.torso == (anim and anim.torso_yaw)
        and state.choice and state.choice.id == cache.choice.id then
        Resolver.performance.cached = Resolver.performance.cached + 1
        state.strategy, state.phase = cache.choice.strategy, cache.phase
        return cache.choice
    end
    Resolver.performance.evaluations = Resolver.performance.evaluations + 1
    local jitter, center, pitchJitter = motion(state.history)
    state.phase = jitter and "jitter" or (pitchJitter and "pitch" or "tracking")
    local yaws, pitches = state.yawScratch, state.pitchScratch
    local yawCount, pitchCount = 0, 0
    local function addYaw(id, angle, prior)
        angle = wrap(angle)
        for i = 1, yawCount do
            if math.abs(wrap(yaws[i].angle - angle)) < 2 then return end
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
    if strategy == "Auto" or strategy == "Auto DT" or strategy == "Debug" then
        local stable, stableCenter = stableJitter(ctx, jitter, center)
        strategy = autoStrategy(state, ctx, name, stable, anim)
        if strategy == "Jitter" then center = stableCenter end
    end
    state.strategy = strategy
    if strategy == "Brute-force" then
        addYaw(bruteOffsetIds[ctx.stage], lby + bruteOffsets[ctx.stage], 3)
    else
        if strategy == "Animation" then
            addYaw("anim-feet", anim.goal_feet_yaw, 4.0)
            if finite(anim.torso_yaw) then addYaw("anim-torso", anim.torso_yaw, 2.6) end
        end
        if strategy == "Jitter" then addYaw("center", center, 4.0) end
        addYaw("feet", lby, 3.2)
        if ctx.winner then addYaw("learned", lby + ctx.winner.offset, 3.6) end
        if jitter and center then addYaw("center", center, 2.5) end
        local delta = finite(info.desync_delta) and math.clamp(math.abs(info.desync_delta), 0, 86) or 58
        addYaw("delta+", lby + delta, 1.8)
        addYaw("delta-", lby - delta, 1.8)
        addYaw("visual", yaw, 1.2)
        for i = 1, 4 do addYaw(extraOffsetIds[i], lby + extraOffsets[i], 1.0) end
    end
    local function addPitch(id, angle, prior)
        if angle ~= nil then
            for i = 1, pitchCount do
                local pAngle = pitches[i].angle
                if pAngle ~= nil and math.abs(pAngle - angle) < 2 then return end
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
        addPitch("median", medianPitch(state), pitchJitter and 2.0 or 1.4)
        if ctx.winner and ctx.winner.pitch ~= nil then addPitch("learned", ctx.winner.pitch, 1.8) end
        addPitch("raw", pitch, 1.2)
        if pitchJitter then
            addPitch("level", 0, 0.3)
            addPitch("down", -89, 0)
            addPitch("up", 89, 0)
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
        local yOffset = wrap(y.angle - lby)
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
                        or (failed.pitch ~= nil and p.angle ~= nil and math.abs(failed.pitch - p.angle) < 2)
                    if samePitch and math.abs(wrap(yOffset - failed.offset)) < 2 then
                        blocked = true
                        break
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
    local best = {id = bestId, yaw = bestYaw, pitch = bestPitch, context = name, lby = lby, strategy = strategy}
    if (state.staticSamples or 0) >= 16 then
        local expires = math.min(elapsed + 0.2, ctx.decayTime + 1)
        if ctx.winner then expires = math.min(expires, (ctx.winner.time or 0) + Options.memory * 2) end
        if ctx.auto then
            expires = math.min(expires, ctx.auto.decayTime + 1)
            if ctx.auto.holdUntil > elapsed then expires = math.min(expires, ctx.auto.holdUntil) end
        end
        if ctx.jitterSignal and ctx.jitterSignal.lastSeen and ctx.jitterSignal.lastSeen + 0.15 > elapsed then
            expires = math.min(expires, ctx.jitterSignal.lastSeen + 0.15)
        end
        for fi = 1, #failedAngles do expires = math.min(expires, failedAngles[fi].expires) end
        for _, untilTime in pairs(ctx.rejected) do if untilTime > elapsed then expires = math.min(expires, untilTime) end end
        local nextCache = cache or {}
        nextCache.ctx, nextCache.revision, nextCache.stage = ctx, ctx.revision, ctx.stage
        nextCache.mode, nextCache.pitchMode, nextCache.memory = Options.mode, Options.pitch, Options.memory
        nextCache.yaw, nextCache.pitch, nextCache.lby, nextCache.delta = yaw, pitch, lby, info.desync_delta
        nextCache.feet, nextCache.torso = anim and anim.goal_feet_yaw, anim and anim.torso_yaw
        nextCache.choice, nextCache.phase, nextCache.expires = best, state.phase, expires
        state.candidateCache = nextCache
    else state.candidateCache = nil end
    return best
end

local function rememberTarget()
    local target = rage.get_target()
    if target and slotKey(target.slot) and playerKey(target.player) then
        owners[slotKey(target.slot)] = playerKey(target.player)
    end
    return target
end
local function fromEvent(value)
    local state = stateForPlayer(value)
    if state then return state end
    local key = slotKey(value)
    if key and owners[key] then return states[owners[key]] end
    if type(value) == "string" and names[value] then return states[names[value]] end
    return nil
end
local function applyOverride(state, key, value)
    if state.refreshOverrides or state.applied[key] ~= value then
        plist.set(state.player, key, value)
        state.applied[key] = value
    end
end
local function update(forceState)
    if not alive or Resolver.fault then return end
    if not Options.enabled then
        if next(states) then Resolver.clear() end
        activeMode = nil
        return
    end
    if activeMode ~= Options.mode then Resolver.clear(); activeMode = Options.mode end
    if Options.mode == "Auto DT" then
        for _, group in pairs(Resolver.dt.groups) do Resolver.finishDT(group) end
    end
    local currentTick = globals.tickcount()
    if not forceState and lastUpdateTick == currentTick then return end
    if not forceState then lastUpdateTick = currentTick end
    local timestamp = now()
    local seen
    if not forceState then seen = {} end
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

                if type(entity.get_player_slot) == "function" and (not state.slotRefresh or timestamp >= state.slotRefresh) then
                    state.slotRefresh = timestamp + 0.5
                    local slot = entity.get_player_slot(player)
                    if slotKey(slot) then owners[slotKey(slot)] = key end
                end
                if state.lastTick ~= currentTick or forceState == state then
                    local pitch, yaw = entity.get_player_angles_deg(player)
                    if finite(yaw) and finite(pitch) then
                        local wrappedYaw, samplePitch = wrap(yaw), clampPitch(pitch)
                        local ctx, historyContext = context(state, info)
                        local angleChanged = state.lastRawYaw == nil or state.lastRawPitch == nil
                            or math.abs(wrap(wrappedYaw - state.lastRawYaw)) >= 5
                            or math.abs(samplePitch - state.lastRawPitch) >= 5
                        local ctxChanged = state.historyContext ~= historyContext or state.lastRevision ~= ctx.revision
                        local due = forceState == state or key == activeKey or state.choice == nil
                            or angleChanged or ctxChanged or not state.sampleTime or (timestamp - state.sampleTime > 0.1)
                            or ((currentTick + state.slotIndex) % 3 == 0)
                        if due then
                            local lby = entity.get_player_lby_deg(player)
                            if finite(lby) then
                                if state.historyContext ~= historyContext or (state.sampleTime and timestamp - state.sampleTime > 0.5) then
                                    state.history = {}
                                    state.staticSamples, state.candidateCache, state.medianDirty = 0, nil, true
                                end
                                state.historyContext, state.sampleTime = historyContext, timestamp
                                state.lastRawYaw, state.lastRawPitch, state.lastRevision = wrappedYaw, samplePitch, ctx.revision
                                if state.lastTick ~= currentTick or #state.history == 0 then
                                    local previous = state.history[#state.history]
                                    state.staticSamples = previous and previous.yaw == wrappedYaw and previous.pitch == samplePitch
                                        and math.min(16, (state.staticSamples or 0) + 1) or 1
                                    local record = #state.history >= 16 and table.remove(state.history, 1) or {}
                                    record.yaw, record.pitch = wrappedYaw, samplePitch
                                    if previous and previous.yaw == wrappedYaw then
                                        record.yawCos, record.yawSin = previous.yawCos, previous.yawSin
                                    else record.yawCos, record.yawSin = math.cos(math.rad(wrappedYaw)), math.sin(math.rad(wrappedYaw)) end
                                    state.history[#state.history + 1] = record
                                    state.medianDirty = true
                                end
                                state.lastTick = currentTick
                                state.choice = candidates(state, info, wrappedYaw, samplePitch, wrap(lby))
                                if not state.saved then
                                    state.saved = {}
                                    for _, k in ipairs(keys) do state.saved[k] = plist.get(player, k) end
                                end
                                state.applied = state.applied or {}
                                state.refreshOverrides = not state.overrideRefresh or timestamp >= state.overrideRefresh
                                if state.refreshOverrides then state.overrideRefresh = timestamp + 2.0 end
                                local choice = state.choice
                                applyOverride(state, "Override yaw offset", 0)
                                applyOverride(state, "Force body yaw value", choice.yaw)
                                applyOverride(state, "Force body yaw", true)
                                if choice.pitch ~= nil then applyOverride(state, "Force pitch value", choice.pitch) end

                                local forcePitch = choice.pitch ~= nil
                                if Options.pitch == "Off" then forcePitch = state.saved["Force pitch"] or false end
                                if Options.pitch == "Off" and state.saved["Force pitch value"] ~= nil then
                                    applyOverride(state, "Force pitch value", state.saved["Force pitch value"])
                                end
                                applyOverride(state, "Force pitch", forcePitch)
                                local baim = state.saved["Override prefer body aim"]
                                if baim == nil then baim = "-" end
                                if Options.bodyAfter > 0 and state.consecutive >= Options.bodyAfter then baim = "Force" end
                                applyOverride(state, "Override prefer body aim", baim)
                                local safe = state.saved["Override safe point"]
                                if safe == nil then safe = "-" end
                                if Options.safe and (state.phase ~= "tracking" or state.consecutive > 0) then safe = "Force" end
                                applyOverride(state, "Override safe point", safe)
                            else
                                restore(state)
                                state.choice = nil
                                state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
                                state.phase = "invalid angles"
                            end
                        end
                    else
                        restore(state)
                        state.choice = nil
                        state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
                        state.phase = "invalid angles"
                    end
                end
            elseif state then
                restore(state)
                state.history, state.choice = {}, nil
                state.candidateCache, state.staticSamples, state.medianDirty = nil, 0, true
                state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
                state.lastTick, state.phase = -1, "dead"
            end
        elseif state then
            restore(state)
            state.history, state.choice = {}, nil
            state.candidateCache, state.staticSamples, state.medianDirty = nil, 0, true
            state.lastRawYaw, state.lastRawPitch, state.lastRevision = nil, nil, nil
            state.lastTick, state.phase = -1, "dead"
        end
    end
    if seen then
    for key, state in pairs(states) do
        if not seen[key] then
            restore(state)
            for _, connection in ipairs(state.connections) do pcall(disconnectConn, connection) end
            if state.player and playerIdCache[state.player] ~= nil then
                playerIdCache[state.player] = nil
                playerIdCacheCount = math.max(0, playerIdCacheCount - 1)
            end
            states[key] = nil
        end
    end
    for slot, key in pairs(owners) do if not states[key] then owners[slot] = nil end end
    for name, key in pairs(names) do if not states[key] then names[name] = nil end end
    end
    for id, shot in pairs(shots) do if timestamp - shot.time > 10 then shots[id] = nil end end
end
local function fail(err)
    Resolver.fault = tostring(err)
    Options.enabled = false
    Resolver.clear()
    warn("[Resolver] Disabled after API error: " .. Resolver.fault)
end
local function guarded(fn)
    return function(...)
        if not alive then return end
        local ok, err = pcall(fn, ...)
        if not ok then fail(err) end
    end
end
Resolver.outputLanguage = "en"
local function eventOutput(kind, event, matchedShot)
    if kind == "fire" and not Options.debug then return end
    local ru = Resolver.outputLanguage == "ru"
    local labels = ru and {fire = "ВЫСТРЕЛ", hit = "ПОПАДАНИЕ", miss = "ПРОМАХ"}
        or {fire = "FIRE", hit = "HIT", miss = "MISS"}
    local prefix = "[AR · " .. labels[kind] .. "] "
    if not event then print(prefix .. (ru and "Нет данных события" or "Missing event data")); return end
    local record = matchedShot or (shotKey(event.id) and shots[shotKey(event.id)])
    local state = fromEvent(event.target) or (record and record.state)
    local target = state and state.player.Name
    if not target and (type(event.target) == "table" or type(event.target) == "userdata") then
        local ok, name = pcall(function() return event.target.Name end)
        if ok then target = name end
    end
    if not target and type(event.target) == "string" and not slotKey(event.target) then target = event.target end
    local parts = {tostring(target or (ru and "Неизвестная цель" or "Unknown target"))}
    local hitbox = event.hitbox or (record and record.hitbox)
    local hitboxes = {
        head = {"Head", "Голова"}, chest = {"Chest", "Грудь"}, pelvis = {"Pelvis", "Таз"},
        uppertorso = {"Upper torso", "Верх корпуса"}, lowertorso = {"Lower torso", "Низ корпуса"},
        arms = {"Arms", "Руки"}, legs = {"Legs", "Ноги"},
        left_arm = {"Left arm", "Левая рука"}, right_arm = {"Right arm", "Правая рука"},
        left_leg = {"Left leg", "Левая нога"}, right_leg = {"Right leg", "Правая нога"},
    }
    if type(hitbox) == "string" and hitbox ~= "" then
        local names = hitboxes[string.lower(hitbox)]
        parts[#parts + 1] = names and names[ru and 2 or 1] or hitbox
    end
    if kind == "miss" then
        local reasons = {
            resolver = {"Resolver", "Резольвер"}, spread = {"Spread", "Разброс"},
            occlusion = {"Obstructed", "Препятствие"}, death = {"Target died", "Цель погибла"},
        }
        local reason = type(event.reason) == "string" and event.reason ~= "" and event.reason or nil
        local names = reason and reasons[string.lower(reason)]
        parts[#parts + 1] = names and names[ru and 2 or 1] or reason
            or (ru and "Причина неизвестна" or "Unknown reason")
    elseif kind == "hit" then
        if finite(event.damage) then parts[#parts + 1] = ru and ("Урон: " .. event.damage) or (event.damage .. " dmg") end
        if finite(event.health_remaining) then
            parts[#parts + 1] = ru and ("Осталось HP: " .. event.health_remaining) or (event.health_remaining .. " HP left")
        end
    end
    if Options.debug then
        if event.id ~= nil then parts[#parts + 1] = "ID: " .. tostring(event.id) end
        local chance = kind == "fire" and event.hitchance or (record and record.hitchance)
        if finite(chance) then parts[#parts + 1] = "event HC: " .. chance end
    end
    print(prefix .. table.concat(parts, " · "))
end
local function debugOptional(library, method, first, second)
    if type(library) ~= "table" or type(library[method]) ~= "function" then return nil end
    
    
    local ok, value = pcall(function()
        if second ~= nil then return library[method](first, second) end
        if first ~= nil then return library[method](first) end
        return library[method]()
    end)
    if ok then return value end
end
local function debugSnapshot(event, state, activeTarget, data)
    data = data or {}
    data.weapon, data.distance, data.ping = "unavailable", "unavailable", "unavailable"
    
    data.engineYaw = activeTarget and playerKey(activeTarget.player) == state.key and activeTarget.resolved_yaw_deg or nil
    data.eventYaw = finite(event.resolved_yaw) and event.resolved_yaw or nil
    data.hitchance = event.hitchance
    data.samples = #state.history
    data.age = state.sampleTime and string.format("%.0fms", (now()-state.sampleTime)*1000) or "unavailable"
    local requested = state.choice and state.choice.yaw
    local reported = data.eventYaw or (finite(data.engineYaw) and data.engineYaw or nil)
    if finite(requested) and reported then data.yawDelta = wrap(reported-requested) end
    data.overrideEnabled = debugOptional(plist, "get", state.player, "Force body yaw")
    data.overrideYaw = debugOptional(plist, "get", state.player, "Force body yaw value")
    data.overrideOffset = debugOptional(plist, "get", state.player, "Override yaw offset")
    data.nativeResolver = debugOptional(rage, "is_resolver_enabled")
    local info = debugOptional(entity, "get_info", 0) or debugOptional(entity, "get_info", localPlayer)
    local targetInfo = debugOptional(entity, "get_info", event.target) or debugOptional(entity, "get_info", state.player)
    local weapon = debugOptional(client, "get_weapon")
    data.weapon = (weapon and weapon.name) or (info and info.weapon_name) or data.weapon
    local ping = debugOptional(client, "latency")
    if finite(ping) then data.ping = string.format("%.0fms", ping * 1000) end
    local origin = (info and info.position) or debugOptional(entity, "get_player_position", 0)

    local position = (targetInfo and targetInfo.position) or debugOptional(entity, "get_player_position", event.target) or debugOptional(entity, "get_player_position", state.player)
    if origin and position then
        data.distance = string.format("%.2f studs", math.sqrt((origin.X-position.X)^2+(origin.Y-position.Y)^2+(origin.Z-position.Z)^2))
    end
    data.desyncDelta = targetInfo and targetInfo.desync_delta
    return data
end
local function debugShot(kind, event, matchedShot)
    if not Options.debug or not event then return end
    local shot = matchedShot or (shotKey(event.id) and shots[shotKey(event.id)])
    local prefix = "[AR DEBUG · " .. kind .. " #" .. tostring(event.id) .. "] "
    if not shot then print(prefix .. "no tracked shot; target=" .. tostring(event.target)); return end
    local state, snapshot = shot.state, shot.debug or {}
    local ctx = state.contexts[shot.context]
    local disposition = "current revision; engine application not verified"
    if states[state.key] ~= state or state.life ~= shot.life then disposition = "old player life"
    elseif not ctx or ctx.revision ~= shot.revision then disposition = "previous hypothesis; no retraining"
    elseif now()-shot.time>10 then disposition = "expired shot" end
    print(prefix .. tostring(state.player.Name) .. " · weapon=" .. tostring(snapshot.weapon or "not captured")
        .. " · distance=" .. tostring(snapshot.distance or "not captured") .. " · ping=" .. tostring(snapshot.ping or "not captured"))
    print(prefix .. "build=" .. BUILD .. " mode=" .. Options.mode .. " strategy=" .. tostring(shot.strategy) .. " state=" .. shot.context
        .. " yaw=" .. tostring(shot.yaw) .. " pitch=" .. tostring(shot.pitch) .. " lby=" .. tostring(shot.lby)
        .. " engine_yaw_deg=" .. tostring(snapshot.engineYaw or "unavailable")
        .. " fire_event_yaw=" .. tostring(snapshot.eventYaw or "unavailable"))
    print(prefix .. "aimed_hitbox=" .. tostring(shot.hitbox) .. " reported_hitbox=" .. tostring(event.hitbox)
        .. " event_hc_raw=" .. tostring(snapshot.hitchance or "unavailable") .. " samples=" .. tostring(snapshot.samples or "unavailable")
        .. " sample_age=" .. tostring(snapshot.age or "unavailable") .. " revision=" .. shot.revision
        .. "/" .. tostring(ctx and ctx.revision) .. " elapsed_ms=" .. string.format("%.0f", (now()-shot.time)*1000))
    if kind == "FIRE" then
        local function shown(value) if value == nil then return "unavailable" end; return tostring(value) end
        print(prefix .. "override_enabled=" .. shown(snapshot.overrideEnabled)
            .. " override_yaw=" .. shown(snapshot.overrideYaw) .. " override_offset=" .. shown(snapshot.overrideOffset)
            .. " engine_minus_requested=" .. shown(snapshot.yawDelta)
            .. " target_desync_delta=" .. shown(snapshot.desyncDelta) .. " native_resolver=" .. shown(snapshot.nativeResolver))
    end
    if kind ~= "FIRE" then
        print(prefix .. "engine_reason=" .. tostring(event.reason or (kind == "HIT" and "hit confirmed" or "not supplied"))
            .. " · handling=" .. disposition)
    end
end
local function safeDebugShot(kind, event, matchedShot)
    if not Options.debug then return end
    local ok, err = pcall(debugShot, kind, event, matchedShot)
    if not ok then warn("[AR DEBUG] Diagnostic failure: " .. tostring(err)) end
end
function Resolver.setMode(value)
    assert(member(value, MODES), "Unknown resolver mode: " .. tostring(value))
    Resolver.clear()
    Options.mode, Options.debug = value, value == "Debug"
    print("[AR MODE] " .. value)
    if Options.debug then
        print("[AR DEBUG] Current Auto algorithm with complete shot and feedback diagnostics enabled.")
    end
    if value == "Auto DT" then print("[AR DT] series angle hold enabled; window=" .. Options.dtWindowMs .. "ms") end
end
local function onFire(event)
    local activeTarget = rememberTarget()
    eventOutput("fire", event)
    Resolver.fireEvents = Resolver.fireEvents + 1
    if not Options.enabled then return end
    local rawID = event and event.id
    local id = shotKey(rawID)
    if not id then Resolver.invalidEvents = Resolver.invalidEvents + 1; traceLine("fire: missing/invalid shot ID"); return end
    if rawID == 0 or rawID == "0" then
        zeroSeq = zeroSeq + 1
        id = "zero:" .. tostring(zeroSeq)
    elseif Options.mode == "Auto DT" and shots[id] then
        traceLine("DT duplicate FIRE ID ignored: " .. id); return
    end
    local state = fromEvent(event.target)
    if not state or not state.choice or not state.saved then
        Resolver.unknownShots = Resolver.unknownShots + 1
        traceLine("fire " .. id .. ": unmapped target=" .. tostring(event.target))
        return
    end
    local choice = state.choice
    local count = 0
    for _ in pairs(shots) do count = count + 1 end
    if count >= 256 then
        local oldestID, oldestTime
        for id, record in pairs(shots) do
            if not oldestTime or record.time < oldestTime then oldestID, oldestTime = id, record.time end
        end
        shots[oldestID] = nil
    end
    Resolver.trackedShots = Resolver.trackedShots + 1
    local engineYaw = activeTarget and playerKey(activeTarget.player) == state.key and activeTarget.resolved_yaw_deg
    traceLine(string.format("fire %s %s strategy=%s requested_yaw=%.1f engine_yaw=%s pitch=%s", id,
        tostring(state.key), tostring(state.strategy), choice.yaw, tostring(engineYaw), tostring(choice.pitch)))
    shots[id] = {state = state, character = state.character, life = state.life, point = event.point, time = now(),
        id = choice.id, context = choice.context, revision = state.contexts[choice.context].revision, offset = wrap(choice.yaw - choice.lby), lby = choice.lby, yaw = choice.yaw, pitch = choice.pitch, hitbox = event.hitbox, hitchance = event.hitchance, strategy = choice.strategy, auto = Options.mode == "Auto" or Options.mode == "Auto DT" or Options.mode == "Debug"}
    if Options.mode == "Auto DT" then Resolver.trackDT(shots[id], id, choice) end
    if Options.debug then
        local snapshot = {}
        shots[id].debug = snapshot
        local ok, err = pcall(debugSnapshot, event, state, activeTarget, snapshot)
        if not ok then warn("[AR DEBUG] Partial snapshot: " .. tostring(err)) end
        safeDebugShot("FIRE", event)
    end
end
local function matchFeedback(event)
    if not event then return nil, nil, "missing event" end
    local id = shotKey(event.id)
    local nonZero = event.id ~= nil and event.id ~= 0 and event.id ~= "0"
    if nonZero and id and shots[id] then
        local target = fromEvent(event.target)
        if target and target ~= shots[id].state then return nil, nil, "shot ID/target mismatch" end
        return id, shots[id], "exact ID"
    end
    if nonZero then return id, nil, "unknown or completed ID" end
    local target = fromEvent(event.target)
    if not target then return id, nil, "zero/missing ID: target not mapped" end
    local found, record, count = nil, nil, 0
    for pendingID, pending in pairs(shots) do
        if pending.state == target and pending.life == target.life and now()-pending.time <= 2 then
            found, record, count = pendingID, pending, count + 1
        end
    end
    if count == 1 then return found, record, "unique target fallback; engine ID=" .. tostring(event.id) end
    if Options.mode == "Auto DT" and count>1 then Resolver.dt.ambiguous=Resolver.dt.ambiguous+1 end
    return id, nil, "zero/missing ID: ambiguous pending shots=" .. count
end
local function feedback(event, hit)
    if event then
        local stats = Resolver.results
        if hit then
            stats.hits = stats.hits + 1
            if finite(event.damage) and event.damage > 0 then stats.damage = stats.damage + event.damage end
        else
            stats.misses = stats.misses + 1
            local reason = type(event.reason) == "string" and string.lower(event.reason) or "unknown"
            if reason:find("death", 1, true) then reason = "death" end
            if stats.reasons[reason] == nil then reason = "unknown" end
            stats.reasons[reason] = stats.reasons[reason] + 1
        end
    end
    local id, shot, matching = matchFeedback(event)
    eventOutput(hit and "hit" or "miss", event, shot)
    safeDebugShot(hit and "HIT" or "MISS", event, shot)
    if Options.debug then print("[AR MATCH] engine_id=" .. tostring(event and event.id) .. " tracked_id=" .. tostring(shot and id) .. " · " .. matching) end
    if hit then Resolver.hitEvents = Resolver.hitEvents + 1 else Resolver.missEvents = Resolver.missEvents + 1 end
    if not Options.enabled then return end
    if not event then Resolver.invalidEvents = Resolver.invalidEvents + 1; return end
    if shot then shots[id] = nil end
    if not shot or now() - shot.time > 10 then
        Resolver.unmatchedResults = Resolver.unmatchedResults + 1
        traceLine("result " .. tostring(id) .. ": " .. matching .. ", reason=" .. tostring(event.reason))
        return
    end
    if shot.dtGroup then
        local group = shot.dtGroup
        if group.closed then return end
        local hitbox = event.hitbox or shot.hitbox
        group.results[#group.results+1] = {hit=hit,reason=event.reason,
            hitbox=type(hitbox)=="string" and string.lower(hitbox) or nil,shot=shot}
        if Resolver.finishDT(group) then update(group.state) end
        return
    end
    local state = shot.state
    if states[state.key] ~= state or state.life ~= shot.life or
        (not state.lifecycle and state.player.Character ~= shot.character) then return end
    traceLine("result " .. id .. " " .. tostring(state.key) .. ": " .. (hit and "hit" or tostring(event.reason)))
    local ctx = state.contexts[shot.context]
    if not ctx then return end
    if shot.revision ~= ctx.revision then
        traceLine("result " .. id .. ": previous hypothesis; logged without retraining")
        return
    end
    if hit then
        Resolver.hits = Resolver.hits + 1
        state.consecutive = 0
        ctx.misses = 0
        ctx.revision = ctx.revision + 1
        local hitbox = event.hitbox
        if type(hitbox) == "string" and string.lower(hitbox) == "head" then
            if shot.auto then autoFeedback(ctx, shot.strategy, true) end
            ctx.scores[shot.id] = math.min(6, (ctx.scores[shot.id] or 0) + 2)
            ctx.rejected[shot.id] = nil
            ctx.winner = {offset = shot.offset, pitch = shot.pitch, time = now()}
            for i = #ctx.failedAngles, 1, -1 do
                local failed = ctx.failedAngles[i]
                local samePitch = failed.body or (failed.pitch == nil and shot.pitch == nil)
                    or (failed.pitch ~= nil and shot.pitch ~= nil and math.abs(failed.pitch - shot.pitch) < 2)
                if math.abs(wrap(failed.offset - shot.offset)) < 2 and samePitch then table.remove(ctx.failedAngles, i) end
            end
        end
    elseif event.reason == "resolver" then
        Resolver.misses = Resolver.misses + 1
        state.consecutive = state.consecutive + 1
        ctx.misses = ctx.misses + 1
        if ctx.misses % Options.cycleAfter == 0 then
            ctx.revision = ctx.revision + 1
            if shot.auto then autoFeedback(ctx, shot.strategy, false) end
            local hitbox = event.hitbox or shot.hitbox
            local body = type(hitbox) == "string" and string.lower(hitbox) ~= "head"
            ctx.failedAngles[#ctx.failedAngles + 1] = {offset = shot.offset, pitch = shot.pitch, body = body, expires = now() + 3}
            if #ctx.failedAngles > 32 then table.remove(ctx.failedAngles, 1) end
            if shot.strategy == "Brute-force" then ctx.stage = ctx.stage % 5 + 1 end
            ctx.scores[shot.id] = math.max(-12, (ctx.scores[shot.id] or 0) - 3)
            ctx.rejected[shot.id] = now() + 3
            
            ctx.winner = nil
        end
    else
        Resolver.ignored = Resolver.ignored + 1
    end
    if hit or event.reason == "resolver" then update(state) end
end
function Resolver.status()
    if Resolver.fault then return "API error — see Lua console" end
    if not Options.enabled then return "Resolver disabled" end
    local count = 0
    for _ in pairs(states) do count = count + 1 end
    return string.format("%s · %d targets · %d hit / %d miss", Options.mode, count, Resolver.hits, Resolver.misses)
end


function Resolver.targetStatus()
    local target = rage.get_target()
    local state = target and (stateForPlayer(target.player) or (target.slot ~= nil and fromEvent(target.slot)))
    if not state then return "No active target" end
    return tostring(state.player.Name or "Target") .. " / " .. tostring(state.strategy or "collecting") .. " / " .. state.phase
end

function Resolver.shotStatistics()
    local s = Resolver.results
    print(string.format("[AR STATS] received results=%d hits=%d misses=%d damage=%.0f", s.hits+s.misses, s.hits, s.misses, s.damage))
    print(string.format("[AR STATS] misses: resolver=%d spread=%d occlusion=%d death=%d unknown=%d",
        s.reasons.resolver, s.reasons.spread, s.reasons.occlusion, s.reasons.death, s.reasons.unknown))
    return "Shot statistics printed"
end
function Resolver.diagnose()
    local count = 0
    for _ in pairs(states) do count = count + 1 end
    local native = "API unavailable"
    if type(rage.is_resolver_enabled) == "function" then
        local ok, value = pcall(rage.is_resolver_enabled)
        native = ok and tostring(value) or "read error"
    end
    print("[AR diag] Lua enabled=" .. tostring(Options.enabled) .. " mode=" .. tostring(Options.mode) .. " native=" .. native .. " targets=" .. count)
    print(string.format("[AR diag] callbacks fire/hit/miss=%d/%d/%d tracked=%d unmapped=%d unmatched_results=%d invalid=%d",
        Resolver.fireEvents, Resolver.hitEvents, Resolver.missEvents, Resolver.trackedShots,
        Resolver.unknownShots, Resolver.unmatchedResults, Resolver.invalidEvents))
    print(string.format("[AR perf] candidate evaluations=%d cached=%d",Resolver.performance.evaluations,Resolver.performance.cached))
    if Options.mode == "Auto DT" then
        local pending = 0
        for _ in pairs(Resolver.dt.groups) do pending = pending+1 end
        print(string.format("[AR DT] window=%dms completed=%d pending=%d expired=%d stale=%d ambiguous=%d",
            Options.dtWindowMs, Resolver.dt.completed, pending, Resolver.dt.expired, Resolver.dt.stale, Resolver.dt.ambiguous))
        if Resolver.dt.last then print("[AR DT] " .. Resolver.dt.last) end
    end
    local target = rage.get_target()
    local state = target and (stateForPlayer(target.player) or fromEvent(target.slot))
    if state then
        for name, ctx in pairs(state.contexts) do
            if ctx.auto then
                print("[AR auto] " .. name .. " selected=" .. tostring(ctx.auto.selected))
                for strategy, record in pairs(ctx.auto.results) do
                    print(string.format("[AR auto] %s %s score=%.2f head_hits=%d failed_hypotheses=%d",
                        name, strategy, record.score, record.hits, record.misses))
                end
            end
        end
        local ok, flag, yaw, pitchFlag, pitch = pcall(function()
            return plist.get(state.player, "Force body yaw"), plist.get(state.player, "Force body yaw value"),
                plist.get(state.player, "Force pitch"), plist.get(state.player, "Force pitch value")
        end)
        if ok then print("[AR diag] plist yaw=" .. tostring(flag) .. "/" .. tostring(yaw) .. " pitch=" .. tostring(pitchFlag) .. "/" .. tostring(pitch)) end
    end
    print("[AR diag] " .. Resolver.status() .. " / " .. Resolver.targetStatus())
    if Resolver.fault then print("[AR diag] fault=" .. Resolver.fault) end
    for _, line in ipairs(Resolver.trace) do print("[AR diag] " .. line) end
    return "Diagnostics printed to Lua console"
end


local Builder = {owned = false, state = nil, profile = "Global", fault = nil, requested = false}
local function builderAPI()
    for _, name in ipairs({"reset", "override_pitch", "override_yaw", "override_yaw_offset", "override_yaw_modifier",
        "override_body_yaw", "override_inverter", "override_desync_limits", "override_fake_lag",
        "override_fake_lag_limit", "override_fake_lag_variability"}) do requireAPI(aa, name) end
    for _, name in ipairs({"is_grounded", "is_ducking", "get_speed"}) do requireAPI(movement, name) end
    requireAPI(input, "is_key_down"); requireAPI(input, "is_typing")
end
function Builder.release(reason)
    if Builder.owned then
        local ok, err = pcall(aa.reset)
        if not ok then
            local detail = "AA reset failed: " .. tostring(err)
            if Builder.releaseFault ~= detail then warn("[AR AA] " .. detail) end
            Builder.releaseFault, Builder.releaseRetry = detail, now()+1
            return false
        end
    end
    Builder.releaseFault, Builder.releaseRetry = nil, nil
    Builder.owned, Builder.defense, Builder.requested = false, nil, false
    Builder.state, Builder.profile, Builder.candidate, Builder.count, Builder.lastTick = nil, nil, nil, 0, nil
    Builder.random, Builder.lastKey, Builder.readyAt = {}, false, nil
    Builder.applied = nil
    Builder.shotTick, Builder.flushRequested, Builder.lastState, Builder.lastProfile = nil, false, nil, nil
    Builder.explicitOwned, Builder.desyncModeOwned, Builder.fakeLagOwned = false, nil, false
    Builder.pause = reason
    return true
end
function Builder.setEnabled(value)
    if value then
        assert(not Builder.releaseFault or Builder.release(), "Cannot enable AA until previous overrides are released")
        builderAPI(); Builder.fault = nil
    end
    Settings.builder.enabled = value
    if not value then Builder.release("disabled") end
    print("[AR AA] enabled=" .. tostring(value))
end
local function localSnapshot()
    local ok, info = pcall(entity.get_info, 0)
    if ok and type(info) == "table" and type(info.is_alive) == "boolean" then return info end
    if type(entity.get_local_player) == "function" then
        local good, player = pcall(entity.get_local_player)
        if good and player then
            local readable, snapshot = pcall(entity.get_info, player)
            if readable and type(snapshot) == "table" and type(snapshot.is_alive) == "boolean" then return snapshot end
        end
    end
    return nil
end
local function readKinematics(info)
    local tbl = type(info) == "table"
    local grounded = tbl and type(info.is_in_air) == "boolean" and not info.is_in_air
    if not tbl or type(info.is_in_air) ~= "boolean" then grounded = movement.is_grounded(0) end
    local duck = tbl and info.is_crouching
    if type(duck) ~= "boolean" then
        duck = type(movement.is_ducking) == "function" and movement.is_ducking(0) or false
    end
    local speed = tbl and info.speed
    if not finite(speed) then speed = movement.get_speed(0) end
    return grounded, duck, speed
end
local function detectState(info)
    local grounded, duck, speed = readKinematics(info)
    assert(type(grounded) == "boolean" and type(duck) == "boolean" and finite(speed), "Invalid local movement snapshot")
    if not grounded then return duck and "Air crouch" or "Air", speed end
    if duck then return speed > 0.4 and "Crouch moving" or "Crouching", speed end
    if speed <= 0.4 then return "Standing", speed end
    return speed <= Settings.builder.slow and "Slow" or "Moving", speed
end
local function randomStep(key, phase, low, high)
    local record = Builder.random[key]
    if not record or record.phase ~= phase or record.low ~= low or record.high ~= high then
        record = {phase = phase, low = low, high = high, value = low + math.random() * (high - low)}
        Builder.random[key] = record
    end
    return record.value
end
local function profilePitch(profile, elapsed, key)
    local period = profile.pitchPeriod or profile.period
    local phase = math.floor(elapsed / period)
    if profile.pitchMode == "Jitter" then return phase % 2 == 0 and profile.pitchA or profile.pitchB end
    if profile.pitchMode == "Random" then
        return randomStep(key, phase, math.min(profile.pitchA, profile.pitchB), math.max(profile.pitchA, profile.pitchB))
    end
    if profile.pitchMode == "Sway" then
        local middle, amplitude = (profile.pitchA+profile.pitchB)*0.5, (profile.pitchB-profile.pitchA)*0.5
        return middle + math.sin(elapsed*math.pi/period)*amplitude
    end
    if profile.pitchMode == "Flick" then return elapsed % period == 0 and profile.pitchB or profile.pitchA end
    return profile.pitchA
end
local function yawWave(profile, elapsed)
    local phase = math.floor(elapsed / profile.yawPeriod)
    local mode, amplitude = profile.yawMode, profile.amplitude
    if mode == "Center" then return phase % 2 == 0 and -amplitude or amplitude end
    if mode == "3-Way" then return ({-amplitude, 0, amplitude})[phase % 3 + 1] end
    if mode == "5-Way" then return ({-amplitude, -amplitude * 0.5, 0, amplitude * 0.5, amplitude})[phase % 5 + 1] end
    if mode == "Spin" then return wrap(elapsed * profile.spinSpeed) end
    if mode == "Random" then return randomStep("yaw", phase, -amplitude, amplitude) end
    if mode == "Sequence" then return profile.sequence[phase % #profile.sequence + 1] end
    return 0
end
local function finishDefense(tick)
    if not Builder.defense then return end
    local config = Builder.defense.config
    Builder.defense, Builder.readyAt = nil, tick + config.cooldown
    if config.flush then Builder.flushRequested = true end
end
function Builder.onShot()
    if Settings.builder.enabled and not Builder.fault then Builder.shotTick = globals.tickcount() end
end
local function builderUpdate()
    if not alive then return end
    if not Settings.builder.enabled then
        if Builder.owned then Builder.release("disabled") end
        return
    end
    local info = localSnapshot()
    if not info or not info.is_alive then
        if Builder.owned then Builder.release("local entity dead or unavailable") end
        Builder.pause = "local entity dead or unavailable"
        return
    end
    if not Builder.owned then
        builderAPI(); Builder.owned = true; aa.reset()
        Builder.explicitOwned, Builder.desyncModeOwned, Builder.fakeLagOwned = false, nil, false
        Builder.applied = nil
        Builder.random, Builder.epoch = {}, globals.tickcount()
    end
    local tick = globals.tickcount()
    if Builder.lastTick == tick then return end
    if Builder.lastTick and tick < Builder.lastTick then
        assert(Builder.release("tick counter reset"), "Cannot release AA on tick counter reset")
        Builder.owned, Builder.epoch = true, tick
    end
    Builder.lastTick, Builder.pause = tick, nil
    local raw = detectState(info)
    if raw == Builder.candidate then Builder.count = Builder.count + 1 else Builder.candidate, Builder.count = raw, 1 end
    if not Builder.state or Builder.count >= Settings.builder.hysteresis then Builder.state = raw end
    local stateProfile = Settings.builder.profiles[Builder.state]
    local profileName = stateProfile.enabled and Builder.state or "Global"
    local profile = Settings.builder.profiles[profileName]
    if profileName ~= Builder.profile then
        if Builder.defense and not profile.defensive.enabled then finishDefense(tick) end
        Builder.profile = profileName
    end
    if Builder.lastState ~= Builder.state or Builder.lastProfile ~= profileName then
        Builder.lastState, Builder.lastProfile = Builder.state, profileName
        print("[AR AA] state=" .. tostring(Builder.state) .. "/" .. profileName)
    end
    local elapsed = tick - Builder.epoch
    local menuOpen = type(ui.is_menu_open) == "function" and ui.is_menu_open()
    local down = not Builder.blockManual and not menuOpen and not input.is_typing() and input.is_key_down(Settings.builder.manualKey)
    local manual = Builder.requested or (down and not Builder.lastKey)
    Builder.requested, Builder.lastKey = false, down
    local shot = Builder.shotTick and tick-Builder.shotTick >= 0 and tick-Builder.shotTick <= 2
    Builder.shotTick = nil
    if Builder.defense and (tick >= Builder.defense.untilTick or not profile.defensive.enabled) then finishDefense(tick) end
    local d = profile.defensive
    if d.enabled and not Builder.defense and tick >= (Builder.readyAt or 0) then
        local trigger = (d.trigger == "Manual" and manual) or (d.trigger == "On shot" and shot)
        local charged = false
        if d.trigger == "Charged" or d.shift then
            requireAPI(rage, "is_double_tap_charged"); charged = rage.is_double_tap_charged()
        end
        if d.trigger == "Charged" then trigger = charged end
        if trigger and (not d.shift or charged) then
            if d.shift then requireAPI(rage, "shift_ticks"); rage.shift_ticks(d.shiftTicks) end
            Builder.defense = {untilTick = tick+d.duration, start = tick, config = clone(d)}
        end
    end
    local pitch = profilePitch(profile, elapsed, "pitch")
    local yaw = profile.yawOffset + yawWave(profile, elapsed)
    local inverted = profile.inverter == "Right" or (profile.inverter == "Alternate" and math.floor(elapsed/profile.desyncPeriod)%2 == 1)
    if Builder.defense then
        local config, phase = Builder.defense.config, tick-Builder.defense.start
        pitch = profilePitch(config, phase, "defensive-pitch")
        yaw = config.yawOffset + (math.floor(phase/config.period)%2 == 0 and -config.amplitude or config.amplitude)
    end
    yaw = wrap(yaw)
    if profile.desyncMode == "Explicit" then requireAPI(aa, "override_desync") end
    local flush = Builder.flushRequested
    if flush and type(aa.unchoke) == "function" then aa.unchoke() end
    local needReset = (Builder.desyncModeOwned ~= nil and Builder.desyncModeOwned ~= profile.desyncMode)
        or (not profile.fakeLag and Builder.fakeLagOwned)
    if needReset then
        aa.reset()
        Builder.explicitOwned, Builder.desyncModeOwned, Builder.fakeLagOwned = false, nil, false
    end
    aa.override_yaw_modifier("Disabled")
    aa.override_yaw_offset(0)
    aa.override_pitch(pitch)
    aa.override_yaw(yaw, profile.yawBase)
    aa.override_body_yaw(true)
    aa.override_inverter(inverted)
    local applied = Builder.applied
    if not applied then applied = {}; Builder.applied = applied end
    applied.pitch, applied.yaw, applied.base, applied.inverter = pitch, yaw, profile.yawBase, inverted
    if profile.desyncMode == "Explicit" then
        local sign = inverted and -1 or 1
        local realVal, fakeVal = profile.real * sign, profile.fake * sign
        aa.override_desync(realVal, fakeVal)
        applied.desyncMode, applied.real, applied.fake = "Explicit", realVal, fakeVal
        applied.left, applied.right = nil, nil
        Builder.explicitOwned, Builder.desyncModeOwned = true, "Explicit"
    else
        aa.override_desync_limits(profile.left, profile.right)
        applied.desyncMode, applied.left, applied.right = "Limits", profile.left, profile.right
        applied.real, applied.fake = nil, nil
        Builder.explicitOwned, Builder.desyncModeOwned = false, "Limits"
    end
    if profile.fakeLag then
        local wantLag = not flush
        local wantLimit = flush and 0 or profile.lagLimit
        local wantVar = profile.lagVariation
        aa.override_fake_lag(wantLag)
        aa.override_fake_lag_limit(wantLimit)
        aa.override_fake_lag_variability(wantVar)
        applied.fakeLag, applied.lagLimit, applied.lagVariation = wantLag, wantLimit, wantVar
        Builder.fakeLagOwned = true
    else
        applied.fakeLag, applied.lagLimit, applied.lagVariation = nil, nil, nil
    end
    applied.defensive, applied.flush = Builder.defense ~= nil, flush
    Builder.flushRequested = false
end
function Builder.tick()
    if not Settings.builder.enabled and not Builder.owned then return end
    if Builder.releaseFault then
        if now() >= (Builder.releaseRetry or 0) then Builder.release("cleanup retry") end
        return
    end
    if not alive or Builder.fault then return end
    local ok, err = pcall(builderUpdate)
    if not ok then
        Builder.fault, Settings.builder.enabled = tostring(err), false
        Builder.release("API error")
        warn("[AR AA] Builder disabled: " .. Builder.fault)
    end
end
function Builder.status()
    if Builder.fault or Builder.releaseFault then return "AA API error: see console" end
    if not Settings.builder.enabled then return "AA: built-in cheat" end
    if not Builder.state then return "AA: waiting for character" end
    return "AA: " .. Builder.state .. " / " .. Builder.profile .. (Builder.defense and " / DEFENSIVE" or "")
end

applySettings = function(value)
    local nextSettings = validate(value)
    Resolver.clear()
    Builder.release()
    Settings, Options = nextSettings, nextSettings.resolver
    Resolver.fault, Builder.fault = nil, nil
    activeMode = nil
    if Sync and Sync.onSettingsApplied then Sync.onSettingsApplied() end
end

do
    -- Fill DEFAULT_SYNC_URL and DEFAULT_LOGO_ASSET before publishing to GitHub.
    local S = {
        DEFAULT_SYNC_URL = "https://brilliant-semolina-d874d6.netlify.app/api/presence",
        DEFAULT_LOGO_ASSET = "",
        DEFAULT_CLIENT_KEY = "",
        POLL_INTERVAL = 15,
        MIN_POLL_GAP = 8.5,
        SCAN_INTERVAL = 0.9,
        EMPTY_SCAN_INTERVAL = 2.4,
        MAX_SCAN_NODES = 1600,
        ROLE_ORDER = {dev = 5, staff = 4, vip = 3, beta = 2, free = 1},
        ROLE_TAGS = {dev = "DEV", staff = "MOD", vip = "VIP", beta = "BETA", free = "AR"},
        SKIP_GUI_HINTS = {"arbadge", "ar_esp", "bubblechat", "experiencechat", "killfeed", "freecam"},
        IGNORE_TEXT_ANCESTOR = {"chat", "kill", "feed", "death", "spectat", "bubble", "log", "menu"},
        SCOREBOARD_HINTS = {"tab", "score", "board", "player", "roster", "list", "leader"},
        nativeViews = {},
        gen = 0,
        inFlight = false,
        scanRunning = false,
        nextPollAt = 0,
        lastAttemptAt = 0,
        nextScanAt = 0,
        failCount = 0,
        lastOkAt = nil,
        storageMode = nil,
        selfRole = "idle",
        statusNote = "Idle",
        peerBadges = {},
        badgeCount = 0,
        tabCount = 0,
        tabBadges = {},
        espDrawings = {},
        espBillboards = {},
        billboardBroken = false,
        cachedScoreboardRoot = nil,
        cachedHttpFn = false,
        cachedPlayersSvc = false,
        lastVisibleLang = nil,
        lastVisiblePage = nil,
    }
    local H = {}

    function H.nowSafe()
        local ok, t = pcall(now)
        if ok and finite(t) then return t end
        return os.clock and os.clock() or 0
    end

    function H.roleColor(role)
        if not S.roleColors then
            S.roleColors = {
                dev = Color3.fromRGB(255, 204, 72),
                staff = Color3.fromRGB(115, 230, 175),
                vip = Color3.fromRGB(205, 130, 255),
                beta = Color3.fromRGB(120, 200, 255),
                free = Color3.fromRGB(130, 165, 255),
            }
        end
        return S.roleColors[role] or S.roleColors.free
    end

    function H.syncCfg()
        if not Settings.sync then
            Settings.sync = {enabled = true, endpoint = "", logoAsset = "", tabBadges = true, espBadges = true, stealth = false}
        end
        return Settings.sync
    end

    function H.trimStr(val)
        if type(val) ~= "string" then return "" end
        return val:match("^%s*(.-)%s*$") or ""
    end

    function H.effectiveUrl()
        local cfg = H.syncCfg()
        local raw = H.trimStr(cfg.endpoint)
        if raw == "" then raw = H.trimStr(S.DEFAULT_SYNC_URL) end
        if raw == "" then return "" end
        raw = raw:gsub("/+$", "")
        if not raw:match("^https?://[%w%.%-_:%/]+$") then return "" end
        if not raw:match("^https?://[^/]+/.+$") then raw = raw .. "/api/presence" end
        return raw
    end

    function H.effectiveAsset()
        local cfg = H.syncCfg()
        local raw = H.trimStr(cfg.logoAsset)
        if raw == "" then raw = H.trimStr(S.DEFAULT_LOGO_ASSET) end
        if raw == "" then return "" end
        if raw:match("^%d+$") then return "rbxassetid://" .. raw end
        if raw:match("^rbxassetid://%d+$") or raw:match("^rbxthumb://") then return raw end
        local urlId = raw:match("asset/(%d+)") or raw:match("library/(%d+)") or raw:match("catalog/(%d+)") or raw:match("id=(%d+)")
        if urlId then return "rbxthumb://type=Asset&id=" .. urlId .. "&w=150&h=150" end
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
        if not lp and type(entity.get_local_player) == "function" then
            local ok, p = pcall(entity.get_local_player)
            if ok and p then lp = p end
        end
        if not lp then return nil, lp end
        local ok, pg = pcall(function()
            return lp:FindFirstChildOfClass("PlayerGui") or lp:FindFirstChild("PlayerGui")
        end)
        return (ok and pg) or nil, lp
    end

    function H.resolveHttpRequest()
        if S.cachedHttpFn ~= false then return S.cachedHttpFn end
        local getters = {
            function() return request end,
            function() return http_request end,
            function() return http and http.request end,
            function() return client and client.request end,
            function() return syn and syn.request end,
        }
        for _, getter in ipairs(getters) do
            local ok, fn = pcall(getter)
            if ok and type(fn) == "function" then
                S.cachedHttpFn = fn
                return fn
            end
        end
        S.cachedHttpFn = nil
        return nil
    end

    function H.readSafeId(player)
        local ok, id = pcall(readUserId, player)
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
                    if id ~= myId and #peerIds < 64 then
                        peerIds[#peerIds + 1] = id
                    end
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
        if entry.gui then pcall(function() entry.gui:Destroy() end) end
        H.recountTab()
    end

    function H.clearTabBadges()
        for id in pairs(S.tabBadges) do
            H.removeTabEntry(id)
        end
        S.tabBadges = {}
        S.tabCount = 0
    end

    function H.destroyDraw(obj)
        if not obj then return end
        pcall(function() obj.Visible = false end)
        if type(obj.Destroy) == "function" then
            pcall(obj.Destroy, obj)
        elseif type(obj.Remove) == "function" then
            pcall(obj.Remove, obj)
        end
    end

    function H.clearEsp()
        for id, obj in pairs(S.espDrawings) do
            H.destroyDraw(obj)
            S.espDrawings[id] = nil
        end
        for id, bb in pairs(S.espBillboards) do
            if bb then pcall(function() bb:Destroy() end) end
            S.espBillboards[id] = nil
        end
    end

    function H.containsHint(text, hints)
        if type(text) ~= "string" or #text == 0 then return false end
        local low = string.lower(text)
        for _, h in ipairs(hints) do
            if low:find(h, 1, true) then return true end
        end
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

    function H.findAncestorScoreboard(node, playerGui)
        local cur = node
        local best = nil
        for _ = 1, 6 do
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or not p or p == playerGui then break end
            if H.containsHint(H.readNameSafe(p), S.SCOREBOARD_HINTS) then best = p end
            cur = p
        end
        return best
    end

    function H.isLikelyRowTextNode(node, playerGui)
        local cur = node
        local hasList = false
        for step = 1, 4 do
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or not p or p == playerGui then break end
            local pName = H.readNameSafe(p)
            if H.containsHint(pName, S.IGNORE_TEXT_ANCESTOR) then return false end
            if H.containsHint(pName, S.SCOREBOARD_HINTS) then hasList = true end
            if step <= 2 and not hasList then
                local okC, ch = pcall(function() return p:GetChildren() end)
                if okC and type(ch) == "table" then
                    if step == 1 and #ch >= 2 then
                        for _, sib in ipairs(ch) do
                            local isImg = pcall(function() return sib:IsA("ImageLabel") or sib:IsA("ImageButton") end) and (sib:IsA("ImageLabel") or sib:IsA("ImageButton"))
                            local isLayout = pcall(function() return sib:IsA("UIListLayout") or sib:IsA("UIGridLayout") end) and (sib:IsA("UIListLayout") or sib:IsA("UIGridLayout"))
                            if isImg or isLayout then hasList = true; break end
                        end
                    end
                    local okSf, sf = pcall(function() return p:IsA("ScrollingFrame") end)
                    if okSf and sf then hasList = true end
                end
            end
            cur = p
        end
        return hasList
    end

    function H.wantedMap(myId)
        local cfg = H.syncCfg()
        local wanted = {}
        local count = 0
        for id, role in pairs(S.peerBadges) do
            wanted[id] = role
            count = count + 1
        end
        if not cfg.stealth and myId and S.ROLE_ORDER[S.selfRole] then
            if not wanted[myId] then count = count + 1 end
            wanted[myId] = S.selfRole
        end
        return wanted, count
    end

    function H.attachTabBadge(id, host, hostKind, role, asset)
        local badgeName = "ARBadge_" .. tostring(id)
        local sig = tostring(role) .. "|" .. tostring(asset) .. "|" .. tostring(hostKind)
        local existing = S.tabBadges[id]
        if existing and existing.host == host and existing.sig == sig then
            local okP, par = pcall(function() return existing.gui and existing.gui.Parent end)
            if okP and par == host then return true end
        end
        if existing then H.removeTabEntry(id) end
        pcall(function()
            local old = host:FindFirstChild(badgeName)
            if old then old:Destroy() end
        end)

        local okMake, frame = pcall(function()
            local zBase = 2
            pcall(function()
                if finite(host.ZIndex) then zBase = math.min(50, math.max(1, host.ZIndex + 4)) end
            end)
            local color = H.roleColor(role)
            local f = Instance.new("Frame")
            f.Name = badgeName
            f.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
            f.BackgroundTransparency = 0.08
            f.BorderSizePixel = 0
            f.ZIndex = zBase
            if hostKind == "avatar" then
                f.Size = asset ~= "" and UDim2.new(0, 16, 0, 16) or UDim2.new(0, 18, 0, 14)
                f.AnchorPoint = Vector2.new(1, 1)
                f.Position = UDim2.new(1, 0, 1, 0)
            else
                f.Size = UDim2.new(0, asset ~= "" and 18 or (role == "free" and 24 or 28), 0, asset ~= "" and 18 or 14)
                f.AnchorPoint = Vector2.new(1, 0.5)
                f.Position = UDim2.new(1, -2, 0.5, 0)
            end
            pcall(function()
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
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
                img.Position = UDim2.new(0, 0, 0, 0)
                img.BackgroundTransparency = 1
                img.Image = asset
                img.ZIndex = zBase + 1
                pcall(function() img.ScaleType = Enum.ScaleType.Fit end)
                pcall(function()
                    local ic = Instance.new("UICorner")
                    ic.CornerRadius = UDim.new(0, 4)
                    ic.Parent = img
                end)
                img.Parent = f
            else
                local lbl = Instance.new("TextLabel")
                lbl.Name = "Tag"
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = S.ROLE_TAGS[role] or "AR"
                lbl.TextColor3 = role == "free" and Color3.fromRGB(255, 255, 255) or color
                lbl.ZIndex = zBase + 1
                pcall(function() lbl.TextScaled = true end)
                pcall(function() lbl.Font = Enum.Font.GothamBold end)
                if role == "free" then
                    pcall(function()
                        local grad = Instance.new("UIGradient")
                        grad.Color = ColorSequence.new(Color3.fromRGB(224, 245, 255), Color3.fromRGB(44, 134, 246))
                        grad.Rotation = 15
                        grad.Parent = lbl
                    end)
                end
                lbl.Parent = f
            end
            f.Parent = host
            return f
        end)
        if okMake and frame then
            S.tabBadges[id] = {gui = frame, host = host, sig = sig, kind = hostKind}
            H.recountTab()
            return true
        end
        return false
    end

    function H.buildMatchIndexes(wanted, meta)
        local byAvatarId, byName, duplicateNames = {}, {}, {}
        for id in pairs(wanted) do
            byAvatarId[tostring(id)] = id
            local m = meta[id]
            if m then
                for _, keyName in ipairs({m.name, m.display}) do
                    if type(keyName) == "string" and #keyName > 0 then
                        local low = string.lower(H.trimStr(keyName))
                        if not duplicateNames[low] then
                            if byName[low] and byName[low] ~= id then
                                byName[low] = nil
                                duplicateNames[low] = true
                            else
                                byName[low] = id
                            end
                        end
                    end
                end
            end
        end
        return byAvatarId, byName
    end

    function H.scanRootForHosts(root, playerGui, byAvatarId, byName)
        local avatarHosts, textHosts = {}, {}
        local queue = {root}
        local head, visited = 1, 0
        local foundScoreboard = nil
        while head <= #queue and visited < S.MAX_SCAN_NODES do
            local node = queue[head]
            head = head + 1
            visited = visited + 1
            if not H.shouldSkipNode(node) then
                local okImg, isImg = pcall(function() return node:IsA("ImageLabel") or node:IsA("ImageButton") end)
                if okImg and isImg then
                    local okSrc, src = pcall(function() return node.Image end)
                    if okSrc and type(src) == "string" and #src > 0 then
                        local low = string.lower(src)
                        local uidStr = low:match("id=(%d+)") or low:match("userid=(%d+)") or low:match("users/(%d+)")
                        if uidStr and byAvatarId[uidStr] then
                            local id = byAvatarId[uidStr]
                            avatarHosts[id] = node
                            if not foundScoreboard then
                                foundScoreboard = H.findAncestorScoreboard(node, playerGui)
                            end
                        end
                    end
                else
                    local okTxt, isTxt = pcall(function() return node:IsA("TextLabel") or node:IsA("TextButton") end)
                    if okTxt and isTxt then
                        local okVal, txt = pcall(function() return node.Text end)
                        if okVal and type(txt) == "string" and #txt > 0 and #txt <= 48 then
                            local clean = string.lower(H.trimStr(txt)):gsub("^@", "")
                            local id = byName[clean]
                            if id and not textHosts[id] and H.isLikelyRowTextNode(node, playerGui) then
                                textHosts[id] = node
                            end
                        end
                    end
                end
                local okCh, children = pcall(function() return node:GetChildren() end)
                if okCh and type(children) == "table" then
                    for _, ch in ipairs(children) do
                        queue[#queue + 1] = ch
                    end
                end
            end
        end
        return avatarHosts, textHosts, foundScoreboard
    end

    function H.startTabScan(gen)
        if S.scanRunning then return end
        local cfg = H.syncCfg()
        if not cfg.enabled or not cfg.tabBadges then H.clearTabBadges(); return end
        local playerGui, _ = H.getPlayerGui()
        if not playerGui then return end
        local myId, _, _, meta = H.collectPlayers()
        local wanted, wantCount = H.wantedMap(myId)
        for id in pairs(S.tabBadges) do
            if not wanted[id] then H.removeTabEntry(id) end
        end
        if wantCount == 0 then return end

        S.scanRunning = true
        local asset = H.effectiveAsset()
        local function work()
            if gen ~= S.gen or not alive then S.scanRunning = false; return end
            local byAvatarId, byName = H.buildMatchIndexes(wanted, meta)
            local roots = {}
            if S.cachedScoreboardRoot then
                local okDesc, inside = pcall(function() return S.cachedScoreboardRoot:IsDescendantOf(playerGui) end)
                if okDesc and inside then
                    roots[1] = S.cachedScoreboardRoot
                else
                    S.cachedScoreboardRoot = nil
                end
            end
            if #roots == 0 then
                local okCh, topList = pcall(function() return playerGui:GetChildren() end)
                if okCh and type(topList) == "table" then
                    local secondary = {}
                    for _, gui in ipairs(topList) do
                        if not H.shouldSkipNode(gui) then
                            if H.containsHint(H.readNameSafe(gui), S.SCOREBOARD_HINTS) then
                                roots[#roots + 1] = gui
                            else
                                secondary[#secondary + 1] = gui
                            end
                        end
                    end
                    for _, gui in ipairs(secondary) do roots[#roots + 1] = gui end
                end
            end

            local mergedAvatar, mergedText = {}, {}
            for _, root in ipairs(roots) do
                if gen ~= S.gen or not alive then break end
                local av, tx, sb = H.scanRootForHosts(root, playerGui, byAvatarId, byName)
                if sb and not S.cachedScoreboardRoot then S.cachedScoreboardRoot = sb end
                for k, v in pairs(av) do if not mergedAvatar[k] then mergedAvatar[k] = v end end
                for k, v in pairs(tx) do if not mergedText[k] then mergedText[k] = v end end
            end

            if gen == S.gen and alive then
                local attachedAny = false
                for id, role in pairs(wanted) do
                    local host = mergedAvatar[id] or mergedText[id]
                    local kind = mergedAvatar[id] and "avatar" or "text"
                    if host then
                        if H.attachTabBadge(id, host, kind, role, asset) then attachedAny = true end
                    else
                        H.removeTabEntry(id)
                    end
                end
                local t = H.nowSafe()
                S.nextScanAt = t + (attachedAny and S.SCAN_INTERVAL or S.EMPTY_SCAN_INTERVAL)
            end
            S.scanRunning = false
        end
        if type(task) == "table" and type(task.spawn) == "function" then
            task.spawn(work)
        else
            pcall(work)
            S.scanRunning = false
        end
    end

    function H.startHttpPoll(url, reqFn)
        if S.inFlight then return end
        if type(json) ~= "table" or type(json.stringify) ~= "function" or type(json.parse) ~= "function" then
            S.statusNote = "JSON API missing"
            S.nextPollAt = H.nowSafe() + 30
            return
        end
        local myId, peerIds = H.collectPlayers()
        if not myId then
            S.statusNote = "Waiting for LocalPlayer"
            S.nextPollAt = H.nowSafe() + 3
            return
        end

        local cfg = H.syncCfg()
        local payload = {user_id = myId, stealth = cfg.stealth == true, peers = peerIds}
        local okEnc, body = pcall(json.stringify, payload)
        if not okEnc or type(body) ~= "string" then
            S.statusNote = "JSON encode failed"
            S.nextPollAt = H.nowSafe() + 20
            return
        end

        local headers = {["Content-Type"] = "application/json"}
        if S.DEFAULT_CLIENT_KEY ~= "" then headers["X-AR-Client"] = S.DEFAULT_CLIENT_KEY end

        S.inFlight = true
        S.lastAttemptAt = H.nowSafe()
        local gen = S.gen

        local function doRequest()
            local okCall, resp = pcall(reqFn, {Url = url, Method = "POST", Headers = headers, Body = body})
            if gen ~= S.gen or not alive then S.inFlight = false; return end
            S.inFlight = false
            local t = H.nowSafe()
            if not okCall or type(resp) ~= "table" then
                S.failCount = S.failCount + 1
                S.statusNote = "Network error"
                S.nextPollAt = t + math.min(60, 18 + S.failCount * 10)
                return
            end

            local code = tonumber(resp.StatusCode) or 0
            if code == 429 then
                local waitSec = 25
                if type(resp.Body) == "string" and #resp.Body > 0 then
                    local okJ, d = pcall(json.parse, resp.Body)
                    if okJ and type(d) == "table" and finite(d.retryAfter) then
                        waitSec = math.clamp(d.retryAfter + 2, 12, 90)
                    end
                end
                S.failCount = S.failCount + 1
                S.statusNote = "Rate limited (" .. tostring(waitSec) .. "s)"
                S.nextPollAt = t + waitSec
                return
            elseif code == 403 then
                S.statusNote = "Client key rejected (403)"
                S.nextPollAt = t + 45
                return
            elseif code < 200 or code >= 300 then
                S.failCount = S.failCount + 1
                S.statusNote = "HTTP " .. tostring(code)
                S.nextPollAt = t + math.min(60, 20 + S.failCount * 10)
                return
            end

            local okDec, data = pcall(json.parse, resp.Body or "")
            if not okDec or type(data) ~= "table" or not data.ok then
                S.failCount = S.failCount + 1
                S.statusNote = "Bad JSON response"
                S.nextPollAt = t + 25
                return
            end

            S.failCount = 0
            S.lastOkAt = t
            S.storageMode = type(data.storage) == "string" and data.storage or nil
            S.selfRole = type(data.self) == "string" and data.self or "free"
            S.statusNote = "Online"

            local nextMap, nextCount = {}, 0
            if type(data.badges) == "table" then
                for idKey, roleVal in pairs(data.badges) do
                    local idNum = tonumber(idKey)
                    if idNum and S.ROLE_ORDER[roleVal] then
                        nextMap[idNum] = roleVal
                        nextCount = nextCount + 1
                    end
                end
            end
            S.peerBadges = nextMap
            S.badgeCount = nextCount
            S.nextPollAt = t + S.POLL_INTERVAL + math.random(0, 3)
            S.nextScanAt = 0
        end

        if type(task) == "table" and type(task.spawn) == "function" then
            task.spawn(doRequest)
        else
            pcall(doRequest)
            S.inFlight = false
        end
    end

    function H.playerHeadPartAndPos(player)
        local headPart = nil
        local okChar, char = pcall(function() return player.Character end)
        if okChar and char then
            local okHp, hp = pcall(function() return char:FindFirstChild("Head") end)
            if okHp and hp then headPart = hp end
        end
        local pos = nil
        if type(entity.get_player_hitbox_position) == "function" then
            local okP, v = pcall(entity.get_player_hitbox_position, player, "head")
            if okP and v then pos = v end
        end
        if not pos and headPart then
            local okV, v = pcall(function() return headPart.Position end)
            if okV and v then pos = v end
        end
        return headPart, pos
    end

    function H.worldToScreenSafe(pos)
        if type(render) == "table" and type(render.world_to_screen) == "function" then
            local ok, x, y, vis = pcall(render.world_to_screen, pos)
            if ok and finite(x) and finite(y) then return x, y, vis == true end
        end
        local okCam, vec, onScreen = pcall(function()
            local cam = workspace and workspace.CurrentCamera
            if not cam then return nil, false end
            local v, vis = cam:WorldToViewportPoint(pos)
            return v, vis
        end)
        if okCam and vec and onScreen and finite(vec.Z) and vec.Z > 0 then
            return vec.X, vec.Y, true
        end
        return nil, nil, false
    end

    function H.updateEsp()
        local cfg = H.syncCfg()
        if not cfg.enabled or not cfg.espBadges then
            H.clearEsp()
            return
        end
        local myId, _, byId = H.collectPlayers()
        local asset = H.effectiveAsset()
        local playerGui = (asset ~= "" and not S.billboardBroken) and (H.getPlayerGui()) or nil
        local active = {}

        for id, role in pairs(S.peerBadges) do
            local player = byId[id]
            if id ~= myId and player then
                local isAlivePlayer = true
                if type(entity.is_alive) == "function" then
                    local okA, resA = pcall(entity.is_alive, player)
                    if okA and resA == false then isAlivePlayer = false end
                end
                if isAlivePlayer then
                    local headPart, headPos = H.playerHeadPartAndPos(player)
                    if headPos then
                        active[id] = true
                        local usedBillboard = false
                        if asset ~= "" and not S.billboardBroken and playerGui and headPart then
                            local bb = S.espBillboards[id]
                            if bb then
                                local okAd = pcall(function()
                                    if bb.Parent ~= playerGui then bb.Parent = playerGui end
                                    if bb.Adornee ~= headPart then bb.Adornee = headPart end
                                    local img = bb:FindFirstChild("Icon")
                                    if img and img.Image ~= asset then img.Image = asset end
                                end)
                                usedBillboard = okAd
                            else
                                local okNew, newBb = pcall(function()
                                    local g = Instance.new("BillboardGui")
                                    g.Name = "AR_Esp_" .. tostring(id)
                                    g.Size = UDim2.new(0, 22, 0, 22)
                                    g.StudsOffset = Vector3.new(0, 2.35, 0)
                                    g.AlwaysOnTop = true
                                    g.Adornee = headPart
                                    local img = Instance.new("ImageLabel")
                                    img.Name = "Icon"
                                    img.Size = UDim2.new(1, 0, 1, 0)
                                    img.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
                                    img.BackgroundTransparency = 0.08
                                    img.BorderSizePixel = 0
                                    img.Image = asset
                                    pcall(function() img.ScaleType = Enum.ScaleType.Fit end)
                                    pcall(function()
                                        local ic = Instance.new("UICorner")
                                        ic.CornerRadius = UDim.new(0, 6)
                                        ic.Parent = img
                                        local st = Instance.new("UIStroke")
                                        st.Thickness = 1
                                        st.Color = H.roleColor(role)
                                        st.Parent = img
                                    end)
                                    img.Parent = g
                                    g.Parent = playerGui
                                    return g
                                end)
                                if okNew and newBb then
                                    S.espBillboards[id] = newBb
                                    usedBillboard = true
                                else
                                    S.billboardBroken = true
                                end
                            end
                        end

                        if usedBillboard then
                            if S.espDrawings[id] then
                                pcall(function() S.espDrawings[id].Visible = false end)
                            end
                        else
                            if S.espBillboards[id] then
                                pcall(function() S.espBillboards[id]:Destroy() end)
                                S.espBillboards[id] = nil
                            end
                            local sx, sy, onScreen = H.worldToScreenSafe(headPos + Vector3.new(0, 1.35, 0))
                            local lbl = S.espDrawings[id]
                            if not lbl and type(Drawing) == "table" and type(Drawing.new) == "function" then
                                local okD, obj = pcall(Drawing.new, "Text")
                                if okD and obj then
                                    pcall(function()
                                        obj.Size = 13
                                        obj.Center = true
                                        obj.Outline = true
                                    end)
                                    S.espDrawings[id] = obj
                                    lbl = obj
                                end
                            end
                            if lbl then
                                pcall(function()
                                    if onScreen and sx and sy then
                                        lbl.Text = "[" .. (S.ROLE_TAGS[role] or "AR") .. "]"
                                        lbl.Color = H.roleColor(role)
                                        lbl.Position = Vector2.new(sx, sy - 14)
                                        lbl.Visible = true
                                    else
                                        lbl.Visible = false
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end

        for id, obj in pairs(S.espDrawings) do
            if not active[id] then
                H.destroyDraw(obj)
                S.espDrawings[id] = nil
            end
        end
        for id, bb in pairs(S.espBillboards) do
            if not active[id] then
                pcall(function() bb:Destroy() end)
                S.espBillboards[id] = nil
            end
        end
    end

    function Sync.statusText(language)
        local ru = language == "RU"
        local cfg = H.syncCfg()
        if not cfg.enabled then return ru and "Статус: выключен" or "Status: disabled" end
        if H.effectiveUrl() == "" then return ru and "Статус: вставьте Sync URL" or "Status: set Sync URL" end
        if not H.resolveHttpRequest() then return ru and "Статус: HTTP API недоступен" or "Status: HTTP API unavailable" end
        if S.lastOkAt then
            local roleStr = cfg.stealth and (ru and "скрыт" or "stealth") or string.upper(tostring(S.selfRole or "free"))
            local memTag = S.storageMode == "memory-fallback" and " · RAM" or ""
            if ru then
                return string.format("Статус: онлайн (%s) · пиры: %d · Tab: %d%s", roleStr, S.badgeCount, S.tabCount, memTag)
            end
            return string.format("Status: online (%s) · peers: %d · Tab: %d%s", roleStr, S.badgeCount, S.tabCount, memTag)
        end
        return (ru and "Статус: " or "Status: ") .. tostring(S.statusNote or "Idle")
    end

    function Sync.buildNativeSection(language, section, T)
        local cfg = H.syncCfg()
        local statusLbl = section:new_label(Sync.statusText(language))
        local urlBox = section:new_textbox(T("Sync URL"), "Default (leave empty)", cfg.endpoint or "", function(v)
            local clean = H.trimStr(v):sub(1, 200)
            H.syncCfg().endpoint = clean
            Sync.onSettingsApplied()
        end)
        local assetBox = section:new_textbox(T("Logo asset ID"), "rbxassetid://123456789", cfg.logoAsset or "", function(v)
            local clean = H.trimStr(v):sub(1, 120)
            H.syncCfg().logoAsset = clean
            Sync.onSettingsApplied()
        end)
        local syncNowBtn = section:new_button(T("Sync now"), function()
            Sync.pollNow(true)
        end)
        local inspectBtn = section:new_button(T("Inspect Tab UI"), function()
            Sync.inspectTabUI()
        end)
        for _, h in ipairs({statusLbl, urlBox, assetBox, syncNowBtn, inspectBtn}) do
            pcall(function() h:set_visible(false) end)
        end
        S.nativeViews[language] = {
            statusLbl = statusLbl,
            urlBox = urlBox,
            assetBox = assetBox,
            syncNowBtn = syncNowBtn,
            inspectBtn = inspectBtn,
            lastStatus = Sync.statusText(language),
        }
    end

    function Sync.syncNativeWidgets(currentLang, currentPage)
        if S.lastVisibleLang == currentLang and S.lastVisiblePage == currentPage then return end
        S.lastVisibleLang = currentLang
        S.lastVisiblePage = currentPage
        for lang, w in pairs(S.nativeViews) do
            local vis = (lang == currentLang) and (currentPage == "Sync")
            for k, h in pairs(w) do
                if k ~= "lastStatus" then pcall(function() h:set_visible(vis) end) end
            end
        end
    end

    function Sync.hideAllViews()
        S.lastVisibleLang = nil
        S.lastVisiblePage = nil
        for _, w in pairs(S.nativeViews) do
            for k, h in pairs(w) do
                if k ~= "lastStatus" then pcall(function() h:set_visible(false) end) end
            end
        end
    end

    function Sync.updateNativeStatus(language)
        local w = S.nativeViews[language]
        if not w or not w.statusLbl then return end
        local text = Sync.statusText(language)
        if text == w.lastStatus then return end
        w.lastStatus = text
        pcall(function() w.statusLbl:set(text) end)
    end

    function Sync.onSettingsApplied()
        local cfg = H.syncCfg()
        S.cachedScoreboardRoot = nil
        if not cfg.enabled then
            S.peerBadges, S.badgeCount = {}, 0
            S.statusNote = "Disabled"
            H.clearTabBadges()
            H.clearEsp()
        else
            if not cfg.tabBadges then H.clearTabBadges() end
            if not cfg.espBadges then H.clearEsp() end
            S.nextPollAt = 0
            S.nextScanAt = 0
        end
        for _, w in pairs(S.nativeViews) do
            if w.urlBox then
                pcall(function()
                    if w.urlBox:get() ~= (cfg.endpoint or "") then w.urlBox:set(cfg.endpoint or "", true) end
                end)
            end
            if w.assetBox then
                pcall(function()
                    if w.assetBox:get() ~= (cfg.logoAsset or "") then w.assetBox:set(cfg.logoAsset or "", true) end
                end)
            end
        end
    end

    function Sync.pollNow(force)
        local cfg = H.syncCfg()
        if not cfg.enabled then S.statusNote = "Disabled"; return end
        local url = H.effectiveUrl()
        if url == "" then S.statusNote = "Set Sync URL"; return end
        local reqFn = H.resolveHttpRequest()
        if not reqFn then S.statusNote = "HTTP API unavailable"; return end
        if S.inFlight then return end
        local t = H.nowSafe()
        local gap = t - (S.lastAttemptAt or 0)
        if gap < S.MIN_POLL_GAP then
            local left = math.ceil(S.MIN_POLL_GAP - gap)
            S.statusNote = "Cooldown (" .. tostring(left) .. "s)"
            if force then S.nextPollAt = (S.lastAttemptAt or t) + S.MIN_POLL_GAP end
            return
        end
        H.startHttpPoll(url, reqFn)
    end

    function Sync.inspectTabUI()
        local function work()
            local playerGui = H.getPlayerGui()
            local myId, peerIds, _, meta = H.collectPlayers()
            print(string.format("[AR Sync] url=%s asset=%s myId=%s peers=%d role=%s storage=%s tabBadges=%d status=%s",
                H.effectiveUrl() == "" and "<unset>" or H.effectiveUrl(),
                H.effectiveAsset() == "" and "<text-fallback>" or H.effectiveAsset(),
                tostring(myId), #peerIds, tostring(S.selfRole), tostring(S.storageMode), S.tabCount, tostring(S.statusNote)))
            if not playerGui then
                print("[AR Sync] PlayerGui not accessible")
                return
            end
            local wantedAll = {}
            for id in pairs(meta) do wantedAll[id] = "free" end
            local byAvatarId, byName = H.buildMatchIndexes(wantedAll, meta)
            local okCh, topList = pcall(function() return playerGui:GetChildren() end)
            if okCh and type(topList) == "table" then
                for _, gui in ipairs(topList) do
                    local okCls, cls = pcall(function() return gui.ClassName end)
                    local okEn, en = pcall(function() return gui.Enabled end)
                    print(string.format("[AR Sync GUI] %s (%s) Enabled=%s", H.readNameSafe(gui), tostring(cls), tostring(en)))
                    if not H.shouldSkipNode(gui) then
                        local av, tx = H.scanRootForHosts(gui, playerGui, byAvatarId, byName)
                        for id, node in pairs(av) do
                            local m = meta[id]
                            print(string.format("[AR Sync MATCH] avatar id=%d (%s) -> %s.%s",
                                id, tostring(m and m.name), H.readNameSafe(gui), H.readNameSafe(node)))
                        end
                        for id, node in pairs(tx) do
                            local m = meta[id]
                            print(string.format("[AR Sync MATCH] text id=%d (%s) -> %s.%s",
                                id, tostring(m and m.name), H.readNameSafe(gui), H.readNameSafe(node)))
                        end
                    end
                end
            end
        end
        if type(task) == "table" and type(task.spawn) == "function" then
            task.spawn(work)
        else
            pcall(work)
        end
    end

    function Sync.tick(stopped)
        if stopped or not alive then return end
        local cfg = H.syncCfg()
        if not cfg.enabled then return end
        local t = H.nowSafe()
        local url = H.effectiveUrl()
        if url ~= "" then
            local reqFn = H.resolveHttpRequest()
            if reqFn and not S.inFlight and t >= S.nextPollAt and (t - (S.lastAttemptAt or 0)) >= S.MIN_POLL_GAP then
                H.startHttpPoll(url, reqFn)
            end
        end
        if cfg.tabBadges and not S.scanRunning and t >= S.nextScanAt then
            S.nextScanAt = t + S.SCAN_INTERVAL
            H.startTabScan(S.gen)
        end
        H.updateEsp()
    end

    function Sync.stop()
        S.gen = S.gen + 1
        S.inFlight = false
        S.scanRunning = false
        S.peerBadges = {}
        S.badgeCount = 0
        H.clearTabBadges()
        H.clearEsp()
        Sync.hideAllViews()
    end
end
local function preset(name)
    local result = defaults()
    if name == "Conservative" then
        result.resolver.mode, result.resolver.safe, result.resolver.bodyAfter = "Auto", true, 2
    elseif name == "Jitter builder" then
        result.builder.enabled = true
        for i, state in ipairs(STATES) do
            local p = result.builder.profiles[state]
            p.enabled = true
            p.yawMode = (state == "Air" or state == "Air crouch") and "3-Way" or "Center"
            p.amplitude, p.period = 20 + i * 3, 2 + i % 3
            p.pitchPeriod, p.yawPeriod, p.desyncPeriod = p.period, p.period, p.period
            p.left, p.right = 50 + i * 3, 50 + i * 3
        end
    end
    return validate(result)
end

function Builder.diagnose()
    local a = Builder.applied or {}
    print("[AR AA] build=" .. BUILD .. " enabled=" .. tostring(Settings.builder.enabled) .. " owned=" .. tostring(Builder.owned)
        .. " state=" .. tostring(Builder.state) .. " profile=" .. tostring(Builder.profile) .. " pause=" .. tostring(Builder.pause))
    print("[AR AA] requested tick=" .. tostring(Builder.lastTick) .. " pitch=" .. tostring(a.pitch) .. " yaw=" .. tostring(a.yaw)
        .. " base=" .. tostring(a.base) .. " desync=" .. tostring(a.desyncMode) .. " limits=" .. tostring(a.left) .. "/" .. tostring(a.right)
        .. " inverter=" .. tostring(a.inverter) .. " defensive=" .. tostring(a.defensive))
    if Builder.fault or Builder.releaseFault then print("[AR AA] fault=" .. tostring(Builder.fault or Builder.releaseFault)) end
    for _, name in ipairs({"get_pitch", "is_pitch_overridden", "get_yaw", "get_yaw_offset", "get_inverter", "get_desync_limits", "get_lby_deg", "get_fake_lby_deg", "get_choked_ticks"}) do
        if type(aa[name]) == "function" then
            local ok, first, second = pcall(aa[name])
            local value = "read error: " .. tostring(first)
            if ok then value = tostring(first) .. (second ~= nil and ("/" .. tostring(second)) or "") end
            print("[AR AA] readback " .. name .. "=" .. value)
        else print("[AR AA] readback " .. name .. "=API unavailable") end
    end
    return "AA diagnostics printed"
end





local UISettings = {language = "en", advanced = false}
local uiPreferenceKey = "antiresolver.ui.v1." .. tostring(localPlayer.UserId)
local okUI, storedUI = pcall(function() return database.read(uiPreferenceKey) end)
if okUI and type(storedUI) == "table" and storedUI.owner == tostring(localPlayer.UserId) then
    if storedUI.language == "en" or storedUI.language == "ru" then UISettings.language = storedUI.language end
    if type(storedUI.advanced) == "boolean" then UISettings.advanced = storedUI.advanced end
end
local UILanguage, UIExpanded = UISettings.language, UISettings.advanced
local Russian = {
    ["Auto DT"] = "Авто DT",
    ["DT series window"] = "Окно серии DT",
    ["Shot statistics"] = "Статистика выстрелов",
    ["Shot statistics printed"] = "Статистика выведена в консоль",
    ["Pitch step ticks"] = "Интервал pitch, тики",
    ["Yaw step ticks"] = "Интервал yaw, тики",
    ["Desync step ticks"] = "Интервал desync, тики",
    ["Desync mode"] = "Режим desync",
    ["Limits"] = "Лимиты",
    ["Explicit"] = "Явные углы",
    ["Real angle"] = "Реальный угол",
    ["Fake angle"] = "Фейковый угол",
    ["Sway"] = "Плавное колебание",
    ["Flick"] = "Флик",
    ["On shot"] = "После выстрела",
    ["Config task"] = "Раздел конфигов",
    ["My sets"] = "Мои сеты",
    ["Sharing"] = "Обмен кодом",
    ["Hold"] = "Удержание",
    ["Toggle"] = "Переключение",

    ["Resolver"] = "Резольвер",
    ["AA Builder"] = "Антиаимы",
    ["Configs"] = "Конфиги",
    ["Sync"] = "Синк",
    ["Main"] = "Основное",
    ["Status"] = "Состояние",
    ["State profile"] = "Профиль движения",
    ["Angles"] = "Углы",
    ["Transfer / examples"] = "Перенос и примеры",
    ["My saved sets"] = "Мои конфиги",
    ["AntiResolver · ready"] = "AntiResolver · готов",
    ["Ready"] = "Готово",
    ["Lua resolver"] = "Включить резольвер",
    ["Strategy"] = "Режим резольвера",
    ["Pitch handling"] = "Обработка наклона",
    ["Body aim after misses · 0 off"] = "На корпус после промахов · 0 — выкл.",
    ["Misses before cycling"] = "Промахов до смены угла",
    ["Learning half-life"] = "Время затухания обучения",
    ["Safe points on instability"] = "Безопасные точки при нестабильности",
    ["Reset learned opponent data"] = "Сбросить обучение противников",
    ["Log shot diagnostics"] = "Логировать выстрелы",
    ["Print resolver diagnostics"] = "Вывести диагностику в консоль",
    ["Resolver: ready"] = "Резольвер: готов",
    ["No active target"] = "Цели пока нет",
    ["Feedback: none"] = "Обратная связь: нет данных",
    ["Only resolver-reason misses train angle selection."] = "Перебор учитывает только промахи резольвера.",
    ["Edit state"] = "Состояние движения",
    ["Own state profile · otherwise Global"] = "Свой профиль · иначе общий",
    ["Copy from state"] = "Скопировать из состояния",
    ["Copy profile into edited state"] = "Скопировать настройки состояния",
    ["Edit section"] = "Обычные / дефенсив",
    ["AA: built-in cheat"] = "Антиаимы: встроенный чит",
    ["Slow movement threshold"] = "Порог медленного движения",
    ["State confirmation ticks"] = "Подтверждение состояния · тики",
    ["Pitch mode"] = "Режим наклона",
    ["Pitch A"] = "Наклон A",
    ["Pitch B"] = "Наклон B",
    ["Yaw base"] = "База поворота",
    ["Yaw offset"] = "Смещение поворота",
    ["Yaw modifier"] = "Режим поворота",
    ["Yaw amplitude"] = "Амплитуда поворота",
    ["Hold each step · ticks"] = "Длительность шага · тики",
    ["Spin · degrees/tick"] = "Кручение · градусов за тик",
    ["Sequence offsets · comma separated"] = "Углы последовательности через запятую",
    ["Apply sequence"] = "Применить последовательность",
    ["Left desync"] = "Десинк слева",
    ["Right desync"] = "Десинк справа",
    ["Inverter"] = "Сторона десинка",
    ["Fake lag"] = "Фейклаг",
    ["Choke limit"] = "Лимит задержки · тики",
    ["Choke variability"] = "Разброс задержки · %",
    ["Defensive enabled"] = "Включить дефенсив",
    ["Defensive activation"] = "Активация дефенсива",
    ["Defensive key · e.g. V or RightShift"] = "Клавиша дефенсива · например V",
    ["Trigger manual defensive now"] = "Активировать ручной дефенсив",
    ["Defensive duration · ticks"] = "Длительность дефенсива · тики",
    ["Defensive cooldown · ticks"] = "Пауза дефенсива · тики",
    ["Defensive pitch"] = "Режим наклона в дефенсиве",
    ["Defensive pitch A"] = "Наклон A в дефенсиве",
    ["Defensive pitch B"] = "Наклон B в дефенсиве",
    ["Defensive yaw offset"] = "Смещение поворота в дефенсиве",
    ["Defensive yaw amplitude"] = "Амплитуда поворота в дефенсиве",
    ["Defensive step ticks"] = "Шаг дефенсива · тики",
    ["Defensive tick shift · charged DT"] = "Сдвиг тиков · нужен заряд DT",
    ["Defensive shift ticks"] = "Количество сдвигаемых тиков",
    ["Flush choke at defensive end"] = "Сбросить задержку в конце дефенсива",
    ["Disabled state profiles inherit Global."] = "Выключенный профиль использует общий.",
    ["Set name"] = "Имя сета",
    ["Save current settings as my set"] = "Сохранить текущие настройки",
    ["Apply selected set"] = "Применить выбранный сет",
    ["Rename selected set to name field"] = "Переименовать в указанное имя",
    ["Delete selected set · press twice"] = "Удалить выбранный сет · нажать дважды",
    ["Only this Roblox account's sets are listed."] = "Здесь только сеты твоего аккаунта.",
    ["Database persistence after leaving the place is unconfirmed."] = "Хранение после выхода из плейса не подтверждено.",
    ["Bundled example"] = "Готовый пример",
    ["Apply bundled example"] = "Применить готовый пример",
    ["JSON · select/copy or paste"] = "JSON · скопируй или вставь",
    ["Export current settings to JSON field"] = "Экспортировать настройки в JSON",
    ["Import JSON as my set and apply"] = "Импортировать JSON и применить",
    ["No saved sets"] = "Сохранённых сетов нет",
    ["My set"] = "Мой сет",
    ["Auto"] = "Авто",
    ["Adaptive"] = "Адаптивный",
    ["Animation"] = "По анимации",
    ["Jitter"] = "Джиттер",
    ["Brute-force"] = "Перебор",
    ["Native"] = "Встроенный",
    ["Raw"] = "Исходный",
    ["Off"] = "Выкл.",
    ["Fixed"] = "Фиксированный",
    ["Random"] = "Случайный",
    ["Center"] = "Попеременный",
    ["3-Way"] = "Три позиции",
    ["5-Way"] = "Пять позиций",
    ["Spin"] = "Кручение",
    ["Sequence"] = "Последовательность",
    ["camera"] = "От камеры",
    ["world"] = "Мировая",
    ["Left"] = "Левая",
    ["Right"] = "Правая",
    ["Alternate"] = "Чередование",
    ["Charged"] = "По заряду DT",
    ["Manual"] = "Вручную",
    ["Global"] = "Общий",
    ["Standing"] = "Стоя",
    ["Moving"] = "Движение",
    ["Slow"] = "Медленно",
    ["Crouching"] = "Сидя",
    ["Crouch moving"] = "Движение сидя",
    ["Air"] = "В воздухе",
    ["Air crouch"] = "В воздухе сидя",
    ["Normal"] = "Обычные",
    ["Defensive"] = "Дефенсив",
    ["Balanced"] = "Базовый",
    ["Conservative"] = "Осторожный",
    ["Jitter builder"] = "Пример джиттера",
    [" sec"] = " сек",
    ["Advanced settings"] = "Расширенные настройки",
    ["Reload script to apply interface changes."] = "Перезагрузи луашку для изменения интерфейса.",
    ["Interface preference saved. Reload this script."] = "Настройка интерфейса сохранена. Перезагрузи луашку.",
    ["Language / Язык"] = "Язык / Language",
    ["Resolver disabled"] = "Резольвер выключен",
    ["Resolver error: see console"] = "Ошибка резольвера: смотри консоль",
    ["AA API error: see console"] = "Ошибка антиаимов: смотри консоль",
    ["AA: waiting for character"] = "Антиаимы: ожидание персонажа",
    ["targets"] = "целей",
    ["hits"] = "попаданий",
    ["misses"] = "промахов",
    ["Ignored"] = "Пропущено",
    ["unmapped shots"] = "выстрелов без цели",
    ["collecting"] = "сбор данных",
    ["tracking"] = "наблюдение",
    ["jitter"] = "джиттер",
    ["pitch"] = "колебания наклона",
    ["invalid angles"] = "нет корректных углов",
    ["Saved to your session store"] = "Сохранено в твоём хранилище сессии",
    ["Opponent data cleared"] = "Обучение противников сброшено",
    ["Defensive requested"] = "Дефенсив запрошен",
    ["Sequence applied"] = "Последовательность применена",
    ["Copy JSON from the field"] = "Скопируй JSON из поля",
    ["Selected set deleted"] = "Выбранный сет удалён",
    ["Name unchanged"] = "Имя не изменено",
    ["Diagnostics printed to Lua console"] = "Диагностика выведена в Lua-консоль",
    ["Copied"] = "Скопировано",
    ["to"] = "в",
    ["Applied"] = "Применён сет",
    ["Press delete again to confirm: "] = "Нажми удаление ещё раз для подтверждения: ",
    ["Select one of your sets"] = "Выбери один из своих сетов",
    ["Select a saved set"] = "Выбери сохранённый сет",
    ["Enable AA Builder first"] = "Сначала включи билдер антиаимов",
    ["Current live profile needs Manual defensive"] = "В активном профиле нужен ручной дефенсив",
    ["Invalid key name"] = "Некорректное имя клавиши",
    ["Sequence angles: -180..180"] = "Углы последовательности: от -180 до 180",
    ["Sequence needs 1–12 angles"] = "В последовательности нужно 1–12 углов",
    ["That name already exists"] = "Такое имя уже существует",
    ["Maximum 32 personal sets"] = "Можно сохранить не больше 32 сетов",
    ["Set needs a name"] = "Укажи имя сета",
    ["Name: 1–40 characters, no control characters"] = "Имя: 1–40 символов без управляющих знаков",
    ["Not an AntiResolver v2 set"] = "Это не сет AntiResolver v2",
    ["JSON is too large"] = "JSON слишком большой",
    ["Personal database unavailable"] = "Личное хранилище недоступно",
}
local function T(value)
    if UILanguage == "ru" and type(value) == "string" then return Russian[value] or value end
    return value
end
local function saveUISettings(language, advanced)
    assert(language == "ru" or language == "en", "Invalid interface language")
    assert(type(advanced) == "boolean", "Invalid interface mode")
    if language == UISettings.language and advanced == UISettings.advanced then return false end
    local current = database.read(uiPreferenceKey)
    assert(current == nil or (type(current) == "table" and current.owner == tostring(localPlayer.UserId)), "Interface settings owner mismatch")
    database.write(uiPreferenceKey, {owner = tostring(localPlayer.UserId), language = language, advanced = advanced})
    UISettings.language, UISettings.advanced = language, advanced
    if type(database.flush) == "function" then
        local ok, err = pcall(database.flush)
        if not ok then warn("[AntiResolver] Interface flush failed: " .. tostring(err)) end
    end
    return true
end
local AdvancedControls = {
    ["Rename selected set to name field"] = true,
    ["Bundled example"] = true,
    ["Apply bundled example"] = true,
    ["Pitch handling"] = true,
    ["Misses before cycling"] = true,
    ["Learning half-life"] = true,
    ["Safe points on instability"] = true,
    ["Reset learned opponent data"] = true,
    ["Log shot diagnostics"] = true,
    ["Print resolver diagnostics"] = true,
    ["No active target"] = true,
    ["Feedback: none"] = true,
    ["Only resolver-reason misses train angle selection."] = true,
    ["Copy from state"] = true,
    ["Copy profile into edited state"] = true,
    ["Slow movement threshold"] = true,
    ["State confirmation ticks"] = true,
    ["Yaw base"] = true,
    ["Hold each step · ticks"] = true,
    ["Spin · degrees/tick"] = true,
    ["Sequence offsets · comma separated"] = true,
    ["Apply sequence"] = true,
    ["Defensive key · e.g. V or RightShift"] = true,
    ["Trigger manual defensive now"] = true,
    ["Defensive pitch A"] = true,
    ["Defensive pitch B"] = true,
    ["Defensive step ticks"] = true,
    ["Defensive tick shift · charged DT"] = true,
    ["Defensive shift ticks"] = true,
    ["Flush choke at defensive end"] = true,
    ["JSON · select/copy or paste"] = true,
    ["Export current settings to JSON field"] = true,
    ["Import JSON as my set and apply"] = true,
}
local function includeControl(title) return UIExpanded or not AdvancedControls[title] end

local ShortCaptions = {
    ["Page"] = {ru = "Раздел", en = "Section"},
    ["Settings"] = {ru = "Настройки", en = "Settings"},
    ["Body aim after misses · 0 off"] = {ru = "Корпус: промахи", en = "Body after misses"},
    ["Pitch handling"] = {ru = "Обработка pitch", en = "Pitch handling"},
    ["Misses before cycling"] = {ru = "Смена после промахов", en = "Cycle after misses"},
    ["Learning half-life"] = {ru = "Память, сек.", en = "Memory, sec."},
    ["Safe points on instability"] = {ru = "Безопасные точки", en = "Safe points"},
    ["Reset learned opponent data"] = {ru = "Сбросить обучение", en = "Reset learning"},
    ["Log shot diagnostics"] = {ru = "Лог выстрелов", en = "Shot logging"},
    ["Print resolver diagnostics"] = {ru = "Диагностика", en = "Diagnostics"},
    ["Strategy"] = {ru = "Режим", en = "Mode"},
    ["Lua resolver"] = {ru = "Резольвер", en = "Resolver"},
    ["Own state profile · otherwise Global"] = {ru = "Использовать свой профиль", en = "Use own profile"},
    ["Edit state"] = {ru = "Редактировать профиль", en = "Edit profile"},
    ["Copy from state"] = {ru = "Копировать из", en = "Copy from"},
    ["Copy profile into edited state"] = {ru = "Копировать профиль", en = "Copy profile"},
    ["Edit section"] = {ru = "Тип настроек", en = "Settings type"},
    ["Slow movement threshold"] = {ru = "Порог медл. хода", en = "Slow speed"},
    ["State confirmation ticks"] = {ru = "Смена, тики", en = "State delay, ticks"},
    ["Pitch mode"] = {ru = "Режим pitch", en = "Pitch mode"},
    ["Pitch A"] = {ru = "Pitch A", en = "Pitch A"},
    ["Pitch B"] = {ru = "Pitch B", en = "Pitch B"},
    ["Yaw base"] = {ru = "База yaw", en = "Yaw base"},
    ["Yaw offset"] = {ru = "Смещение yaw", en = "Yaw offset"},
    ["Yaw modifier"] = {ru = "Режим yaw", en = "Yaw mode"},
    ["Yaw amplitude"] = {ru = "Амплитуда yaw", en = "Yaw amplitude"},
    ["Hold each step · ticks"] = {ru = "Шаг, тики", en = "Step, ticks"},
    ["Spin · degrees/tick"] = {ru = "Скорость спина", en = "Spin speed"},
    ["Sequence offsets · comma separated"] = {ru = "Углы через запятую", en = "Sequence angles"},
    ["Apply sequence"] = {ru = "Применить углы", en = "Apply sequence"},
    ["Left desync"] = {ru = "Десинк слева", en = "Left desync"},
    ["Right desync"] = {ru = "Десинк справа", en = "Right desync"},
    ["Choke limit"] = {ru = "Задержка, тики", en = "Choke, ticks"},
    ["Choke variability"] = {ru = "Разброс, %", en = "Variation, %"},
    ["Defensive enabled"] = {ru = "Дефенсив", en = "Defensive"},
    ["Defensive activation"] = {ru = "Запуск", en = "Activation"},
    ["Defensive key · e.g. V or RightShift"] = {ru = "Клавиша дефенсива", en = "Defensive key"},
    ["Trigger manual defensive now"] = {ru = "Запустить дефенсив", en = "Trigger defensive"},
    ["Defensive duration · ticks"] = {ru = "Длительность, тики", en = "Duration, ticks"},
    ["Defensive cooldown · ticks"] = {ru = "Пауза, тики", en = "Cooldown, ticks"},
    ["Defensive pitch"] = {ru = "Д: режим pitch", en = "Def pitch mode"},
    ["Defensive pitch A"] = {ru = "Д: pitch A", en = "Def pitch A"},
    ["Defensive pitch B"] = {ru = "Д: pitch B", en = "Def pitch B"},
    ["Defensive yaw offset"] = {ru = "Д: yaw", en = "Def yaw offset"},
    ["Defensive yaw amplitude"] = {ru = "Д: амплитуда", en = "Def yaw amplitude"},
    ["Defensive step ticks"] = {ru = "Д: шаг, тики", en = "Def step, ticks"},
    ["Defensive tick shift · charged DT"] = {ru = "Сдвиг тиков", en = "Tick shift"},
    ["Defensive shift ticks"] = {ru = "Сдвиг, тики", en = "Shift, ticks"},
    ["Flush choke at defensive end"] = {ru = "Сброс в конце", en = "Flush at end"},
    ["Save current settings as my set"] = {ru = "Сохранить сет", en = "Save set"},
    ["Apply selected set"] = {ru = "Загрузить сет", en = "Load set"},
    ["Rename selected set to name field"] = {ru = "Переименовать", en = "Rename set"},
    ["Delete selected set · press twice"] = {ru = "Удалить: дважды", en = "Delete: twice"},
    ["Export current settings to JSON field"] = {ru = "Экспорт JSON", en = "Export JSON"},
    ["Import JSON as my set and apply"] = {ru = "Импорт JSON", en = "Import JSON"},
    ["Apply bundled example"] = {ru = "Применить пример", en = "Apply example"},
    ["Only this Roblox account's sets are listed."] = {ru = "Только твои сеты.", en = "Only your sets."},
    ["Database persistence after leaving the place is unconfirmed."] = {ru = "Сеты: память сессии.", en = "Sets: session storage."},
    ["Reload script to apply interface changes."] = {ru = "Язык и вид: нужен перезапуск.", en = "Language/view need reload."},
}
local function Caption(value)
    local entry = ShortCaptions[value]
    return entry and entry[UILanguage] or T(value)
end

Russian["Select action"] = "Выбери действие"
ShortCaptions["Set action"] = {ru = "Действие с сетом", en = "Set action"}
ShortCaptions["Resolver action"] = {ru = "Действие", en = "Resolver action"}
ShortCaptions["AA action"] = {ru = "Действие AA", en = "AA action"}

local function Translate(value, language)
    return language == "ru" and type(value) == "string" and (Russian[value] or value) or value
end
local function LocalCaption(value, language)
    local entry = ShortCaptions[value]
    return entry and entry[language] or Translate(value, language)
end
ShortCaptions["Pitch A"].ru = "Наклон A"
ShortCaptions["Pitch B"].ru = "Наклон B"
Russian["AA diagnostics"] = "Диагностика AA"
Russian["Share code"] = "Код сета"
Russian["Generate share code"] = "Получить код сета"
Russian["Load share code"] = "Загрузить код сета"

Russian["Config name"] = "Название конфига"
Russian["Save"] = "Сохранить"
Russian["Load"] = "Загрузить"
Russian["Delete"] = "Удалить"
Russian["Enable sync"] = "Включить синк"
Russian["Sync URL"] = "URL сервера"
Russian["Logo asset ID"] = "ID логотипа"
Russian["Tab badges"] = "Значок в табе"
Russian["3D ESP badges"] = "Значок в 3D ESP"
Russian["Stealth mode"] = "Скрытый режим"
Russian["Sync now"] = "Обновить сейчас"
Russian["Inspect Tab UI"] = "Скан Tab UI"
Russian["Import"] = "Импорт"
Russian["Import code"] = "Код для импорта"
Russian["Share code"] = "Код для друга"



requireAPI(menu,"new_tab")
local rootTab=menu.new_tab("AntiResolver","rbxassetid://10734975692")
local rootLeft=rootTab:new_section("AntiResolver","Left")
local rootRight=rootTab:new_section("Options / Настройки","Right")
local uiStopped=false
local views={}
local activeLanguage=UISettings.language
local selectLanguage
local languageHandle
languageHandle=rootRight:new_combobox("Language / Язык",{"English","Русский"},activeLanguage=="ru" and "Русский" or "English",function(value)
    if uiStopped then return end
    local language=value=="Русский" and "ru" or (value=="English" and "en" or nil)
    if language and language~=activeLanguage and selectLanguage then selectLanguage(language) end
end)
local lifeConnection
pcall(function() lifeConnection=localPlayer.CharacterAdded:Connect(function() Builder.release() end) end)
client.set_event_callback("shutdown",function()
    if uiStopped then return end
    uiStopped=true
    for _,view in pairs(views) do view.hide() end
    Builder.release();Resolver.stop();Sync.stop()
    if lifeConnection then pcall(function() lifeConnection:Disconnect() end) end
end)
local function buildView(language)
local view={active=false}
local UILanguage=language
local function T(value) return Translate(value,language) end
local function Caption(value) return LocalCaption(value,language) end
local function includeControl() return true end

requireAPI(menu, "new_tab")
local controls, syncing = {}, true
local page, editState, editPart = "Resolver", "Global", "Normal"
local copyState, selectedSet, nameDraft = "Global", library.last, library.last or ""
local sequenceDraft, importDraft, shareCode, shareSelection = "", "", "", nil
local nameEdited = false
local syncControls, syncVisibility, rebuildPicker, refreshConfigs
local message = startupNote or "Ready"
local setPicker, setPickerSignature
local actions, actionMenus = {}, {}
local refreshActions
local updatingActions = false
local reported = {}
local function reportOnce(key, detail)
    if not reported[key] then
        reported[key] = true
        warn("[AntiResolver UI] " .. key .. ": " .. tostring(detail))
    end
end
local function readNative(handle, title)
    if handle ~= nil then
        local ok, value = pcall(function() return handle:get() end)
        if ok then return value end
        if type(ui) == "table" and type(ui.get) == "function" then
            local fallback, result = pcall(ui.get, handle)
            if fallback then return result end
        end
        reportOnce("read " .. title, value)
    else
        reportOnce("read " .. title, "constructor returned nil")
    end
    return nil
end
local function writeNative(handle, value, title)
    if handle ~= nil then
        local ok, err = pcall(function() handle:set(value, true) end)
        if ok then return true end
        
        
        if type(ui) == "table" and type(ui.set) == "function" then
            local fallback = pcall(ui.set, handle, value)
            if fallback then return true end
        end
        reportOnce("set " .. title, err)
    else
        reportOnce("set " .. title, "constructor returned nil; cannot update this displayed value")
    end
    return false
end
local function visibleNative(handle, value, title)
    if handle == nil then return false end
    local ok, err = pcall(function() handle:set_visible(value) end)
    if not ok then reportOnce("visibility " .. title, err) end
    return ok
end


local left, right = rootLeft, rootRight
local routes = {Resolver={left=left,right=right},["AA Builder"]={left=left,right=right},Configs={left=left,right=right},Sync={left=left,right=right}}
local function route(section, group) return section end
local function say(text)
    message = T(tostring(text))
    print("[AntiResolver] " .. message)
end
local function invoke(fn)
    return function(...)
        if uiStopped or not view.active or syncing then return end
        local ok, result = pcall(fn, ...)
        if ok then if result then say(result) end else say(result); warn("[AntiResolver] " .. tostring(result)) end
        if syncVisibility then syncVisibility() end
    end
end
local function record(handle, getter, section, predicate, title, create)
    controls[#controls + 1] = {handle = handle, get = getter, section = section, visible = predicate,
        title = title or section, create = create, created = create == nil}
    return handle
end
local function bind(kind, section, title, getter, setter, args, predicate)
    local handle
    local callback = function(value)
        if not syncing and not uiStopped and view.active then
            local ok, err = pcall(function()
                
                
                local validValue = (kind == "toggle" and type(value) == "boolean")
                    or (kind == "slider" and finite(value))
                    or (kind == "color" and value ~= nil)
                    or ((kind == "choice" or kind == "text" or kind == "display") and type(value) == "string")
                if not validValue then value = readNative(handle, title) end
                assert(value ~= nil, "No callback value or readable native handle: " .. title)
                if kind == "choice" then
                    local mapped
                    for _, raw in ipairs(args) do
                        if value == raw or value == T(raw) then mapped = raw; break end
                    end
                    assert(mapped, "Unknown UI choice: " .. tostring(value))
                    value = mapped
                end
                
                if value == getter() then return end
                if kind == "display" then
                    syncing = true
                    local restored = writeNative(handle, getter(), title)
                    syncing = false
                    assert(restored, "Cannot restore share-code field")
                    return
                end
                
                
                for _, item in ipairs(controls) do
                    if item.handle == handle then
                        item.lastValue = kind == "choice" and T(value) or value
                        break
                    end
                end
                setter(value)
            end)
            if not ok then
                say(err)
                syncing = true; writeNative(handle, kind == "choice" and T(getter()) or getter(), title); syncing = false
            end
            if syncVisibility then syncVisibility() end
        end
    end
    if kind == "toggle" then handle = section:new_toggle(Caption(title), getter(), callback)
    elseif kind == "choice" then
        local translated = {}
        for _, raw in ipairs(args) do translated[#translated + 1] = T(raw) end
        handle = section:new_combobox(Caption(title), translated, T(getter()), callback)
    elseif kind == "color" then handle = section:new_colorpicker(Caption(title), getter(), callback)
    elseif kind == "slider" then handle = section:new_slider(Caption(title), args[1], args[2], getter(), args[3] or 0, T(args[4] or ""), callback)
    else handle = section:new_textbox(Caption(title), "", getter(), callback) end
    if handle == nil then reportOnce("constructor " .. title, kind .. " returned nil; callback values will still be accepted") end
    return handle
end
local function element(kind, section, group, title, getter, setter, args, predicate)
    if not includeControl(title) then return nil end
    local displayGetter = function() return kind == "choice" and T(getter()) or getter() end
    return record(nil, displayGetter, group, predicate, title, function()
        return bind(kind, route(section, group), title, getter, setter, args, predicate)
    end)
end
local function button(section, group, title, fn, predicate)
    if not includeControl(title) then return nil end
    actions[group] = actions[group] or {}
    actions[group][#actions[group] + 1] = {title = title, run = fn, visible = predicate}
    return nil
end
local function label(section, group, value, predicate)
    
    
    if group ~= "Always" or not includeControl(value) then return nil end
    return record(section:new_label(Caption(value)), nil, group, predicate, value)
end
local function profile() return Settings.builder.profiles[editState] end
local function defense() return profile().defensive end
local function prepareProfile()
    local values = {}
    for _, angle in ipairs(profile().sequence) do values[#values + 1] = tostring(angle) end
    sequenceDraft = table.concat(values, ", ")
end
element("choice", left, "Always", "Page", function() return page end,
    function(value) page=value;syncVisibility();Sync.syncNativeWidgets(language, page) end, {"Resolver","AA Builder","Configs","Sync"})
element("toggle", right, "Always", "Advanced settings", function() return UISettings.advanced end,
    function(v) saveUISettings(activeLanguage,v);syncVisibility() end)


element("toggle", left, "Resolver", "Lua resolver", function() return Options.enabled end, Resolver.setEnabled)
element("choice", left, "Resolver", "Strategy", function() return Options.mode end,
    Resolver.setMode, MODES)
element("slider", left, "Resolver", "DT series window", function() return Options.dtWindowMs end,
    function(v) Options.dtWindowMs = v end, {50,250,0," ms"}, function() return Options.mode == "Auto DT" end)
element("choice", left, "Resolver", "Pitch handling", function() return Options.pitch end,
    function(v) Options.pitch = v end, {"Auto", "Raw", "Off"})
element("slider", left, "Resolver", "Body aim after misses · 0 off", function() return Options.bodyAfter end,
    function(v) Options.bodyAfter = v end, {0, 5})
element("slider", left, "Resolver", "Misses before cycling", function() return Options.cycleAfter end,
    function(v) Options.cycleAfter = v end, {1, 5})
element("slider", left, "Resolver", "Learning half-life", function() return Options.memory end,
    function(v) Options.memory = v end, {3, 60, 0, " sec"})
element("toggle", left, "Resolver", "Safe points on instability", function() return Options.safe end,
    function(v) Options.safe = v end, nil)
button(left, "Resolver", "Reset learned opponent data", function() Resolver.clear(); return "Opponent data cleared" end)

button(left, "Resolver", "Print resolver diagnostics", Resolver.diagnose)
button(left, "Resolver", "Shot statistics", Resolver.shotStatistics)
button(left, "AA Builder", "AA diagnostics", Builder.diagnose)
local resolverLabel = label(right, "Resolver", "Resolver: ready")
local targetLabel = label(right, "Resolver", "No active target")
local feedbackLabel = label(right, "Resolver", "Feedback: none")
label(right, "Resolver", "Only resolver-reason misses train angle selection.")

element("toggle", left, "AA Builder", "AA Builder", function() return Settings.builder.enabled end, Builder.setEnabled)
element("choice", left, "AA Builder", "Edit state", function() return editState end,
    function(v) editState = v; prepareProfile(); syncControls() end, STATES)
element("toggle", left, "AA Builder", "Own state profile · otherwise Global", function() return profile().enabled end,
    function(v) profile().enabled = v end, nil, function() return editState ~= "Global" end)
element("choice", left, "AA Builder", "Copy from state", function() return copyState end,
    function(v) copyState = v end, STATES)
button(left, "AA Builder", "Copy profile into edited state", function()
    Settings.builder.profiles[editState] = clone(Settings.builder.profiles[copyState])
    if editState == "Global" then profile().enabled = true end
    Builder.release(); prepareProfile(); syncControls()
    return T("Copied") .. " " .. T(copyState) .. " " .. T("to") .. " " .. T(editState)
end)
element("choice", left, "AA Builder", "Edit section", function() return editPart end,
    function(v) editPart = v; syncVisibility() end, {"Normal", "Defensive"})
local builderLabel = label(left, "AA Builder", "AA: built-in cheat")
element("slider", left, "AA Builder", "Slow movement threshold", function() return Settings.builder.slow end,
    function(v) Settings.builder.slow = v end, {0, 30})
element("slider", left, "AA Builder", "State confirmation ticks", function() return Settings.builder.hysteresis end,
    function(v) Settings.builder.hysteresis = v end, {1, 12})
local function ownProfile() return editState == "Global" or profile().enabled end
local function normal() return ownProfile() and editPart == "Normal" end
local function defensive() return ownProfile() and editPart == "Defensive" end
local function pchoice(title, field, values)
    element("choice", right, "AA Builder", title, function() return profile()[field] end,
        function(v) profile()[field] = v end, values, normal)
end
local function pslider(title, field, low, high, predicate)
    element("slider", right, "AA Builder", title, function() return profile()[field] end,
        function(v) profile()[field] = v end, {low, high}, predicate or normal)
end
pchoice("Pitch mode", "pitchMode", {"Fixed", "Jitter", "Random", "Sway", "Flick"})
pslider("Pitch A", "pitchA", -89, 89)
pslider("Pitch B", "pitchB", -89, 89)
pchoice("Yaw base", "yawBase", {"camera", "world"})
pslider("Yaw offset", "yawOffset", -180, 180)
pchoice("Yaw modifier", "yawMode", {"Off", "Center", "3-Way", "5-Way", "Spin", "Random", "Sequence"})
pslider("Yaw amplitude", "amplitude", 0, 180)
pslider("Pitch step ticks", "pitchPeriod", 1, 64, function() return normal() and profile().pitchMode ~= "Fixed" end)
pslider("Yaw step ticks", "yawPeriod", 1, 64, function() return normal() and profile().yawMode ~= "Off" end)
pslider("Spin · degrees/tick", "spinSpeed", -30, 30, function() return normal() and profile().yawMode == "Spin" end)
local function sequenceVisible() return normal() and profile().yawMode == "Sequence" end
element("text", right, "AA Builder", "Sequence offsets · comma separated", function() return sequenceDraft end,
    function(v) sequenceDraft = v end, nil, sequenceVisible)
button(right, "AA Builder", "Apply sequence", function()
    local values = {}
    for token in sequenceDraft:gmatch("[^,]+") do
        local value = tonumber(token)
        assert(finite(value) and value >= -180 and value <= 180, "Sequence angles: -180..180")
        values[#values + 1] = value
    end
    assert(#values >= 1 and #values <= 12, "Sequence needs 1–12 angles")
    profile().sequence = values
    return "Sequence applied"
end, sequenceVisible)
local function limitsVisible() return normal() and profile().desyncMode == "Limits" end
pslider("Left desync", "left", 0, 86, limitsVisible)
pslider("Right desync", "right", 0, 86, limitsVisible)
pchoice("Desync mode", "desyncMode", {"Limits", "Explicit"})
local function explicitVisible() return normal() and profile().desyncMode == "Explicit" end
pslider("Real angle", "real", -86, 86, explicitVisible)
pslider("Fake angle", "fake", -86, 86, explicitVisible)
pchoice("Inverter", "inverter", {"Left", "Right", "Alternate"})
pslider("Desync step ticks", "desyncPeriod", 1, 64)

element("toggle", right, "AA Builder", "Fake lag", function() return profile().fakeLag end,
    function(v) profile().fakeLag = v end, nil, normal)
pslider("Choke limit", "lagLimit", 0, 14, function() return normal() and profile().fakeLag end)
pslider("Choke variability", "lagVariation", 0, 100, function() return normal() and profile().fakeLag end)
element("toggle", right, "AA Builder", "Defensive enabled", function() return defense().enabled end,
    function(v) defense().enabled = v end, nil, defensive)
element("choice", right, "AA Builder", "Defensive activation", function() return defense().trigger end,
    function(v) defense().trigger = v end, {"Charged", "Manual", "On shot"}, defensive)
element("text", left, "AA Builder", "Defensive key · e.g. V or RightShift", function() return Settings.builder.manualKey end,
    function(v)
        assert(type(v) == "string" and #v >= 1 and #v <= 24 and v:match("^[A-Za-z0-9]+$"), "Invalid key name")
        Settings.builder.manualKey = v
    end)
button(left, "AA Builder", "Trigger manual defensive now", function()
    assert(Settings.builder.enabled, "Enable AA Builder first")
    local activeProfile = Settings.builder.profiles[Builder.profile]
    if not activeProfile or (Builder.profile ~= "Global" and not activeProfile.enabled) then
        activeProfile = Settings.builder.profiles.Global
    end
    local live = activeProfile.defensive
    assert(live.enabled and live.trigger == "Manual", "Current live profile needs Manual defensive")
    Builder.requested = true
    return "Defensive requested"
end)
local function dslider(title, field, low, high)
    element("slider", right, "AA Builder", title, function() return defense()[field] end,
        function(v) defense()[field] = v end, {low, high}, defensive)
end
dslider("Defensive duration · ticks", "duration", 1, 16)
dslider("Defensive cooldown · ticks", "cooldown", 0, 512)
element("choice", right, "AA Builder", "Defensive pitch", function() return defense().pitchMode end,
    function(v) defense().pitchMode = v end, {"Fixed", "Jitter", "Random"}, defensive)
dslider("Defensive pitch A", "pitchA", -89, 89)
dslider("Defensive pitch B", "pitchB", -89, 89)
dslider("Defensive yaw offset", "yawOffset", -180, 180)
dslider("Defensive yaw amplitude", "amplitude", 0, 180)
dslider("Defensive step ticks", "period", 1, 16)
element("toggle", right, "AA Builder", "Defensive tick shift · charged DT", function() return defense().shift end,
    function(v) defense().shift = v end, nil, defensive)
dslider("Defensive shift ticks", "shiftTicks", 1, 14)
element("toggle", right, "AA Builder", "Flush choke at defensive end", function() return defense().flush end,
    function(v) defense().flush = v end, nil, defensive)
label(right, "AA Builder", "Disabled state profiles inherit Global.", function() return not ownProfile() end)

element("toggle", left, "Sync", "Enable sync", function() return Settings.sync and Settings.sync.enabled ~= false end,
    function(v) Settings.sync.enabled = v; Sync.onSettingsApplied(); syncControls() end)
element("toggle", left, "Sync", "Tab badges", function() return Settings.sync and Settings.sync.tabBadges ~= false end,
    function(v) Settings.sync.tabBadges = v; Sync.onSettingsApplied() end)
element("toggle", left, "Sync", "3D ESP badges", function() return Settings.sync and Settings.sync.espBadges ~= false end,
    function(v) Settings.sync.espBadges = v; Sync.onSettingsApplied() end)
element("toggle", left, "Sync", "Stealth mode", function() return Settings.sync and Settings.sync.stealth == true end,
    function(v) Settings.sync.stealth = v; Sync.onSettingsApplied() end)
Sync.buildNativeSection(language, right, T)

refreshConfigs = function()
    local names = Store.list()
    if not table.find(names, selectedSet) then
        selectedSet = names[1]
        if not nameEdited then nameDraft = selectedSet or "" end
    end
    if shareSelection ~= selectedSet then
        shareCode = selectedSet and Store.encodeCode(Store.get(selectedSet), selectedSet) or ""
        shareSelection = selectedSet
    end
    return names
end
local function configButton(section, title, fn)
    record(nil, nil, "Configs", nil, title, function()
        local handle = section:new_button(Caption(title), invoke(function()
            if page ~= "Configs" then return end
            return fn()
        end))
        assert(handle ~= nil, "Native button returned nil: " .. title)
        return handle
    end)
end
element("text", left, "Configs", "Config name", function() return nameDraft end,
    function(v) nameDraft = v; nameEdited = true end)
configButton(left, "Save", function()
    local result, name = Store.save(nameDraft, Settings)
    selectedSet, nameDraft, nameEdited, shareSelection = name, name, false, nil
    refreshConfigs(); rebuildPicker(); syncControls()
    return result
end)
configButton(left, "Load", function()
    assert(selectedSet, "Select one of your saved sets")
    applySettings(Store.use(selectedSet))
    nameDraft, nameEdited = selectedSet, false
    prepareProfile(); syncControls()
    return T("Applied") .. " " .. selectedSet
end)
configButton(left, "Delete", function()
    assert(selectedSet, "Select a saved set")
    local result = Store.delete(selectedSet)
    selectedSet, nameDraft, nameEdited, shareSelection = nil, "", false, nil
    shareCode = ""
    refreshConfigs(); rebuildPicker(); syncControls()
    return result
end)
element("display", right, "Configs", "Share code", function() return shareCode end)
element("text", right, "Configs", "Import code", function() return importDraft end,
    function(v) importDraft = v end)
configButton(right, "Import", function()
    local value, encodedName = Store.decodeCode(importDraft)
    local base = nameEdited and nameDraft:match("%S") and validateName(nameDraft) or encodedName or "Imported config"
    local name, suffix = base, 1
    while library.sets[name] do
        suffix = suffix + 1
        local ending = " (" .. suffix .. ")"
        name = ((utf8.len(base) + #ending <= 40) and base or "Imported config") .. ending
    end
    local result = Store.save(name, value)
    applySettings(value)
    selectedSet, nameDraft, nameEdited, shareSelection = name, name, false, nil
    importDraft = ""
    refreshConfigs(); rebuildPicker(); prepareProfile(); syncControls()
    return result
end)

rebuildPicker = function()
    if not view.active or page ~= "Configs" then return end
    local names = refreshConfigs()
    local options = #names > 0 and names or {T("No saved sets")}
    local signature = table.concat(options, "\n")
    if signature == setPickerSignature then
        if setPicker then writeNative(setPicker, selectedSet or options[1], "saved-set picker") end
        return
    end
    visibleNative(setPicker, false, "saved-set picker")
    setPickerSignature = signature
    local handle
    local previousSync = syncing
    syncing = true
    handle = routes.Configs.left:new_combobox(T("My saved sets"), options, selectedSet or options[1], invoke(function(value)
        if page ~= "Configs" then return end
        if type(value) ~= "string" then value = readNative(handle, "saved-set picker") end
        if library.sets[value] and value ~= selectedSet then
            selectedSet, nameDraft, nameEdited = value, value, false
            refreshConfigs(); syncControls()
        end
    end))
    setPicker = handle
    syncing = previousSync
end
refreshActions = function()
    if updatingActions or uiStopped then return end
    updatingActions = true
    local ok, err = pcall(function()
    for _, group in ipairs({"Resolver", "AA Builder"}) do
        local entry = actionMenus[group] or {}
        actionMenus[group] = entry
        local allowed, options = {}, {T("Select action")}
        for _, action in ipairs(actions[group] or {}) do
            if (UISettings.advanced or not AdvancedControls[action.title]) and (not action.visible or action.visible()) then
                allowed[Caption(action.title)] = action
                options[#options + 1] = Caption(action.title)
            end
        end
        local signature = table.concat(options, "\n")
        if view.active and page == group and #options > 1 and signature ~= entry.signature then
            visibleNative(entry.handle, false, group)
            entry.variants = entry.variants or {}
            local cached = entry.variants[signature]
            if cached then
                entry.handle, entry.signature = cached.handle, signature
                local previous = syncing
                syncing = true
                writeNative(entry.handle, T("Select action"), group)
                syncing = previous
            else
            local handle
            local previous = syncing
            syncing = true
            local title = group == "Resolver" and "Resolver action" or "AA action"
            handle = left:new_combobox(Caption(title), options, options[1], function(value)
                if syncing or updatingActions or uiStopped or not view.active or page ~= group or entry.signature ~= signature then return end
                if type(value) ~= "string" then value = readNative(handle, title) end
                local selected = allowed[value]
                if not selected then return end
                invoke(selected.run)()
                local wasSyncing = syncing
                syncing = true
                writeNative(handle, T("Select action"), title)
                syncing = wasSyncing
            end)
            entry.handle, entry.signature = handle, signature
            entry.variants[signature] = {handle=handle}
            syncing = previous
            end
            entry.shown = nil
        end
        local wanted = view.active and page == group and #options > 1
        if entry.shown ~= wanted then visibleNative(entry.handle, wanted, group);entry.shown=wanted end
    end
    end)
    updatingActions = false
    if not ok then reportOnce("action menu", err) end
end
syncVisibility = function()
    if uiStopped then return end
    if view.active and page == "Configs" then rebuildPicker() end
    for _, item in ipairs(controls) do
        local wanted = view.active and (item.section == "Always" or item.section == page)
            and (UISettings.advanced or not AdvancedControls[item.title]) and (not item.visible or item.visible())
        if wanted and not item.created then
            local previous = syncing
            syncing = true
            local ok, handle = pcall(item.create)
            syncing = previous
            item.created = true
            if ok then item.handle = handle else reportOnce("constructor " .. item.title, handle) end
            if item.get then item.lastValue = item.get() end
        end
        if item.created and item.shown ~= wanted then
            visibleNative(item.handle, wanted, item.title)
            item.shown = wanted
        end
    end
    visibleNative(setPicker, view.active and page == "Configs", "saved-set picker")
    refreshActions()
end
syncControls = function()
    if uiStopped then return end
    syncing = true
    for _, item in ipairs(controls) do
        if item.created and item.get then
            local value = item.get()
            if value ~= item.lastValue then
                if writeNative(item.handle, value, item.title) then item.lastValue = value end
            end
        end
    end
    syncing = false
    syncVisibility()
end
prepareProfile(); rebuildPicker(); syncing = false; syncControls()

local function localizedResolverStatus()
    if Resolver.fault then return T("Resolver error: see console") end
    if not Options.enabled then return T("Resolver disabled") end
    local count = 0
    for _ in pairs(states) do count = count + 1 end
    return string.format("%s · %d %s · %d %s / %d %s", T(Options.mode), count, T("targets"), Resolver.hits, T("hits"), Resolver.misses, T("misses"))
end
local function localizedTargetStatus()
    local target = rage.get_target()
    local state = target and (stateForPlayer(target.player) or fromEvent(target.slot))
    if not state then return T("No active target") end
    return tostring(state.player.Name or "Target") .. " · " .. T(state.strategy or "collecting") .. " · " .. T(state.phase)
end
local function localizedBuilderStatus()
    if Builder.fault then return T("AA API error: see console") end
    if not Settings.builder.enabled then return T("AA: built-in cheat") end
    if not Builder.state then return T("AA: waiting for character") end
    return T(Builder.state) .. " / " .. T(Builder.profile) .. (Builder.defense and " / " .. T("Defensive") or "")
end
local previousEnabled, previousBuilderEnabled = Options.enabled, Settings.builder.enabled
local nextLabelUpdate = 0
local function updateViewPaint()
    if resolverLabel then writeNative(resolverLabel, localizedResolverStatus(), "resolver status") end
    if targetLabel then writeNative(targetLabel, localizedTargetStatus(), "target status") end
    if builderLabel then writeNative(builderLabel, localizedBuilderStatus(), "builder status") end
    if feedbackLabel then writeNative(feedbackLabel, string.format("%s: %d / %s: %d", T("Ignored"), Resolver.ignored, T("unmapped shots"), Resolver.unknownShots), "feedback status") end
    if previousEnabled ~= Options.enabled or previousBuilderEnabled ~= Settings.builder.enabled then
        previousEnabled, previousBuilderEnabled = Options.enabled, Settings.builder.enabled
        syncControls()
    end
    if page == "Sync" then Sync.updateNativeStatus(language) end
    Sync.syncNativeWidgets(language, uiStopped and "" or page)
end
view.paint = function()
    if uiStopped or not view.active or not alive then return end
    local t = now()
    if t < nextLabelUpdate then return end
    nextLabelUpdate = t + 0.2
    local ok, err = pcall(updateViewPaint)
    if not ok then warn("[AntiResolver] Native UI update: " .. tostring(err)) end
end

view.hide=function()
    local ok=true
    view.active=false
    for _,item in ipairs(controls) do
        if item.created then
            if item.handle==nil or not visibleNative(item.handle,false,item.title) then ok=false end
            item.shown=false
        end
    end
    if setPickerSignature and not visibleNative(setPicker,false,"sets") then ok=false end
    for group,entry in pairs(actionMenus) do
        for _,variant in pairs(entry.variants or {}) do
            if not visibleNative(variant.handle,false,group) then ok=false end
        end
        entry.shown=false
    end
    return ok
end
view.selection=function() return {page,editState,editPart,copyState,selectedSet,nameDraft,importDraft,nameEdited} end
view.show=function(selection)
    if selection then
        page,editState,editPart,copyState,selectedSet,nameDraft,importDraft,nameEdited=table.unpack(selection,1,8)
    end
    if page ~= "Resolver" and page ~= "AA Builder" and page ~= "Configs" and page ~= "Sync" then page = "Resolver" end
    Sync.syncNativeWidgets(language, page)
    view.active=true
    shareSelection, shareCode = nil, ""
    prepareProfile();rebuildPicker();syncControls()
end
return view

end
selectLanguage=function(language)
    local previous=views[activeLanguage]
    local selection=previous and previous.selection()
    if previous and not previous.hide() then
        previous.show(selection)
        pcall(function() languageHandle:set(activeLanguage=="en" and "English" or "Русский",true) end)
        warn("[AR UI] Language switch requires valid widget handles; host did not return them")
        return
    end
    views[language]=views[language] or buildView(language)
    activeLanguage=language
    Resolver.outputLanguage=language
    pcall(saveUISettings, language, UISettings.advanced)
    views[language].show(selection)
    print("[AR UI] language=" .. language)
end
Resolver.outputLanguage=activeLanguage
views[activeLanguage]=buildView(activeLanguage)
views[activeLanguage].show()
local function normalizeEvent(kind, e, hitbox, extra)
    if e ~= nil and type(e) ~= "table" then
        local out = {target = e, hitbox = hitbox == 0 and "head" or hitbox}
        if kind == "hit" then out.damage = extra else out.reason = extra end
        return out
    end
    return e
end
local resolverTick=guarded(update)
events.on_tick(function()
    if not uiStopped and alive then resolverTick();Builder.tick() end
end)
client.set_event_callback("aim_fire",guarded(function(e)
    if e then Builder.onShot() end
    onFire(e)
end))
client.set_event_callback("aim_hit",guarded(function(e,hitbox,damage)
    feedback(normalizeEvent("hit",e,hitbox,damage),true)
end))
client.set_event_callback("aim_miss",guarded(function(e,hitbox,reason)
    feedback(normalizeEvent("miss",e,hitbox,reason),false)
end))
client.set_event_callback("paint",function() Sync.tick(uiStopped); if views[activeLanguage] then views[activeLanguage].paint() end end)
print("[AR BUILD] " .. BUILD .. " · Beta 1.3 · luapi-updated · modules=resolver+builder+configs+sync · schema=2")
