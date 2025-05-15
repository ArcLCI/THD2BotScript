
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0


function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	local item_blue = IsItemAvailable( "item_yatagarasu" ) or IsItemAvailable( "item_yueyaomishi" )
	if ( item_morenjingjuan~=nil and item_morenjingjuan:IsFullyCastable() )
	then
		--print("stun item exist")
		castItemMoRenDesire, castItemMoRenTarget = ConsiderItemRoot( item_morenjingjuan )
		if ( castItemMoRenDesire > 0 )
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_morenjingjuan, castItemMoRenTarget )
			return
		end
	end
	if ( item_blue~=nil and item_blue:IsFullyCastable() )
	then
		castItemBlueDesire = ConsiderItemBlue(item_blue)
		if ( castItemBlueDesire > 0 )
		then
			npcBot:Action_UseAbility(item_blue)
			return
		end
	end
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_yumemi01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_yumemi02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_yumemi03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_yumemi04" )

	--cross_index = npcBot:GetModifierByName("modifier_ability_thdots_yumemiEx_cross")
	--cross_num = npcBot:GetModifierStackCount(cross_index)

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityYumemi01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01, cast01Location)
		return
	end

	cast02Desire, cast02Location = ConsiderAbilityYumemi02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability02, cast02Location)
		return
	end

	cast03Desire = ConsiderAbilityYumemi03()
	if ( cast03Desire > 0 )
	then
		npcBot:Action_UseAbility( ability03)
		return
	end

	cast04Desire = ConsiderAbilityYumemi04()

	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbility( ability04)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastYumemi01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastYumemi02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastYumemi03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastYumemi04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityYumemi01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = ability01:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastYumemi01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYumemi02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local lvl = ability02:GetLevel()
	if (npcBot:GetMana() < 200 - lvl * 25)
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end
	--if ability02:GetLevel() == 4 then
	--------------------------------------
	-- Mode based usage
	--------------------------------------
	local nCastRange = 600 + lvl * 250
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK) then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			local target1 = npcBot:GetTarget()
			if ( target1 == npcEnemy and GetUnitToUnitDistance(npcBot,npcEnemy)>=500)
			then
				if (target1:GetHealth() < target1:GetMaxHealth()*0.3) then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
					--[[
				else
					local v = npcBot:GetLocation() + 0.6*(npcEnemy:GetLocation()-npcBot:GetLocation())
					return BOT_ACTION_DESIRE_HIGH, v
					--]]
				end
			end
		end
	end
	-- If we're going after someone
	if ( npcBot:GetActiveMode() == BOT_MODE_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
		 npcBot:GetActiveMode() == BOT_MODE_GANK or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY )
	then
		local npcTarget = npcBot:GetTarget()

		if ( npcTarget ~= nil )
		then
			if ( CanCastYumemi01OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
			end
		end
	end
	--end
	if IsSeriouslyRetreating(npcBot) then
		return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
	end
	return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityYumemi03()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_OUTPOST )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Fighting or Retreating with hero
	if (npcBot:GetActiveMode() == BOT_MODE_ATTACK or npcBot:GetActiveMode() == BOT_MODE_RETREAT)
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 300, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil )
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	local tableNearbyEnemyHeroes0 = CachedGetNearbyHeroes( npcBot, 850, true, BOT_MODE_NONE )
	if (#tableNearbyEnemyHeroes0 == 0 or npcBot:GetActiveMode() == BOT_MODE_LANING)
	then
		return BOT_ACTION_DESIRE_MODERATE
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityYumemi04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end
	if (npcBot:HasModifier("modifier_item_morenjingjuan_buff"))
	then
		return BOT_ACTION_DESIRE_NONE
	end
	--[[
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
	-- Get some of its values
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 500, true, BOT_MODE_NONE )
		local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 800, false, BOT_MODE_NONE )

		if #tableNearbyEnemyHeroes > 0 and 
		(#tableNearbyEnemyHeroes <= #tableNearbyFriendlyHeroes + 1 or
		#tableNearbyFriendlyHeroes >3) then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end
	--]]
	if ( npcBot:HasModifier("modifier_fountain_aura_buff"))
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE )
		if (#tableNearbyEnemyHeroes > 0)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

