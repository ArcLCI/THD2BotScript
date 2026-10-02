-- 协议1只解码自身观察标记；不访问游戏侧全局表，也不把过期观察当作当前状态。
local Config=require(GetScriptDirectory()..'/THDFuncLib/modes/shared/execution_config')
local M={}
local cache=setmetatable({}, {__mode='k'})
local retries=setmetatable({}, {__mode='k'})
local function Stack(bot,field,slot)
	local index=bot:GetModifierByName('modifier_thd2_map_resource_'..field..'_'..slot)
	if type(index)~='number' or index<0 then return 0,index end
	return bot:GetModifierStackCount(index),index
end
function M.Read(bot)
	if not Config.MAP_RESOURCES_ENABLED or not bot or not bot:IsAlive() then return {} end
	local now=DotaTime();local saved=cache[bot]
	if saved and now-saved.at<0.5 then return saved.nodes end
	local nodes={}
	local diagnostics=saved and saved.diagnostics or {}
	for slot=1,4 do
		local location,locationIndex=Stack(bot,'location',slot)
		local meta,metaIndex=Stack(bot,'meta',slot)
		local packet,stateIndex=Stack(bot,'state',slot)
		if location>0 and math.floor(meta/16777216)==1 then
			local encoded=location-1;local details=meta%16777216
			local radius=details%1024
			local countdown=math.floor(details/1024)%256/10
			local at=packet>0 and (math.floor(packet/64)-1)/2-120 or nil
			local count=packet>0 and packet%64-1 or nil
			local fresh=at and count and count>=0 and count<=31 and now-at>=-0.5 and now-at<=Config.MAP_RESOURCE_OBSERVATION_TTL
			local known=radius>0 and countdown>0
			if known then
				nodes[slot]={slot=slot,kind=slot<=2 and 'wisdom' or 'lotus',index=slot<=2 and slot or slot-2,
					location=Vector(encoded%32768-16384,math.floor(encoded/32768)-16384,math.floor(details/262144)*32-1024),
					radius=radius,countdown=countdown,observedAt=at,count=fresh and count or nil,
					state=fresh and count and (count>0 and 'ready' or 'empty') or 'unknown',identity=location}
			end
		end
		-- 原始索引/值和解码状态一起记录，区分缺标记、协议不符、过期及正常空资源。
		local function Missing(index) return type(index)~='number' or index<0 end
		local reason=Missing(locationIndex) and 'missing_location'
			or (Missing(metaIndex) and 'missing_meta') or (Missing(stateIndex) and 'missing_state')
			or (location<=0 and 'location_unavailable') or (math.floor(meta/16777216)~=1 and 'meta_protocol_invalid')
			or (not nodes[slot] and 'metadata_invalid') or (packet<=0 and 'never_observed')
			or (nodes[slot].state=='unknown' and 'stale_or_invalid_state') or 'decoded'
		local diagnostic=diagnostics[slot]
		if Config.DEBUG and (not diagnostic or now-diagnostic.at>=60 or diagnostic.reason~=reason) then
			diagnostics[slot]={at=now,reason=reason}
			print(string.format('[BOT][MapResourceRead] run=MAP-RESOURCES-20261002-R2 time=%.2f pid=%s slot=%d reason=%s location_index=%s meta_index=%s state_index=%s location=%s meta=%s packet=%s decoded_state=%s count=%s',
				now,bot:GetPlayerID(),slot,reason,tostring(locationIndex),tostring(metaIndex),tostring(stateIndex),tostring(location),tostring(meta),tostring(packet),tostring(nodes[slot] and nodes[slot].state),tostring(nodes[slot] and nodes[slot].count)))
		end
	end
	cache[bot]={at=now,nodes=nodes,logs=saved and saved.logs or {},diagnostics=diagnostics}
	return nodes
end
function M.Get(bot,kind,index)
	local slot=(kind=='wisdom' and 0 or 2)+(index or 1)
	return M.Read(bot)[slot]
end
function M.Defer(bot,kind,index,reason,seconds)
	local state=retries[bot] or {};retries[bot]=state
	state[kind..':'..index]={untilAt=DotaTime()+(seconds or 8),reason=reason}
end
function M.CanTry(bot,kind,index)
	local state=retries[bot];local old=state and state[kind..':'..index]
	return not old or DotaTime()>=old.untilAt
end
function M.Log(bot,observation,phase,reason)
	if not Config.DEBUG then return end
	local state=cache[bot] or {at=-90,nodes={}};cache[bot]=state
	state.logs=state.logs or {}
	local key=tostring(observation and observation.slot)..':'..phase..':'..reason
	if DotaTime()-(state.logs[key] or -90)<2 then return end
	state.logs[key]=DotaTime()
	print(string.format('[BOT][MapResource] run=%s time=%.3f pid=%s kind=%s slot=%s phase=%s reason=%s state=%s count=%s observed_at=%s radius=%s',
		Config.RUN_ID,DotaTime(),bot:GetPlayerID(),tostring(observation and observation.kind),tostring(observation and observation.slot),phase,reason,
		tostring(observation and observation.state),tostring(observation and observation.count),tostring(observation and observation.observedAt),tostring(observation and observation.radius)))
end
function M.RuneReceipt(bot)
	if bot~=GetBot() then return nil end
	local function Value(field)
		local index=bot:GetModifierByName('modifier_thd2_rune_receipt_'..field)
		if type(index)~='number' or index<0 then return 0 end
		return bot:GetModifierStackCount(index)
	end
	local sequence=Value('sequence')
	if sequence<=0 then return nil end
	local time,location,kind=Value('time'),Value('location'),Value('type')
	if time<=0 or location<=0 or kind<=0 or sequence~=Value('sequence') then return nil end
	local packed=location-1
	return {sequence=sequence,time=(time-1)/10-120,runeType=kind-2,
		location=Vector(packed%32768-16384,math.floor(packed/32768)-16384,0)}
end
return M
