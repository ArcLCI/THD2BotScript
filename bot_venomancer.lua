
require(GetScriptDirectory() ..  "/bot_generic")

----------------------------------------------------------------------------------------------------


function MinionThink( hMinionUnit )
    local ownerBot = GetBot()
    if hMinionUnit:GetUnitName() == "ability_yuuka_flower" then
        hMinionUnit.attack_desire, hMinionUnit.attack_target = ConsiderAttack(hMinionUnit)
	    local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( hMinionUnit, 500, true, BOT_MODE_NONE )
	    for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	    do
		    if ownerBot:GetTarget() == npcEnemy
		    then
		    	hMinionUnit.attack_target = npcEnemy
		    	hMinionUnit.attack_desire = 0.95
		    end
	    end

        if hMinionUnit.attack_desire > 0 then
            if IsValidUnit(hMinionUnit.attack_target) and GetUnitToUnitDistance(hMinionUnit,hMinionUnit.attack_target) < 500 then
                hMinionUnit:Action_AttackUnit(hMinionUnit.attack_target, false)
                return
            end
        end
    end

    if hMinionUnit:IsIllusion() then
	    THD2MinionThink( hMinionUnit )
    end

    THD2DemonThink(hMinionUnit)
end