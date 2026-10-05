_G.AnimSkinsGen = _G.AnimSkinsGen or {}
local G = _G.AnimSkinsGen

local MOD_PATH = ModPath

G.VERSION = 9

G.MATERIALS_DB = "units/"
G.TEX_ORIGINAL = "textures/original/"
G.TEX_IMPORTED = "textures/imported/"
G.FILE_MANIFEST = "data/generated.json"
-- white + colour textures used by the see-through colour option (keep in sync with T.TINTS in core.lua)
G.TINT_TEXTURES = { "white", "tint_red", "tint_orange", "tint_gold", "tint_yellow", "tint_lime", "tint_green", "tint_mint", "tint_cyan", "tint_sky", "tint_blue", "tint_purple", "tint_magenta", "tint_pink" }

local function prompt_restart(message)
	local yes = {
		text = managers.localization and managers.localization:text("dialog_yes") or "Yes",
		callback = function()
			local function do_quit()
				if setup and setup.quit then
					setup:quit()
				elseif Application and Application.quit then
					Application:quit()
				end
			end
			if DelayedCalls and DelayedCalls.Add then
				DelayedCalls:Add("AnimSkins_restart", 0.15, do_quit)
			else
				do_quit()
			end
		end,
	}
	local no = {
		text = managers.localization and managers.localization:text("dialog_no") or "Later",
		is_cancel_button = true,
	}
	QuickMenu:new("AnimSkins", message, { yes, no }, true)
end


local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() return true end
	return false
end

local function file_size(path)
	local f = io.open(path, "rb")
	if not f then return -1 end
	local n = f:seek("end")
	f:close()
	return n
end

