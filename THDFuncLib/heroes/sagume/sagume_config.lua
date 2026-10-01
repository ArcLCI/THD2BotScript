local C = {}

C.VERSION = 'sagume-20260909-03'
C.DIAGNOSTICS = true
-- 敌方冷却不可读；先记录关键技能观测，手动实战核对后再开启实际封锁。
C.ENEMY_LOCK_ENABLED = false
C.THINK_INTERVAL = 0.25
C.ACTIVE_INTERVAL = 0.05
C.OBSERVE_INTERVAL = 0.10
C.OUTPUT_MARGIN = 1.15
C.MIN_REFRESH_GAIN = 60
C.REFRESH_HORIZON = 3.0
C.REFRESH_REUSE_DELAY = 8.0
C.ACTION_TIMEOUT_MARGIN = 1.0
C.Q = 'ability_thdots_sagume_1'
C.W = 'ability_thdots_sagume_2'
C.E = 'ability_thdots_sagume_3'
C.R = 'ability_thdots_sagume_4'
C.RETURN = 'modifier_ability_sagume_telent7_check'
C.BOUNCE = 'modifier_ability_sagume_2_bounce'
C.SCEPTER = 'modifier_item_wanbaochui'

return C
