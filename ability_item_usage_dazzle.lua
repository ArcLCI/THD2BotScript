
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

	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )

	local item_moon_bow  = IsItemAvailable( "item_moon_bow" )
	local item_root = IsItemAvailable( "item_tentacle" )
	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )

	local item_horse_red = IsItemAvailable( "item_horse_red" )
	local item_horse_king = IsItemAvailable( "item_horse_king")

	local item_yukkuri_stick = IsItemAvailable( "item_yukkuri_stick" )

	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		local castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
			return
		end
	end
	if ( item_root~=nil and item_root:IsFullyCastable() )
	then
		local castItemRootDesire, castItemRootTarget = ConsiderItemRoot( item_root )
		if ( castItemRootDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_root, castItemRootTarget )
			return
		end
	end
	if ( item_morenjingjuan~=nil and item_morenjingjuan:IsFullyCastable() )
	then
		local castItemMoRenDesire, castItemMoRenTarget = ConsiderItemRoot( item_morenjingjuan )
		if ( castItemMoRenDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_morenjingjuan, castItemMoRenTarget )
			return
		end
	end
	if ( item_moon_bow~=nil and item_moon_bow:IsFullyCastable() )
	then 
		local castItemMoonBowDesire, castItemMoonBowTarget = ConsiderItemMoonBow( item_moon_bow )
		if ( castItemMoonBowDesire > 0 )
		then
			npcBot:Action_UseAbilityOnLocation( item_moon_bow, castItemMoonBowTarget)
			return
		end
	end
	if ( item_horse_red~=nil and item_horse_red:IsFullyCastable() )
	then
		local castItemHorseRedDesire = ConsiderItemHorseRed(item_horse_red)
		if ( castItemHorseRedDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_red )
			return
		end
	end

	if ( item_horse_king~=nil and item_horse_king:IsFullyCastable() )
	then
		local castItemHorseKingDesire = ConsiderItemHorseKing(item_horse_king)
		if ( castItemHorseKingDesire > 0 )
		then
			npcBot:Action_UseAbility( item_horse_king )
			return
		end
	end
	
	if ( item_yukkuri_stick~=nil and item_yukkuri_stick:IsFullyCastable() )
	then
		local castItemYukkuriStickDesire, castItemYukkuriStickTarget = ConsiderItemYukkuriStick( item_yukkuri_stick )
		if ( castItemYukkuriStickDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_yukkuri_stick, castItemYukkuriStickTarget )
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_lunasa01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_lunasa02" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_lunasa03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_lunasa04" )
	abilityWbc = npcBot:GetAbilityByName("ability_thdots_lunasa_wanbaochui")

	-- Consider using each ability
	cast01Desire, cast01Location = ConsiderAbilityLunasa01()
	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbilityOnLocation( ability01 , cast01Location)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityLunasa04()
	if ( cast04Desire > 0 )
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target )
		return
	end
	castWbcDesire = ConsiderAbilityLunasaWbc()
	if ( castWbcDesire > 0 )
	then
		npcBot:Action_UseAbility( abilityWbc )
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastLunasa01OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, false, false)
end

function CanCastLunasa04OnTarget( npcTarget )
	return IsValidCastTarget(npcTarget, true, false)
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLunasa01()

	local npcBot = GetBot()
	local nCastRange = ability01:GetCastRange()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	if ( npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_PUSH_TOWER_BOT or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_TOP or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_MID or
		 npcBot:GetActiveMode() == BOT_MODE_DEFEND_TOWER_BOT )
	then
		local tableNearbylanecreeps = npcBot:GetNearbyLaneCreeps(900,true)
		if tableNearbylanecreeps ~= nil and #tableNearbylanecreeps >= 2
        then
            return BOT_ACTION_DESIRE_HIGH, GetCenterOfUnits(tableNearbylanecreeps)
        end
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastLunasa01OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityLunasa04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = ability04:GetCastRange()

		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if ( CanCastLunasa04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy
			end
		end

	return BOT_ACTION_DESIRE_NONE, nil
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityLunasaWbc()
	local npcBot = GetBot()

	if ( (not abilityWbc:IsFullyCastable()) or abilityWbc:IsHidden())
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if npcBot:GetHealth()/npcBot:GetMaxHealth() > 0.4 and
		npcBot:GetActiveMode() == BOT_MODE_ATTACK and
	 	not npcBot:HasModifier("modifier_fountain_aura_buff") then
		if npcBot:HasModifier("modifier_ability_thdots_lunasa_wanbaochui") then
			return BOT_ACTION_DESIRE_NONE
		end
		return BOT_ACTION_DESIRE_MODERATE
	end
	if npcBot:HasModifier("modifier_ability_thdots_lunasa_wanbaochui") then
		if npcBot:GetHealth()/npcBot:GetMaxHealth() <= 0.25 or
		not npcBot:GetActiveMode() == BOT_MODE_ATTACK or
		npcBot:HasModifier("modifier_fountain_aura_buff") then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end

	return BOT_ACTION_DESIRE_NONE
end
