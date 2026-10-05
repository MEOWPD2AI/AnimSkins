_G.AnimSkinsTuner = _G.AnimSkinsTuner or {}
local T = _G.AnimSkinsTuner

if T._core_loaded then
	return
end
T._core_loaded = true

T._path = ModPath
T._save = SavePath .. "animskins_tuner.json"

T._legacy_save = SavePath .. "glitchwave_tuner.json"

T.defaults = {
	enabled = true,
	scroll = false,
	fixed_scroll = true,
	breath = true,
	breath_rate = 1.5,
	breath_depth = 0.4,
	breath_offset = 0,
	see_through = false,
	see_through_gain = 3,
	st_color = false,
	st_tint = 1,
	skin_list_v = 2,
	ghost = false,
	ghost_rate = 0.4,
	ghost_min = 0.1,
	glow = 5,
	bloom = 1.0,
	speed = 0.1,
	direction = 6,
	menus = true,

	primary_skin = 1,
	secondary_skin = 1,

	reactive = true,
	react_stealth = 0.35,
	react_assault = 1.6,
	react_smooth = 4.0,
	react_heat_gain = 0.06,
	react_heat_cool = 0.35,
	react_heat_glow = 1.5,
	react_heat_speed = 3.0,
	react_shot_flash = false,
	react_shot_flash_boost = 2.5,
	react_shot_flash_decay = 6,
	react_heat_fx = 2,
	react_heat_at = 0.5,
	react_heat_fx_period = 1.0,
	react_flash_fx = 2,
	react_flash_life = 0.6,

	light = false,
	light_intensity = 1.0,
	light_range = 200,
	light_r = 0.55,
	light_g = 0.7,
	light_b = 1.0,
}

-- See-through colour: the white texture, plus tiny solid-colour copies of it (white first).
-- Keep in sync with G.TINT_TEXTURES in generator/generate.lua and the files in assets/textures/original.
T.TINTS = {
	{ name = "White", tex = "textures/original/white" },
	{ name = "Red", tex = "textures/original/tint_red" },
	{ name = "Orange", tex = "textures/original/tint_orange" },
	{ name = "Gold", tex = "textures/original/tint_gold" },
	{ name = "Yellow", tex = "textures/original/tint_yellow" },
	{ name = "Lime", tex = "textures/original/tint_lime" },
	{ name = "Green", tex = "textures/original/tint_green" },
	{ name = "Mint", tex = "textures/original/tint_mint" },
	{ name = "Cyan", tex = "textures/original/tint_cyan" },
	{ name = "Sky blue", tex = "textures/original/tint_sky" },
	{ name = "Blue", tex = "textures/original/tint_blue" },
	{ name = "Purple", tex = "textures/original/tint_purple" },
	{ name = "Magenta", tex = "textures/original/tint_magenta" },
	{ name = "Pink", tex = "textures/original/tint_pink" },
}

T.settings = {}
for k, v in pairs(T.defaults) do
	T.settings[k] = v
end

T.DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.707, 0.707 }, false }

local function animskins_path()
	local mod = BLT and BLT.Mods and BLT.Mods:GetModByName("AnimSkins")
	if mod and mod:WasEnabledAtStart() then
		return mod:GetPath()
	end
	return _G.AnimSkins and _G.AnimSkins.path
end

-- Built-in 4x4 black texture (always loaded). It is the default for anything a skin does not provide,
-- so a skin only needs the textures it really has and a missing one shows black instead of white.
T.BLACK = "textures/original/black"

T.skins = { { id = "default", name = "Default" } }
T.baked = { glow = 5, bloom = 1.0, speed = 0.1 }

function T:load_manifest()
	local path = animskins_path()
	if not path then
		return
	end
	self._animskins = path

	local f = io.open(path .. "data/variants.json", "r")
	if f then
		local ok, data = pcall(function() return json.decode(f:read("*all")) end)
		f:close()
		if ok and type(data) == "table" and type(data.skins) == "table" and #data.skins > 0 then
			self.skins = data.skins
			if type(data.baked) == "table" then
				self.baked = data.baked
			end
			if type(data.imported) == "table" then
				for _, s in ipairs(data.imported) do
					table.insert(self.skins, s)
				end
			end
		end
	end

	for _, skin in ipairs(self.skins) do
		skin.ids_base = Idstring(skin.base or T.BLACK)
		skin.ids_glow = Idstring(skin.glow or T.BLACK)
	end

	self._config_cache = {}
