--[[
    nx_core / server/main.lua
    Event wiring, exports and validated callbacks.

    Every export here is safe to call from another resource. Optional
    dependencies (nx_notify, nx_permissions) are feature detected.
]]

NX = NX or {}

local QBCore = exports['qb-core']:GetCoreObject()
local cfg = NX.CoreConfig
local TAG = 'nx_core'

-- ───────────────────────────── player lifecycle ─────────────────────────────

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    if not src then return end
    -- Give dependent resources a tick to finish their own load handlers.
    SetTimeout(250, function()
        if not QBCore.Functions.GetPlayer(src) then return end
        NX.State.Push(src)
        NX.Log.info(TAG, ('state pushed for %s'):format(Player.PlayerData.citizenid))
    end)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
        NX.State.ForgetSettings(Player.PlayerData.citizenid)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
        NX.State.ForgetSettings(Player.PlayerData.citizenid)
    end
end)

AddEventHandler('QBCore:Server:OnMoneyChange', function(src)
    NX.State.PushMoney(src)
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    NX.State.PushJob(src)
    NX.State.Push(src)
end)

AddEventHandler('QBCore:Server:OnGangUpdate', function(src)
    NX.State.Push(src)
end)

-- Drift corrector: QBCore is the source of truth, but a resource may mutate
-- player data without firing an event. Re-push a light snapshot periodically.
CreateThread(function()
    while true do
        Wait(cfg.stateReconcileMs)
        for _, src in ipairs(QBCore.Functions.GetPlayers()) do
            if QBCore.Functions.GetPlayer(src) then
                NX.State.PushMoney(src)
            end
        end
    end
end)

-- ───────────────────────────── exports ──────────────────────────────────────

exports('GetState', function(src)
    return NX.State.Build(src)
end)

exports('PushState', function(src)
    return NX.State.Push(src)
end)

--- Send a notification through the unified notification service.
--- Falls back to QBCore's built-in notify so gameplay never loses feedback.
exports('Notify', function(src, payload)
    if type(payload) == 'string' then
        payload = { message = payload, type = 'info' }
    end
    if type(payload) ~= 'table' then return false end
    payload.message = payload.message or payload.text
    if not payload.message then return false end

    if GetResourceState(cfg.notifyResource) == 'started' then
        TriggerClientEvent('nx_notify:client:push', src, payload)
        return true
    end
    TriggerClientEvent('QBCore:Notify', src, payload.message, payload.type or 'primary', payload.duration)
    return true
end)

--- Broadcast to everyone (system / city-wide announcements).
exports('Broadcast', function(payload)
    if type(payload) ~= 'table' then return false end
    if GetResourceState(cfg.notifyResource) == 'started' then
        TriggerClientEvent('nx_notify:client:push', -1, payload)
        return true
    end
    TriggerClientEvent('QBCore:Notify', -1, payload.message or '', payload.type or 'primary')
    return true
end)

--- Authoritative money read.
exports('GetMoney', function(src, moneyType)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    return Player.PlayerData.money[moneyType or 'cash'] or 0
end)

--- Permission check. nx_permissions wins, QBCore ACE is the fallback.
exports('HasPermission', function(src, node)
    if type(node) ~= 'string' or node == '' then return false end
    if GetResourceState(cfg.permissionsResource) == 'started' then
        local ok, result = pcall(function()
            return exports[cfg.permissionsResource]:HasPermission(src, node)
        end)
        if ok then return result == true end
        NX.Log.warn(TAG, 'permission backend error, falling back to ACE', tostring(result))
    end
    return QBCore.Functions.HasPermission(src, node) == true
end)

exports('GetPermissionNodes', function(src)
    local state = NX.State.Build(src)
    return state and state.permissions or {}
end)

exports('GetSettings', function(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return {} end
    return NX.State.LoadSettings(Player.PlayerData.citizenid)
end)

exports('SaveSettings', function(src, settings)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    return NX.State.SaveSettings(Player.PlayerData.citizenid, settings)
end)

exports('Brand', function()
    return NX.Config.Brand
end)

-- ───────────────────────────── callbacks ────────────────────────────────────

QBCore.Functions.CreateCallback('nx_core:server:getState', function(source, cb)
    cb(NX.State.Build(source))
end)

--- Static payload every interface may need once per session.
QBCore.Functions.CreateCallback('nx_core:server:getBootstrap', function(source, cb)
    cb({
        brand = NX.Config.Brand,
        features = NX.Features,
        locale = NX.GetLocalePayload(),
        ui = NX.Config.UI,
        notify = NX.Config.Notify,
        economy = NX.Config.Economy,
    })
end)

QBCore.Functions.CreateCallback('nx_core:server:saveSettings', function(source, cb, settings)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    if type(settings) ~= 'table' then return cb(false) end
    if not NX.Utils.RateLimit(('settings:%s'):format(source), cfg.settingsRateLimit.limit, cfg.settingsRateLimit.windowMs) then
        return cb(false)
    end
    cb(NX.State.SaveSettings(Player.PlayerData.citizenid, settings))
end)

-- ───────────────────────────── commands ─────────────────────────────────────

QBCore.Commands.Add('nxstate', 'Print your NOVARA state payload (debug)', {}, false, function(source)
    local state = NX.State.Build(source)
    if not state then return end
    print(json.encode(state, { indent = true }))
    NX.Log.info(TAG, 'state dump requested', { source = source })
end, 'admin')
