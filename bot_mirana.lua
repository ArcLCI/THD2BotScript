
require(GetScriptDirectory() ..  "/bot_generic")

----------------------------------------------------------------------------------------------------

local nNextMoveTime = 0

function MinionThink( hMinionUnit )

	local ownerBot = GetBot()
	if not hMinionUnit:IsIllusion() then return end

	if hMinionUnit.isIllusion then
        if ConfuseEnemyWithIllusions(ownerBot, hMinionUnit) > 0 then
			print("Confusing Enemy...")
            return
        end
    end

	hMinionUnit.attack_desire, hMinionUnit.attack_target = ConsiderAttack(hMinionUnit)
    if ConsiderRetreat(hMinionUnit, hMinionUnit.attack_target) then return end
	local tableNearbyEnemyHeroes = CachedGetNearbyHeroes( ownerBot, 1200, true, BOT_MODE_NONE )
	for _,npcEnemy in pairs( tableNearbyEnemyHeroes )
	do
		if npcEnemy:HasModifier("modifier_thdots_reisen03_full")
		then
			hMinionUnit.attack_target = npcEnemy
			hMinionUnit.attack_desire = 0.95
		end
	end

    if hMinionUnit.attack_desire > 0 then
        if IsValidUnit(hMinionUnit.attack_target) then
            hMinionUnit:Action_AttackUnit(hMinionUnit.attack_target, false)
            return
        end
    end

    if DotaTime() >= nNextMoveTime then
        hMinionUnit.move_desire, hMinionUnit.move_location = ConsiderMove(hMinionUnit)
        if hMinionUnit.move_desire > 0 then
            hMinionUnit:Action_MoveToLocation(hMinionUnit.move_location)
            nNextMoveTime = DotaTime() + 0.2
            return
        end

        -- Default
        if ownerBot:IsAlive()
        then
            hMinionUnit:Action_MoveToLocation(GetRandomLocationWithinDist(ownerBot:GetLocation(), 400, 800))
        else
            hMinionUnit:Action_MoveToLocation(GetClosestTeamLane(hMinionUnit))
        end
        nNextMoveTime = DotaTime() + 0.2
    end

end