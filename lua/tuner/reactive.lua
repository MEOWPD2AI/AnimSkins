dofile(ModPath .. "lua/tuner/core.lua")
local T = _G.AnimSkinsTuner

if T._reactive_loaded then
	return
end
T._reactive_loaded = true

T.react = {
	assault = false,
	anticipation = false,
	heat = 0,
	shot_boost = 0,
	current = 1.0,
	applied = nil,
	weapon = nil,
	groups = nil,
	groups_age = 0,
	fx_id = nil,
	fx_kind = nil,
	fx_unit = nil,
	fx_at = 0,
	flash_at = 0,
	flashes = {},
	time = 0,
}

local OBJ_FIRE = Idstring("fire")
local IDS_EFFECT = Idstring("effect")

T.HEAT_FX = {
	{ name = "Off" },
	{ name = "Overheat",        path = "effects/payday2/particles/weapons/heat/overheat" },
	{ name = "Hailstorm heat",  path = "effects/payday2/particles/weapons/heat/hailstorm_heat" },
	{ name = "Sparks",          path = "effects/payday2/particles/explosions/sparks/sparks_loop" },
	{ name = "Electric sparks", path = "effects/payday2/particles/electric/electric_sparks_cable" },
	{ name = "Drill sparks",    path = "effects/payday2/environment/parts/drill_sparks_particles" },
}

T.FLASH_FX = {
	{ name = "Off" },
	{ name = "Kawaii sparkles", path = "effects/payday2/particles/character/overkillpack/mega_kawaii_sparkles",
	  package = "packages/dlcs/dlc_pack_overkill/game_base" },
	{ name = "Sparkle burst",   path = "effects/payday2/particles/explosions/sparkle_enemies",
	  package = "packages/dlcs/sparkle/game_base" },
	{ name = "Small sparkles",  path = "effects/particles/fire/small_sparkles" },
	{ name = "Sniper glint",    path = "effects/particles/weapons/sniper_glint_marshal" },
	{ name = "Spark flash (FPS)",   path = "effects/payday2/particles/weapons/fps_parts/fps_spark_flash" },
	{ name = "Sparse flash (FPS)",  path = "effects/payday2/particles/weapons/fps_parts/fps_sparse_flash" },
	{ name = "Ball flash (FPS)",    path = "effects/payday2/particles/weapons/fps_parts/fps_ball_flash" },
	{ name = "Fireball (FPS)",      path = "effects/payday2/particles/weapons/fps_parts/fps_fireball" },
	{ name = "Blue flash (FPS)",    path = "effects/payday2/particles/weapons/fps_parts/fps_small_silence_blue_flash" },
}

local function names_of(list)
	local out = {}
	for _, fx in ipairs(list) do table.insert(out, fx.name) end
	return out
end
function T:heat_fx_names() return names_of(self.HEAT_FX) end
function T:flash_fx_names() return names_of(self.FLASH_FX) end

local ids_cache = {}
local function ids(path)
	if not ids_cache[path] then ids_cache[path] = Idstring(path) end
	return ids_cache[path]
end

local reported = {}
local function effect_ready(fx)
	local path = fx.path
	if reported[path] ~= nil then return reported[path] end
	local function resident()
		local ok, has = pcall(PackageManager.has, PackageManager, IDS_EFFECT, ids(path))
		return ok and has and true or false
	end
	local has = resident()
	if not has and fx.package then
		pcall(function()
			if PackageManager:package_exists(fx.package) and not PackageManager:loaded(fx.package) then
				PackageManager:load(fx.package)
							end
		end)
		has = resident()
	end
	reported[path] = has
		return has
end

function T:on_assault(active)
	self.react.assault = active and true or false
	if active then self.react.anticipation = false end
end

function T:on_anticipation()
	self.react.anticipation = true
end

local function equipped_base()
	local p = managers.player and managers.player:player_unit()
	if not alive(p) then return nil end
	local inventory = p:inventory()
	local unit = inventory and inventory:equipped_unit()
	local base = alive(unit) and unit:base()
	if base and base._unit and alive(base._unit) then return base end
	return nil
end

-- Akimbo left gun unit/base linked from the primary via _second_gun
local function second_base(weapon)
	if not weapon then return nil end
	local u = weapon._second_gun
	if not alive(u) then return nil end
	local base = u:base()
	if base and base._unit and alive(base._unit) then return base end
	return nil
end

local function is_equipped_pair(weapon, primary)
	if not weapon or not primary then return false end
	if weapon == primary then return true end
	local sec = second_base(primary)
	return sec and weapon == sec
end

