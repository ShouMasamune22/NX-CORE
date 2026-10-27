--[[ nx_core / shared/config.lua — resource-level compatibility settings ]]

NX = NX or {}
NX.CoreConfig = {
    -- Optional resources this core can talk to. Everything is feature
    -- detected at runtime; a missing resource degrades gracefully.
    notifyResource = 'nx_notify',
    permissionsResource = 'nx_permissions',

    -- How often (ms) the server re-verifies a client's job/duty snapshot.
    -- State changes are event driven; this is only a drift corrector.
    stateReconcileMs = 120000,

    -- Settings payload limits (protects against oversized NUI writes).
    maxSettingsBytes = 4096,

    -- Rate limit for settings saves per player.
    settingsRateLimit = { limit = 10, windowMs = 10000 },

    -- Keys allowed in the persisted settings blob.
    allowedSettingKeys = {
        'hud.position', 'hud.scale', 'hud.visible',
        'hud.showSpeed', 'hud.showFuel', 'hud.showCompass',
        'notify.position', 'notify.duration', 'notify.sound', 'notify.volume',
        'ui.locale', 'ui.reduceMotion',
    },
}
