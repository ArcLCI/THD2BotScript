
require(GetScriptDirectory() ..  "/thd2_item_usage")

----------------------------------------------------------------------------------------------------

function MyItemUsageThink()

	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsMuted() or npcBot:IsUsingAbility() ) then return end

	local item_rocket = IsItemAvailable( "item_rocket" ) or
					IsItemAvailable( "item_rocket_2" ) or
					IsItemAvailable( "item_rocket_3" ) or
					IsItemAvailable( "item_rocket_4" ) or
					IsItemAvailable( "item_rocket_5" )
	local item_yukkuri_stick = IsItemAvailable( "item_yukkuri_stick" )

	--红魔火箭判定
	if ( item_rocket~=nil and item_rocket:IsFullyCastable() )
	then
		castItemStunDesire, castItemStunTarget = ConsiderItemStun( item_rocket )
		if ( castItemStunDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_rocket, castItemStunTarget )
			return
		end
	end

	--油库里杖判定
	if ( item_yukkuri_stick~=nil and item_yukkuri_stick:IsFullyCastable() )
	then
		castItemYukkuriStickDesire, castItemYukkuriStickTarget = ConsiderItemYukkuriStick( item_yukkuri_stick )
		if ( castItemYukkuriStickDesire > 0 )
		then
			npcBot:Action_UseAbilityOnEntity( item_yukkuri_stick, castItemYukkuriStickTarget )
			return
		end
	end

end
----------------------------------------------------------------------------------------------------

cast01Desire = 0
cast02Desire = 0
cast03Desire = 0
cast04Desire = 0

function AbilityUsageThink()

	if not IsBotAwake() then return end

	MyItemUsageThink()
	SpecificAttackTargetThink()
	local npcBot = GetBot()

	-- Check if we're already using an ability
	if ( npcBot:IsSilenced() or npcBot:IsUsingAbility() ) then return end

	ability01 = npcBot:GetAbilityByName( "ability_thdots_wriggle01" )
	ability02 = npcBot:GetAbilityByName( "death_prophet_exorcism" )
	--ability03 = npcBot:GetAbilityByName( "ability_thdots_wriggle03" )
	--ability04 = npcBot:GetAbilityByName( "ability_thdots_wriggle04" )

	-- Consider using each ability
	cast01Desire = ConsiderAbilityWriggle01()

	if ( cast01Desire > 0 )
	then
		npcBot:Action_UseAbility( ability01 )
		return
	end

	cast02Desire = ConsiderAbilityWriggle02()
	if ( cast02Desire > 0 )
	then
		npcBot:Action_UseAbility( ability02 )
		return
	end

end

----------------------------------------------------------------------------------------------------
function CanCastWriggle01OnTarget( npcTarget )
	return npcTarget:CanBeSeen() and not npcTarget:IsMagicImmune() and not npcTarget:IsInvulnerable()
end
----------------------------------------------------------------------------------------------------

function ConsiderAbilityWriggle01()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability01:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 800 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil )
		then
			return BOT_ACTION_DESIRE_NONE
		end

	end

	return BOT_ACTION_DESIRE_HIGH

end

----------------------------------------------------------------------------------------------------

function ConsiderAbilityWriggle02()

	local npcBot = GetBot()

	-- Make sure it's castable
	if ( not ability02:IsFullyCastable() )
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( npcBot, 400 , true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if ( npcEnemy ~= nil )
		then
			return BOT_ACTION_DESIRE_HIGH
		end

	end

	return BOT_ACTION_DESIRE_NONE

end
