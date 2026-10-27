--[[
    NOVARA CITY RP — nx_core
    Bootstrap layer between QBCore and the NOVARA CITY ecosystem.

    Responsibilities:
      * one authoritative player state payload pushed to clients
      * a single NUI focus manager shared by every nx_* interface
      * cross-resource exports (notify / permissions / settings)
      * graceful degradation when optional resources are absent

    This resource does NOT reimplement QBCore. It adapts it.
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nx_core'
author 'NOVARA CITY'
description 'NOVARA CITY core: player state bridge, focus manager and shared exports'
version '0.1.0'

shared_scripts {
    '@nx_shared/shared/config.lua',
    '@nx_shared/shared/utils.lua',
    '@nx_shared/shared/logger.lua',
    '@nx_shared/shared/locale.lua',
    '@nx_shared/shared/bridge.lua',
    '@nx_shared/locales/id.lua',
    '@nx_shared/locales/en.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/focus.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/state.lua',
    'server/main.lua',
}

dependencies {
    'qb-core',
    'nx_shared',
    'oxmysql',
}