end

local BASE_DIFFUSE = "textures/original/default_df"
T.GHOST_TEMPLATE = "effect:BLEND_ADD:DIFFUSE0_TEXTURE:FPS"

function T:info_for_config(config_name)
	if not config_name or not self._animskins then
		return nil
	end
	local cache = self._config_cache
	local cached = cache[config_name]
	if cached ~= nil then
		return cached or nil
	end
	local path = self._animskins .. "assets/units/" .. config_name .. ".material_config"
	local f = io.open(path, "rb")
	if not f then
		cache[config_name] = false
		return nil
	end
	local text = f:read("*all") or ""
	f:close()

	local entry = { anim = {}, base = {}, ghost = {} }
	local pos = 1
	while true do
		local s, e, attrs = text:find("<material%s+([^>]-)>", pos)
		if not s then break end
		local body = ""
		if attrs:sub(-1) == "/" then
			pos = e + 1
		else
			local cs, ce = text:find("</material>", e + 1, true)
			if not cs then break end
			body = text:sub(e + 1, cs - 1)
			pos = ce + 1
		end
		local name, template
		for k, v in attrs:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
			if k == "name" then name = v end
			if k == "render_template" then template = v end
		end
		if name then
			local has_uv, ux, uy = false, 1, 0
			local diffuse_file
			for vk, vv in body:gmatch('<variable%s+([^>]+)/?>') do
				local vn, val
				for k, v in vk:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
					if k == "name" then vn = v end
					if k == "value" then val = v end
				end
				if vn == "uv_speed" and val then
					has_uv = true
					local a, b = val:match("(%S+)%s+(%S+)")
					ux, uy = tonumber(a) or 0, tonumber(b) or 0
					local len = math.sqrt(ux * ux + uy * uy)
					if len > 1e-6 then
						ux, uy = ux / len, uy / len
					else
						ux, uy = 1, 0
					end
				end
			end
			for fk in body:gmatch('<diffuse_texture%s+([^>]+)/?>') do
				diffuse_file = fk:match('file%s*=%s*"([^"]*)"')
			end
			local key = Idstring(name):key()
			if template == T.GHOST_TEMPLATE then
				entry.ghost[key] = true
			elseif has_uv then
				entry.anim[key] = { ux, uy }
			elseif diffuse_file == BASE_DIFFUSE then
				entry.base[key] = true
			end
		end
	end
	cache[config_name] = entry
	return entry
end

function T:load()
	local f = io.open(self._save, "r") or io.open(self._legacy_save, "r")
	local raw
	if f then
		local ok, data = pcall(function() return json.decode(f:read("*all")) end)
		f:close()
		if ok and type(data) == "table" then
			raw = data
			for k, v in pairs(data) do
				if self.defaults[k] ~= nil and type(v) == type(self.defaults[k]) then
					self.settings[k] = v
				end
			end

			local function old_slot(value)
				if type(value) == "number" and value > 1 then return value - 1 end
				return type(data.skin) == "number" and data.skin or nil
			end
			if data.primary_skin == nil and old_slot(data.skin_primary) then
				self.settings.primary_skin = old_slot(data.skin_primary)
			end
			if data.secondary_skin == nil and old_slot(data.skin_secondary) then
				self.settings.secondary_skin = old_slot(data.skin_secondary)
			end
		end
	end

	local s = self.settings
	-- The "Black" skin (list slot 16) was removed from the skin list: shift saved slots after it
	if type(raw) == "table" and raw.skin_list_v == nil then
		for _, key in ipairs({ "primary_skin", "secondary_skin" }) do
			local v = s[key]
			if type(v) == "number" then
				if v == 16 then s[key] = 1 elseif v > 16 then s[key] = v - 1 end
			end
		end
	end
	s.skin_list_v = self.defaults.skin_list_v
	if not self.TINTS[s.st_tint] then s.st_tint = 1 end
	-- Ghost fade was removed from the menu: always off
	s.ghost = self.defaults.ghost
	if not self.skins[s.primary_skin] then s.primary_skin = 1 end
	if not self.skins[s.secondary_skin] then s.secondary_skin = 1 end
	if self.DIRECTIONS[s.direction] == nil then s.direction = self.defaults.direction end
	self:sync_animskins()
