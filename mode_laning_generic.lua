
local debug_printed = false;

function GetDesire()
	
	if not debug_printed then
		print('laning_generic_ok')
		debug_printed = true
	end
	
	local npcBot = GetBot()
	local t = DotaTime();
	local mod_t = t % 60;
	local base_desire = 0;
	
	if mod_t > 50 or mod_t < 5 then
		base_desire = 0.15
	else
		if t < 1200 then base_desire = 0.25 end
		if t < 900 then base_desire = 0.35 end
		if t < 600 then base_desire = 0.45 end
		if t < 300 then base_desire = 0.55 end
	end
	
	return base_desire;
	
end
