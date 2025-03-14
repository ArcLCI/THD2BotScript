local J = {}

J.Utils = require( GetScriptDirectory()..'/THDFuncLib/utils' )


--- Item 相关方法库 ---
function J.HasItem( bot, sItemName )

	local Slot = bot:FindItemSlot( sItemName )

	if Slot >= 0 and Slot <= 5 then	return true end

	return false

end

----------------------------------------------------------------

--- DotaTime 相关方法库 ---
function J.IsInLaningPhase()
	return DotaTime() < 12 * 60
	and GetBot():GetNetWorth() < 5000
end

----------------------------------------------------------------

--- 距离相关方法库 ---
function J.GetDistance(s, t)
    return math.sqrt((s[1] - t[1]) * (s[1]-t[1]) + (s[2] - t[2]) * (s[2] - t[2]))
end

function J.GetEnemiesAroundAncient(bot, nRadius)
	return J.GetEnemiesAroundLoc(GetAncient(bot:GetTeam()):GetLocation(), nRadius)
end

function J.GetEnemiesAroundLoc(vLoc, nRadius)
	if not nRadius then nRadius = 2000 end
	local cacheKey = 'GetEnemiesAroundLoc'..tostring(nRadius) ..'-'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	if cache ~= nil then return cache end

	local nUnitCount = 0
	local ancientLoc = GetAncient(GetBot():GetTeam()):GetLocation()

	-- Check Heroes. 
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
				and J.GetLocationToLocationDistance(vLoc, dInfo.location) <= nRadius
				and dInfo.time_since_seen < 5.0
				then
					nUnitCount = nUnitCount + GetHeroLevel(id) / 3
					if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then
						nUnitCount = nUnitCount + 2 -- Increase weight for critical defense.
					end
				end
			end
		end
	end

	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES))
	do
		if J.IsValid(unit)
		and GetUnitToLocationDistance(unit, vLoc) <= nRadius
		then
			local unitName = unit:GetUnitName()
			if unit:IsCreep() then
				nUnitCount = nUnitCount + 1
				if unit:IsAncientCreep()
				or unit:HasModifier('modifier_chen_holy_persuasion')
				or unit:HasModifier('modifier_dominated') then
					nUnitCount = nUnitCount + 1
				end
			elseif string.find(unit:GetUnitName(), 'spiderling') then nUnitCount = nUnitCount + 0.1
			elseif string.find(unit:GetUnitName(), 'eidolon') then nUnitCount = nUnitCount + 0.3
			elseif string.find(unitName, 'siege') and not string.find(unitName, 'upgraded') then
				nUnitCount = nUnitCount + 0.6
			elseif string.find(unitName, 'upgraded') then nUnitCount = nUnitCount + 1
			elseif string.find(unitName, 'warlock_golem') then
				if DotaTime() < 10 * 60 then nUnitCount = nUnitCount + 3
				elseif DotaTime() < 20 * 60 then nUnitCount = nUnitCount + 2.5
				elseif DotaTime() < 30 * 60 then nUnitCount = nUnitCount + 2
				else nUnitCount = nUnitCount + 1.5 end
			elseif string.find(unitName, 'lone_druid_bear') then nUnitCount = nUnitCount + 3
			elseif string.find(unitName, 'shadow_shaman_ward') then nUnitCount = nUnitCount + 2
			elseif string.find(unit:GetUnitName(), "tombstone") then nUnitCount = nUnitCount + 2
			elseif J.IsSuspiciousIllusion(unit) then
				if unit:HasModifier('modifier_arc_warden_tempest_double')
					or string.find(unit:GetUnitName(), 'chaos_knight')
					or string.find(unit:GetUnitName(), 'naga_siren') then nUnitCount = nUnitCount + 2 end
			elseif not (string.find(unitName, 'observer_wards') or string.find(unitName, 'sentry_wards')) then nUnitCount = nUnitCount + 1 end
			if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then nUnitCount = nUnitCount + 2 end
		end
	end

	J.Utils.SetCachedVars('GetEnemiesAroundLoc'..cacheKey, nUnitCount)
	return nUnitCount
end

function J.ToNearest500(num)
    return math.floor(num / 500 + 0.5) * 500
end

--RoundToNearestThousand
function J.ToNearest1000(num)
    return math.floor(num / 1000 + 0.5) * 1000
end

function J.GetLocationToLocationDistance( fLoc, sLoc )

	local x1 = fLoc.x
	local x2 = sLoc.x
	local y1 = fLoc.y
	local y2 = sLoc.y

	return math.sqrt( ( y2-y1 )^2 + ( x2-x1 )^2 )

end
----------------------------------------------------------------
---
function J.IsValid( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and not nTarget:IsBuilding()
end

function J.IsSuspiciousIllusion( npcTarget )
	if npcTarget == nil or npcTarget:IsNull() then return false end
	if npcTarget.is_suspicious_illusion ~= nil then
		return npcTarget.is_suspicious_illusion
	end
	if not npcTarget:CanBeSeen() then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	if npcTarget:CanBeSeen() and (
		not npcTarget:IsHero()
		or npcTarget:IsCastingAbility()
		or npcTarget:IsUsingAbility()
		or npcTarget:IsChanneling()
	)
		-- or npcTarget:HasModifier( "modifier_item_satanic_unholy" )
		-- or npcTarget:HasModifier( "modifier_item_mask_of_madness_berserk" )
		-- or npcTarget:HasModifier( "modifier_black_king_bar_immune" )
		-- or npcTarget:HasModifier( "modifier_rune_doubledamage" )
		-- or npcTarget:HasModifier( "modifier_rune_regen" )
		-- or npcTarget:HasModifier( "modifier_rune_haste" )
		-- or npcTarget:HasModifier( "modifier_rune_arcane" )
		-- or npcTarget:HasModifier( "modifier_item_phase_boots_active" )
	then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	local bot = GetBot()

	if npcTarget:GetTeam() == bot:GetTeam()
	then
		npcTarget.is_suspicious_illusion = npcTarget:IsIllusion() or npcTarget:HasModifier( "modifier_arc_warden_tempest_double" )
		return npcTarget.is_suspicious_illusion
	elseif npcTarget:GetTeam() == GetOpposingTeam()
	then

		if npcTarget:HasModifier( 'modifier_illusion' )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		local tID = npcTarget:GetPlayerID()

		if not IsHeroAlive( tID )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		if GetHeroLevel( tID ) > npcTarget:GetLevel()
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end
		--[[
		if GetSelectedHeroName( tID ) ~= "npc_dota_hero_morphling"
			and GetSelectedHeroName( tID ) ~= npcTarget:GetUnitName()
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end
		--]]
	end

	npcTarget.is_suspicious_illusion = false
	return false

end