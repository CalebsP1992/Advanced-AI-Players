local QBCore = exports['qb-core']:GetCoreObject()
local aiModels = {"mp_m_freemode_01", "mp_f_freemode_01"}
local aiCount = 5
local aiList = {}
local spawnLocations = {
    paleto = {
        {x = -141.06, y = 6357.37, z = 31.49},  -- Paleto Bay Apartment Parking Lot --
        {x = -446.6, y = 6045.87, z = 31.34}   -- Paleto PD Parking Lot --
    },
    sandy = {
        {x = 1839.19, y = 3663.73, z = 33.83},  -- Sandy Medical Parking Lot --
        {x = 1856.81, y = 3675.24, z = 33.64}   -- Sandy Sheriffs Department --
    },
    city = {
        {x = 244.56, y = -565.24, z = 43.28},   -- Pillbox Hospital across the street --
        {x = 413.48, y = -986.87, z = 29.42},  -- MissionRow PD --
        {x = 235.68, y = -783.01, z = 30.65},   -- Legion Parking Lot --
        {x = 414.70, y = -643.64, z = 28.50}    -- Near PillBox in Parking Lot --
    },
    grapeseed = {
        {x = 1702.70, y = 4801.58, z = 41.78}   -- Grapeseed Parking Lot --
    }
}
local exploreRadius = 100.0
local waitTimeMin = 5000
local waitTimeMax = 15000
local detectDeadDistance = 300.0
local reviveDistance = 1.5
local reviveTime = 10000
local rescueVehicleModel = "mesa" -- CHANGE ME TO YOUR VEHICLE MODEL --
local playerRescueDistance = 1000.0
local rescueInProgress = false

function ShowTimedNotification(message, duration)
    exports['qb-core']:DrawText(message, "right", "red")
    SetTimeout(duration, function()
        exports['qb-core']:HideText()
    end)
end


RegisterCommand('respawnai', function()
    print("Manual spawn triggered")
    TriggerServerEvent('ai:requestSpawn')
end, false)

