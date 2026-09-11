-- 来源生命周期独立于移动租约；只保存Bot可见数值，不跨帧保存敌方句柄。
local Config = require(GetScriptDirectory()..'/THDFuncLib/avoidance_config')
local G = require(GetScriptDirectory()..'/THDFuncLib/avoidance_geometry')
local Diagnostics = require(GetScriptDirectory()..'/THDFuncLib/bot_diagnostics_config')
local Zones = {}
-- 正常仅保留来源、租约和失败；详细候选/轨迹按需启用。
local detailedEvents={near_impact=true,escape_move=true,escape_request_boundary=true,escape_release_boundary=true,escape_exit_boundary=true,route_choice=true,detour_candidate=true,detour_fallback=true,local_goal_probe=true,bridge_path_probe=true,bridge_budget_plan=true,bridge_move=true,bridge_gate=true,route_move=true,move_intent=true}
local Effects = require(GetScriptDirectory()..'/THDFuncLib/skill_effects')
local function Safe(default, callback)
	local ok, v = pcall(callback)
	if not ok or v == nil then return default end
	return v
end
local function Number(v)
	v = tonumber(v)
	return v ~= nil and v == v and math.abs(v) < math.huge and v or nil
end
local function Now() return Safe(0, DotaTime) end
function Zones.Log(bot, event, extra)
	if not Config.DEBUG_LOG then return end
	if event=='threat_decision' and not Diagnostics.SKILL_DECISION_LOG then return end
	if detailedEvents[event] and not Diagnostics.SKILL_TRACE_LOG then return end
	print(string.format('[BOT][SkillAvoidance] run=%s team=%s player=%s dota_time=%.3f event=%s %s',
		tostring(Config.RUN_ID), tostring(bot:GetTeam()), tostring(bot:GetPlayerID()), Now(), event, extra or ''))
end
function Zones.Enabled() return Config.ENABLED == true and Config.SKILL_AVOIDANCE_ENABLED == true end
local function State(bot)
	if bot.THD_SkillZones == nil then bot.THD_SkillZones = {seq = 0, nextAt = -90, cursor = 1, entries = {}, tokens = {}} end
	return bot.THD_SkillZones
end
local function Remove(bot, state, id, reason)
	local entry = state.entries[id]
	if entry == nil then return end
	if state.tokens[entry.token] == id then state.tokens[entry.token] = nil end
	state.entries[id] = nil
	Zones.Log(bot, 'source_removed', 'key='..id..' reason='..reason)
