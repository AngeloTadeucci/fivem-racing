-- CLIENT CONFIGURATION
CONFIG_CL = {
	joinProximity = 45,                 -- Proximity to draw 3D text and join race
	joinKeybind = 51,                   -- Keybind to join race ("E" by default)
	joinDuration = 30000,               -- Duration in ms to allow players to join the race
	freezeDuration = 5000,              -- Duration in ms to freeze players and countdown start (set to 0 to disable)
	checkpointBlipColor = 3,            -- Color of checkpoint map blips and navigation (see SetBlipColour native reference)
	hudEnabled = true,                  -- Enable racing HUD with time and checkpoints
	hudPosition = vec(0.015, 0.700)     -- Screen position to draw racing HUD
}

-- SERVER CONFIGURATION
CONFIG_SV = {
	finishTimeout = 180000,             -- Timeout in ms for removing a race after winner finishes
	notifyOfWinner = true               -- Notify all players of the winner (false will only notify the winner)
}
