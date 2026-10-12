fx_version 'cerulean'
game 'gta5'
version '2.5.0-rc1'
description 'Dios Scripts | Presidential detail and motorcade'
shared_scripts {
    'config/config.lua',
    'shared/config-check.lua',
    'shared/locale.lua',
    'shared/policy.lua',
    'shared/tactical.lua',
    'shared/runtime.lua',
    'shared/keys.lua',
}
server_scripts {
    'config/integration.lua',
    'server/keys.lua',
    'server/bridge.lua',
    'server/environment.lua',
    'server/journal.lua',
    'server/tactical.lua',
    'server/main.lua',
}
client_scripts {
    'client/keys.lua',
    'client/bridge.lua',
    'client/motion.lua',
    'client/tactical.lua',
    'client/main.lua',
}
ui_page 'web/index.html'
files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/app.js',
    'web/icons.svg',
    'locales/*.json',
}
dependency '/onesync'
