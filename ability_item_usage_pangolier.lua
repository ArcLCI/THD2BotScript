
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
castExDesire = 0

last_time = 0
function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	item_stun = IsItemAvailable( "item_yuetufensuijvren" )
	if item_stun == nil then
		item_stun = IsItemAvailable( "item_pocket_watch" )
	end
	
	if ( item_stun~=nil and item_stun:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemStunDesire, castItemStunTarget = ConsiderItemStun(item_stun)
		if ( castItemStunDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_stun, castItemStunTarget )
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


----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	ConsiderNeutralItems()

	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_flandrev2_01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_flandrev2_02" )
	ability3A = npcBot:GetAbilityByName( "ability_thdots_flandrev2_04" )
	ability3B = npcBot:GetAbilityByName( "ability_thdots_flandrev2_05" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_flandrev2_06" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_flandrev2_wanbaochui" )

	-- Consider using each ability
	cast01Desire, cast01Target = ConsiderAbilityFlandrev201()
	if ( cast01Desire > 0 ) 
	then
		if not npcBot:HasModifier("modifier_ability_thdots_flandrev2_01_change") then
			npcBot:Action_UseAbilityOnEntity( ability01, cast01Target )
		else
			npcBot:Action_UseAbility( ability01)
		end
		return
	end

	cast02Desire = ConsiderAbilityFlandrev202()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end
	
	cast3ADesire, cast3BDesire = ConsiderAbilityFlandrev203()
	if ( cast3ADesire > cast3BDesire ) then
		last_time = GameTime()
		npcBot:Action_UseAbility( ability3A )
		return
	elseif ( cast3ADesire < cast3BDesire ) then
		last_time = GameTime()
		npcBot:Action_UseAbility( ability3B )
		return
	end
	
	cast04Desire, cast04Target = ConsiderAbilityFlandrev204()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target)
		return
	end
	if npcBot:HasScepter() then
		castExDesire = ConsiderAbilityFlandrev2Ex()
		if ( castExDesire > 0 ) 
		then
			npcBot:Action_UseAbility( abilityEx )
		end
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastFlandrev201OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end

function CanCastFlandrev204OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false, { allowMagicImmune = true })
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityFlandrev201()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	--local nCastRange = ability01:GetCastRange()
	local nCastRange = npcBot:GetAttackRange() * 0.7

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastFlandrev201OnTarget( npcEnemy ) ) 
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end
	end
		
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityFlandrev202()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	local nCastRange = 180 + ability02:GetLevel()*30
	if ( npcBot:GetActiveMode() == BOT_MODE_GANK or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcEnemy ~= nil ) 
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityFlandrev203()

	local npcBot = GetBot()

	-- Make sure it's castable
	if (not ability3A:IsFullyCastable()) or (not ability3B:IsFullyCastable())
	then 
		return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE
	end
	
	local least_interval = 1
	if npcBot:GetLevel() >= 15 then
		least_interval = 0.5
	end
	
	local Is3AOn = npcBot:HasModifier("modifier_ability_thdots_flandrev2_04")
	local Is3BOn = npcBot:HasModifier("modifier_ability_thdots_flandrev2_05")
	local nCastRange = npcBot:GetAttackRange()
	
	--切换瞬间就会掉血 所以当开着一个的时候就等一等再切
	if Is3AOn or Is3BOn then
		if GameTime() - last_time < 2 then
			return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE
		end
	end
	
	--挨打开3A
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	if (npcBot:WasRecentlyDamagedByAnyHero(least_interval) or IsUnderAttack(npcBot,true)) and #tableNearbyEnemyHeroes > 0 then
		-- print("flandrev2 3A")
		-- print(Is3AOn, Is3BOn)
		if not Is3AOn then	
			return BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_NONE
		end
	end
	
	--打人开3B
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
	local Target = npcBot:GetTarget()
		if ( Target == npcEnemy ) 
		then
			local TargetDistance = GetUnitToUnitDistance(npcBot, Target)
			if TargetDistance <= nCastRange then --能打着，开3B
				-- print("flandrev2 3B")
				-- print(Is3AOn, Is3BOn)
				if not Is3BOn then						
					return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end
	
	--无所谓开着哪个
	if npcBot:GetLevel() >= 25 then
		return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE
	end
	--关闭所有
	if not (#tableNearbyEnemyHeroes > 0) then
		-- print("flandrev2 3C")
		-- print(Is3AOn, Is3BOn)
		if Is3AOn then
			return BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_NONE
		elseif Is3BOn then
			return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH
		else
			return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE
		end
	end
	return BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityFlandrev204()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = 850

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastFlandrev204OnTarget( npcEnemy ) ) 
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end
	end
		
	return BOT_ACTION_DESIRE_NONE, nil
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityFlandrev2Ex()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local nCastRangeEnemy = 800
	local nCastRangeFriend = 1200
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRangeEnemy, true, BOT_MODE_NONE )
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRangeFriend, false, BOT_MODE_NONE )
	
	if not (#tableNearbyFriendlyHeroes > 0) and #tableNearbyEnemyHeroes > 2 then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end