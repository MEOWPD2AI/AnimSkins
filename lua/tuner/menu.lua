dofile(ModPath .. "lua/tuner/core.lua")
dofile(ModPath .. "lua/tuner/reactive.lua")
dofile(ModPath .. "lua/tuner/light.lua")
local T = _G.AnimSkinsTuner

_G.AnimSkinsGen = _G.AnimSkinsGen or {}
local GEN = _G.AnimSkinsGen

local MENU           = "animskins_tuner"
local MENU_SKIN      = "animskins_tuner_skin"
local MENU_REACTIVE  = "animskins_tuner_reactive"
local MENU_GLOW      = "animskins_tuner_glow"
local MENU_STCOLOR   = "animskins_tuner_stcolor"
local MENU_LIGHT     = "animskins_tuner_light"
local MENU_MUZZLE    = "animskins_tuner_muzzle"
local MENU_GENERATOR = "animskins_generator"

Hooks:Add("LocalizationManagerPostInit", "AnimSkinsTuner_loc", function(loc)
	loc:load_localization_file(T._path .. "loc/english.txt")
end)

local function refresh_active_menu(menu_id)
	local menu = MenuHelper:GetMenu(menu_id)
	if not (menu and menu._items) then
		return
	end
	for _, item in pairs(menu._items) do
		local p = item._parameters
		if p and p.name then
			local key = p.name:match("^ast_(.+)$")
			if key and T.settings[key] ~= nil then
				local v = T.settings[key]
				if type(v) == "boolean" then v = v and "on" or "off" end
				item:set_value(v)
			end
		end
	end
end

-- Options that only matter while their toggle is on are hidden while it is off.
-- key -> list of toggles that must all be on for the option to show
local SHOW_IF = {
	breath_rate = { "breath" }, breath_depth = { "breath" }, breath_offset = { "breath" },
	see_through_gain = { "see_through" },
	speed = { "scroll" }, direction = { "scroll" },
	fixed_scroll = { "scroll", "see_through" },
	light_intensity = { "light" }, light_range = { "light" },
	light_r = { "light" }, light_g = { "light" }, light_b = { "light" },
	react_stealth = { "reactive" }, react_assault = { "reactive" },
	react_shot_flash = { "reactive" },
	react_shot_flash_boost = { "reactive", "react_shot_flash" },
	react_shot_flash_decay = { "reactive", "react_shot_flash" },
	react_heat_gain = { "reactive" }, react_heat_cool = { "reactive" },
	react_heat_glow = { "reactive" }, react_heat_speed = { "reactive" },
	react_smooth = { "reactive" },
}

local function node_items(node)
	if not node then return {} end
	if type(node.items) == "function" then
		local ok, items = pcall(node.items, node)
		if ok and type(items) == "table" then return items end
	end
	return node._items or {}
end

local function apply_visibility(node)
	for _, item in pairs(node_items(node)) do
		local p = item._parameters
		local name = p and p.name
		local key = name and (name:match("^ast_(.+)$") or name)
		local deps = key and SHOW_IF[key]
		if deps then
			item.visible = function()
				for _, toggle in ipairs(deps) do
					if not T.settings[toggle] then return false end
				end
				return true
			end
		end
	end
end

-- Options that cannot be used together are greyed out (not hidden).
-- key -> function returning true when the option should be greyed out
local DISABLE_IF = {
	-- the colour only does something while See-through weapon is on
	st_color    = function() return not T.settings.see_through end,
	st_tint     = function() return not (T.settings.see_through and T.settings.st_color) end,
}

local function set_item_enabled(item, enabled)
	if type(item.set_enabled) == "function" then
		pcall(item.set_enabled, item, enabled)
	else
		item._enabled = enabled
	end
end

local function apply_enabled(node)
	for _, item in pairs(node_items(node)) do
		local p = item._parameters
		local name = p and p.name
		local key = name and (name:match("^ast_(.+)$") or name)
		local rule = key and DISABLE_IF[key]
		if rule then
			set_item_enabled(item, not rule())
		end
	end
end

