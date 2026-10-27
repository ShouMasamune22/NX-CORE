--[[
    nx_core / client/focus.lua
    Single NUI focus manager shared by every NOVARA CITY interface.

    Why: multiple NUI resources fighting over SetNuiFocus is the most common
    cause of "stuck mouse cursor" and unresponsive ESC handling on FiveM
    servers. Every interface requests focus through this stack and releases
    it when it closes. A watchdog force-releases focus if an interface dies
    without releasing (crashed script, resource restart, NUI exception).

    Contract for consumers:
        if not exports['nx_core']:RequestFocus('nx_inventory') then return end
        -- ... open NUI, send NUI message ...
        exports['nx_core']:ReleaseFocus('nx_inventory')
]]

NX = NX or {}
NX.UI = NX.UI or {}

local TAG = 'nx_core'
local stack = {}          -- ordered list of { id = string, at = ms }
local lastActivity = 0
local watchdogMs = (NX.Config and NX.Config.UI and NX.Config.UI.focusWatchdogMs) or 30000

local function indexOf(id)
    for i = 1, #stack do
        if stack[i].id == id then return i end
    end
    return nil
end

local function applyFocus()
    local focused = #stack > 0
    SetNuiFocus(focused, focused)
    SetNuiFocusKeepInput(false)
    lastActivity = GetGameTimer()
    TriggerEvent('nx_core:client:focusChanged', focused, stack[#stack] and stack[#stack].id)
end

--- Request NUI focus for an interface. Returns false when another interface
--- already owns focus (the caller must not open in that case).
function NX.UI.Request(id)
    if type(id) ~= 'string' or id == '' then return false end
    local existing = indexOf(id)
    if existing then
        stack[existing].at = GetGameTimer()
        return true
    end
    if #stack > 0 then
        -- Only the current owner may be replaced by an explicit takeover.
        NX.Log.warn(TAG, ('focus denied for %s — held by %s'):format(id, NX.UI.Owner() or 'unknown'))
        return false
    end
    stack[#stack + 1] = { id = id, at = GetGameTimer() }
    applyFocus()
    return true
end

--- Force focus for an interface that must interrupt the current one
--- (e.g. an admin action or a death screen). Replaces the stack.
function NX.UI.Takeover(id)
    if type(id) ~= 'string' or id == '' then return false end
    stack = { { id = id, at = GetGameTimer() } }
    applyFocus()
    return true
end

--- Release focus for an interface. Safe to call when not focused.
function NX.UI.Release(id)
    local index = indexOf(id)
    if not index then return false end
    table.remove(stack, index)
    applyFocus()
    return true
end

--- Release everything (resource stop, disconnect, death, character switch).
function NX.UI.ReleaseAll()
    if #stack == 0 then
        SetNuiFocus(false, false)
        return
    end
    stack = {}
    applyFocus()
end

function NX.UI.IsFocused()
    return #stack > 0
end

function NX.UI.Owner()
    return stack[#stack] and stack[#stack].id or nil
end

--- Called by consumers from their NUI callbacks so the watchdog can tell the
--- difference between "open and idle" and "open and dead".
function NX.UI.Touch()
    lastActivity = GetGameTimer()
end

-- Watchdog: never let a dead interface hold the cursor hostage.
CreateThread(function()
    while true do
        Wait(2000)
        if #stack > 0 and (GetGameTimer() - lastActivity) > watchdogMs then
            NX.Log.warn(TAG, ('focus watchdog released stale interface: %s'):format(NX.UI.Owner() or 'unknown'))
            NX.UI.ReleaseAll()
        end
    end
end)

-- Always release focus when this resource stops.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        stack = {}
        SetNuiFocus(false, false)
    end
end)

-- Release on death / character unload so the player can play again.
AddEventHandler('nx_core:client:unloaded', function()
    NX.UI.ReleaseAll()
end)

-- ───────────────────────────── exports ──────────────────────────────────────

exports('RequestFocus', function(id) return NX.UI.Request(id) end)
exports('TakeoverFocus', function(id) return NX.UI.Takeover(id) end)
exports('ReleaseFocus', function(id) return NX.UI.Release(id) end)
exports('ReleaseAllFocus', function() NX.UI.ReleaseAll() end)
exports('IsFocused', function() return NX.UI.IsFocused() end)
-- `or nil` guarantees a single return value: a bare `NX.UI.Owner()` can resolve
-- to no values in some Lua/export bridges, which makes `tostring(...)` on the
-- caller side throw "bad argument #1 to 'tostring' (value expected)".
exports('FocusOwner', function() return NX.UI.Owner() or nil end)
exports('TouchFocus', function() NX.UI.Touch() end)

--- Diagnostic: `/nxui` prints the focus stack, `/nxui release` force-releases.
--- Used when a player reports "the mouse is stuck" or "I cannot click".
RegisterCommand('nxui', function(_, args)
    local owner = NX.UI.Owner()
    local focused = NX.UI.IsFocused()
    print(('[nx_core] focus=%s owner=%s depth=%d idle=%dms watchdog=%dms'):format(
        tostring(focused), tostring(owner), #stack, GetGameTimer() - lastActivity, watchdogMs))

    if args[1] == 'release' then
        NX.UI.ReleaseAll()
        print('[nx_core] focus released')
    elseif args[1] == 'take' then
        SetNuiFocus(true, true)
        print('[nx_core] forced SetNuiFocus(true, true)')
    end
end, false)

--- Re-assert NUI focus if the page is open but the game lost the cursor.
--- Some overlays (and the native pause menu) can silently reset NUI focus.
CreateThread(function()
    while true do
        Wait(5000)
        if #stack > 0 then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
        end
    end
end)
