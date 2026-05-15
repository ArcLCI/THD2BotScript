
require(GetScriptDirectory() ..  "/bot_generic")

----------------------------------------------------------------------------------------------------

function MinionThink( hMinionUnit )

	if hMinionUnit:IsIllusion() then
        THD2MinionThink( hMinionUnit )
    end
end