local function read_text(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local d = f:read("*all")
	f:close()
	return d
end

local function write_text(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

local function hash_list(list)
	local h = 5381
	for _, s in ipairs(list) do
		for i = 1, #s do
			h = (h * 33 + s:byte(i)) % 4294967296
		end
		h = (h * 33 + 10) % 4294967296
	end
	return ("%08x"):format(h)
end

local function ensure_dir(path)
	if not file.DirectoryExists(path) then
		file.CreateDirectory(path)
	end
end

local function dir_files(path)
	if not path or path == "" or not file.DirectoryExists(path) then
		return {}
	end
	return file.GetFiles(path) or {}
end

function G:config_names_from_dir()
	local names = {}
	local dir = MOD_PATH .. "assets/" .. G.MATERIALS_DB
	ensure_dir(dir)
	for _, f in ipairs(dir_files(dir)) do
		local n = f:match("^(.*)%.material_config$")
		if n then names[#names + 1] = n end
	end
	table.sort(names)
	return names
end

function G:config_signature(units)
	return table.concat({
		G.VERSION,
		file_size(MOD_PATH .. "data/animated.txt"),
		file_size(MOD_PATH .. "data/static.xml"),
		#units,
		hash_list(units),
	}, "|")
end

function G:skin_signature(skin)
	local s = _G.ColorSkinRT.settings
	return table.concat({
		G.VERSION, s.max_size, s.glow_contrast, s.glow_brightness, s.glow_scale,
		"tile" .. _G.ColorSkinRT.TILE_SIZE .. "b" .. _G.ColorSkinRT.BLEND_WIDTH,
		"scroll" .. _G.ColorSkinRT.FRAME_COUNT .. "x" .. _G.ColorSkinRT.FRAME_SIZE,
		skin.pattern, file_size(skin.pattern),
		skin.gradient or "none", skin.gradient and file_size(skin.gradient) or 0,
	}, "|")
end

-- Textures every generated material config points at (default_df / default_il are used by ~2000 of
-- them, ghost_df by the see-through ones). They must ALWAYS be registered, otherwise the weapon breaks.
G.REQUIRED_TEXTURES = { "black", "default_df", "default_il", "ghost_df", "ghost_il" }

function G:build_main_xml(bundled, imported, config_names)
	local xml = { '<table name="AnimSkins">', '\t<AddFiles directory="assets" load="true">' }
	local written = {}
	local function tex(path)
		if not path or written[path] then return end
		written[path] = true
		xml[#xml + 1] = ('\t\t<texture path="%s" force="true"/>'):format(path)
	end
	for _, n in ipairs(G.REQUIRED_TEXTURES) do tex(G.TEX_ORIGINAL .. n) end
	for _, n in ipairs(G.TINT_TEXTURES) do tex(G.TEX_ORIGINAL .. n) end
	for _, s in ipairs(bundled) do
		tex(s.base); tex(s.glow)
		-- bundled skins ship see-through scroll frames too (<glow>_f00 .. _f47)
		for i = 0, (tonumber(s.frames) or 0) - 1 do
			tex(("%s_f%02d"):format(s.glow, i))
		end
	end
	for _, s in ipairs(imported) do
		tex(s.base); tex(s.glow)
		-- see-through scroll frames (only listed when they exist, see write_state)
		for i = 0, (tonumber(s.frames) or 0) - 1 do
			tex(("%s_f%02d"):format(s.glow, i))
		end
	end
	tex(G.TEX_ORIGINAL .. "black")
	for _, name in ipairs(config_names) do
		xml[#xml + 1] = ('\t\t<material_config path="%s%s"/>'):format(G.MATERIALS_DB, name)
	end
	xml[#xml + 1] = "\t</AddFiles>"
	xml[#xml + 1] = "</table>"
	xml[#xml + 1] = ""
	return table.concat(xml, "\n")
end

function G:write_main_xml(bundled, imported, config_names)
	write_text(MOD_PATH .. "main.xml", G:build_main_xml(bundled, imported, config_names))
end

-- Repairs a main.xml written by an older generator (it dropped default_df / default_il and the bundled
-- scroll frames, which broke the weapon and the see-through weapon). Returns true when it rewrote it.
function G:heal_main_xml()
	local config_names = G:config_names_from_dir()
	if #config_names == 0 then return false end
	local variants = json.decode(read_text(MOD_PATH .. "data/variants.json") or "{}") or {}
	local text = G:build_main_xml(variants.skins or {}, variants.imported or {}, config_names)
	local cur = read_text(MOD_PATH .. "main.xml")
	if cur and cur:gsub("\r\n", "\n") == text then return false end
	write_text(MOD_PATH .. "main.xml", text)
	return true
end

G.RESOLUTIONS = { 512, 1024, 2048 }
G.SETTINGS_FILE = SavePath .. "animskins_generator.json"
G.settings = G.settings or { resolution = 1024 }
G.selection = G.selection or {}

function G:load_settings()
	local text = read_text(G.SETTINGS_FILE)
	local data = text and json.decode(text)
	local res = type(data) == "table" and tonumber(data.resolution)
	for _, r in ipairs(G.RESOLUTIONS) do
		if r == res then G.settings.resolution = r end
	end
end

function G:save_settings()
	write_text(G.SETTINGS_FILE, json.encode({ resolution = G.settings.resolution }))
end

function G:apply_resolution()
	local CS = _G.ColorSkinRT
	CS.TILE_SIZE = G.settings.resolution
	CS.settings.max_size = math.min(CS.TILE_SIZE, 1024)
end

function G:read_manifest()
	local text = read_text(MOD_PATH .. G.FILE_MANIFEST)
	local old = text and json.decode(text) or {}
	old.skins = old.skins or {}
	return old
end

function G:scan(force)
	if G.found and not force then return G.found end
	G:apply_resolution()
	for _, dir in ipairs(_G.ColorSkinRT.custom_dirs()) do
		pcall(ensure_dir, dir)
	end
	G.found = _G.ColorSkinRT:find_color_skins()
	return G.found
end

function G:skin_state(skin, old)
	local names = _G.ColorSkinRT:names(skin)
	if not exists(names.glow_file) then return "new" end
	if old.skins[names.key] ~= G:skin_signature(skin) then return "outdated" end
	if not _G.ColorSkinRT:frames_present(names) then return "outdated" end
	return "ok"
end

function G:write_state(found, sigs, config_names, csig)
	local CS = _G.ColorSkinRT
	local variants_path = MOD_PATH .. "data/variants.json"
	local variants = json.decode(read_text(variants_path)) or {}
	local bundled = variants.skins or {}
	local imported, keep = {}, {}
	for _, skin in ipairs(found) do
		local names = CS:names(skin)
		if sigs[names.key] ~= nil then
			local entry = {
				id = names.id, name = names.name,
				base = G.TEX_ORIGINAL .. "black", glow = names.glow_name,
				glow_scale = CS.settings.glow_scale,
			}
			-- "frames" turns on Scroll pattern for this skin while See-through weapon is on
			if CS:frames_present(names) then
				entry.frames = CS.FRAME_COUNT
				for i = 0, CS.FRAME_COUNT - 1 do keep[names.frame_key(i)] = true end
			end
			imported[#imported + 1] = entry
			keep[names.key .. "_il.texture"] = true
		end
	end
	table.sort(imported, function(a, b) return a.id < b.id end)

	local texdir = MOD_PATH .. "assets/" .. G.TEX_IMPORTED
	ensure_dir(texdir)
	for _, f in ipairs(dir_files(texdir)) do
		if f:find("%.texture$") and not keep[f] then
			os.remove(texdir .. f)
					end
	end

	variants.imported = imported
	write_text(variants_path, json.encode(variants))
	G:write_main_xml(bundled, imported, config_names)
	write_text(MOD_PATH .. G.FILE_MANIFEST, json.encode({
		version = G.VERSION, configs = csig, skins = sigs,
	}))
	return #imported
end

local function existing_sigs(found, old)
	local sigs = {}
	for _, skin in ipairs(found) do
		local names = _G.ColorSkinRT:names(skin)
		if G:skin_state(skin, old) ~= "new" then
			sigs[names.key] = old.skins[names.key] or ""
		end
	end
	return sigs
end

function G:run()
	local C = _G.CSR_Config
	local old = G:read_manifest()
	local healed = false
	local ok_heal, res_heal = pcall(G.heal_main_xml, G)
	if ok_heal then healed = res_heal else pcall(log, "[AnimSkins] main.xml repair failed: " .. tostring(res_heal)) end
	local found = G:scan()
	local sigs = existing_sigs(found, old)

	local same_set = true
	for key in pairs(sigs) do if old.skins[key] == nil then same_set = false end end
	for key in pairs(old.skins) do if sigs[key] == nil then same_set = false end end

	local units = C.game_part_units() or {}
	local csig = G:config_signature(units)
	local config_names = G:config_names_from_dir()
	local configs_stale = old.configs ~= csig
		or not exists(MOD_PATH .. "data/material_configs.txt")
		or not exists(MOD_PATH .. "data/material_configs_ghost.txt")
		or #config_names == 0

	if same_set and not configs_stale then
		if healed then
			prompt_restart("AnimSkins repaired its texture list (the see-through weapon needs it). Restart now?")
		end
		return
	end

	if configs_stale then
		local res = C.build(MOD_PATH .. "data/", {
			df = G.TEX_ORIGINAL .. "default_df",
			il = G.TEX_ORIGINAL .. "default_il",
			black = G.TEX_ORIGINAL .. "black",
			ghost = G.TEX_ORIGINAL .. "ghost_df",
		})
		local matdir = MOD_PATH .. "assets/" .. G.MATERIALS_DB
		ensure_dir(matdir)
		config_names = {}
		for name, content in pairs(res.configs) do
			config_names[#config_names + 1] = name
			write_text(matdir .. name .. ".material_config", content)
		end
		table.sort(config_names)
		local keep_cfg = {}
		for _, n in ipairs(config_names) do keep_cfg[n .. ".material_config"] = true end
		for _, f in ipairs(dir_files(matdir)) do
			if f:find("%.material_config$") and not keep_cfg[f] then
				os.remove(matdir .. f)
			end
		end
		write_text(MOD_PATH .. "data/material_configs.txt", C.mapping_text(res))
		write_text(MOD_PATH .. "data/material_configs_ghost.txt", C.ghost_mapping_text(res))
	end

	G:write_state(found, sigs, config_names, csig)
	prompt_restart(("Generated %d material configs. Restart now to load them?"):format(#config_names))
end

function G:generate_skins(selected)
	local CS = _G.ColorSkinRT
	local old = G:read_manifest()
	local config_names = G:config_names_from_dir()
	if #config_names == 0 then
		QuickMenu:new("AnimSkins", "The material configs have not been generated yet. Restart the game first.", {}, true)
		return
	end
	local found = G:scan(true)
	G:apply_resolution()
	local sigs = existing_sigs(found, old)
	ensure_dir(MOD_PATH .. "assets/" .. G.TEX_IMPORTED)

	local done, failed, reasons = 0, 0, {}
	for _, skin in ipairs(found) do
		local names = CS:names(skin)
		if selected[names.key] then
			local ok, out, err = pcall(CS.generate, CS, skin)
			if ok and out then
				sigs[names.key] = G:skin_signature(skin)
				done = done + 1
				if out.frames_error then
					reasons[#reasons + 1] = tostring(skin.id) .. " (no see-through scroll): " .. out.frames_error
				end
			else
				failed = failed + 1
				local why = ok and err or out
				reasons[#reasons + 1] = tostring(skin.id) .. ": " .. tostring(why)
				if log then pcall(log, "[AnimSkins] generate failed for " .. tostring(skin.id) .. ": " .. tostring(why)) end
			end
		end
	end

	G:write_state(found, sigs, config_names, old.configs)
	if done == 0 and failed == 0 then
		QuickMenu:new("AnimSkins", "No skins are ticked. Tick at least one skin in the list first.", {}, true)
		return 0, 0
	end
	local msg = ("Generated %d skin(s) at %d px, with %d see-through scroll frames each."):format(done, G.settings.resolution, _G.ColorSkinRT.FRAME_COUNT)
	if #reasons > 0 then
		msg = msg .. (failed > 0 and (" %d failed:\n"):format(failed) or " Notes:\n")
		for i = 1, math.min(#reasons, 4) do msg = msg .. reasons[i] .. "\n" end
		if #reasons > 4 then msg = msg .. ("...and %d more (see mods/logs)\n"):format(#reasons - 4) end
	end
	if done == 0 then
		QuickMenu:new("AnimSkins", msg, {}, true)
		return done, failed
	end
	prompt_restart(msg .. " Restart now to load them?")
	return done, failed
end

dofile(MOD_PATH .. "lua/generator/colorskins.lua")
dofile(MOD_PATH .. "lua/generator/configs.lua")
G:load_settings()
G:apply_resolution()

if not G._hooked then
	G._hooked = true
	Hooks:Add("MenuManagerOnOpenMenu", "AnimSkinsGen_start", function(menu_manager, menu_name)
		if menu_name == "menu_main" and not G._started then
			G._started = true
			G:run()
		end
	end)
end