end

function T:save()
	local f = io.open(self._save, "w+")
	if f then
		f:write(json.encode(self.settings))
		f:close()
	end
end

function T:sync_animskins()
	_G.AnimSkins = _G.AnimSkins or {}
	_G.AnimSkins.menus = self.settings.menus
	local on = self.settings.enabled ~= false
	if _G.AnimSkins.set_see_through then
		_G.AnimSkins.set_see_through(self.settings.see_through)
	else
		_G.AnimSkins.see_through = self.settings.see_through and true or false
	end
	if _G.AnimSkins.set_enabled then
		_G.AnimSkins.set_enabled(on)
	else
		_G.AnimSkins.enabled = on
	end
end

function T:skin_names()
	local out = {}
	for _, s in ipairs(self.skins) do table.insert(out, s.name or s.id) end
	return out
end

function T:tint_names()
	local out = {}
	for _, t in ipairs(self.TINTS) do table.insert(out, t.name) end
	return out
end

function T:skin_for(weapon)
	local s = self.settings
	local idx
	local w = weapon
	-- Akimbo left gun often has no selection_index; use the primary if linked
	if w and not (type(w.selection_index) == "function") then
		w = nil
	end
	if weapon and weapon._unit and alive(weapon._unit) then
		-- if this is the second gun, prefer the equipped primary for slot
	end
	if weapon and type(weapon.selection_index) == "function" then
		local ok, sel = pcall(weapon.selection_index, weapon)
		if ok then idx = sel end
	end
	if idx == nil then
		local eq = managers.player and managers.player:player_unit()
		eq = eq and alive(eq) and eq:inventory() and eq:inventory():equipped_unit()
		local base = eq and alive(eq) and eq:base()
		if base and type(base.selection_index) == "function" then
			local ok, sel = pcall(base.selection_index, base)
			if ok then idx = sel end
		end
	end
	local choice = idx == 1 and s.secondary_skin or s.primary_skin
	return self.skins[choice] or self.skins[1]
end

local IDS_MATERIAL = Idstring("material")
local IDS_TEXTURE = Idstring("texture")
local IDS_NORMAL = Idstring("normal")
local IL_MULT = Idstring("il_multiplier")
local IL_BLOOM = Idstring("il_bloom")
local UV_SPEED = Idstring("uv_speed")
local SLOT_DIFFUSE = Idstring("diffuse_texture")
local SLOT_GLOW = Idstring("self_illumination_texture")
local IDS_INTENSITY = Idstring("intensity")

local IDS_BLACK = Idstring(T.BLACK)

local ready = {}
local function texture_ready(ids)
	if not ids then return false end
	local key = ids:key()
	if not ready[key] then
		local ok, is = pcall(function()
			return managers.dyn_resource:is_resource_ready(IDS_TEXTURE, ids, DynamicResourceManager.DYN_RESOURCES_PACKAGE)
		end)
		ready[key] = ok and is or nil
	end
	return ready[key] and true or false
end

function T:collect(weapon)
	local groups = {}
	local swapped = _G.AnimSkins and _G.AnimSkins.swapped and _G.AnimSkins.swapped[weapon]
	if not swapped then
		return groups
	end
	-- skins built from one bright image (custom .dds) carry a glow_scale instead of a pre-darkened file
	local skin = self:skin_for(weapon)
	local gscale = tonumber(skin and skin.glow_scale) or 1
	for _, part in ipairs(swapped) do
		local unit = part.unit
		local info = self:info_for_config(part.config)
		if info and alive(unit) and unit:material_config() == part.ids then
			local group = { unit = unit, ids = part.ids, anim = {}, base = {}, ghost = {}, glow_scale = gscale, skin = skin }
			for _, m in ipairs(unit:get_objects_by_type(IDS_MATERIAL)) do
				local key = m:name():key()
				local dir = info.anim[key]
				if dir then
					table.insert(group.anim, { m, dir[1], dir[2] })
				elseif info.base[key] then
					table.insert(group.base, m)
				elseif info.ghost[key] then
					table.insert(group.ghost, m)
				end
			end
			table.insert(groups, group)
		end
	end
	return groups
end

function T.group_live(group)
	return alive(group.unit) and group.unit:material_config() == group.ids
end

