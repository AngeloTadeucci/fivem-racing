-- Recording race vars
local realSize = 6.0
local currentMap = {}
local SetBlips = {}
local checkpointMarkers = {}

-- Races and race status
local temprace = {}
local races = {}
local raceStatus = {
	state = RACE_STATE_NONE,
	index = 0,
	checkpoint = 0,
	lap = 0,
	lapTime = 0,
	lastLapTime = 0,
	fastestLap = 0
}

-- DEFINITIONS AND CONSTANTS
local RACE_STATE_NONE = 0
local RACE_STATE_JOINED = 1
local RACE_STATE_RACING = 2
local RACE_STATE_RECORDING = 3

-- NUI
local display = false
local racesLoaded = false

-- Main command for races
RegisterCommand("race", function(source, args)
	source = PlayerId()
	if args[1] == "clear" or args[1] == "leave" then
		-- If player is part of a race, clean up map and send leave event to server
		if raceStatus.state == RACE_STATE_JOINED or raceStatus.state == RACE_STATE_RACING then
			ClearBlipsAndCheckpoints()
			if IsPedInAnyVehicle(PlayerPedId(), false) then
				local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
				FreezeEntityPosition(vehicle, false)
			end
			TriggerServerEvent('racing:leaveRace_sv', raceStatus.index)
		end
		ClearBlipsAndCheckpoints()
		-- Reset state
		ResetRace()
	elseif args[1] == "record" then
		-- Clear waypoint, cleanup recording and set flag to start recording
		SetWaypointOff()
		ClearBlipsAndCheckpoints()
		raceStatus.state = RACE_STATE_RECORDING
		TriggerEvent('chat:addMessage', {
			color = { 255, 0, 0},
			multiline = true,
			args = {"[Races]", "Recording..."}
		  })
	elseif args[1] == "save" then
		-- Check name was provided and checkpoints are recorded
		table.remove(args, 1)
		local name = TableToString(args)
		if name == nil then
			return TriggerEvent('chat:addMessage', {
				color = { 255, 0, 0},
				multiline = true,
				args = {"[Races]", "Type an name for the race dummy. 😡"}
			})
		end

		SaveMap(TableToString(args))
	elseif args[1] == "delete" then
		TriggerEvent('chat:addMessage', {
				color = { 255, 0, 0},
				multiline = true,
				args = {"[Races]", "Sorry, you can only delete races manually for now ask the server owner"}
			})
	elseif args[1] == "cancel" then
		-- Send cancel event to server
		TriggerServerEvent('StreetRaces:cancelRace_sv')
	else
		racesLoaded = false
		TriggerServerEvent("racing:load-races")
		local i = 1
		while racesLoaded == false do
			if (i > 1000) then break end
			Wait(1)
			i = i +1
		end
		SetDisplay(not display)
		return
	end
end)

RegisterNUICallback("error", function (data)
	chat(data.error, {255,0,0})
	SetDisplay(false)
end)

RegisterNUICallback("exit", function (data)
	SetDisplay(false)
end)

RegisterNetEvent("racing:loaded-races")
AddEventHandler("racing:loaded-races", function (races, pRacesLoaded)
	racesLoaded = pRacesLoaded
	SendNUIMessage({
		type = "RacesData",
		data = races
	})
end)

--Toggles the NUI
function SetDisplay(bool)
	display = bool
	SetNuiFocus(bool, bool)
	SendNUIMessage({
		type = "ui",
		status = bool,
	})
end

RegisterNUICallback("loadRace", function (data)
	TriggerServerEvent("racing:load-map", data.raceID)
end)

RegisterNUICallback("startRace", function (data)
	TriggerServerEvent('racing:createRace_sv', data.voltas, 15000, vector3(temprace.checkpoints[1].x, temprace.checkpoints[1].y, temprace.checkpoints[1].z), temprace.checkpoints)
end)

-- Client event for loading a race
RegisterNetEvent("racing:loaded-map")
AddEventHandler("racing:loaded-map", function(data)
	temprace = data
	local ped = PlayerPedId()
	local entity
	if IsPedInAnyVehicle(ped, false) then
		entity = GetVehiclePedIsIn(ped, false)
	else
		entity = ped
	end
	if #(GetEntityCoords(entity) - vector3(data.checkpoints[1].x,data.checkpoints[1].y,data.checkpoints[1].z)) > 20.0 then
		SetEntityCoords(entity, data.checkpoints[1].x,data.checkpoints[1].y,data.checkpoints[1].z+5.0)
	end
	LoadMapBlips(data)
end)

