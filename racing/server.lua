local races = {}

RegisterNetEvent("racing:save-map")
AddEventHandler("racing:save-map", function(pCurrentMap, pName, pDistance, pCreator)
	local src = source
	local pCreatorID = GetPlayerIdentifier(source)
	exports.mongodb:findOne({collection = "corridas", query = {name = pName}}, function (success, result)
		if not success then
			print("[MongoDB] Error in findOne: "..tostring(result))
			TriggerClientEvent("racing:notify", src, "Something went wrong")
			return
		end
		if #result == 0 then
		   exports.mongodb:insertOne({collection = "corridas", document = {
			   name = pName, distance = pDistance, checkpoints = pCurrentMap, creator = pCreator, creatorid = pCreatorID
			}}, function (success, result, insertedIds)
				if not success then
					 print("[MongoDB] Error in insertOne: "..tostring(result))
					TriggerClientEvent("racing:notify", src, "Something went wrong2")
					return
				end
				print("[MongoDB] Successfuly inserted: " .. insertedIds[1])
				TriggerClientEvent("racing:saved", src)
				TriggerClientEvent("racing:notify", src, "Salvo com sucesso")
			end)
		end
		if #result ~= 0 then
			return TriggerClientEvent("racing:notify", src, "Já existe uma corrida com esse nome. Tente outro nome.")
		end
	end)
end)

RegisterNetEvent("racing:load-races")
AddEventHandler("racing:load-races", function()
	local src = source
	exports.mongodb:find({collection = "corridas", query = {}}, function (success, result)
		if not success then
		   print("[MongoDB] Error in findOne: "..tostring(result))
			return
		end
		if #result > 0 then
			TriggerClientEvent("racing:loaded-races", src, result, true)
		end
	end)
end)

RegisterNetEvent("racing:load-map")
AddEventHandler("racing:load-map", function(pID)
	local src = source
	-- Get saved player races and load race
	exports.mongodb:findOne({collection = "corridas", query = {_id = pID}}, function (success, result)
		if not success then
			print("[MongoDB] Error in findOne: "..tostring(result))
			TriggerClientEvent("racing:notify", src, "Something went wrong")
			return
		end

		if #result == 1 then
			-- Send race data to client
			TriggerClientEvent("racing:loaded-map", src, result[1])

			-- Send notification to player
			local msg = result[1].name .. " carregado!"
			TriggerClientEvent("racing:notify", src, msg)
		end
	end)
end)

RegisterNetEvent("racing:delete-map") -- Não usado no momento
AddEventHandler("racing:delete-map", function(pName)
	local src = source
	exports.mongodb:deleteOne({collection = "corridas", query = {name = pName}}, function(success, result)
		if not success then
			print("[MongoDB] Error in deleteOne: "..tostring(result))
			TriggerClientEvent("racing:notify", src, "Error")
			return
		end
		print("[MongoDB] Successfuly deleted: " .. result)
		TriggerClientEvent("racing:notify", src, "Deletado com sucesso.")
	end)
end)

-- Server event for creating a race
RegisterNetEvent("racing:createRace_sv")
AddEventHandler("racing:createRace_sv", function(pLaps, pStartDelay, pStartCoords, pCheckpoints)
	local src = source
	-- Add fields to race struct and add to races array
	local race = {
		owner = src,
		startTime = GetGameTimer() + pStartDelay,
		startCoords = pStartCoords,
		checkpoints = pCheckpoints,
		laps = pLaps,
		finishTimeout = CONFIG_SV.finishTimeout,
		players = {},
		finishTime = 0
	}
	table.insert(races, race)

	-- Send race data to all clients
	local index = #races
	TriggerClientEvent("racing:createRace_cl", -1, index, pLaps, pStartDelay, pStartCoords, pCheckpoints)
end)

-- Server event for joining a race
RegisterNetEvent("racing:joinRace_sv")
AddEventHandler("racing:joinRace_sv", function(index)
	local src = source
	-- Add player to race and send join event back to client
	table.insert(races[index].players, src)
	TriggerClientEvent("racing:joinedRace_cl", src, index)
end)

-- Server event for leaving a race
RegisterNetEvent("racing:leaveRace_sv")
AddEventHandler("racing:leaveRace_sv", function(index)
	-- Validate player is part of the race
	local race = races[index]
	local players = race.players
	for index, player in pairs(players) do
		if source == player then
			-- Remove player from race and break
			table.remove(players, index)
			break
		end
	end
end)

-- Server event for finishing a race
RegisterNetEvent("racing:finishedRace_sv")
AddEventHandler("racing:finishedRace_sv", function(index, fastestLap)
	local src = source
	-- Check player was part of the race
	local race = races[index]
	local players = race.players
	for index, player in pairs(players) do
		if source == player then
			-- Calculate finish time
			local gameTime = GetGameTimer()
			local timeSeconds = (gameTime - race.startTime)/1000.0
			local timeMinutes = math.floor(timeSeconds/60.0)
			local fastestTimeSeconds = (fastestLap)/1000.0
			local fastestTimeMinutes = math.floor(fastestTimeSeconds/60.0)
			timeSeconds = timeSeconds - 60.0*timeMinutes
			fastestTimeSeconds = fastestTimeSeconds - fastestTimeMinutes*60.0

			-- If race has not finished already
			if race.finishTime == 0 then
				-- Winner, set finish time and award prize money
				race.finishTime = gameTime
				-- Send winner notification to players
				for _, pSource in pairs(players) do
					if pSource == src then
						local msg = ("Você ganhou: [%02d:%06.3f]"):format(timeMinutes, timeSeconds)
						local msg2 = ("Volta mais rápida: [%02d:%06.3f]"):format(fastestTimeMinutes, fastestTimeSeconds)
						TriggerClientEvent("racing:notify", pSource, msg)
						TriggerClientEvent("racing:notify", pSource, msg2)
					elseif CONFIG_SV.notifyOfWinner then
						local msg = ("%s ganhou [%02d:%06.3f]"):format(getName(src), timeMinutes, timeSeconds)
						TriggerClientEvent("racing:notify", pSource, msg)
					end
				end
			else
				-- Loser, send notification to only the player
				local msg = ("Você perdeu: [%02d:%06.3f]"):format(timeMinutes, timeSeconds)
				local msg2 = ("Volta mais rápida: [%02d:%06.3f]"):format(fastestTimeMinutes, fastestTimeSeconds)
				TriggerClientEvent("racing:notify", src, msg)
				TriggerClientEvent("racing:notify", src, msg2)
			end

			-- Remove player form list and break
			table.remove(players, index)
			break
		end
	end
end)

-- Cleanup thread
CreateThread(function()
	-- Loop forever and check status every 100ms
	while true do
		Wait(100)

		-- Check active races and remove any that become inactive
		for index, race in pairs(races) do
			-- Get time and players in race
			local time = GetGameTimer()
			local players = race.players

			-- Check start time and player count
			if (time > race.startTime) and (#players == 0) then
				-- Race past start time with no players, remove race and send event to all clients
				table.remove(races, index)
				TriggerClientEvent("racing:removeRace_cl", -1, index)
			-- Check if race has finished and expired
			elseif (race.finishTime ~= 0) and (time > race.finishTime + race.finishTimeout) then
				-- Did not finish, notify players still racing
				for _, player in pairs(players) do
					TriggerClientEvent("racing:notify", player, "DNF (timeout)")
				end

				-- Remove race and send event to all clients
				table.remove(races, index)
				TriggerClientEvent("racing:removeRace_cl", -1, index)
			end
		end
	end
end)

function getName(source)
	return GetPlayerName(source)
end