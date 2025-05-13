
local Illusion = dofile(GetScriptDirectory()..'/thd2_illusion')
local npcBot = GetBot()

function THD2MinionThink( hMinionUnit )
	Illusion.IllusionThink(npcBot, hMinionUnit)
end
