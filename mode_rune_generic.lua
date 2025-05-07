
--local RUNE_LOCATIONS = {RUNE_POWERUP_1,RUNE_POWERUP_2,RUNE_BOUNTY_1,RUNE_BOUNTY_2,RUNE_BOUNTY_3,RUNE_BOUNTY_4}
local RUNE_LOCATIONS = {RUNE_POWERUP_1,RUNE_POWERUP_2,RUNE_BOUNTY_1,RUNE_BOUNTY_2}
local RUNE_LOCATIONS_POWERUP = {RUNE_POWERUP_1,RUNE_POWERUP_2}
local RUNE_LOCATIONS_BOUNTY = {RUNE_BOUNTY_1,RUNE_BOUNTY_2}
local debug_printed = false

--signal to exit this think phase immediately
local stop_this_think = false

targetRuneID = -1

function HasRune( runeID )
	if GetRuneStatus( runeID ) ~= RUNE_STATUS_AVAILABLE then return false end
	if GetRuneType( runeID ) == RUNE_ILLUSION then return false end
	if GetRuneType( runeID ) == RUNE_INVALID then return false end
	return true
end

function GetNearestRuneID( runeType )

	local npcBot = GetBot()
	local dis = 7000
	local rune_id = -1
	
	local RUNE_LOCS = RUNE_LOCATIONS
	
	if runeType == 1 then RUNE_LOCS = RUNE_LOCATIONS_POWERUP end
	if runeType == 2 then RUNE_LOCS = RUNE_LOCATIONS_BOUNTY end
	
	for _,i in pairs(RUNE_LOCS) do
		local t_dis = GetUnitToLocationDistance(npcBot,GetRuneSpawnLocation(i))
		if t_dis < dis then
			dis = t_dis
			rune_id = i
		end
	end
	
	return rune_id
	
end


function GetDesire()
	
	if not debug_printed then
		print('=========================================')
		print('rune_generic_ok')
		
		for _,i in pairs(RUNE_LOCATIONS) do
			print(i)
			print(GetRuneSpawnLocation(i))
		end
		
		print('=========================================')
		
		debug_printed = true
	end
	
	if stop_this_think then
		stop_this_think = false
		return 0
	end
	
	local npcBot = GetBot()
	local t = DotaTime()
	local mod_t1 = t % 120
	local mod_t2 = t % 180
	local base_desire = 0
	
	for _,i in pairs(RUNE_LOCATIONS) do
		if GetUnitToLocationDistance(npcBot,GetRuneSpawnLocation(i)) < 600 then
			if HasRune(i) then
				if GetUnitToLocationDistance(npcBot,GetRuneSpawnLocation(i)) > 120 then
					print('should pickup')
					return 1.0
				else
					print('too close')
					return 0 --auto pickup?
				end
			end
		end
	end
	
	if t > -15 and t < 3 then
	
		base_desire = 0.98
		
	elseif t > 100 then
		
		local runeType = 0
		
		if mod_t1 > 105 or mod_t1 < 2 then
			if npcBot:GetAssignedLane() == LANE_MID then
				if t < 900 then runeType = 1 end
				base_desire = 0.95 ^ ( 1.0 + math.floor( t / 60.0 ) )
			end
		end
	
		if mod_t2 > 165 or mod_t2 < 2 then
			if npcBot:GetAssignedLane() ~= LANE_MID then
				if t < 900 then runeType = 2 end
				base_desire = 0.95 ^ ( 1.0 + math.floor( t / 60.0 ) )
			end
		end
		
		if GetNearestRuneID(runeType) == -1 then
			base_desire = 0
		end
		
	end

	if base_desire > 0 and npcBot:WasRecentlyDamagedByAnyHero( 3.0 ) then
		base_desire = base_desire / 5
	end
	
	return base_desire
	
end


function OnStart()

	local npcBot = GetBot()
	local t = DotaTime()
	local mod_t1 = t % 120
	local mod_t2 = t % 180
	local base_desire = 0
	
	targetRuneID = -1
	
	for _,i in pairs(RUNE_LOCATIONS) do
		if GetUnitToLocationDistance(npcBot,GetRuneSpawnLocation(i)) < 600 then
			if HasRune(i) then
				targetRuneID = i
				return
			end
		end
	end
	
	local runeType = 0
	
	if targetRuneID < 0 and (mod_t1 > 105 or mod_t1 < 5 or t < 10) then
		if npcBot:GetAssignedLane() == LANE_MID then
			--targetRuneID = RUNE_LOCATIONS[RandomInt(1,2)]
			if t < 900 then runeType = 1 end
			targetRuneID = GetNearestRuneID(runeType)
		end
	end
		
	if targetRuneID < 0 and (mod_t2 > 165 or mod_t2 < 5 or t < 10) then
		if npcBot:GetAssignedLane() ~= LANE_MID then
			--targetRuneID = RUNE_LOCATIONS[RandomInt(3,6)]
			if t < 900 then runeType = 2 end
			targetRuneID = GetNearestRuneID(runeType)
		end
	end
		
		
end


function OnEnd()
	targetRuneID = -1
end

local last_move_time = -2333

function Think()
	
	if targetRuneID == -1 then return end
	
	local t = DotaTime()
	local npcBot = GetBot()
	local targetRuneLocation = GetRuneSpawnLocation( targetRuneID )
	
	--pick up
	if HasRune( targetRuneID ) then
		if GetUnitToLocationDistance(npcBot,GetRuneSpawnLocation(targetRuneID)) > 80 then
			npcBot:Action_MoveDirectly( targetRuneLocation )
		else
			print(string.format("%s: %d",'rune_pickup', targetRuneID))
			--npcBot:Action_PickUpRune( targetRuneID )
			--npcBot:Action_PickUpRune()
			stop_this_think = true
			targetRuneID = -1
		end
	--bad
	elseif GetRuneStatus( targetRuneID ) ~= RUNE_STATUS_UNKNOWN and t%60 < 30 and t%60 > 2 then
		print(string.format("%s: %d stopped",'rune_pickup', targetRuneID))
		stop_this_think = true
		targetRuneID = -1
	--wait
	elseif DotaTime() - last_move_time > 0.5 then
		local movementTarget = targetRuneLocation + RandomVector( 300 )
		npcBot:Action_MoveDirectly( movementTarget )
		last_move_time = DotaTime()
	end
	
end