function T:speed_for(u, v, scale)
	local s = self.settings
	if not s.enabled or not s.scroll then
		return Vector3(0, 0, 0)
	end
	local d = self.DIRECTIONS[s.direction]
	local speed = s.speed * (scale or 1)
	if d then
		return Vector3(d[1] * speed, d[2] * speed, 0)
	end
	return Vector3(u * speed, v * speed, 0)
end

function T:breath_factor()
	local s = self.settings
	if not s.enabled or not (s.breath or s.ghost) then
		return 1
	end
	if s.ghost then
		return self:ghost_factor()
	end
	local rate = s.breath_rate or 1.5
	local depth = s.breath_depth or 0.4
	local offset = s.breath_offset or 0
	local t = Application:time()
	if TimerManager and TimerManager.game then
		local ok, gt = pcall(function() return TimerManager:game():time() end)
		if ok and type(gt) == "number" then
			t = gt
		end
	end
	-- center at 1+offset, swing by depth; never below 0
	local v = 1 + offset + depth * math.sin(t * rate * (math.pi * 2))
	if v < 0 then v = 0 end
	return v
end

-- Ghost fade: the glow slowly fades almost out and back in, with a faint flicker, so the gun
-- seems to phase in and out of existence. ghost_min is how visible it stays at its faintest.
function T:ghost_factor()
	local s = self.settings
	local t = Application:time()
	if TimerManager and TimerManager.game then
		local ok, gt = pcall(function() return TimerManager:game():time() end)
		if ok and type(gt) == "number" then
			t = gt
		end
	end
	local rate = s.ghost_rate or 0.4
	local lo = math.max(0, math.min(1, s.ghost_min or 0.1))
	local wave = 0.5 + 0.5 * math.sin(t * rate * math.pi * 2)
	wave = wave * wave * (3 - 2 * wave)
	local flick = 1 - 0.25 * math.max(0, math.sin(t * 17.3) * math.sin(t * 5.1 + 1.7))
	return (lo + (1 - lo) * wave) * flick
end

function T:write_vars(groups, mult, speed_scale, bloom)
	mult = mult or 0
	local n = 0
	-- see-through (additive) materials have no glow slot: the same glow value drives their intensity
	local intensity = mult / math.max(tonumber(self.baked and self.baked.glow) or 5, 0.01) * (self.settings.see_through_gain or 3)
	for _, group in ipairs(groups) do
		if T.group_live(group) then
			for _, m in ipairs(group.ghost or {}) do
				m:set_variable(IDS_INTENSITY, intensity)
				n = n + 1
			end
			for _, entry in ipairs(group.anim) do
				local m = entry[1]
				m:set_variable(IL_MULT, mult * (group.glow_scale or 1))
				m:set_variable(UV_SPEED, self:speed_for(entry[2], entry[3], speed_scale))
				if bloom then
					m:set_variable(IL_BLOOM, bloom)
				end
				n = n + 1
			end
		end
	end
	return n
end

-- Texture for the see-through colour option (nil when the option is off)
function T:tint_ids()
	local s = self.settings
	if not (s.see_through and s.st_color) then return nil end
	local function ids_of(t)
		if t and not t.ids then t.ids = Idstring(t.tex) end
		return t and t.ids
	end
	local ids = ids_of(self.TINTS[s.st_tint])
	if ids and texture_ready(ids) then return ids end
	local white = ids_of(self.TINTS[1])
	if white and texture_ready(white) then return white end
	return nil
end

-- Stepped see-through scroll.
-- The additive see-through shader has no UV scroll, so the pattern is moved by swapping between
-- pre-shifted copies of the skin texture (<glow>_f00 .. _f<N-1>, built from the skin image, see
-- "frames" in data/variants.json). Skins without frames (Ghost) simply do not scroll.
T._ghost_idx = setmetatable({}, { __mode = "k" })
T._scroll_pos = 0
T._scroll_acc = 0
T.react_speed_scale = 1

function T:ghost_scroll_active()
	local s = self.settings
	return s.enabled and s.scroll and s.see_through and not s.st_color and true or false
end

local function frame_ids(skin, i)
	local n = skin and tonumber(skin.frames)
	if not n or n < 2 or not skin.glow then return nil end
	skin._frame_ids = skin._frame_ids or {}
	local ids = skin._frame_ids[i]
	if not ids then
		ids = Idstring(("%s_f%02d"):format(skin.glow, i))
		skin._frame_ids[i] = ids
	end
	return ids
