
require(GetScriptDirectory() ..  "/bot_generic")
local SunnyIllusion = require(GetScriptDirectory() .. "/THDFuncLib/sunny_illusion")

----------------------------------------------------------------------------------------------------


function MinionThink( hMinionUnit )

	if SunnyIllusion.Think(GetBot(), hMinionUnit) then return end
	THD2MinionThink( hMinionUnit )

end
