_G.AnimSkins = _G.AnimSkins or {}
local AS = _G.AnimSkins

AS.path = ModPath
AS.MATERIALS_DIR = "units/"

if AS.menus == nil then
	AS.menus = true
end
if AS.enabled == nil then
	AS.enabled = true
end

AS.swapped = AS.swapped or setmetatable({}, { __mode = "k" })

local IDS_MATERIAL_CONFIG = Idstring("material_config")

local replacements = {}
local ghost_replacements = {}
local count = 0

AS.replacements = replacements
AS.ghost_replacements = ghost_replacements

local function load_mapping(file_name, into)
	local list = io.open(ModPath .. file_name, "r")

	if list then
		list:close()

		for line in io.lines(ModPath .. file_name) do
			local vanilla, name = line:match("^%s*(%S+)%s+(%S+)%s*$")

			if vanilla then
				into[Idstring(vanilla):key()] = { name = name, ids = Idstring(AS.MATERIALS_DIR .. name) }
				count = count + 1
			end
		end
	end
end

load_mapping("data/material_configs.txt", replacements)
load_mapping("data/material_configs_ghost.txt", ghost_replacements)

local function is_loaded(ids)
	return managers.dyn_resource:is_resource_ready(IDS_MATERIAL_CONFIG, ids, DynamicResourceManager.DYN_RESOURCES_PACKAGE)
end

-- When see-through is on, use the additive ghost copy of the config (if it is loaded),
-- otherwise the normal animated one.
local function replacement_for(part_data)

	local vanilla = part_data.material_config or part_data.unit

	if type(vanilla) == "string" then
		vanilla = Idstring(vanilla)
	end

	local key = vanilla:key()

	if AS.see_through then
		local ghost = ghost_replacements[key]
		if ghost and is_loaded(ghost.ids) then
			return ghost
		end
	end

	return replacements[key]
end

local function in_game()
	return Global.level_data and Global.level_data.level_id ~= nil
end

local function has_cosmetics(self)
	return self._cosmetics_data and true or false
end

local function wanted(self)
	if not AS.enabled or _G.IS_VR or not managers.dyn_resource then
		return false
	end
	if has_cosmetics(self) then
		return false
	end
	if self:is_npc() then
		return AS.menus and not in_game()
	end
	return AS.menus or in_game()
end

local material_config_name = NewRaycastWeaponBase._material_config_name

if material_config_name and not AS._name_wrapped then
	AS._name_wrapped = true

	function NewRaycastWeaponBase:_material_config_name(part_id, part_data, use_cc_material_config, force_third_person, ...)
		if use_cc_material_config and not force_third_person and part_data and wanted(self) then
			local replacement = replacement_for(part_data)

			if replacement and is_loaded(replacement.ids) then
				return replacement.ids
			end
		end

		return material_config_name(self, part_id, part_data, use_cc_material_config, force_third_person, ...)
	end
end

Hooks:PostHook(NewRaycastWeaponBase, "_update_materials", "AnimSkins_update_materials", function(self)
	if not self._parts then
		return
	end
	if has_cosmetics(self) then
		if AS.swapped[self] then
			AS.restore_weapon(self)
		end
		return
	end
	if not wanted(self) then
		return
	end

	local skinned = self._cosmetics_data and true or false
	local swapped = {}

	for part_id, part in pairs(self._parts) do
		local part_data = managers.weapon_factory:get_part_data_by_part_id_from_weapon(part_id, self._factory_id, self._blueprint)
		local replacement = part_data and replacement_for(part_data)

		if replacement and alive(part.unit) then
			if part.unit:material_config() ~= replacement.ids and not skinned then
				if is_loaded(replacement.ids) then
					part.unit:set_material_config(replacement.ids, true)
				end
			end

			if part.unit:material_config() == replacement.ids then
				local vanilla = part_data.material_config or part_data.unit
				if type(vanilla) == "string" then
					vanilla = Idstring(vanilla)
				end
				table.insert(swapped, {
					unit = part.unit,
					config = replacement.name,
					ids = replacement.ids,
					vanilla_ids = vanilla,
				})
			end
		end
	end

	AS.swapped[self] = swapped

	if #swapped > 0 then
		pcall(Hooks.Call, Hooks, "AnimSkinsSwapped", self, swapped)
	end
end)

function AS.restore_weapon(weapon)
	local swapped = AS.swapped[weapon]
	if not swapped then
		return
	end
	for _, part in ipairs(swapped) do
		if alive(part.unit) and part.vanilla_ids then
			if part.unit:material_config() == part.ids then
				part.unit:set_material_config(part.vanilla_ids, true)
			end
		end
	end
	AS.swapped[weapon] = nil
end

function AS.restore_all()
	local weapons = {}
	for weapon in pairs(AS.swapped) do
		weapons[#weapons + 1] = weapon
	end
	for _, weapon in ipairs(weapons) do
		AS.restore_weapon(weapon)
	end
end

function AS.refresh_weapon(weapon)
	if not weapon or type(weapon._update_materials) ~= "function" or not weapon._parts then
		return
	end
	local u = weapon._unit
	if not u or not alive(u) then
		return
	end
	pcall(function()
		weapon:_update_materials()
	end)
end

function AS.refresh_all()
	local seen = {}
	local function try(w)
		if w and not seen[w] then
			seen[w] = true
			AS.refresh_weapon(w)
		end
	end
	for weapon in pairs(AS.swapped) do
		try(weapon)
	end
	local pm = managers.player
	if pm and pm.player_unit and alive(pm:player_unit()) then
		local inv = pm:player_unit():inventory()
		if inv then
			local eq = inv:equipped_unit()
			if eq and alive(eq) then
				try(eq:base())
			end
			if inv.available_selections then
				for _, sel in pairs(inv:available_selections()) do
					if sel.unit and alive(sel.unit) then
						try(sel.unit:base())
					end
				end
			end
		end
	end
	if not in_game() and World and World.find_units_quick then
		local ok, units = pcall(World.find_units_quick, World, "all")
		if ok and units then
			for _, unit in ipairs(units) do
				if alive(unit) and unit.base then
					local base = unit:base()
					if base and base._parts and base._unit and alive(base._unit) then
						try(base)
					end
				end
			end
		end
	end
end

function AS.set_see_through(on)
	on = on and true or false
	if AS.see_through == on then
		return
	end
	AS.see_through = on
	if AS.enabled and AS.refresh_all then
		-- Rebuild cleanly: back to the vanilla config, then into the right (see-through or normal) one.
		-- Swapping ghost -> normal in place left the gun with blank gray materials.
		local weapons = {}
		for weapon in pairs(AS.swapped) do
			weapons[#weapons + 1] = weapon
		end
		AS.restore_all()
		AS.refresh_all()
		for _, weapon in ipairs(weapons) do
			AS.refresh_weapon(weapon)
		end
	end
end

function AS.set_enabled(on)
	AS.enabled = on and true or false
	if not AS.enabled then
		AS.restore_all()
	else
		AS.refresh_all()
	end
end

Hooks:Add("MenuManagerOnOpenMenu", "AnimSkins_menu_refresh", function(menu_manager, menu_name)
	if menu_name == "menu_main" and AS.enabled and AS.menus and AS.refresh_all then
		AS.refresh_all()
	end
end)