end

function T:ghost_frame_index(skin)
	local n = skin and tonumber(skin.frames)
	if not n or n < 2 then return nil end
	return math.floor(self._scroll_pos * n) % n
end

-- Texture to show on the see-through materials right now, or nil when the skin does not scroll
function T:ghost_frame_texture(skin)
	if not self:ghost_scroll_active() then return nil end
	local i = self:ghost_frame_index(skin)
	local ids = i and frame_ids(skin, i)
	if ids and texture_ready(ids) then return ids, i end
	return nil
end

function T:apply(weapon)
	local s = self.settings
	local groups = self:collect(weapon)
	if #groups == 0 then
		return
	end
	self._ghost_idx[weapon] = nil

	local skin = self:skin_for(weapon)
	local base = skin and texture_ready(skin.ids_base) and skin.ids_base
	local glow = skin and texture_ready(skin.ids_glow) and skin.ids_glow
	-- skin textures missing or not loaded (e.g. an imported skin before its restart): black, not white
	if not base and texture_ready(IDS_BLACK) then base = IDS_BLACK end
	if not glow and texture_ready(IDS_BLACK) then glow = IDS_BLACK end

	local tint = self:tint_ids()

	local mult = s.enabled and s.glow or 0
	if s.enabled then
		mult = mult * self:breath_factor()
	end
	self:write_vars(groups, mult, 1, s.bloom)
	for _, group in ipairs(groups) do
		if T.group_live(group) then
			for _, entry in ipairs(group.anim) do
				if base then Application:set_material_texture(entry[1], SLOT_DIFFUSE, base, IDS_NORMAL) end
				if glow then Application:set_material_texture(entry[1], SLOT_GLOW, glow, IDS_NORMAL) end
			end
			if base then
				for _, m in ipairs(group.base) do
					Application:set_material_texture(m, SLOT_DIFFUSE, base, IDS_NORMAL)
				end
			end
			-- see-through is additive, so a black base would vanish: use the glow image for those skins;
			-- with the colour option on, the white / tint texture is used instead of the skin
			local ghost_tex = tint or self:ghost_frame_texture(skin) or ((skin.glow_scale and glow) or base)
			if ghost_tex then
				for _, m in ipairs(group.ghost or {}) do
					Application:set_material_texture(m, SLOT_DIFFUSE, ghost_tex, IDS_NORMAL)
				end
			end
		end
	end

	if self.react then
		self.react.applied = nil
		self.react.groups = nil
	end
end

function T:apply_all()
	local swapped = _G.AnimSkins and _G.AnimSkins.swapped
	if not swapped then
		return
	end
	for weapon in pairs(swapped) do
		if weapon._unit and alive(weapon._unit) then
			pcall(self.apply, self, weapon)
		end
	end
end

-- After a material config is swapped at runtime (e.g. see-through turned off) the new materials can
-- finish setting up a moment after the swap, which left the gun with blank gray textures. So the
-- skin textures are applied right away and then re-applied a few times over the next ~1.5 s.
local REAPPLY_AT = { 0.1, 0.35, 0.8, 1.5 }
T._rq = nil

function T:queue_reapply()
	self._rq = { t = 0, i = 1 }
end

Hooks:Add("AnimSkinsSwapped", "AnimSkinsTuner_apply", function(weapon)
	pcall(T.apply, T, weapon)
	T:queue_reapply()
end)

Hooks:Add("GameSetupUpdate", "AnimSkinsTuner_Reapply", function(t, dt)
	local q = T._rq
	if not q then return end
	q.t = q.t + (dt or 0.016)
	local at = REAPPLY_AT[q.i]
	if not at then
		T._rq = nil
	elseif q.t >= at then
		q.i = q.i + 1
		pcall(T.apply_all, T)
	end
end)

if not pcall(T.load_manifest, T) then
	T._config_cache = {}
end
T:load()

Hooks:Add("GameSetupUpdate", "AnimSkinsTuner_Breath", function(t, dt)
	local s = T.settings
	if not s.enabled or not (s.breath or s.ghost) then
		return
	end
	if s.reactive then
		return
	end
	local swapped = _G.AnimSkins and _G.AnimSkins.swapped
	if not swapped then
		return
	end
	for weapon in pairs(swapped) do
		if weapon._unit and alive(weapon._unit) then
			local groups = T:collect(weapon)
			if #groups > 0 then
				T:write_vars(groups, s.glow * T:breath_factor(), 1, s.bloom)
			end
		end
	end
end)

