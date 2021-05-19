fx_version 'cerulean'
game 'gta5'

ui_page('html/index.html')

files {
    'html/index.html',
    'html/index.js',
    'html/index.css',
    'html/reset.css'
}

client_script {
	'client.lua',
    'config.lua'
}

server_script {
	'server.lua',
	'config.lua'
}
