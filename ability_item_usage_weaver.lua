
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
	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_green = IsItemAvailable( "item_horse_green" )
	local item_horse_blue = IsItemAvailable( "item_horse_blue" )
	local item_horse_king = IsItemAvailable( "item_horse_king")
	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	local item_xinyan = IsItemAvailable( "item_third_eyes" )
	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	local item_qijizhixing = IsItemAvailable( "item_qijizhixing" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	if ( item_xinyan~=nil and item_xinyan:IsFullyCastable() )
	then 
		castItemXinYanDesire, castItemXinYanTarget = ConsiderItemXinYan( item_xinyan )
		if ( castItemXinYanDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_xinyan, castItemXinYanTarget )
			return
		end
	end
	
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then 
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end
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
	if ( item_qijizhixing~=nil and item_qijizhixing:IsFullyCastable() )
	then 
		castItemQiJjZhiXingDesire, castItemQiJjZhiXingTarget = ConsiderItemQiJiZhiXing(item_qijizhixing)
		if ( castItemQiJjZhiXingDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_qijizhixing, castItemQiJjZhiXingTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_lyrica01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_lyrica02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_lyrica03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_lyrica04" )

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityLyrica01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
		return
	end

	cast02Desire, cast02Target = ConsiderAbilityLyrica02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability02, cast02Target )
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityLyrica04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastLyrica01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastLyrica02OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastLyrica04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLyrica01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, 0
	end
	
	local nCastRange = 500
	local nRadius = ability01:GetSpecialValueInt( "radius" )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange+200, true, BOT_MODE_NONE )
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	--救人
	if #tableNearbyEnemyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.5 and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )
				)
				) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend:GetLocation()
			end
		end
	end
	--追击
	if npcBot:GetActiveMode() == BOT_MODE_ATTACK then
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			local target1 = npcBot:GetTarget()
			if ( target1 == npcEnemy and 
			GetUnitToUnitDistance(npcBot,npcEnemy)>=400 and
			target1:GetHealth() < target1:GetMaxHealth()*0.3
			) 
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
			end
		end
	end
		--逃命
	if npcBot:GetActiveMode() == BOT_MODE_RETREAT then
		return BOT_ACTION_DESIRE_HIGH, GetShopLocation(npcBot:GetTeam(),SHOP_HOME)
	end
	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLyrica02()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end

	-- Get some of its values
	local nCastRange = ability02:GetCastRange()
	
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, false, BOT_MODE_NONE )
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	
	for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
	do
		if ( CanCastLyrica02OnTarget( npcFriend ) and 
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 or
				npcFriend:WasRecentlyDamagedByAnyHero( 1.0 ) or
				IsUnderAttack( npcFriend )
				)
			) then
			return BOT_ACTION_DESIRE_HIGH, npcFriend
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLyrica04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 900, true, BOT_MODE_NONE )
	local tableNearbyFriendlyHeroes = CachedGetNearbyHeroes( npcBot, 550, false, BOT_MODE_NONE )
	
	if #tableNearbyEnemyHeroes > 0 then
		for _,npcFriend in pairs( tableNearbyFriendlyHeroes )
		do
			if ( npcFriend:GetHealth() < npcFriend:GetMaxHealth()*0.3 and
				( GetModifiersTimeLeft(npcFriend, ModifierNamesHighDebuff) > 0.5 
				or npcFriend:WasRecentlyDamagedByAnyHero( 1.0 )
				or IsUnderAttack( npcFriend )
				)
				) then
				return BOT_ACTION_DESIRE_HIGH, npcFriend
			end
		end
	end
		
	return BOT_ACTION_DESIRE_NONE, nil

end

