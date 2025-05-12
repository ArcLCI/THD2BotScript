require(GetScriptDirectory() ..  "/bot_generic")

----------------------------------------------------------------------------------------------------

local nNextMoveTime = 0

function MinionThink( hMinionUnit )

	if hMinionUnit:IsIllusion() then
        THD2MinionThink( hMinionUnit )
    end

	if hMinionUnit:GetUnitName() == "npc_thdots_unit_minoriko02_box" then
        local ownerBot = GetBot()
        local nMoveRange = 1200
        local nRadius = 500
        local locationBox = CachedFindAoELocation( ownerBot, 1, false, true, hMinionUnit:GetLocation(), nMoveRange, nRadius, 0, 0 )
        if DotaTime() >= nNextMoveTime then
            hMinionUnit:Action_MoveToLocation(locationBox.targetloc)
            nNextMoveTime = DotaTime() + 0.2
        end
    end

end