-- Steps the see-through scroll. Position is accumulated (so speed changes never make it jump) and the
-- texture is only swapped when the frame number changes.
-- Runs on both the in-heist update and the menu update, so the main menu / lobby / inventory previews move too.
local logged_not_ready = false

-- Fixed see-through scroll: the frame number advances at exactly FIXED_FPS frames per second (one
-- frame per 1/48 s for the 48-frame skins), independent of Scroll speed, heat and the game's frame
-- rate. The frame swap runs on every update (no 25 Hz gate), so it is as smooth as the game allows.
local FIXED_FPS = 48
local FRAME_COUNT = 48

local function ghost_scroll_step(dt)
	if not T:ghost_scroll_active() then
		T._last_key = nil
		return
	end
	local s = T.settings
	dt = math.min(dt or 0.016, 0.1)
	local d = T.DIRECTIONS[s.direction]
	local dir = 1
	if d then
		if d[1] ~= 0 then dir = d[1] > 0 and 1 or -1
		elseif d[2] ~= 0 then dir = d[2] > 0 and 1 or -1 end
	end
	if s.fixed_scroll ~= false then
		T._scroll_pos = (T._scroll_pos + dt * (FIXED_FPS / FRAME_COUNT) * dir) % 1
		-- All weapons share one position: nothing to do until the frame number actually changes.
		-- a frame that was not loaded yet is retried a moment later instead of being skipped for good
		if (T._retry_wait or 0) > 0 then
			T._retry_wait = T._retry_wait - dt
			return
		end
		local key = math.floor(T._scroll_pos * FRAME_COUNT)
		if key == T._last_key then return end
		T._last_key = key
	else
		T._last_key = nil
		local scale = s.reactive and T.react_speed_scale or 1
		T._scroll_pos = (T._scroll_pos + dt * (s.speed or 0.1) * scale * dir) % 1

		T._scroll_acc = T._scroll_acc + dt
		if T._scroll_acc < 0.04 then return end
		T._scroll_acc = 0
	end

	local swapped = _G.AnimSkins and _G.AnimSkins.swapped
	if not swapped then return end
	local failed = false
	for weapon in pairs(swapped) do
		if weapon._unit and alive(weapon._unit) then
			local groups = T:collect(weapon)
			local skin = groups[1] and groups[1].skin
			local idx = T:ghost_frame_index(skin)
			if idx and T._ghost_idx[weapon] ~= idx then
				local ids = frame_ids(skin, idx)
				if ids and texture_ready(ids) then
					for _, group in ipairs(groups) do
						if T.group_live(group) then
							for _, m in ipairs(group.ghost or {}) do
								Application:set_material_texture(m, SLOT_DIFFUSE, ids, IDS_NORMAL)
							end
						end
					end
					T._ghost_idx[weapon] = idx
				else
					failed = true
					if not logged_not_ready and log then
						logged_not_ready = true
						pcall(log, "[AnimSkins] see-through scroll: frame texture not ready (still loading is normal for a few seconds): " .. tostring(skin and skin.glow) .. "_f" .. tostring(idx))
					end
				end
			end
		end
	end

	if failed then
		-- keep the current frame, try again shortly; after ~10 s of failing, say what to check (once)
		T._last_key = nil
		T._retry_wait = 0.25
		T._fail_time = (T._fail_time or 0) + 0.25 + dt
		if T._fail_time > 10 and not T._fail_hint and log then
			T._fail_hint = true
			pcall(log, "[AnimSkins] see-through scroll frames still not loaded after 10 s: check that mods/AnimSkins/main.xml lists textures/original/*_il_f00 .. _f47 and restart the game once")
		end
	else
		T._fail_time = 0
	end
end

local function ghost_scroll_safe(t, dt)
	pcall(ghost_scroll_step, dt)
end

Hooks:Add("GameSetupUpdate", "AnimSkinsTuner_GhostScroll", ghost_scroll_safe)
Hooks:Add("MenuUpdate", "AnimSkinsTuner_GhostScroll_Menu", ghost_scroll_safe)
