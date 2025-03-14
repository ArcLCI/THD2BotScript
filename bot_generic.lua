
local last_time = -5000;

function THD2MinionThink( hMinionUnit )

	local npcBot = GetBot();
	if not hMinionUnit:IsIllusion() then return end

	if hMinionUnit:NumQueuedActions() > 0 then
		return;
	end

	if GetUnitToUnitDistanceSqr(npcBot,hMinionUnit) > 800 * 800 then
		local vec = hMinionUnit:GetLocation();
		hMinionUnit:ActionQueue_AttackMove( vec + 0.5 * ( npcBot:GetLocation() - vec) );
		return;
	end

	hMinionUnit:ActionQueue_AttackMove( hMinionUnit:GetLocation() );

end