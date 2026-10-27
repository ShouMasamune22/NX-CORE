--[[
    nx_core / server/state.lua
    Builds the single authoritative player-state payload consumed by every
    NOVARA CITY interface.

    Rule: money, job, permissions and metadata are read from the server-side
    QBCore player object — never from anything the client sent us.
]]

NX = NX or {}
NX.State = NX.State or {}

local QBCore = exports['qb-core']:GetCoreObject()
local cfg = NX.CoreConfig
local TAG = 'nx_core'

local settingsCache = {}   -- [citizenid] = table
local lastStateAt = {}     -- [source] = ms

-- ───────────────────────────── settings ─────────────────────────────────────

local function flattenAllowed()
    local set = {}
    for _, key in ipairs(cfg.allowedSettingKeys) do set[key] = true end
    return set
end
local ALLOWED_KEYS = flattenAllowed()

--- Load and cache a character's persisted settings.
function NX.State.LoadSettings(citizenid)
    if not citizenid then return {} end
    if settingsCache[citizenid] then return settingsCache[citizenid] end
    local row = MySQL.single.await('SELECT `settings` FROM `nx_player_settings` WHERE `citizenid` = ? LIMIT 1', { citizenid })
    local decoded = {}
    if row and row.settings then
        local ok, value = pcall(json.decode, row.settings)
        if ok and type(value) == 'table' then decoded = value end
    end
    settingsCache[citizenid] = decoded
    return decoded
end

--- Persist a validated settings blob. Returns true on success.
function NX.State.SaveSettings(citizenid, incoming)
    if not citizenid or type(incoming) ~= 'table' then return false end

    local clean = {}
    for key, value in pairs(incoming) do
        if ALLOWED_KEYS[key] then
            local vt = type(value)
            if vt == 'string' then
                clean[key] = value:sub(1, 64)
            elseif vt == 'number' or vt == 'boolean' then
                clean[key] = value
            end
        end
    end

    local ok, encoded = pcall(json.encode, clean)
    if not ok then return false end
    if #encoded > cfg.maxSettingsBytes then return false end

    settingsCache[citizenid] = clean
    MySQL.insert.await([[
        INSERT INTO `nx_player_settings` (`citizenid`, `settings`) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)
    ]], { citizenid, encoded })
    return true
end

function NX.State.ForgetSettings(citizenid)
    settingsCache[citizenid] = nil
end

-- ───────────────────────────── permissions ──────────────────────────────────

--- Resolve the permission node list for a player.
--- nx_permissions is authoritative when present; QBCore ACE is the fallback.
local function getPermissionNodes(src)
    if GetResourceState(cfg.permissionsResource) == 'started' then
        local ok, nodes = pcall(function()
            return exports[cfg.permissionsResource]:GetNodes(src)
        end)
        if ok and type(nodes) == 'table' then return nodes end
    end
    local out = {}
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData.permissions then
        for node, granted in pairs(Player.PlayerData.permissions) do
            if granted then out[#out + 1] = node end
        end
    end
    return out
end

-- ───────────────────────────── payload ──────────────────────────────────────

local function shallowCopy(source)
    local out = {}
    if type(source) ~= 'table' then return out end
    for k, v in pairs(source) do out[k] = v end
    return out
end

--- Build the full state payload for a connected player.
function NX.State.Build(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    local pd = Player.PlayerData
    local charinfo = pd.charinfo or {}
    local metadata = pd.metadata or {}
    local job = pd.job or { name = 'unemployed', label = 'Civilian', grade = { level = 0, name = 'Freelancer' }, onduty = false }

    return {
        source = src,
        citizenid = pd.citizenid,
        cid = pd.cid,
        firstName = charinfo.firstname or '',
        lastName = charinfo.lastname or '',
        fullName = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        birthdate = charinfo.birthdate,
        gender = charinfo.gender,
        nationality = charinfo.nationality,
        job = {
            name = job.name,
            label = job.label,
            onduty = job.onduty == true,
            isboss = job.isboss == true,
            grade = {
                level = (job.grade and job.grade.level) or 0,
                name = (job.grade and job.grade.name) or '',
                payment = (job.grade and job.grade.payment) or 0,
            },
        },
        gang = pd.gang and {
            name = pd.gang.name,
            label = pd.gang.label,
            grade = pd.gang.grade and pd.gang.grade.level or 0,
        } or nil,
        -- Authoritative balances only.
        money = {
            cash = (pd.money and pd.money.cash) or 0,
            bank = (pd.money and pd.money.bank) or 0,
            crypto = (pd.money and pd.money.crypto) or 0,
        },
        metadata = {
            hunger = metadata.hunger or 100,
            thirst = metadata.thirst or 100,
            stress = metadata.stress or 0,
            armor = metadata.armor or 0,
            isdead = metadata.isdead == true,
            inlaststand = metadata.inlaststand == true,
            callsign = metadata.callsign,
        },
        permissions = getPermissionNodes(src),
        settings = shallowCopy(NX.State.LoadSettings(pd.citizenid)),
        serverTime = os.time(),
    }
end

--- Push the full state payload to one player.
function NX.State.Push(src)
    local payload = NX.State.Build(src)
    if not payload then return false end
    lastStateAt[src] = GetGameTimer()
    TriggerClientEvent('nx_core:client:state', src, payload)
    return true
end

--- Push only the money slice (called on every balance change).
function NX.State.PushMoney(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local money = Player.PlayerData.money or {}
    TriggerClientEvent('nx_core:client:money', src, {
        cash = money.cash or 0,
        bank = money.bank or 0,
        crypto = money.crypto or 0,
    })
end

--- Push only the job slice.
function NX.State.PushJob(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local job = Player.PlayerData.job or {}
    TriggerClientEvent('nx_core:client:job', src, {
        name = job.name,
        label = job.label,
        onduty = job.onduty == true,
        isboss = job.isboss == true,
        grade = {
            level = (job.grade and job.grade.level) or 0,
            name = (job.grade and job.grade.name) or '',
            payment = (job.grade and job.grade.payment) or 0,
        },
    })
end

function NX.State.LastPushAt(src)
    return lastStateAt[src]
end

NX.Log.info(TAG, 'state bridge initialised')
