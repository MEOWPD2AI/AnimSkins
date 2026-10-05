dofile(ModPath .. "lua/tuner/core.lua")
local T = _G.AnimSkinsTuner

if T._light_loaded then
	return
end
T._light_loaded = true

local lights = {} -- unit -> { light = light, linked = unit }

local function kill_one(entry)
	if entry and entry.light then
		pcall(function()
			World:delete_light(entry.light)
		end)
	end
end

local function kill_all()
	for u, entry in pairs(lights) do
		kill_one(entry)
	end
	lights = {}
end

local function fire_object(base)
	if not base or not base._unit or not alive(base._unit) then
		return nil, nil
	end
	local unit = base._unit
	if type(base._obj_fire) == "userdata" then
		return base._obj_fire, unit
	end
	local obj = unit:get_object(Idstring("fire"))
	if obj then
		return obj, unit
	end
	return nil, unit
end

local function ensure_light(unit)
	local entry = lights[unit]
	if entry and entry.light then
		return entry.light
	end
	local light = World:create_light("omni|specular")
	if not light then
		return nil
	end
	lights[unit] = { light = light }
	return light
end

local function bases_to_light()
	local out = {}
	local swapped = _G.AnimSkins and _G.AnimSkins.swapped
	if not swapped then
		return out
	end
	local p = managers.player and managers.player:player_unit()
	if not alive(p) then
		return out
	end
	local inv = p:inventory()
	local eq = inv and inv:equipped_unit()
	if not alive(eq) then
		return out
	end
	local primary = eq:base()
	if primary and swapped[primary] then
		out[#out + 1] = primary
		local sec_u = primary._second_gun
		if alive(sec_u) then
			local sec = sec_u:base()
			if sec and swapped[sec] then
				out[#out + 1] = sec
			end
		end
	end
	return out
end

local function update()
	local s = T.settings
	if not s.enabled or not s.light then
		kill_all()
		return
	end
	local want = bases_to_light()
	local keep = {}
	for _, base in ipairs(want) do
		keep[base._unit] = true
	end
	for unit, entry in pairs(lights) do
		if not keep[unit] or not alive(unit) then
			kill_one(entry)
			lights[unit] = nil
		end
	end
	local mult = (T.react and T.react.applied) or (s.glow * (T.breath_factor and T:breath_factor() or 1))
	local base_glow = T.defaults.glow > 0 and T.defaults.glow or 5
	local intensity = (s.light_intensity or 1) * (mult / base_glow)
	local color = Vector3(s.light_r or 0.6, s.light_g or 0.7, s.light_b or 1.0)
	local range = s.light_range or 200
	for _, base in ipairs(want) do
		local unit = base._unit
		if alive(unit) then
			local light = ensure_light(unit)
			if light then
				local obj, owner = fire_object(base)
				if obj then
					pcall(function()
						light:link(obj)
						light:set_local_position(Vector3(0, 0, 0))
					end)
				else
					pcall(function()
						light:set_position(unit:position())
					end)
				end
				pcall(function()
					light:set_far_range(range)
					light:set_color(color)
					light:set_multiplier(intensity)
					light:set_enable(true)
				end)
			end
		end
	end
end

Hooks:Add("GameSetupUpdate", "AnimSkinsTuner_Light", function()
	local ok = pcall(update)
	if not ok then
		kill_all()
	end
end)
