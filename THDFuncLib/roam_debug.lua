local RoamDebug = {}

local IMMEDIATE_STATUS_KEYS = {
	invalid_or_dead = true,
	bot_handle_refreshed = true,
	disabled_or_invalid_config = true,
	signal_teamfight = true,
	signal_accept = true,
	signal_objective_lock = true,
	urgent_defense = true,
	proposal_teamfight = true,
	proposal = true,
}

function RoamDebug.GetStatusKey(message)
	local text = tostring(message or 'unknown')
	return string.match(text, '^reason=([^%s]+)')
		or string.match(text, '^([^%s]+)')
		or text
end

function RoamDebug.GetStatusFamily(key)
	key = tostring(key or 'unknown')
	if string.match(key, '^hard_blocked_mode_') then return 'mode_blocked' end
	if string.match(key, '^position_not_allowed_')
		or key == 'level_too_low'
		or key == 'health_too_low'
		or key == 'mana_too_low'
		or string.match(key, '^early_lane_')
		or string.match(key, '^mid_lane_')
	then
		return 'eligibility_blocked'
	end
	if key == 'no_proposal' or key == 'other_leader' then
		return 'mission_unavailable'
	end
	if key == 'team_objective_lock'
		or key == 'push_objective_participant'
		or key == 'pushing_t2_or_high_ground'
	then
		return 'team_lock'
	end
	return key
end

function RoamDebug.IsImmediateStatusKey(key)
	return IMMEDIATE_STATUS_KEYS[tostring(key or 'unknown')] == true
end

local function ClearPending(state)
	state.pendingFamily = nil
	state.pendingSince = nil
	state.pendingMessage = nil
end

local function Emit(state, message, now, event, key, family)
	local suppressedChanges = state.suppressedChanges or 0
	state.lastKey = key
	state.lastFamily = family
	state.lastMessage = tostring(message or 'unknown')
	state.lastLogTime = now
	state.suppressedChanges = 0
	ClearPending(state)
	return true, event, key, {
		family = family,
		suppressedChanges = suppressedChanges,
	}
end

function RoamDebug.ShouldLogStatus(state, message, now, heartbeatInterval, force, options)
	if type(state) ~= 'table' then return false, 'invalid_state', nil end
	now = type(now) == 'number' and now or -9999
	heartbeatInterval = type(heartbeatInterval) == 'number' and heartbeatInterval > 0
		and heartbeatInterval or 15.0
	options = type(options) == 'table' and options or {}
	local debounceInterval = type(options.debounceInterval) == 'number'
		and math.max(0, options.debounceInterval) or 0
	local key = RoamDebug.GetStatusKey(message)
	local family = options.useReasonFamilies == true
		and RoamDebug.GetStatusFamily(key) or key
	if state.lastObservedFamily ~= nil and state.lastObservedFamily ~= family then
		state.suppressedChanges = (state.suppressedChanges or 0) + 1
	end
	state.lastObservedKey = key
	state.lastObservedFamily = family

	if force == true then
		return Emit(state, message, now, 'forced', key, family)
	end
	if state.lastFamily == nil then
		return Emit(state, message, now, 'reason_change', key, family)
	end
	if family == state.lastFamily then
		ClearPending(state)
		local suppressedHeartbeats = type(options.suppressHeartbeatFamilies) == 'table'
			and options.suppressHeartbeatFamilies[family] == true
		if suppressedHeartbeats then
			return false, 'suppressed', key, {
				family = family,
				suppressedChanges = state.suppressedChanges or 0,
			}
		end
		if now - (state.lastLogTime or -9999) < heartbeatInterval then
			return false, 'suppressed', key, {
				family = family,
				suppressedChanges = state.suppressedChanges or 0,
			}
		end
		return Emit(state, message, now, 'heartbeat', key, family)
	end

	local immediate = options.useImmediateReasons == true
		and RoamDebug.IsImmediateStatusKey(key)
	if immediate or debounceInterval <= 0 then
		return Emit(state, message, now, 'reason_change', key, family)
	end
	if state.pendingFamily ~= family then
		state.pendingFamily = family
		state.pendingSince = now
		state.pendingMessage = tostring(message or 'unknown')
		return false, 'debouncing', key, {
			family = family,
			suppressedChanges = state.suppressedChanges or 0,
		}
	end
	if now - (state.pendingSince or now) >= debounceInterval then
		return Emit(state, message, now, 'reason_change', key, family)
	end
	local recoveringFromSuppressedFamily = type(options.suppressHeartbeatFamilies) == 'table'
		and options.suppressHeartbeatFamilies[state.lastFamily] == true
	-- 从死亡等禁用 family 恢复时必须先取得稳定新状态，不能让 pending 心跳伪装成普通 heartbeat。
	if not recoveringFromSuppressedFamily
		and now - (state.lastLogTime or -9999) >= heartbeatInterval
	then
		return Emit(state, message, now, 'heartbeat', key, family)
	end
	return false, 'debouncing', key, {
		family = family,
		suppressedChanges = state.suppressedChanges or 0,
	}
end

return RoamDebug