RegisterNetEvent("racing:joinedRace_cl")
AddEventHandler("racing:joinedRace_cl", function(index)
	-- Set index and state to joined
	raceStatus.index = index
	raceStatus.state = RACE_STATE_JOINED
	LoadMapBlips(races[index])
end)

-- Client event for when a race is created
RegisterNetEvent("racing:createRace_cl")
AddEventHandler("racing:createRace_cl", function(index, pLaps, pStartDelay, pStartCoords, pCheckpoints)
	-- Create race struct and add to array
	local race = {
		started = false,
		startTime = GetGameTimer() + pStartDelay,
		startCoords = pStartCoords,
		checkpoints = pCheckpoints,
		laps = pLaps
	}
	races[index] = race
end)

-- Client event for when a race is removed
RegisterNetEvent("racing:removeRace_cl")
AddEventHandler("racing:removeRace_cl", function(index)
	-- Check if index matches active race
	if index == raceStatus.index then
		-- Cleanup map blips and checkpoints
		ClearBlipsAndCheckpoints()

		-- Reset racing state
		resetRace()
	elseif index < raceStatus.index then
		-- Decrement raceStatus.index to match new index after removing race
		raceStatus.index = raceStatus.index - 1
	end

	-- Remove race from table
	table.remove(races, index)
end)


