
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
ability02LocationCache = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	
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
	
	if ( item_horse_green~=nil and item_horse_green:IsFullyCastable() )
	then 
		castItemHorseGreenDesire = ConsiderItemHorseGreen(item_horse_green)
		if ( castItemHorseGreenDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_green )
			return
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then 
		castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_horse_king )
			return
		end
	end
end
	

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	local npcBot = GetBot()
	
	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_sagume_1" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_sagume_2" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_sagume_3" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_sagume_4" )

	-- Consider using each ability

	cast01Desire, cast01Target = ConsiderAbilitySagume01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability01 , cast01Target)
		return
	end
	
	cast02Desire, cast02Location = ConsiderAbilitySagume02()
	if ( cast02Desire > 0 ) 
	then
		if npcBot:GetLevel() >=25 and npcBot:HasModifier("modifier_ability_sagume_telent7_check") then
			npcBot:Action_UseAbility( ability02 )
		else
			npcBot:Action_UseAbilityOnLocation( ability02, cast02Location )
		end
		return
	end
	
	cast03Desire, cast03Target = ConsiderAbilitySagume03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability03 , cast03Target)
		return
	end
	
	cast04Desire, cast04Target = ConsiderAbilitySagume04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastSagume01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSagume03OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastSagume04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 700

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastSagume01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end
		
	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end

	-- Get some of its values
	local nCastRange = ability02:GetLevel()*100 + 400
	if npcBot:GetLevel() >= 25 then
		ability02LocationCache = npcBot:GetLocation()
	end
	--------------------------------------
	-- Mode based usage
	--------------------------------------
	if not npcBot:HasModifier("modifier_ability_sagume_telent7_check") then 
		if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK or
			 npcBot:GetActiveMode() == BOT_MODE_ROAM or
			 npcBot:GetActiveMode() == BOT_MODE_TEAM_ROAM or
			 npcBot:GetActiveMode() == BOT_MODE_GANK or
			 npcBot:GetActiveMode() == BOT_MODE_DEFEND_ALLY ) 
		then
			local npcTarget = npcBot:GetTarget()
			
			if npcBot:GetTarget() ~= nil then
				local disT = GetUnitToUnitDistance( npcBot, npcBot:GetTarget())
				local dimin = 200
				local dimax = 200 + nCastRange + npcBot:GetLevel() * 10
				if disT > dimin and disT < dimax then
					return BOT_ACTION_DESIRE_HIGH, npcTarget:GetLocation()
				end
			end
		end
		
		if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and 
		npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
			return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
		end
	else
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		if #tableNearbyEnemyHeroes>1 and 
		(npcBot:GetActiveMode() == BOT_MODE_ATTACK or 
		npcBot:GetActiveMode() == BOT_MODE_RETREAT or 
		npcBot:GetActiveMode() == BOT_MODE_GANK )
		then
			return BOT_ACTION_DESIRE_HIGH, 0
		end
	end
	return BOT_ACTION_DESIRE_NONE, 0
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilitySagume03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	-- Get some of its values
	local nCastRange = ability02:GetCastRange()

	-- If we're seriously attacking
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if CanCastSagume03OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) then
				return BOT_ACTION_DESIRE_MODERATE, npcEnemy
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
			if ( CanCastSagume03OnTarget( npcTarget ) )
			then
				return BOT_ACTION_DESIRE_HIGH,npcTarget
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end
----------------------------------------------------------------------------------------------------
function ConsiderAbilitySagume04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	--简易版
	if ( not ability01:IsFullyCastable() ) and ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_HIGH, npcBot
	end
	return BOT_ACTION_DESIRE_NONE, nil
end