end
function Zones.Update(bot)
	local state, now = State(bot), Now()
	for id, entry in pairs(state.entries) do if now >= entry.expiresAt then Remove(bot, state, id, 'expired') end end
	if not Zones.Enabled() then
		for id in pairs(state.entries) do Remove(bot, state, id, 'disabled') end
		return
	end
	if now < state.nextAt or not Safe(false, function() return bot:IsAlive() end) then return end
	state.nextAt = now + Config.SKILL_SCAN_INTERVAL
	local units = Safe({}, function() return GetUnitList(UNIT_LIST_ALL) end)
	if state.cursor > #units then state.cursor = 1 end
	local last = math.min(#units, state.cursor + 255)
	for i = state.cursor, last do
		local unit = units[i]
		if unit ~= nil and not Safe(true, function() return unit:IsNull() end)
		and Safe('', function() return unit:GetUnitName() end) == 'npc_no_vision_dummy_unit'
		and Safe(false, function() return unit:CanBeSeen() end) then
			local center = Safe(nil, function() return unit:GetLocation() end)
			local team = Safe(-1, function() return unit:GetTeam() end)
			if center ~= nil and (team == TEAM_RADIANT or team == TEAM_DIRE) and team ~= bot:GetTeam()
			and G.Distance(bot:GetLocation(), center) <= Config.SKILL_SCAN_RANGE
			and Safe(false, function() return IsLocationVisible(center) end) then
				local token = string.gsub(tostring(unit), '%s+', '')
				local id = state.tokens[token]
				local entry = id ~= nil and state.entries[id] or nil
				local profile,index=nil,-1
				for _,candidate in ipairs(Effects.sources) do
					local found=Number(Safe(-1,function() return unit:GetModifierByName(candidate.modifier) end)) or -1
					if found>=0 and Safe('',function() return unit:GetModifierName(found) end)==candidate.modifier then profile,index=candidate,found;break end
				end
				if profile then
					if entry and entry.abilityId~=profile.id then Remove(bot,state,id,'source_kind_changed');entry=nil end
					local remaining = Number(Safe(nil, function() return unit:GetModifierRemainingDuration(index) end))
					local radius = Number(Safe(nil, function() return unit:GetModifierStackCount(index) end))
					if remaining ~= nil and remaining > 0 and remaining <= 10 and radius ~= nil and radius > 0 and radius <= 2000 then
						local expires = now + remaining
						-- 地址复用/寿命明显重新开始时建立新代，不把诊断token单独当永久实例ID。
						if entry ~= nil and expires > entry.expiresAt + 0.5 then Remove(bot, state, id, 'new_lifetime'); entry = nil end
						if entry == nil then
							state.seq = state.seq + 1
							id = profile.prefix..':'..tostring(state.seq)
							entry = {key = id, token = token, sourceKind = 'skill', abilityId = profile.id,
								center = G.MakeVector(center.x, center.y, center.z), radius = radius, expiresAt = expires, observedAt = now,
								impactAt = profile.kind=='delayed_burst' and expires-profile.markerTail or nil}
							state.entries[id], state.tokens[token] = entry, id
							Zones.Log(bot, 'source_added', string.format('key=%s x=%.1f y=%.1f radius=%.1f expires_at=%.3f ability=%s kind=%s impact_at=%.3f', id, center.x, center.y, radius, expires,profile.id,profile.kind,entry.impactAt or -1))
						elseif G.Distance(center, entry.center) > 32 or math.abs(radius - entry.radius) > 1 then
							-- 首个来源必须静止；异常移动不转化成一个猜测的移动危险圆。
							if not entry.invalid then Zones.Log(bot, 'source_rejected', 'key='..id..' reason=marker_changed') end
							entry.invalid = true
						else
							entry.observedAt = now
							entry.expiresAt = math.min(entry.expiresAt, expires)
							if entry.impactAt then entry.impactAt=math.min(entry.impactAt,entry.expiresAt-profile.markerTail) end
						end
					end
				elseif entry ~= nil then Remove(bot, state, id, 'visible_modifier_removed') end
			end
		end
	end
	state.cursor = last + 1
	if state.cursor > #units then state.cursor = 1 end
end
function Zones.Get(bot)
	Zones.Update(bot)
	local result = {}
	for _, entry in pairs(State(bot).entries) do
		if not entry.invalid then
			table.insert(result, {key = entry.key, sourceKind = entry.sourceKind, abilityId = entry.abilityId,
				center = G.MakeVector(entry.center.x, entry.center.y, entry.center.z), radius = entry.radius,
				expiresAt = entry.expiresAt, observedAt = entry.observedAt, impactAt = entry.impactAt})
		end
	end
	table.sort(result, function(a, b) return a.key < b.key end)
	-- 只报告本Bot已合法观察并保留的来源集合；Game的pair/role不传给Bot做决策。
	local keys,delayed={},0
	for _,entry in ipairs(result) do table.insert(keys,entry.key);if entry.impactAt then delayed=delayed+1 end end
	local signature=table.concat(keys,'|')
	local state=State(bot)
	if state.loggedSignature~=signature then
		if #result>0 or state.loggedSignature~=nil then
			Zones.Log(bot,'source_set',string.format('count=%d delayed_count=%d keys=%s scope=local_observed_registry',#result,delayed,signature~='' and signature or 'none'))
		end
		state.loggedSignature=signature
	end
	return result
end
return Zones