CreateThread(function ()
	while true do
		Wait(0)
		local player = PlayerPedId()
		if IsPedInAnyVehicle(player, false) then

			local position = GetEntityCoords(player)
			local vehicle = GetVehiclePedIsIn(player, false)
			if raceStatus.state == RACE_STATE_RACING then
				-- Initialize first checkpoint if not set
				local race = races[raceStatus.index]
				if raceStatus.checkpoint == 0 then
					-- Increment to first checkpoint
					raceStatus.checkpoint = 1
					raceStatus.lap = 0
					-- Set blip route for navigation
					NextBlip(SetBlips[raceStatus.checkpoint])
				else
					-- Check player distance from current checkpoint
					local checkpoint = race.checkpoints[raceStatus.checkpoint]
					if GetDistanceBetweenCoords(vector3(position.x, position.y, position.z), vector3(checkpoint.x, checkpoint.y, 0), false) < checkpoint.dist then
						if raceStatus.checkpoint == 1 and raceStatus.lap ~= race.laps then
							LoadMapBlips(races[raceStatus.index])
						end -- Last lap
						local nextBlip = SetBlips[raceStatus.checkpoint]
						-- Set blip colour
						SetBlipColour(nextBlip, 18)
						SetBlipScale(nextBlip, 1.0)

						-- Check if at finish line
						if race.laps == 1 then -- Sprint
							if raceStatus.checkpoint == #(race.checkpoints) then -- Last Checkpoint
								-- Play finish line sound
								PlaySoundFrontend(-1, "ScreenFlash", "WastedSounds")

								-- Send finish event to server
								TriggerServerEvent('racing:finishedRace_sv', raceStatus.index, raceStatus.fastestLap)

								-- Reset state
								raceStatus.index = 0
								raceStatus.state = RACE_STATE_NONE
							else --Next checkpoint
								-- Play checkpoint sound
								PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS")

								-- Increment checkpoint counter and get next checkpoint
								raceStatus.checkpoint = raceStatus.checkpoint + 1
								nextBlip = SetBlips[raceStatus.checkpoint]
								-- Set blip route for navigation
								NextBlip(nextBlip)
							end
						else -- Circuit
							if raceStatus.checkpoint == 1 then -- Last Checkpoint from the lap
								if raceStatus.lap == race.laps then -- Last lap
									-- Play finish line sound
									PlaySoundFrontend(-1, "ScreenFlash", "WastedSounds")

									-- lap time
									if raceStatus.lap == 0 then
										raceStatus.lapTime = 0
									else
										if raceStatus.lapTime == 0 then
											raceStatus.lapTime = GetGameTimer() - race.startTime
											raceStatus.fastestLap = raceStatus.lapTime
										else
											raceStatus.lapTime = GetGameTimer() - raceStatus.lastLapTime
										end
										raceStatus.lastLapTime = GetGameTimer()
									end
									if raceStatus.lapTime < raceStatus.fastestLap then
										raceStatus.fastestLap = raceStatus.lapTime
									end

									-- Send finish event to server
									TriggerServerEvent('racing:finishedRace_sv', raceStatus.index, raceStatus.fastestLap)

									-- Reset state
									raceStatus.index = 0
									raceStatus.state = RACE_STATE_NONE
								else -- Another lap
									-- Play checkpoint sound
									PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS")

									-- lap time
									if raceStatus.lap == 0 then
										raceStatus.lapTime = 0
									else
										if raceStatus.lapTime == 0 then
											raceStatus.lapTime = GetGameTimer() - race.startTime
											raceStatus.fastestLap = raceStatus.lapTime
										else
											raceStatus.lapTime = GetGameTimer() - raceStatus.lastLapTime
										end
										raceStatus.lastLapTime = GetGameTimer()
									end
									if raceStatus.lapTime < raceStatus.fastestLap then
										raceStatus.fastestLap = raceStatus.lapTime
									end
									-- Increment lap
									raceStatus.lap = raceStatus.lap+1

									-- Increment checkpoint counter and get next checkpoint
									raceStatus.checkpoint = raceStatus.checkpoint + 1
									nextBlip = SetBlips[raceStatus.checkpoint]
									-- Set blip route for navigation
									NextBlip(nextBlip)
								end
							else -- Next checkpoint
								-- Play checkpoint sound
								PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS")

								-- Increment checkpoint counter and get next checkpoint
								if raceStatus.checkpoint == #race.checkpoints then
									 raceStatus.checkpoint = 1
								else
									raceStatus.checkpoint = raceStatus.checkpoint + 1
								end
								nextBlip = SetBlips[raceStatus.checkpoint]
								-- Set blip route for navigation
								NextBlip(nextBlip)
							end
						end
					end
				end

				-- Draw HUD when it's enabled
				if CONFIG_CL.hudEnabled then
					-- Draw time and checkpoint HUD above minimap
					local timeSeconds = (GetGameTimer() - race.startTime)/1000.0
					local timeMinutes = math.floor(timeSeconds/60.0)
					timeSeconds = timeSeconds - 60.0*timeMinutes
					Draw2DText(CONFIG_CL.hudPosition.x, CONFIG_CL.hudPosition.y-0.035, ("~y~Total time %02d:%06.3f"):format(timeMinutes, timeSeconds), 0.7)

					local fastestTimeSeconds = (raceStatus.fastestLap)/1000.0
					local fastestTimeMinutes = math.floor(fastestTimeSeconds/60.0)
					fastestTimeSeconds = fastestTimeSeconds - 60.0*fastestTimeMinutes
					Draw2DText(CONFIG_CL.hudPosition.x, CONFIG_CL.hudPosition.y, ("~y~Fastest lap %02d:%06.3f"):format(fastestTimeMinutes, fastestTimeSeconds), 0.7)

					local checkpoint = race.checkpoints[raceStatus.checkpoint]
					local checkpointDist = math.floor(GetDistanceBetweenCoords(position.x, position.y, position.z, vector3(checkpoint.x, checkpoint.y, 0), false))
					Draw2DText(CONFIG_CL.hudPosition.x, CONFIG_CL.hudPosition.y + 0.04, ("~y~CHECKPOINT %d/%d (%dm)"):format(raceStatus.checkpoint-1, #race.checkpoints, checkpointDist), 0.5)
					Draw2DText(CONFIG_CL.hudPosition.x, CONFIG_CL.hudPosition.y + 0.07, ("~y~Lap %d/%d"):format(raceStatus.lap, race.laps), 0.5)
				end

			elseif raceStatus.state == RACE_STATE_JOINED then --Player joined, waiting for countdown
				-- Check countdown to race start
				local race = races[raceStatus.index]
				local currentTime = GetGameTimer()
				local count = race.startTime - currentTime
				if count <= 0 then
					-- Race started, set racing state and unfreeze vehicle position
					raceStatus.state = RACE_STATE_RACING
					raceStatus.checkpoint = 0
					FreezeEntityPosition(vehicle, false)
				elseif count <= CONFIG_CL.freezeDuration then
					-- Display countdown text and freeze vehicle position
					Draw2DText(0.5, 0.4, ("~y~%d"):format(math.ceil(count/1000.0)), 3.0)
					FreezeEntityPosition(vehicle, true)
				else
					-- Draw 3D start time and join text
					-- local temp, zCoord = GetGroundZFor_3dCoord(race.startCoords.x, race.startCoords.y, 9999.9, 1)
					Draw3DText(race.startCoords.x, race.startCoords.y, race.startCoords.z+1.0, ("Race starting in ~y~%d~w~s"):format(math.ceil(count/1000.0)))
					Draw3DText(race.startCoords.x, race.startCoords.y, race.startCoords.z+0.80, "Joined")
				end
			elseif raceStatus.state == RACE_STATE_NONE and raceStatus.checkpoint ~= 0 then
				ClearBlipsAndCheckpoints()
				ResetRace()
			else -- Player isn't in a race
				-- Loop through all the races
				if #races == 0 then
					Wait(1000)
				end
				for index, race in pairs(races) do
					-- Get current time and player proximity to start
					local currentTime = GetGameTimer()
					-- local proximity = GetDistanceBetweenCoords(position.x, position.y, position.z, race.startCoords.x, race.startCoords.y, race.startCoords.z, true)
					local proximity = #(position - vector3(race.checkpoints[1].x, race.checkpoints[1].y, race.checkpoints[1].z))

					-- When in proximity and race hasn't started draw 3D text and prompt to join
					if proximity < CONFIG_CL.joinProximity and currentTime < race.startTime then
						-- Draw 3D text
						local count = math.ceil((race.startTime - currentTime)/1000.0)
						-- local temp, zCoord = GetGroundZFor_3dCoord(race.startCoords.x, race.startCoords.y, 9999.9, 0)
						Draw3DText(race.startCoords.x, race.startCoords.y, race.startCoords.z+1.0, ("Race starting in ~y~%d~w~s"):format(count))
						Draw3DText(race.startCoords.x, race.startCoords.y, race.startCoords.z+0.80, "Press [~g~E~w~] to join")

						-- Check if player enters the race and send join event to server
						if IsControlJustReleased(1, CONFIG_CL.joinKeybind) then
							TriggerServerEvent('racing:joinRace_sv', index)
							break
						end
					end
				end
			end
		else
			Wait(500)
		end
	end
end)


-- Thread for recording a race
CreateThread(function ()
	while true do
		if raceStatus.state == RACE_STATE_RECORDING then
			local ped = PlayerPedId()
			local pos = GetEntityCoords(ped)
			if IsPedInAnyVehicle(ped, false) then
				if IsControlJustPressed(0, 16) then
					if (IsControlPressed(0, 209)) then
						realSize = realSize-0.2
					else
						realSize = realSize-1.0
					end
					if realSize < 4.0 then
						realSize=4.0
					end
				end
				if IsControlJustPressed(0, 17) then
					if (IsControlPressed(0, 209)) then
						realSize = realSize+0.2
					else
						realSize = realSize+1.0
					end
					if realSize > 60.0 then
						realSize=60.0
					end
				end

				Draw3DText(pos.x,pos.y,pos.z+1.0,"[E] Add | [Shift + E] Remove | Scroll wheel ⬆ Radius ⬇")
				DrawMarker(1, pos.x, pos.y, pos.z-0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, realSize, realSize, 0.3, 255, 0, 0, 255, false, false,
												2, nil, nil, false)
				if IsControlJustPressed(0, 38) then
					if (IsControlPressed(0, 21)) then
						PopLastCheckpoint()
					else
						AddCheckPoint()
					end
				end
			else
				Draw3DText(pos.x,pos.y,pos.z+1.0,"Enter an vehicle to continue")
			end
			Wait(0)
		else
			Wait(1000)
		end
	end
end)

function LoadCheckpointModels()
	local models = {}
	models[1] = "prop_offroad_tyres02"
	models[2] = "prop_beachflag_01"
	for i = 1, #models do
		local checkpointModel = GetHashKey(models[i])
		RequestModel(checkpointModel)
		while not HasModelLoaded(checkpointModel) do
			Wait(1)
		end
	end
end

function AddCheckPoint()
	LoadCheckpointModels()
	local ped = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(ped)
	local vehiclecoords = GetEntityCoords(vehicle)
	local diff = realSize/2
	local fx,fy,fz = table.unpack(GetOffsetFromEntityInWorldCoords(vehicle,  diff, 0.0, -0.25))
	local fx2,fy2,fz2 = table.unpack(GetOffsetFromEntityInWorldCoords(vehicle, 0.0 - diff, 0.0, -0.25))

	AddCheckpointMarker(vector3(fx,fy,fz), vector3(fx2,fy2,fz2))

	local start = false

	if #currentMap == 0 then
		start = true
	end

	local checkcounter = #currentMap + 1
	currentMap[checkcounter] = {
		["marker1x"] = FUCKK(fx), ["marker1y"] = FUCKK(fy), ["marker1z"] = FUCKK(fz),
		["marker2x"] = FUCKK(fx2), ["marker2y"] = FUCKK(fy2), ["marker2z"] = FUCKK(fz2),
		["x"] = FUCKK(vehiclecoords.x),  ["y"] = FUCKK(vehiclecoords.y), ["z"] = FUCKK(vehiclecoords.z-1.1), ["start"] = start, ["dist"] = diff, ["checkpoint"] = checkcounter,
	}

	local key = #SetBlips+1
	SetBlips[key] = AddBlipForCoord(vehiclecoords.x,vehiclecoords.y,vehiclecoords.z)
	SetBlipAsFriendly(SetBlips[key], true)
	SetBlipSprite(SetBlips[key], 1)
	ShowNumberOnBlip(SetBlips[key], key)
	BeginTextCommandSetBlipName("STRING");
	AddTextComponentString(tostring("Checkpoint " .. key))
	EndTextCommandSetBlipName(SetBlips[key])
end

function PopLastCheckpoint()
	if #currentMap > 1 then
		local lastCheckpoint = #currentMap
		SetEntityAsNoLongerNeeded(checkpointMarkers[lastCheckpoint].left)
		DeleteObject(checkpointMarkers[lastCheckpoint].left)
		SetEntityAsNoLongerNeeded(checkpointMarkers[lastCheckpoint].right)
		DeleteObject(checkpointMarkers[lastCheckpoint].right)
		RemoveBlip(SetBlips[lastCheckpoint])
		table.remove(checkpointMarkers)
		table.remove(currentMap)
		table.remove(SetBlips)
	end
end

function AddCheckpointMarker(leftMarker, rightMarker)
	local model = #checkpointMarkers == 0 and 'prop_beachflag_01' or 'prop_offroad_tyres02'

	local checkpointLeft = CreateObject(GetHashKey(model), leftMarker, false, false, false)
	local checkpointRight = CreateObject(GetHashKey(model), rightMarker, false, false, false)
	checkpointMarkers[#checkpointMarkers+1] = {
		left = checkpointLeft,
		right = checkpointRight
	}
	PlaceObjectOnGroundProperly(checkpointLeft)
	SetEntityAsMissionEntity(checkpointLeft)
	PlaceObjectOnGroundProperly(checkpointRight)
	SetEntityAsMissionEntity(checkpointRight)
end

function LoadMapBlips(race)

	ClearBlipsAndCheckpoints()
	LoadCheckpointModels()
	if(race.checkpoints ~= nil) then
		local checkpoints = race.checkpoints
		for mId, map in pairs(checkpoints) do
			local key = #SetBlips+1
			-- SetBlips[key] = AddBlipForCoord(ToFloat(map["x"]),ToFloat(map["y"]),ToFloat(map["z"]))
			SetBlips[key] = AddBlipForCoord(vector3(map["x"],map["y"],map["z"]))
			SetBlipAsFriendly(SetBlips[key], true)
			SetBlipAsShortRange(SetBlips[key], true)
			SetBlipSprite(SetBlips[key], 1)
			SetBlipColour(SetBlips[key], 0)
			ShowNumberOnBlip(SetBlips[key], key)
			BeginTextCommandSetBlipName("STRING");
			AddTextComponentString(tostring("Checkpoint " .. key))
			EndTextCommandSetBlipName(SetBlips[key])

			AddCheckpointMarker(vector3(map["marker1x"], map["marker1y"], map["marker1z"]), vector3(map["marker2x"], map["marker2y"], map["marker2z"]))
		end
	end
end

function SaveMap(name)
  -- get distance here between checkpoints

	local distanceMap = 0.0
	for i = 1, #currentMap do
		if i == #currentMap then
			distanceMap = Vdist(currentMap[i]["x"],currentMap[i]["y"],currentMap[i]["z"], currentMap[1]["x"],currentMap[1]["y"],currentMap[1]["z"]) + distanceMap
		else
			distanceMap = Vdist(currentMap[i]["x"],currentMap[i]["y"],currentMap[i]["z"], currentMap[i+1]["x"],currentMap[i+1]["y"],currentMap[i+1]["z"]) + distanceMap
		end
	end
	distanceMap = math.ceil(distanceMap)

	if #currentMap > 1 then
		TriggerServerEvent("racing:save-map", currentMap, name, distanceMap, GetPlayerName(PlayerId()))
	else
		return TriggerEvent('chat:addMessage', {
					color = { 255, 0, 0},
					multiline = true,
					args = {"[Races]", "Your race has zero checkpoints? lol"}
				})
	end
end

RegisterNetEvent("racing:saved")
AddEventHandler("racing:saved", function ()
	currentMap = {}
	raceStatus.state = RACE_STATE_NONE
	ClearBlipsAndCheckpoints()
end)

function ResetRace()
	currentMap = {}
	raceStatus.index = 0
	raceStatus.checkpoint = 0
	raceStatus.state = RACE_STATE_NONE
	raceStatus.lap = 0
	raceStatus.lapTime = 0
	raceStatus.lastLapTime = 0
	raceStatus.fastestLap = 0
end

function Draw2DText(x, y, text, scale)
	-- Draw text on screen
	SetTextFont(4)
	SetTextProportional(7)
	SetTextScale(scale, scale)
	SetTextColour(255, 255, 255, 255)
	SetTextDropShadow(0, 0, 0, 0,255)
	SetTextDropShadow()
	SetTextEdge(4, 0, 0, 0, 255)
	SetTextOutline()
	SetTextEntry("STRING")
	AddTextComponentString(text)
	DrawText(x, y)
end

function Draw3DText(x, y, z, text)
	-- Check if coords are visible and get 2D screen coords
	local onScreen, _x, _y = World3dToScreen2d(x, y, z)
	if onScreen then
			-- Calculate text scale to use
			local dist = GetDistanceBetweenCoords(GetGameplayCamCoords(), x, y, z, 1)
			local scale = 1.2*(1/dist)*(1/GetGameplayCamFov())*100

			-- Draw text on screen
			SetTextScale(scale, scale)
			SetTextFont(4)
			SetTextProportional(1)
			SetTextColour(255, 255, 255, 255)
			SetTextDropShadow(0, 0, 0, 0,255)
			SetTextDropShadow()
			SetTextEdge(4, 0, 0, 0, 255)
			SetTextOutline()
			SetTextEntry("STRING")
			SetTextCentre(1)
			AddTextComponentString(text)
			DrawText(_x, _y)
	end
end

function FUCKK(num)
	local new = math.ceil(num*100.0)
	new = new / 100.0
	return new
end

function ClearBlipsAndCheckpoints()
	ClearBlips()
	RemoveCheckpoints()
end

function ClearBlips()
	for i = 1, #SetBlips do
		RemoveBlip(SetBlips[i])
	end
	SetBlips = {}
end

function RemoveCheckpoints()
  for i = 1, #checkpointMarkers do
	SetEntityAsNoLongerNeeded(checkpointMarkers[i].left)
	DeleteObject(checkpointMarkers[i].left)
	SetEntityAsNoLongerNeeded(checkpointMarkers[i].right)
	DeleteObject(checkpointMarkers[i].right)
	checkpointMarkers[i] = nil
  end
end

RegisterNetEvent("racing:notify")
AddEventHandler("racing:notify", function (msg)
	TriggerEvent('chat:addMessage', {
			color = { 255, 0, 0},
			multiline = true,
			args = {"[Races]", msg}
	})
end)

function Trim(s)
   return s:gsub("^%s+", ""):gsub("%s+$", "")
end

function TableToString(tab)
	local str = ""
	for i = 1, #tab do
		str = str .. " " .. tab[i]
	end
	return Trim(str)
end

function NextBlip(blip)
	SetBlipRoute(blip, true)
	SetBlipColour(blip, CONFIG_CL.checkpointBlipColor)
	SetBlipRouteColour(blip, CONFIG_CL.checkpointBlipColor)
	SetBlipScale(blip, 1.5)
end