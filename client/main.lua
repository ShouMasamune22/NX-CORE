--[[
    nx_core / client/main.lua
    Client-side mirror of the authoritative player state + public exports.
]]

NX = NX or {}

local QBCore = exports['qb-core']:GetCoreObject()

NX.State = {
    source = 0,
    citizenid = nil,
    cid = nil,
    fullName = '',
    job = { name = 'unemployed', label = 'Civilian', onduty = false, grade = { level = 0, name = '' } },
    money = { cash = 0, bank = 0, crypto = 0 },
    metadata = {},
    permissions = {},
    settings = {},
    loaded = false,
}

local TAG = 'nx_core'
local bootstrapCache = nil

--- Merge a payload into the local mirror (never replaces wholesale so a
--- partial push cannot blank out unrelated fields).
local function mergeInto(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == 'table' and type(target[key]) == 'table' then
            mergeInto(target[key], value)
        else
            target[key] = value
        end
    end
end

RegisterNetEvent('nx_core:client:state', function(payload)
    if type(payload) ~= 'table' then return end
    mergeInto(NX.State, payload)
    NX.State.loaded = true
    TriggerEvent('nx_core:client:stateChanged', NX.State)
    NX.Log.debug(TAG, 'state applied')
end)

RegisterNetEvent('nx_core:client:money', function(money)
    if type(money) ~= 'table' then return end
    mergeInto(NX.State.money, money)
    TriggerEvent('nx_core:client:moneyChanged', NX.State.money)
end)

RegisterNetEvent('nx_core:client:job', function(job)
    if type(job) ~= 'table' then return end
    mergeInto(NX.State.job, job)
    TriggerEvent('nx_core:client:jobChanged', NX.State.job)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    NX.RequestState()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    NX.State.loaded = false
    NX.State.citizenid = nil
    TriggerEvent('nx_core:client:unloaded')
end)

--- Ask the server for a fresh authoritative snapshot.
function NX.RequestState()
    QBCore.Functions.TriggerCallback('nx_core:server:getState', function(state)
        if type(state) ~= 'table' then return end
        mergeInto(NX.State, state)
        NX.State.loaded = true
        TriggerEvent('nx_core:client:stateChanged', NX.State)
    end)
end

--- Cached bootstrap payload (brand, features, locale strings, theme values).
function NX.GetBootstrap(cb)
    if bootstrapCache then return cb(bootstrapCache) end
    QBCore.Functions.TriggerCallback('nx_core:server:getBootstrap', function(data)
        bootstrapCache = data or {}
        cb(bootstrapCache)
    end)
end

--- Send a notification. Accepts a string or a full payload table.
function NX.Notify(payload)
    if type(payload) == 'string' then
        payload = { message = payload, type = 'info' }
    end
    if type(payload) ~= 'table' then return end
    if GetResourceState('nx_notify') == 'started' then
        TriggerEvent('nx_notify:client:push', payload)
    else
        QBCore.Functions.Notify(payload.message or '', payload.type or 'primary', payload.duration)
    end
end

function NX.HasPermission(node)
    for _, value in ipairs(NX.State.permissions or {}) do
        if value == node then return true end
    end
    return false
end

--- Persist a preference change. Debounced so a slider drag is one write.
local pendingSettings = nil
local saveScheduled = false
function NX.SaveSettings(partial)
    if type(partial) ~= 'table' then return end
    pendingSettings = pendingSettings or {}
    for key, value in pairs(partial) do pendingSettings[key] = value end

    if saveScheduled then return end
    saveScheduled = true
    SetTimeout(1500, function()
        local payload = pendingSettings
        pendingSettings = nil
        saveScheduled = false
        if not payload then return end
        QBCore.Functions.TriggerCallback('nx_core:server:saveSettings', function(ok)
            if ok then
                mergeInto(NX.State.settings, payload)
                -- Consumers (HUD, notifications) re-read their settings on this event.
                TriggerEvent('nx_core:client:stateChanged', NX.State)
            else
                NX.Log.warn(TAG, 'settings save rejected by server')
            end
        end, payload)
    end)
end

--- Read a dotted settings key with a default.
function NX.GetSetting(key, default)
    local node = NX.State.settings
    for part in key:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return default end
        node = node[part]
    end
    if node == nil then return default end
    return node
end

-- ───────────────────────────── exports ──────────────────────────────────────

exports('GetState', function() return NX.State end)
exports('RequestState', function() NX.RequestState() end)
exports('Notify', function(payload) NX.Notify(payload) end)
exports('HasPermission', function(node) return NX.HasPermission(node) end)
exports('GetSetting', function(key, default) return NX.GetSetting(key, default) end)
exports('SaveSettings', function(partial) NX.SaveSettings(partial) end)
exports('GetBootstrap', function(cb) NX.GetBootstrap(cb) end)

NX.Log.info(TAG, 'client core ready')
