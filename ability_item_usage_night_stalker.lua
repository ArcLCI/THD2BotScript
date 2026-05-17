
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
castExDesire = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
	local item_frock = IsItemAvailable( "item_frock" )
	local item_root = IsItemAvailable( "item_tentacle" )
	local item_feixiangjian = IsItemAvailable( "item_feixiangjian" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then 
		castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end
	
	if ( item_feixiangjian~=nil and item_feixiangjian:IsFullyCastable() )
	then 
		castItemFeiXiangJianDesire, castItemFeiXiangJianTarget = ConsiderItemFeiXiangJian( item_feixiangjian )
		if ( castItemFeiXiangJianDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_feixiangjian, castItemFeiXiangJianTarget )
			return
		end
	end
	if ( item_frock~=nil and item_frock:IsFullyCastable() )
	then 
		castItemDuQunDesire = ConsiderItemDuQun(item_frock)
		if ( castItemDuQunDesire > 0 ) 
		then
			npcBot:Action_UseAbility(item_frock)
			return
		end
	end
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_speed )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_mystia01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_mystia02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_mystia04" )
	abilityEx = npcBot:GetAbilityByName( "ability_thdots_mystiaEx" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityMystia01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01)
		return
	end

	cast02Desire = ConsiderAbilityMystia02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02)
		return
	end

	cast04Desire = ConsiderAbilityMystia04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability04)
		return
	end

	castExDesire = ConsiderAbilityMystiaEx()
	
	if ( castExDesire > 0 ) 
	then
		npcBot:Action_UseAbility( abilityEx)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastMystia01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastMystia02OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false, { allowMagicImmune = true })
end

function CanCastMystia04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastMystiaExOnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityMystia01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 550, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMystia01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
		
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMystia02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1000, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMystia02OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy )) 
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end

	return BOT_ACTION_DESIRE_NONE
end


----------------------------------------------------------------------------------------------------

function ConsiderAbilityMystia04()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 750, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastMystia04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ) and
				(npcBot:GetActiveMode() == BOT_MODE_RETREAT or 
				(npcBot:GetActiveMode() == BOT_MODE_ATTACK and #tableNearbyEnemyHeroes>1))) 
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
		
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityMystiaEx()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not abilityEx:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT or npcBot:GetActiveMode() == BOT_MODE_ATTACK ) 
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	return BOT_ACTION_DESIRE_NONE
end