RegisterCommand('debugai', function()
    print("Current AI count: " .. #aiList)
    for id, data in pairs(aiList) do
        if DoesEntityExist(data.ped) then
            print(id .. " exists at: " .. GetEntityCoords(data.ped))
        else
            print(id .. " does not exist")
        end
    end
end, false)

RegisterNetEvent('ai:spawnConfirmed')
AddEventHandler('ai:spawnConfirmed', function()
    spawnAI()
end)

function findNearestHealthyAI()
    local availableAIs = {}
    
    for _, aiData in pairs(aiList) do
        if DoesEntityExist(aiData.ped) and GetEntityHealth(aiData.ped) > 0 then
            local distance = #(GetEntityCoords(aiData.ped) - GetEntityCoords(PlayerPedId()))
            table.insert(availableAIs, {ai = aiData, distance = distance})
        end
    end
    
    table.sort(availableAIs, function(a, b)
        return a.distance < b.distance
    end)
    
    -- Return the next available AI if first one is busy
    for _, aiData in ipairs(availableAIs) do
        if not aiData.ai.isRescuing then
            return aiData.ai
        end
    end
    
    return nil
end



function startRescueMission(aiData, playerPed)
    Citizen.CreateThread(function()
        aiData.isRescuing = true
        local aiStartPosition = GetEntityCoords(aiData.ped)
        local hash = GetHashKey(rescueVehicleModel)
        
        RequestModel(hash)
        while not HasModelLoaded(hash) do
            Citizen.Wait(0)
        end
        
        local success, roadPosition = GetClosestVehicleNode(aiStartPosition.x, aiStartPosition.y, aiStartPosition.z, 1, 3.0, 0)
        local vehicle = CreateVehicle(hash, roadPosition.x, roadPosition.y, roadPosition.z, 0.0, true, false)

        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleEngineOn(vehicle, true, true, false)
        
        TaskEnterVehicle(aiData.ped, vehicle, -1, -1, 2.0, 1, 0)
        
        Citizen.Wait(2000)
        
        local playerCoords = GetEntityCoords(playerPed)
        local offsetCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 35.0, 0.0)
        TaskVehicleDriveToCoord(aiData.ped, vehicle, offsetCoords.x, offsetCoords.y, offsetCoords.z, 20.0, 0, hash, 786603, 1.0, true)
        
        while #(GetEntityCoords(aiData.ped) - offsetCoords) > 3.0 do
            if #(GetEntityCoords(aiData.ped) - GetEntityCoords(playerPed)) < 35.0 then
                ClearPedTasks(aiData.ped)
                TaskLeaveVehicle(aiData.ped, vehicle, 0)
                ShowTimedNotification("AI Player arrived at your location", 10000)
                break
            end
            Citizen.Wait(1000)
        end
        
        TaskGoToEntity(aiData.ped, playerPed, -1, 1.0, 2.0, 0, 0)
        while #(GetEntityCoords(aiData.ped) - playerCoords) > 1.0 do
            Citizen.Wait(100)
        end
        
        TaskStartScenarioInPlace(aiData.ped, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
        Citizen.Wait(reviveTime)
        TriggerEvent("hospital:client:Revive")
        NetworkResurrectLocalPlayer(playerCoords.x, playerCoords.y, playerCoords.z, 0.0, true, false)
        SetEntityHealth(playerPed, 200)
        
        TaskEnterVehicle(aiData.ped, vehicle, -1, -1, 2.0, 1, 0)
        Citizen.Wait(2000)
        TaskVehicleDriveToCoord(aiData.ped, vehicle, aiStartPosition.x, aiStartPosition.y, aiStartPosition.z, 20.0, 0, hash, 786603, 1.0, true)
        
        while #(GetEntityCoords(aiData.ped) - aiStartPosition) > 3.0 do
            Citizen.Wait(1000)
        end
        
        DeleteVehicle(vehicle)
        ShowTimedNotification("AI Player RTB success. Ready for further tasking", 10000)
        aiData.isRescuing = false
        rescueInProgress = false
        initializeAI(aiData)

        -- Force reinitialize with original spawn location
        local spawnLocation = aiData.spawnLocation
        initializeAI(aiData)
    
        -- Ensure AI stays active
        SetPedKeepTask(aiData.ped, true)
        SetEntityDistanceCullingRadius(aiData.ped, 9999.0)
    end)
end

function setupAIAppearance(ped, model)
    if model == "mp_m_freemode_01" then
        -- Male preset outfits
        local maleOutfits = {
            {torso = 0, torsoTexture = 0, undershirt = 15, undershirtTexture = 0, top = 4, topTexture = 0},
            {torso = 11, torsoTexture = 0, undershirt = 15, undershirtTexture = 0, top = 14, topTexture = 0},
            {torso = 6, torsoTexture = 0, undershirt = 23, undershirtTexture = 0, top = 23, topTexture = 0},
            {torso = 4, torsoTexture = 0, undershirt = 31, undershirtTexture = 0, top = 31, topTexture = 0}
        }
        
        local outfit = maleOutfits[math.random(#maleOutfits)]
        
        SetPedComponentVariation(ped, 3, outfit.torso, outfit.torsoTexture, 0)  -- Torso
        SetPedComponentVariation(ped, 8, outfit.undershirt, outfit.undershirtTexture, 0)  -- Undershirt
        SetPedComponentVariation(ped, 11, outfit.top, outfit.topTexture, 0)  -- Top
        
        -- Always valid combinations for other parts
        SetPedComponentVariation(ped, 0, math.random(0, 45), 0, 0)  -- Face
        SetPedComponentVariation(ped, 2, math.random(0, 36), 0, 0)  -- Hair
        SetPedComponentVariation(ped, 4, math.random(0, 114), 0, 0)  -- Legs
        SetPedComponentVariation(ped, 6, math.random(0, 71), 0, 0)  -- Shoes
    else
        -- Female preset outfits and face
        SetPedHeadBlendData(ped, 21, 45, 0, 21, 45, 0, 0.8, 0.8, 0, false)
        -- Set feminine features
        SetPedFaceFeature(ped, 0, 0.9) -- Nose Width
        SetPedFaceFeature(ped, 1, 0.3) -- Nose Peak Height
        SetPedFaceFeature(ped, 2, 0.9) -- Nose Peak Length
        SetPedFaceFeature(ped, 9, 0.9) -- Cheek Width
        SetPedFaceFeature(ped, 10, 0.9) -- Cheek Size
        
        -- Female preset complete outfits including legs
        local femaleOutfits = {
            {torso = 0, torsoTexture = 0, undershirt = 15, undershirtTexture = 0, top = 4, topTexture = 0, legs = 0, legsTexture = 0},
            {torso = 11, torsoTexture = 0, undershirt = 15, undershirtTexture = 0, top = 14, topTexture = 0, legs = 14, legsTexture = 0},
            {torso = 6, torsoTexture = 0, undershirt = 23, undershirtTexture = 0, top = 23, topTexture = 0, legs = 23, legsTexture = 0},
            {torso = 4, torsoTexture = 0, undershirt = 31, undershirtTexture = 0, top = 31, topTexture = 0, legs = 31, legsTexture = 0}
        }
        
        local outfit = femaleOutfits[math.random(#femaleOutfits)]
        
        SetPedComponentVariation(ped, 3, outfit.torso, outfit.torsoTexture, 0)  -- Torso
        SetPedComponentVariation(ped, 8, outfit.undershirt, outfit.undershirtTexture, 0)  -- Undershirt
        SetPedComponentVariation(ped, 11, outfit.top, outfit.topTexture, 0)  -- Top
        SetPedComponentVariation(ped, 4, outfit.legs, outfit.legsTexture, 0)  -- Legs
        
        -- Always valid combinations for other parts
        SetPedComponentVariation(ped, 0, math.random(0, 45), 0, 0)  -- Face
        SetPedComponentVariation(ped, 2, math.random(0, 38), 0, 0)  -- Hair
        SetPedComponentVariation(ped, 6, math.random(0, 77), 0, 0)  -- Shoes
    end
    
end



function spawnAI()
    print("Starting AI spawn sequence...")
    Citizen.CreateThread(function()
        local aiIndex = 1
        
        -- Spawn Paleto Bay AIs
        for _, loc in ipairs(spawnLocations.paleto) do
            spawnSingleAI(aiIndex, loc)
            aiIndex = aiIndex + 1
        end
        
        -- Spawn Sandy Shores AIs
        for _, loc in ipairs(spawnLocations.sandy) do
            spawnSingleAI(aiIndex, loc)
            aiIndex = aiIndex + 1
        end
        
        -- Spawn City AIs
        for _, loc in ipairs(spawnLocations.city) do
            spawnSingleAI(aiIndex, loc)
            aiIndex = aiIndex + 1
        end
        
        -- Spawn Grapeseed AI
        spawnSingleAI(aiIndex, spawnLocations.grapeseed[1])
    end)
end

function spawnSingleAI(index, location)
    local model = aiModels[math.random(#aiModels)]
    local hash = GetHashKey(model)
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Citizen.Wait(1)
    end
    
    local ai = CreatePed(4, hash, location.x, location.y, location.z, 0.0, true, false)
    if DoesEntityExist(ai) then
        setupAIAppearance(ai, model)
        SetEntityAsMissionEntity(ai, true, true)
        SetBlockingOfNonTemporaryEvents(ai, true)
        SetPedCanRagdoll(ai, false)
        FreezeEntityPosition(ai, false)
        SetEntityInvincible(ai, false)
        
        local aiID = "AI_" .. index
        aiList[aiID] = {
            ped = ai,
            name = aiID,
            memoryFile = "ai_memories/" .. aiID .. ".json",
            spawnLocation = location
        }
        
        setupBlips(aiList[aiID])
        setupHealthAndVisibility(aiList[aiID])
        initializeAI(aiList[aiID])
    end
    SetModelAsNoLongerNeeded(hash)
end

function setupBlips(aiData)
    local blip = AddBlipForEntity(aiData.ped)
    SetBlipSprite(blip, 1)
    SetBlipScale(blip, 0.8)
    SetBlipAsFriendly(blip, true)
    SetBlipColour(blip, 47)
    SetBlipDisplay(blip, 4)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(aiData.name)
    EndTextCommandSetBlipName(blip)
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(7)
        SetTextProportional(1)
        SetTextColour(0, 255, 0, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        SetTextDropshadow(0, 0, 0, 0, 255)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

function setupHealthAndVisibility(aiData)
    Citizen.CreateThread(function()
        while DoesEntityExist(aiData.ped) do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local aiCoords = GetEntityCoords(aiData.ped)
            
            if #(playerCoords - aiCoords) < 30.0 then
                local onScreen, screenX, screenY = World3dToScreen2d(aiCoords.x, aiCoords.y, aiCoords.z + 2.0)
                if onScreen then
                    DrawText3D(aiCoords.x, aiCoords.y, aiCoords.z + 2.3, aiData.name)
                    
                    local health = GetEntityHealth(aiData.ped)
                    local maxHealth = GetEntityMaxHealth(aiData.ped)
                    local healthPercent = (health / maxHealth)
                    
                    DrawRect(screenX, screenY + 0.02, 0.08, 0.01, 255, 255, 255, 150)
                    DrawRect(screenX - (0.04 * (1.0 - healthPercent)), screenY + 0.02, 0.08 * healthPercent, 0.01, 255, 0, 0, 200)
                end
            end
            
            Citizen.Wait(0)
        end
    end)
end


function monitorHealth()
    Citizen.CreateThread(function()
        while true do
            -- First verify and restore any missing AI
            for aiID, aiData in pairs(aiList) do
                if not DoesEntityExist(aiData.ped) then
                    -- Respawn this AI at their original position
                    spawnSingleAI(tonumber(aiID:sub(4)), aiData.spawnLocation)
                end
            end
            
            -- Then check for player death and rescue needs
            local playerPed = PlayerPedId()
            if DoesEntityExist(playerPed) and GetEntityHealth(playerPed) <= 0 then
                local nearestAI = findNearestHealthyAI()
                
                if nearestAI and not rescueInProgress then
                    rescueInProgress = true
                    ShowTimedNotification("AI Player in route to your location - standby for revival", 10000)
                    startRescueMission(nearestAI, playerPed)
                end
            end
            
            Citizen.Wait(1000)
        end
    end)
end


function attemptRevival(deadAI)
    local rescuers = {}
    for aiID, aiData in pairs(aiList) do
        if DoesEntityExist(aiData.ped) and GetEntityHealth(aiData.ped) > 0 then
            local rescuerCoords = GetEntityCoords(aiData.ped)
            local deadCoords = GetEntityCoords(deadAI.ped)
            local distance = #(rescuerCoords - deadCoords)
            
            if distance <= detectDeadDistance then
                table.insert(rescuers, aiData)
                ClearPedTasks(aiData.ped)
                TaskGoToEntity(aiData.ped, deadAI.ped, -1, 1.0, 2.0, 0, 0)
                
                if distance <= reviveDistance then
                    TaskTurnPedToFaceEntity(aiData.ped, deadAI.ped, -1)
                    TaskStartScenarioInPlace(aiData.ped, "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
                    
                    Citizen.Wait(reviveTime)
                    
                    ClearPedTasks(aiData.ped)
                    ResurrectPed(deadAI.ped)
                    SetEntityHealth(deadAI.ped, 200)
                    SetPedCanRagdoll(deadAI.ped, false)
                    SetEntityCollision(deadAI.ped, true, true)
                    SetBlockingOfNonTemporaryEvents(deadAI.ped, true)
                    ClearPedTasksImmediately(deadAI.ped)
                    
                    initializeAI(deadAI)
                    for _, rescuer in ipairs(rescuers) do
                        initializeAI(rescuer)
                    end
                    
                    break
                end
            end
        end
    end
end

function initializeAI(aiData)
    Citizen.CreateThread(function()

        while DoesEntityExist(aiData.ped) do
            local angle = math.random() * 2 * math.pi
            local radius = math.random() * exploreRadius
            local destX = spawnLocation.x + radius * math.cos(angle)
            local destY = spawnLocation.y + radius * math.sin(angle)
            
            ClearPedTasks(aiData.ped)
            TaskGoStraightToCoord(aiData.ped, destX, destY, spawnLocation.z, 1.0, -1, 0.0, 0.0)
            
            local memory = {
                location = {x = destX, y = destY, z = spawnLocation.z},
                timestamp = GetGameTimer(),
                type = "exploration"
            }
            saveMemory(aiData, memory)
            
            Citizen.Wait(math.random(waitTimeMin, waitTimeMax))
        end
    end)
end

Citizen.CreateThread(function()
    while true do
        -- Set population density to maximum in all zones
        SetPedDensityMultiplierThisFrame(1.0)
        SetScenarioPedDensityMultiplierThisFrame(1.0, 1.0)
        
        -- Keep all AI active regardless of distance
        for _, aiData in pairs(aiList) do
            if DoesEntityExist(aiData.ped) then
                SetPedKeepTask(aiData.ped, true)
                SetEntityDistanceCullingRadius(aiData.ped, 9999.0)
                -- Force AI to stay in simulation range
                SetPedAsGroupMember(aiData.ped, GetPedGroupIndex(PlayerPedId()))
                SetPedNeverLeavesGroup(aiData.ped, true)
            end
        end
        Citizen.Wait(0)
    end
end)


Citizen.CreateThread(function()
    while true do
        for _, aiData in pairs(aiList) do
            if DoesEntityExist(aiData.ped) then
                SetPedKeepTask(aiData.ped, true)
                SetEntityDistanceCullingRadius(aiData.ped, 9999.0)
            end
        end
        Citizen.Wait(1000)
    end
end)

function saveMemory(aiData, memory)
    local file = io.open(aiData.memoryFile, "a")
    if file then
        file:write(json.encode(memory) .. "\n")
        file:close()
    end
end

Citizen.CreateThread(function()
    print("Main thread starting")
    Wait(1000)
    print("Triggering AI spawn")
    TriggerServerEvent('ai:requestSpawn')
    monitorHealth()
    
    while true do
        Citizen.Wait(1000)
    end
end)

print("Client script loaded and ready.")
