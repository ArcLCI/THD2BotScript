
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0
cast05Desire = 0

function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_slow = IsItemAvailable( "item_zaiezhizhurenxing" ) or
					IsItemAvailable( "item_jiao_shou" )
	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )
	local item_ghost = IsItemAvailable( "item_ghost_balloon" )
	local item_weijin = IsItemAvailable( "item_xuenvdeweijin" )
	local item_jump = IsItemAvailable( "item_wanmeitiaoyuezhuangzhi" )
	
	if ( item_slow~=nil and item_slow:IsFullyCastable() )
	then 
		castItemSlowDesire, castItemSlowTarget = ConsiderItemSlow( item_slow )
		if ( castItemSlowDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_slow, castItemSlowTarget)
			return
		end
	end
	
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then 
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
			return
		end
	end
	
	if ( item_ghost~=nil and item_ghost:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemGhostDesire, castItemGhostTarget = ConsiderItemGhost(item_ghost)
		if ( castItemGhostDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbilityOnEntity( item_ghost, castItemGhostTarget )
			return
		end
	end

	if ( item_weijin~=nil and item_weijin:IsFullyCastable() )
	then 
		--print("stun item exist")
		castItemWeijinDesire = ConsiderItemWeiJin(item_weijin)
		if ( castItemWeijinDesire > 0 ) 
		then
			--print("stun luanch")
			npcBot:Action_UseAbility( item_weijin )
			return
		end
	end
	
	if ( item_jump~=nil and item_jump:IsFullyCastable() )
	then 
		castItemJumpDesire, castItemJumpTarget = ConsiderItemJump( item_jump )
		if ( castItemJumpDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnLocation( item_jump, castItemJumpTarget)
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

	ability01 = npcBot:GetAbilityByName( "ability_thdots_shion_01" )
	ability02 = npcBot:GetAbilityByName( "ability_thdots_shion_02" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_shion_04" )
	ability05 = npcBot:GetAbilityByName( "ability_thdots_shion_05" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityShion01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01)
		return
	end

	cast02Desire = ConsiderAbilityShion02()
	if ( cast02Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability02)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityShion04()
	
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04 , cast04Target)
		return
	end

end

----------------------------------------------------------------------------------------------------

function CanCastShion04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityShion01()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	-- Fighting or Retreating with hero
	local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes( 700, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil ) 
		then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end
	
	if npcBot:HasModifier("modifier_ability_thdots_shion_04_caster")
	then
		return BOT_ACTION_DESIRE_MODERATE
	end
	
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShion02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	if npcBot:HasModifier("modifier_ability_thdots_shion_04_caster")
	then
		return BOT_ACTION_DESIRE_MODERATE
	end
	
	
	local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(300, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil ) 
		then
			return BOT_ACTION_DESIRE_MODERATE
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityShion04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE,nil
	end
--[[	
	if npcBot:HasModifier("modifier_ability_thdots_shion_04_caster")
	then
		return BOT_ACTION_DESIRE_NONE,nil
	end
--]]	
	-- Get some of its values
	local nCastRange = 300
	if npcBot:GetLevel() >= 20
	then
		nCastRange = 700
	end
	
	local tableNearbyEnemyHeroes = npcBot:GetNearbyHeroes(nCastRange, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( CanCastShion04OnTarget( npcEnemy ) ) 
		then
			if ability01:IsFullyCastable() then 
				npcBot:Action_UseAbility( ability01)
			end
			if ability02:IsFullyCastable() then 
				npcBot:Action_UseAbility( ability02)
			end
			return BOT_ACTION_DESIRE_MODERATE, npcEnemy
		end
	end	
	return BOT_ACTION_DESIRE_NONE,nil
end

