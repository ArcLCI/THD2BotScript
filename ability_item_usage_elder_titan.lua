
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast03Desire = 0
cast04Desire = 0


function MyItemUsageThink()
	
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end
	
	local item_morenjingjuan = IsItemAvailable( "item_morenjingjuan" )
	local item_speed = IsItemAvailable( "item_mystia_wings" ) or
					IsItemAvailable( "item_brother_sharp" ) or
					IsItemAvailable( "item_bone_flute" )
	local item_kafziel = IsItemAvailable( "item_kafziel" )
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
	if ( item_speed~=nil and item_speed:IsFullyCastable() )
	then 
		castItemSpeedDesire = ConsiderItemSpeed( item_speed )
		if ( castItemSpeedDesire > 0 ) 
		then
			npcBot:Action_UseAbility( item_speed )
			return
		end
	end
	if ( item_kafziel~=nil and item_kafziel:IsFullyCastable() )
	then 
		castItemKafzielDesire, castItemKafzielTarget = ConsiderItemKafziel( item_kafziel )
		if ( castItemKafzielDesire > 0 ) 
		then
			npcBot:Action_UseAbilityOnEntity( item_kafziel, castItemKafzielTarget )
			return
		end
	end
end

----------------------------------------------------------------------------------------------------

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_komachi01" )
	ability03 = npcBot:GetAbilityByName( "ability_thdots_komachi03" )
	ability04 = npcBot:GetAbilityByName( "ability_thdots_komachi04" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityKomachi01()
	if ( cast01Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability01)
		return
	end

	cast03Desire = ConsiderAbilityKomachi03()
	if ( cast03Desire > 0 ) 
	then
		npcBot:Action_UseAbility( ability03)
		return
	end

	cast04Desire, cast04Target = ConsiderAbilityKomachi04()
	if ( cast04Desire > 0 ) 
	then
		npcBot:Action_UseAbilityOnEntity( ability04, cast04Target )
		return
	end
end

----------------------------------------------------------------------------------------------------

function CanCastKomachi01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastKomachi03OnTarget( npcTarget )
	return not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end

function CanCastKomachi04OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and npcTarget:IsHero() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityKomachi01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
		
	local nCastRange = 300
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) 
	then
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange, true, BOT_MODE_NONE )	
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (npcBot:HasModifier("modifier_item_morenjingjuan_buff") and
				npcEnemy:HasModifier("modifier_item_morenjingjuan_antiblink") and
				GetUnitToUnitDistance( npcBot, npcEnemy ) < npcBot:GetAttackRange())
			then
				return BOT_ACTION_DESIRE_NONE
			end	
			if (npcBot:IsFacingLocation( npcEnemy:GetLocation(), 90 ) and CanCastKomachi01OnTarget(npcEnemy) and not IsPossibleIllusion( npcEnemy ))
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end
	--撤退
	if ( npcBot:GetActiveMode() == BOT_MODE_RETREAT and 
		npcBot:GetHealth() < npcBot:GetMaxHealth() * 0.3 and
		npcBot:IsFacingLocation(GetShopLocation(npcBot:GetTeam(),SHOP_HOME), 90)) 
	then
		return BOT_ACTION_DESIRE_HIGH
	end
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKomachi03()
	
	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability03:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE
	end
	
	--local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 1600, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if ( npcEnemy~=nil )
		then
		if ( npcEnemy:IsAlive() and CanCastKomachi03OnTarget(npcEnemy) and not IsPossibleIllusion( npcEnemy ))
		then
		local soul_index = npcEnemy:GetModifierByName("modifier_thdots_komachi_03_soul")
		if (soul_index ~= nil)
		then
			local soul_num = npcEnemy:GetModifierStackCount(soul_index)
			local soul_time = npcEnemy:GetModifierRemainingDuration(soul_index)
			local damage = (10 + npcEnemy:GetMaxHealth()*0.01)*(ability03:GetLevel()+1)*soul_num
			local kill_coef = 0
			-- 斩杀
			if (npcEnemy:HasModifier("modifier_thdots_komachi_04_debuff"))
			then
				if (npcBot:GetLevel() >= 25) then 
				kill_coef = 0.4 
				else
				kill_coef = 0.25
				end
			end
			if (damage*(1-npcEnemy:GetMagicResist())>npcEnemy:GetHealth()-npcEnemy:GetMaxHealth()*kill_coef)
			then
				return BOT_ACTION_DESIRE_HIGH
			end
			-- 打伤害
			if ( soul_time > 0.1 and soul_time <= 1.0 ) 
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
			if ( soul_num == 12 )
			then
				return BOT_ACTION_DESIRE_MODERATE
			end
			if (npcBot:GetActiveMode() == BOT_MODE_RETREAT and 
				npcBot:GetHealth() < npcBot:GetMaxHealth()*0.3) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
		end
		end
	end	
	return BOT_ACTION_DESIRE_NONE
end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityKomachi04()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability04:IsFullyCastable() ) 
	then 
		return BOT_ACTION_DESIRE_NONE, nil
	end
	
	local nCastRange = ability04:GetCastRange()
	if ( npcBot:GetActiveMode() == BOT_MODE_ATTACK and npcBot:GetActiveModeDesire() >= BOT_MODE_DESIRE_MODERATE ) 
	then	
		local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
		local max_hr = 0
		local target_cache = nil
		for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
		do
			if (CanCastKomachi04OnTarget( npcEnemy ) and not IsPossibleIllusion( npcEnemy ))
			then
				if (npcEnemy:GetHealthRegen() >= max_hr) then target_cache = npcEnemy end
				if (npcEnemy:GetUnitName() == "npc_dota_hero_drow_ranger" or
					npcEnemy:GetUnitName() == "npc_dota_hero_warlock" or
					npcEnemy:GetUnitName() == "npc_dota_hero_dark_seer" or
					npcEnemy:GetUnitName() == "npc_dota_hero_naga_siren" )
				then
					return BOT_ACTION_DESIRE_HIGH, npcEnemy
				end
			end
		end
		if (target_cache ~= nil)
		then
			return BOT_ACTION_DESIRE_HIGH, target_cache
		end
	end
	local kill_coef = 0.25
	if (npcBot:GetLevel() >= 25) then kill_coef = 0.4 end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, nCastRange , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if (npcEnemy:GetHealth() < npcEnemy:GetMaxHealth()*kill_coef and not IsPossibleIllusion( npcEnemy ))
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy
		end
	end
	return BOT_ACTION_DESIRE_NONE, nil
end

