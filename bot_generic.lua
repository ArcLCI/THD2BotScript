
local Illusion = dofile(GetScriptDirectory()..'/thd2_illusion')
local npcBot = GetBot()

function THD2MinionThink( hMinionUnit )
	Illusion.IllusionThink(npcBot, hMinionUnit)
	Illusion.DemonThink(npcBot, hMinionUnit)
end

function THD2DemonThink( hMinionUnit )
	Illusion.DemonThink(npcBot, hMinionUnit)
end