local built_nodes = {}
local function update_enabled()
	for _, node in pairs(built_nodes) do
		pcall(apply_enabled, node)
	end
end

-- Rebuild the open menu so options appear / disappear right away.
local function refresh_gui()
	pcall(update_enabled)
	local function go()
		local mm = managers.menu
		local menu = mm and mm:active_menu()
		local logic = menu and menu.logic
		local node = logic and logic.selected_node and logic:selected_node()
		if not node then return end
		local name = node:parameters().name
		local ok = pcall(function() logic:refresh_node(name, true) end)
		if not ok and menu.renderer and menu.renderer.refresh_node then
			pcall(function() menu.renderer:refresh_node(node) end)
		end
	end
	if DelayedCalls and DelayedCalls.Add then
		DelayedCalls:Add("AnimSkinsTuner_refresh_gui", 0, function() pcall(go) end)
	else
		pcall(go)
	end
end

local function do_reset(menu_id, keys)
	for _, k in ipairs(keys) do
		if T.defaults[k] ~= nil then
			T.settings[k] = T.defaults[k]
		end
	end
	T:sync_animskins()
	T:save()
	T:apply_all()
	refresh_active_menu(menu_id)
	refresh_gui()
end

Hooks:Add("MenuManagerInitialize", "AnimSkinsTuner_callbacks", function(menu_manager)
	local function set(key, value, repaint)
		T.settings[key] = value
		if repaint then
			T:apply_all()
		end
	end

	local function slider(key, repaint)
		return function(self, item) set(key, tonumber(item:value()) or T.defaults[key], repaint) end
	end
	local function toggle(key, repaint)
		return function(self, item) set(key, item:value() == "on", repaint) end
	end
	local function choice(key, repaint)
		return function(self, item) set(key, item:value(), repaint) end
	end

	MenuCallbackHandler.ast_set_primary_skin = choice("primary_skin", true)
	MenuCallbackHandler.ast_set_secondary_skin = choice("secondary_skin", true)
	MenuCallbackHandler.ast_set_enabled = function(self, item)
		set("enabled", item:value() == "on")
		T:sync_animskins()
		T:save()
		if T.settings.enabled then
			T:apply_all()
		end
	end
	local function toggle_vis(key, repaint)
		local base = toggle(key, repaint)
		return function(self, item)
			base(self, item)
			refresh_gui()
		end
	end
	MenuCallbackHandler.ast_set_scroll = function(self, item)
		set("scroll", item:value() == "on")
		T:apply_all()
		refresh_active_menu(MENU_SKIN)
		refresh_gui()
	end
	MenuCallbackHandler.ast_set_breath = toggle_vis("breath", true)
	MenuCallbackHandler.ast_set_breath_rate = slider("breath_rate", true)
	MenuCallbackHandler.ast_set_breath_depth = slider("breath_depth", true)
	MenuCallbackHandler.ast_set_breath_offset = slider("breath_offset", true)
	MenuCallbackHandler.ast_set_see_through = function(self, item)
		set("see_through", item:value() == "on")
		T:sync_animskins()
		T:apply_all()
		refresh_active_menu(MENU_SKIN)
		refresh_gui()
	end
	MenuCallbackHandler.ast_set_see_through_gain = slider("see_through_gain", true)
	MenuCallbackHandler.ast_set_fixed_scroll = function(self, item)
		set("fixed_scroll", item:value() == "on")
		refresh_gui()
	end
	MenuCallbackHandler.ast_set_st_color = toggle_vis("st_color", true)
	MenuCallbackHandler.ast_set_st_tint = choice("st_tint", true)
	MenuCallbackHandler.ast_set_ghost = toggle("ghost", true)
	MenuCallbackHandler.ast_set_ghost_rate = slider("ghost_rate", true)
	MenuCallbackHandler.ast_set_ghost_min = slider("ghost_min", true)
	MenuCallbackHandler.ast_set_light = toggle_vis("light", true)
	MenuCallbackHandler.ast_set_light_intensity = slider("light_intensity", true)
	MenuCallbackHandler.ast_set_light_range = slider("light_range", true)
	MenuCallbackHandler.ast_set_light_r = slider("light_r", true)
	MenuCallbackHandler.ast_set_light_g = slider("light_g", true)
	MenuCallbackHandler.ast_set_light_b = slider("light_b", true)
	MenuCallbackHandler.ast_set_glow = slider("glow", true)
	MenuCallbackHandler.ast_set_bloom = slider("bloom", true)
	MenuCallbackHandler.ast_set_speed = slider("speed", true)
	MenuCallbackHandler.ast_set_direction = choice("direction", true)
	MenuCallbackHandler.ast_set_menus = function(self, item)
		set("menus", item:value() == "on")
		T:sync_animskins()
	end

	MenuCallbackHandler.ast_set_reactive = toggle_vis("reactive", true)
	MenuCallbackHandler.ast_set_react_shot_flash = toggle_vis("react_shot_flash", true)
	MenuCallbackHandler.ast_set_react_shot_flash_boost = slider("react_shot_flash_boost", true)
	MenuCallbackHandler.ast_set_react_shot_flash_decay = slider("react_shot_flash_decay", true)
	MenuCallbackHandler.ast_set_react_stealth = slider("react_stealth")
	MenuCallbackHandler.ast_set_react_assault = slider("react_assault")
	MenuCallbackHandler.ast_set_react_heat_gain = slider("react_heat_gain")
	MenuCallbackHandler.ast_set_react_heat_cool = slider("react_heat_cool")
	MenuCallbackHandler.ast_set_react_heat_glow = slider("react_heat_glow")
	MenuCallbackHandler.ast_set_react_heat_speed = slider("react_heat_speed")
	MenuCallbackHandler.ast_set_react_heat_fx = choice("react_heat_fx")
	MenuCallbackHandler.ast_set_react_heat_fx_period = slider("react_heat_fx_period")
	MenuCallbackHandler.ast_set_react_heat_at = slider("react_heat_at")
	MenuCallbackHandler.ast_set_react_flash_fx = choice("react_flash_fx")
	MenuCallbackHandler.ast_set_react_flash_life = slider("react_flash_life")
	MenuCallbackHandler.ast_set_react_smooth = slider("react_smooth")

	local SKIN_KEYS = {
		"primary_skin", "secondary_skin", "enabled",
		"scroll", "breath", "breath_rate", "breath_depth", "breath_offset",
		"see_through", "see_through_gain", "fixed_scroll", "ghost", "ghost_rate", "ghost_min",
		"menus",
	}
	local GLOW_KEYS = { "glow", "speed", "bloom", "direction" }
	local STCOLOR_KEYS = { "st_color", "st_tint" }
	local LIGHT_KEYS = {
		"light", "light_intensity", "light_range", "light_r", "light_g", "light_b",
	}
	local REACTIVE_KEYS = {
		"reactive",
		"react_stealth", "react_assault",
		"react_heat_gain", "react_heat_cool", "react_heat_glow",
		"react_heat_speed",
		"react_shot_flash", "react_shot_flash_boost", "react_shot_flash_decay",
		"react_smooth",
	}
	local MUZZLE_KEYS = {
		"react_heat_fx", "react_heat_fx_period", "react_heat_at",
		"react_flash_fx", "react_flash_life",
	}

	MenuCallbackHandler.ast_reset_skin = function()
		do_reset(MENU_SKIN, SKIN_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_skin_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_glow = function()
		do_reset(MENU_GLOW, GLOW_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_glow_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_stcolor = function()
		do_reset(MENU_STCOLOR, STCOLOR_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_stcolor_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_light = function()
		do_reset(MENU_LIGHT, LIGHT_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_light_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_muzzle = function()
		do_reset(MENU_MUZZLE, MUZZLE_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_muzzle_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_reactive = function()
		do_reset(MENU_REACTIVE, REACTIVE_KEYS)
		QuickMenu:new(
			managers.localization:text("ast_reset_reactive_title"),
			managers.localization:text("ast_reset_done"), {}, true)
	end

	MenuCallbackHandler.ast_reset_generator = function()
		if GEN.selection then
			for k in pairs(GEN.selection) do GEN.selection[k] = nil end
		end
		refresh_active_menu()
		QuickMenu:new(
			managers.localization:text("ast_reset_generator_title"),
			managers.localization:text("ast_reset_generator_done"), {}, true)
	end

	MenuCallbackHandler.ast_save = function()
		T:save()
	end

	MenuCallbackHandler.ast_set_resolution = function(self, item)
		if not GEN.RESOLUTIONS then return end
		local i = tonumber(item:value()) or 1
		local res = GEN.RESOLUTIONS[i]
		if res then
			GEN.settings.resolution = res
			if GEN.apply_resolution then GEN:apply_resolution() end
			if GEN.save_settings then GEN:save_settings() end
		end
	end

	MenuCallbackHandler.ast_generate = function()
		if not (GEN.generate_skins and GEN.settings) then return end
		if GEN.save_settings then GEN:save_settings() end
		GEN:generate_skins(GEN.selection or {})
	end
end)

for _, name in ipairs({ "open_node", "back", "close_menu" }) do
	if type(MenuManager[name]) == "function" then
		Hooks:PostHook(MenuManager, name, "AnimSkinsTuner_repaint_" .. name, function()
			T:apply_all()
			pcall(update_enabled)
		end)
	end
end

Hooks:Add("MenuManagerSetupCustomMenus", "AnimSkinsTuner_setup", function()
	MenuHelper:NewMenu(MENU)
	MenuHelper:NewMenu(MENU_SKIN)
	MenuHelper:NewMenu(MENU_GLOW)
	MenuHelper:NewMenu(MENU_STCOLOR)
	MenuHelper:NewMenu(MENU_LIGHT)
	MenuHelper:NewMenu(MENU_REACTIVE)
	MenuHelper:NewMenu(MENU_MUZZLE)
	MenuHelper:NewMenu(MENU_GENERATOR)
end)

local function add_to(menu_id, kind, id, data)
	data.id = "ast_" .. id
	data.title = "ast_" .. id .. "_title"
	data.desc = "ast_" .. id .. "_desc"
	if not data.callback then data.callback = "ast_set_" .. id end
	data.menu_id = menu_id
	data.priority = data.priority or 100
	if kind == "slider" then
		data.show_value = true
		MenuHelper:AddSlider(data)
	elseif kind == "toggle" then
		MenuHelper:AddToggle(data)
	else
		MenuHelper:AddMultipleChoice(data)
	end
end

Hooks:Add("MenuManagerPopulateCustomMenus", "AnimSkinsTuner_populate", function()
	local s = T.settings

	add_to(MENU_SKIN, "choice", "primary_skin",
		{ value = s.primary_skin, items = T:skin_names(), localized_items = false, priority = 100 })
	add_to(MENU_SKIN, "choice", "secondary_skin",
		{ value = s.secondary_skin, items = T:skin_names(), localized_items = false, priority = 99 })
	add_to(MENU_SKIN, "toggle", "enabled",
		{ value = s.enabled, priority = 98 })
	add_to(MENU_SKIN, "toggle", "scroll",
		{ value = s.scroll, priority = 97 })
	add_to(MENU_SKIN, "toggle", "breath",
		{ value = s.breath, priority = 96 })
	add_to(MENU_SKIN, "slider", "breath_rate",
		{ value = s.breath_rate, min = 0.2, max = 30, step = 0.1, priority = 95 })
	add_to(MENU_SKIN, "slider", "breath_depth",
		{ value = s.breath_depth, min = 0, max = 1, step = 0.05, priority = 94 })
	add_to(MENU_SKIN, "slider", "breath_offset",
		{ value = s.breath_offset, min = -0.8, max = 0.8, step = 0.05, priority = 93 })

	add_to(MENU_SKIN, "toggle", "see_through",
		{ value = s.see_through, priority = 93.5 })
	add_to(MENU_SKIN, "slider", "see_through_gain",
		{ value = s.see_through_gain, min = 0.5, max = 10, step = 0.25, priority = 93.2 })
	add_to(MENU_SKIN, "toggle", "fixed_scroll",
		{ value = s.fixed_scroll, priority = 93.1 })

	MenuHelper:AddDivider({ id = "ast_div_glow", size = 12, menu_id = MENU_SKIN, priority = 90 })
	add_to(MENU_SKIN, "toggle", "menus", { value = s.menus, priority = 85 })

	-- Glow tab (inside Skin)
	add_to(MENU_GLOW, "slider", "glow",  { value = s.glow,  min = 0, max = 20,  step = 0.5,  priority = 100 })
	add_to(MENU_GLOW, "slider", "speed", { value = s.speed, min = 0, max = 0.5, step = 0.01, priority = 99 })
	add_to(MENU_GLOW, "slider", "bloom", { value = s.bloom, min = 0, max = 10,  step = 0.25, priority = 98 })
	add_to(MENU_GLOW, "choice", "direction",
		{ value = s.direction, priority = 97,
		  items = { "ast_dir_right", "ast_dir_left", "ast_dir_down", "ast_dir_up", "ast_dir_diag", "ast_dir_part" } })
	MenuHelper:AddButton({
		id = "ast_reset_glow",
		title = "ast_reset_glow_title",
		desc = "ast_reset_glow_desc",
		callback = "ast_reset_glow",
		menu_id = MENU_GLOW,
		priority = 10,
	})

	-- See-through Color tab (inside Skin)
	add_to(MENU_STCOLOR, "toggle", "st_color",
		{ value = s.st_color, priority = 100 })
	add_to(MENU_STCOLOR, "choice", "st_tint",
		{ value = s.st_tint, items = T:tint_names(), localized_items = false, priority = 99 })
	MenuHelper:AddButton({
		id = "ast_reset_stcolor",
		title = "ast_reset_stcolor_title",
		desc = "ast_reset_stcolor_desc",
		callback = "ast_reset_stcolor",
		menu_id = MENU_STCOLOR,
		priority = 10,
	})

	-- World Light tab
	add_to(MENU_LIGHT, "toggle", "light",
		{ value = s.light, priority = 100 })
	add_to(MENU_LIGHT, "slider", "light_intensity",
		{ value = s.light_intensity, min = 0, max = 5, step = 0.1, priority = 99 })
	add_to(MENU_LIGHT, "slider", "light_range",
		{ value = s.light_range, min = 50, max = 800, step = 10, priority = 98 })
	add_to(MENU_LIGHT, "slider", "light_r",
		{ value = s.light_r, min = 0, max = 1, step = 0.05, priority = 97 })
	add_to(MENU_LIGHT, "slider", "light_g",
		{ value = s.light_g, min = 0, max = 1, step = 0.05, priority = 96 })
	add_to(MENU_LIGHT, "slider", "light_b",
		{ value = s.light_b, min = 0, max = 1, step = 0.05, priority = 95 })
	MenuHelper:AddButton({
		id = "ast_reset_light",
		title = "ast_reset_light_title",
		desc = "ast_reset_light_desc",
		callback = "ast_reset_light",
		menu_id = MENU_LIGHT,
		priority = 10,
	})

	MenuHelper:AddButton({
		id = "ast_reset_skin",
		title = "ast_reset_skin_title",
		desc = "ast_reset_skin_desc",
		callback = "ast_reset_skin",
		menu_id = MENU_SKIN,
		priority = 10,
	})

		add_to(MENU_REACTIVE, "toggle", "reactive", { value = s.reactive, priority = 100 })
	add_to(MENU_REACTIVE, "slider", "react_stealth",
		{ value = s.react_stealth, min = 0, max = 1, step = 0.05, priority = 99 })
	add_to(MENU_REACTIVE, "slider", "react_assault",
		{ value = s.react_assault, min = 1, max = 4, step = 0.1, priority = 98 })
	add_to(MENU_REACTIVE, "toggle", "react_shot_flash",
		{ value = s.react_shot_flash, priority = 97 })
	add_to(MENU_REACTIVE, "slider", "react_shot_flash_boost",
		{ value = s.react_shot_flash_boost, min = 0.5, max = 8, step = 0.25, priority = 96 })
	add_to(MENU_REACTIVE, "slider", "react_shot_flash_decay",
		{ value = s.react_shot_flash_decay, min = 1, max = 50, step = 0.5, priority = 95 })
	add_to(MENU_REACTIVE, "slider", "react_heat_gain",
		{ value = s.react_heat_gain, min = 0, max = 0.3, step = 0.01, priority = 94 })
	add_to(MENU_REACTIVE, "slider", "react_heat_cool",
		{ value = s.react_heat_cool, min = 0.05, max = 2, step = 0.05, priority = 93 })
	add_to(MENU_REACTIVE, "slider", "react_heat_glow",
		{ value = s.react_heat_glow, min = 0, max = 5, step = 0.1, priority = 92 })
	add_to(MENU_REACTIVE, "slider", "react_heat_speed",
		{ value = s.react_heat_speed, min = 1, max = 10, step = 0.5, priority = 91 })
	add_to(MENU_REACTIVE, "slider", "react_smooth",
		{ value = s.react_smooth, min = 0.5, max = 20, step = 0.5, priority = 88 })

	MenuHelper:AddButton({
		id = "ast_reset_reactive",
		title = "ast_reset_reactive_title",
		desc = "ast_reset_reactive_desc",
		callback = "ast_reset_reactive",
		menu_id = MENU_REACTIVE,
		priority = 10,
	})

	add_to(MENU_MUZZLE, "choice", "react_heat_fx",
		{ value = s.react_heat_fx, items = T:heat_fx_names(), localized_items = false, priority = 100 })
	add_to(MENU_MUZZLE, "slider", "react_heat_fx_period",
		{ value = s.react_heat_fx_period, min = 0.2, max = 5, step = 0.1, priority = 99 })
	add_to(MENU_MUZZLE, "slider", "react_heat_at",
		{ value = s.react_heat_at, min = 0, max = 1, step = 0.05, priority = 98 })
	add_to(MENU_MUZZLE, "choice", "react_flash_fx",
		{ value = s.react_flash_fx, items = T:flash_fx_names(), localized_items = false, priority = 97 })
	add_to(MENU_MUZZLE, "slider", "react_flash_life",
		{ value = s.react_flash_life, min = 0.05, max = 2, step = 0.05, priority = 96 })

	MenuHelper:AddButton({
		id = "ast_reset_muzzle",
		title = "ast_reset_muzzle_title",
		desc = "ast_reset_muzzle_desc",
		callback = "ast_reset_muzzle",
		menu_id = MENU_MUZZLE,
		priority = 10,
	})


	do
		local res_index = 2
		if GEN.RESOLUTIONS and GEN.settings then
			for i, r in ipairs(GEN.RESOLUTIONS) do
				if r == GEN.settings.resolution then res_index = i end
			end
		end
		MenuHelper:AddMultipleChoice({
			id = "ast_resolution",
			title = "ast_resolution_title",
			desc = "ast_resolution_desc",
			callback = "ast_set_resolution",
			menu_id = MENU_GENERATOR,
			priority = 100,
			value = res_index,
			items = { "ast_res_512", "ast_res_1024", "ast_res_2048" },
		})

		local priority = 90
		local found = (GEN.scan and GEN:scan()) or {}
		for _, skin in ipairs(found) do
			local names = _G.ColorSkinRT:names(skin)
			local key = names.key
			local cb_name = "ast_gen_skin_" .. key
			MenuCallbackHandler[cb_name] = function(self, item)
				if GEN.selection then
					GEN.selection[key] = item:value() == "on"
				end
			end
			-- Titles go through the localizer, and an unknown id shows up as "ERROR: <id>".
			-- Register the skin name as a real string; if that is not possible, show it unlocalized.
			local title_id = "ast_gen_skin_" .. key .. "_title"
			local localized = false
			if managers.localization and managers.localization.add_localized_strings then
				localized = pcall(function()
					managers.localization:add_localized_strings({ [title_id] = names.name })
				end)
			end
			MenuHelper:AddToggle({
				id = cb_name,
				title = localized and title_id or names.name,
				localized = localized,
				localized_help = true,
				desc = "ast_gen_skin_desc",
				callback = cb_name,
				menu_id = MENU_GENERATOR,
				priority = priority,
				value = GEN.selection and GEN.selection[key] or false,
			})
			priority = priority - 1
		end

		MenuHelper:AddButton({
			id = "ast_generate",
			title = "ast_generate_title",
			desc = "ast_generate_desc",
			callback = "ast_generate",
			menu_id = MENU_GENERATOR,
			priority = priority - 1,
		})

		MenuHelper:AddButton({
			id = "ast_reset_generator",
			title = "ast_reset_generator_title",
			desc = "ast_reset_generator_desc",
			callback = "ast_reset_generator",
			menu_id = MENU_GENERATOR,
			priority = priority - 2,
		})
	end
end)

Hooks:Add("MenuManagerBuildCustomMenus", "AnimSkinsTuner_build", function(menu_manager, nodes)
	nodes[MENU]           = MenuHelper:BuildMenu(MENU,           { back_callback = "ast_save" })
	nodes[MENU_SKIN]      = MenuHelper:BuildMenu(MENU_SKIN,      { back_callback = "ast_save" })
	nodes[MENU_GLOW]      = MenuHelper:BuildMenu(MENU_GLOW,      { back_callback = "ast_save" })
	nodes[MENU_STCOLOR]   = MenuHelper:BuildMenu(MENU_STCOLOR,   { back_callback = "ast_save" })
	nodes[MENU_LIGHT]     = MenuHelper:BuildMenu(MENU_LIGHT,     { back_callback = "ast_save" })
	nodes[MENU_REACTIVE]  = MenuHelper:BuildMenu(MENU_REACTIVE,  { back_callback = "ast_save" })
	nodes[MENU_MUZZLE]    = MenuHelper:BuildMenu(MENU_MUZZLE,    { back_callback = "ast_save" })
	nodes[MENU_GENERATOR] = MenuHelper:BuildMenu(MENU_GENERATOR, { back_callback = "ast_save" })

	MenuHelper:AddMenuItem(nodes.blt_options, MENU, "ast_menu_title", "ast_menu_desc")

	MenuHelper:AddMenuItem(nodes[MENU], MENU_SKIN,      "ast_skin_menu_title",     "ast_skin_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_LIGHT,     "ast_light_menu_title",     "ast_light_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_REACTIVE,  "ast_reactive_menu_title", "ast_reactive_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_MUZZLE,    "ast_muzzle_menu_title",   "ast_muzzle_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU], MENU_GENERATOR, "ast_gen_menu_title",      "ast_gen_menu_desc")

	-- Brightness & Speed and See-through Color tabs sit inside the Skin menu, under the options
	MenuHelper:AddMenuItem(nodes[MENU_SKIN], MENU_GLOW,    "ast_glow_menu_title",    "ast_glow_menu_desc")
	MenuHelper:AddMenuItem(nodes[MENU_SKIN], MENU_STCOLOR, "ast_stcolor_menu_title", "ast_stcolor_menu_desc")
	local function place_after(node, item_name, after_name)
		pcall(function()
			local items = node_items(node)
			local moving, after_at
			for i, item in ipairs(items) do
				if item._parameters and item._parameters.name == item_name then
					moving = item
					table.remove(items, i)
					break
				end
			end
			for i, item in ipairs(items) do
				if item._parameters and item._parameters.name == after_name then after_at = i end
			end
			if moving then table.insert(items, (after_at or #items) + 1, moving) end
		end)
	end
	place_after(nodes[MENU_SKIN], MENU_GLOW,    "ast_menus")
	place_after(nodes[MENU_SKIN], MENU_STCOLOR, MENU_GLOW)

	for _, id in ipairs({ MENU_SKIN, MENU_GLOW, MENU_STCOLOR, MENU_LIGHT, MENU_REACTIVE }) do
		pcall(apply_visibility, nodes[id])
	end

	for _, id in ipairs({ MENU_SKIN, MENU_STCOLOR }) do
		built_nodes[id] = nodes[id]
	end
	update_enabled()
end)
