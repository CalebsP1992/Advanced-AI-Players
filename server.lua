RegisterNetEvent('ai:requestSpawn')
AddEventHandler('ai:requestSpawn', function()
    local source = source
    TriggerClientEvent('ai:spawnConfirmed', source)
end)

RegisterCommand('spawnAI', function(source, args, rawCommand)
    TriggerClientEvent('ai:spawnConfirmed', source)
end, false)

print("[AI - Advanced AI Players] Server side initialized.")