local function collect_pair(primary)
	local groups = T:collect(primary)
	local sec = second_base(primary)
	if sec then
		for _, g in ipairs(T:collect(sec)) do
			groups[#groups + 1] = g
		end
	end
	return groups
end

local MUZZLE_TYPES = { "barrel_ext", "barrel", "slide" }

local function muzzle_object(weapon)
	if type(weapon._obj_fire) == "userdata" then return weapon._obj_fire, weapon._unit end
	local fparts = tweak_data.weapon.factory.parts
	for _, want in ipairs(MUZZLE_TYPES) do
		for part_id, part in pairs(weapon._parts or {}) do
			if fparts[part_id] and fparts[part_id].type == want and alive(part.unit) then
				local fire = part.unit:get_object(OBJ_FIRE)
				if fire then return fire, part.unit end
			end
		end
	end
	return weapon._unit:get_object(OBJ_FIRE), weapon._unit
end

local function spawn_at_muzzle(weapon, fx)
	local obj, owner = muzzle_object(weapon)
	if not obj or not alive(owner) or not effect_ready(fx) then return nil end
	local id = World:effect_manager():spawn({ effect = ids(fx.path), parent = obj })
	return id, owner
end

local function effect_kill(id)
	local em = World:effect_manager()
	if type(em.fade_kill) == "function" then em:fade_kill(id) else em:kill(id) end
end

function T:on_shot(weapon)
	local s = self.settings
	local r = self.react
	if not s.reactive or not s.enabled then return end
	if not is_equipped_pair(weapon, r.weapon) then return end
	if s.react_shot_flash then
		r.shot_boost = s.react_shot_flash_boost or 2.5
	else
		r.heat = math.min(1, r.heat + s.react_heat_gain)
	end

	local fx = self.FLASH_FX[s.react_flash_fx]
	if fx and fx.path and r.time - r.flash_at > 0.06 then
		r.flash_at = r.time
		local id, owner = spawn_at_muzzle(weapon, fx)
		if id and id ~= -1 then
			table.insert(r.flashes, { id = id, dies = r.time + s.react_flash_life, unit = owner })
		end
	end
end

local MAX_FLASHES = 8

local function flashes_update(all)
	local r = T.react
	local kept = {}
	for _, f in ipairs(r.flashes) do
		if all or r.time >= f.dies or not alive(f.unit) then
			pcall(effect_kill, f.id)
		else
			table.insert(kept, f)
		end
	end
	while #kept > MAX_FLASHES do
		pcall(effect_kill, table.remove(kept, 1).id)
	end
	r.flashes = kept
end

local function fx_kill()
	local r = T.react
	if r.fx_id then
		pcall(effect_kill, r.fx_id)
	end
	r.fx_id, r.fx_kind, r.fx_unit = nil, nil, nil
end

local function fx_update(weapon)
	local s = T.settings
	local r = T.react
	if r.fx_id and not alive(r.fx_unit) then fx_kill() end
	local want = s.react_heat_fx > 1 and r.heat >= s.react_heat_at
	local keep = r.fx_id and r.heat >= s.react_heat_at * 0.6
	if r.fx_id and (not (want or keep) or r.fx_kind ~= s.react_heat_fx) then fx_kill() end
	if want and r.fx_id and r.time - r.fx_at >= s.react_heat_fx_period then fx_kill() end
	if want and not r.fx_id then
		local fx = T.HEAT_FX[s.react_heat_fx]
		if fx and fx.path then
			local id, owner = spawn_at_muzzle(weapon, fx)
			if id and id ~= -1 then
				r.fx_id, r.fx_kind, r.fx_unit, r.fx_at = id, s.react_heat_fx, owner, r.time
			end
		end
	end
end

function T:react_target()
	local s = self.settings
	local whisper = managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
	if whisper then return s.react_stealth end
	if self.react.assault then return s.react_assault end
	if self.react.anticipation then return 1.0 + (s.react_assault - 1.0) * 0.4 end
	return 1.0
end

local function update(dt)
	local s = T.settings
	local r = T.react
	r.time = r.time + dt

	if not s.reactive or not s.enabled then

		if r.fx_id or #r.flashes > 0 then
			fx_kill()
			flashes_update(true)
		end
		if r.applied ~= nil and r.groups then
			local m = s.enabled and s.glow * T:breath_factor() or 0
			T:write_vars(r.groups, m, 1, s.bloom)
		end
		r.applied, r.current, r.heat, r.shot_boost = nil, 1.0, 0, 0
		return
	end

	local weapon = equipped_base()
	if weapon ~= r.weapon then
		fx_kill()
		flashes_update(true)
		r.weapon, r.groups, r.applied, r.heat, r.shot_boost = weapon, nil, nil, 0, 0
	end
	if not weapon then return end

	r.groups_age = r.groups_age + dt
	if not r.groups or r.groups_age > 2.0 then
		r.groups = collect_pair(weapon)
		r.groups_age = 0
		r.applied = nil
	end

	if s.react_shot_flash then
		r.heat = 0
		r.shot_boost = math.max(0, r.shot_boost - dt * (s.react_shot_flash_decay or 6))
	else
		r.shot_boost = 0
		r.heat = math.max(0, r.heat - dt * s.react_heat_cool)
	end

	local k = 1 - math.exp(-dt * math.max(s.react_smooth, 0.1))
	r.current = r.current + (T:react_target() - r.current) * k

	local base = s.glow * r.current
	local breath = T:breath_factor()
	local mult
	local speed_scale = 1
	if s.react_shot_flash then
		-- Breathing only on the steady glow; shot flash is additive and independent
		mult = base * breath + base * r.shot_boost
	else
		mult = base * (1 + r.heat * s.react_heat_glow) * breath
		speed_scale = 1 + r.heat * (s.react_heat_speed - 1)
	end
	T.react_speed_scale = speed_scale
	if s.breath or s.ghost or r.applied == nil or math.abs(mult - (r.applied or 0)) > 0.02 or r.shot_boost > 0.01 then
		T:write_vars(r.groups, mult, speed_scale, s.bloom)
		r.applied = mult
	end

	if not s.react_shot_flash then
		fx_update(weapon)
	else
		fx_kill()
	end
	flashes_update(false)
end

local failed = false
Hooks:Add("GameSetupUpdate", "AnimSkinsTuner_Reactive", function(t, dt)
	if failed then return end
	local ok = pcall(update, dt or 0.016)
	if not ok then
		failed = true
	end
end)
