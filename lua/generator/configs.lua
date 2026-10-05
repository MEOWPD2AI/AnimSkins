_G.CSR_Config = _G.CSR_Config or {}
local C = _G.CSR_Config

C.SCROLL_SPEED = 0.1
C.GLOW_MULTIPLIER = "5"
C.GLOW_BLOOM = "1.0"
C.RENDER_TEMPLATE = "generic:DEPTH_SCALING:DIFFUSE_TEXTURE:DIFFUSE_UVANIM:SELF_ILLUMINATION:SELF_ILLUMINATION_BLOOM:SELF_ILLUMINATION_UVANIM"
-- See-through "ghost" copies of every config. Additive blend (copied from the game's own glow parts):
-- dark pixels vanish and the world shows through the gun. Order independent, so no sorting glitches.
C.GHOST_TEMPLATE = "effect:BLEND_ADD:DIFFUSE0_TEXTURE:FPS"
C.GHOST_INTENSITY = "3"
C.GHOST_SUFFIX = "_ghost"
C.DIRECTIONS = {
	e = { 1, 0 }, w = { -1, 0 }, n = { 0, 1 }, s = { 0, -1 },
	ne = { 0.7, 0.7 }, nw = { -0.7, 0.7 }, se = { 0.7, -0.7 }, sw = { -0.7, -0.7 },
}
C.ids_of = C.ids_of or {}

local function number(v)
	local r = math.floor(math.abs(v) * 1e6 + 0.5) / 1e6
	if v < 0 and r ~= 0 then r = -r end
	return ("%.6g"):format(r)
end

local function read_all(path)
	local f = assert(io.open(path, "rb"))
	local d = f:read("*all")
	f:close()
	return d
end

local function read_lines(path)
	local out = {}
	local f = io.open(path, "rb")
	if not f then return out end
	f:close()
	for line in (read_all(path) .. "\n"):gmatch("(.-)\r?\n") do
		if line:find("%S") and line:sub(1, 1) ~= "#" then
			local fields = {}
			for w in line:gmatch("%S+") do fields[#fields + 1] = w end
			out[#out + 1] = fields
		end
	end
	return out
end

local function attrs_of(s)
	local out = {}
	for k, v in s:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do out[#out + 1] = { k, v } end
	return out
end

local function el(tag, attrs, children)
	return { tag = tag, attrs = attrs or {}, children = children or {} }
end

local function render(e, depth, out)
	local pad = string.rep("\t", depth)
	local parts = { pad, "<", e.tag }
	for _, a in ipairs(e.attrs) do
		parts[#parts + 1] = (' %s="%s"'):format(a[1], a[2])
	end
	if #e.children == 0 then
		parts[#parts + 1] = " />"
		out[#out + 1] = table.concat(parts)
	else
		parts[#parts + 1] = ">"
		out[#out + 1] = table.concat(parts)
		for _, c in ipairs(e.children) do render(c, depth + 1, out) end
		out[#out + 1] = pad .. "</" .. e.tag .. ">"
	end
end

local function parse_elements(text)
	local list, pos = {}, 1
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
		local id, kept, name = nil, {}, nil
		for _, kv in ipairs(attrs_of(attrs)) do
			if kv[1] == "id" then id = kv[2] else kept[#kept + 1] = kv end
			if kv[1] == "name" then name = kv[2] end
		end
		local children = {}
		for tag, cattrs in body:gmatch("<([%w_]+)%s+([^>]-)/?>") do
			children[#children + 1] = { tag = tag, attrs = attrs_of(cattrs) }
		end
		list[#list + 1] = { id = id, attrs = kept, children = children, name = name }
	end
	return list
end

local function parse_static(text)
	local static = {}
	for _, m in ipairs(parse_elements(text)) do
		if m.id then static[m.id] = m end
	end
	return static
end

local function index_by_name(static)
	local idx = {}
	for _, m in pairs(static) do
		idx[m.name] = idx[m.name] or {}
		table.insert(idx[m.name], m)
	end
	for _, l in pairs(idx) do table.sort(l, function(a, b) return a.id < b.id end) end
	return idx
end

local function signature(m)
	local out = {}
	for _, kv in ipairs(m.attrs) do
		if kv[1] ~= "name" and kv[1] ~= "id" then out[#out + 1] = kv[1] .. "=" .. kv[2] end
	end
	for _, c in ipairs(m.children) do
		if c.tag ~= "diffuse_texture" then
			local t = { c.tag }
			for _, kv in ipairs(c.attrs) do t[#t + 1] = kv[1] .. "=" .. kv[2] end
			out[#out + 1] = table.concat(t, ",")
		end
	end
	table.sort(out)
	return table.concat(out, "|")
end

local function pick_static(idx, vel)
	local cands = idx[vel.name]
	if not cands then return nil end
	local sig = signature(vel)
	for _, c in ipairs(cands) do
		c._sig = c._sig or signature(c)
		if c._sig == sig then return c end
	end
end

local function ensure_unique(attrs)
	local out, has = {}, false
	for _, kv in ipairs(attrs or {}) do
		if kv[1] == "unique" then has = true end
		out[#out + 1] = { kv[1], kv[2] }
	end
	if not has then out[#out + 1] = { "unique", "true" } end
	return out
end

local function animated_material(name, dir, skin)
	local d = C.DIRECTIONS[dir]
	return el("material", {
		{ "name", name }, { "render_template", C.RENDER_TEMPLATE },
		{ "version", "2" }, { "unique", "true" },
	}, {
		el("diffuse_texture", { { "file", skin.df } }),
		el("self_illumination_texture", { { "file", skin.il } }),
		el("variable", { { "name", "uv_speed" }, { "value", number(d[1] * C.SCROLL_SPEED) .. " " .. number(d[2] * C.SCROLL_SPEED) .. " 0" }, { "type", "vector3" } }),
		el("variable", { { "name", "il_bloom" }, { "value", C.GLOW_BLOOM }, { "type", "float" } }),
		el("variable", { { "name", "il_multiplier" }, { "value", C.GLOW_MULTIPLIER }, { "type", "scalar" } }),
	})
end

local function ghost_material(name, skin)
	return el("material", {
		{ "name", name }, { "render_template", C.GHOST_TEMPLATE },
		{ "version", "2" }, { "unique", "true" },
	}, {
		el("diffuse_texture", { { "file", skin.ghost or skin.df } }),
		el("variable", { { "name", "intensity" }, { "value", C.GHOST_INTENSITY }, { "type", "scalar" } }),
	})
end

local function template_of(attrs)
	for _, kv in ipairs(attrs or {}) do
		if kv[1] == "render_template" then return kv[2] end
	end
	return ""
end

local function is_solid(attrs)
	return template_of(attrs):sub(1, 8) == "generic:"
end

local function static_material(src, skin)
	local map = {
		["$diffuse"] = skin.df,
		["textures/original/default_df"] = skin.df,
		["textures/original/default_il"] = skin.il,
	}
	local children = {}
	for _, c in ipairs(src.children) do
		local a = {}
		for _, kv in ipairs(c.attrs) do a[#a + 1] = { kv[1], map[kv[2]] or kv[2] } end
		children[#children + 1] = el(c.tag, a)
	end
	return el("material", ensure_unique(src.attrs), children)
end

local function retexturable(src)
	local rt
	for _, kv in ipairs(src.attrs) do if kv[1] == "render_template" then rt = kv[2] end end
	if not (rt and rt:sub(1, 8) == "generic:") then return false end
	for _, c in ipairs(src.children) do
		if c.tag == "diffuse_texture" then
			for _, kv in ipairs(c.attrs) do
				if kv[1] == "file" and kv[2] == "$diffuse" then return true end
			end
		end
	end
	return false
end

local function config_path(part)
	local mc = part.material_config
	if mc == nil then return part.unit end
	if type(mc) == "string" then return mc end
	local key = tostring(mc)
	C.ids_of[key] = mc
	return key
end

local OPTIC_EXCLUDE = {
	optical = true, screen = true,
	mtr_mullplan = true, mullplan = true, mtr_mullplane = true,
}

local function collect_optic_housings()
	local factory = tweak_data and tweak_data.weapon and tweak_data.weapon.factory
	if not (factory and factory.parts) then return {} end
	local found = {}
	for _, part in pairs(factory.parts) do
		local unit = part.unit
		if type(unit) == "string" and unit:find("wpn_fps_upg_o_") then
			local path = config_path(part)
			if path then
				local info = C.read_vanilla_config(path)
				if info then
					for _, m in ipairs(info.elements) do
						if m.name and not OPTIC_EXCLUDE[m.name] then
							local rt
							for _, kv in ipairs(m.attrs) do
								if kv[1] == "render_template" then rt = kv[2] end
							end
							if rt and rt:sub(1, 8) == "generic:" then
								found[m.name] = true
							end
						end
					end
				end
			end
		end
	end
	return found
end

function C.auto_animate_optics(animated)
	for name in pairs(collect_optic_housings()) do
		if not animated[name] then animated[name] = "e" end
	end
end

function C.game_part_units()
	local factory = tweak_data and tweak_data.weapon and tweak_data.weapon.factory
	if not (factory and factory.parts) then return nil end
	local seen, list = {}, {}
	for _, part in pairs(factory.parts) do
		local path = config_path(part)
		if path and not seen[path] then
			seen[path] = true
			list[#list + 1] = path
		end
	end
	table.sort(list)
	return list
end

function C.read_vanilla_config(path)
	local t = Idstring("material_config")
	local n = C.ids_of[path] or Idstring(path)
	if not DB:has(t, n) then return nil end
	local f = DB:open(t, n)
	if not f then return nil end
	local data = f:read()
	f:close()
	if type(data) ~= "string" or data:sub(1, 1) ~= "<" then return nil end
	local elements = parse_elements(data)
	if #elements == 0 then return nil end
	return { group = data:match("<materials[^>]-group%s*=%s*\"([^\"]*)\""), elements = elements }
end

function C.load_parts()
	local units = C.game_part_units()
	if not units then return {} end
	local out = {}
	for _, unit in ipairs(units) do
		local info = C.read_vanilla_config(unit)
		if info then
			out[#out + 1] = {
				name = unit:match("[^/]+$"),
				vanilla = unit,
				group = info.group or "-",
				elements = info.elements,
			}
		end
	end
	return out
end

local function resolve(p, animated, static, idx)
	local out = {}
	if not p.elements then return out end
	for _, vel in ipairs(p.elements) do
		if animated[vel.name] then
			out[#out + 1] = { name = vel.name, anim = animated[vel.name] }
		else
			local src = pick_static(idx, vel)
			if src then
				out[#out + 1] = { name = vel.name, src = src }
			else
				out[#out + 1] = { name = vel.name, vanilla = vel }
			end
		end
	end
	return out
end

function C.build(dir, skin)
	local animated = {}
	for _, f in ipairs(read_lines(dir .. "animated.txt")) do
		animated[f[1]] = f[2]
	end
	C.auto_animate_optics(animated)

	local static = parse_static(read_all(dir .. "static.xml"))
	local idx = index_by_name(static)
	local parts = C.load_parts()
	table.sort(parts, function(a, b) return a.vanilla < b.vanilla end)

	local by_content, configs, mapping, retexture = {}, {}, {}, {}
	local ghost_mapping, ghost_of = {}, {}
	for _, p in ipairs(parts) do
		local attrs = { { "version", "3" } }
		if p.group and p.group ~= "-" then attrs[#attrs + 1] = { "group", p.group } end
		local mats = resolve(p, animated, static, idx)

		local children, ghost_children = {}, {}
		for _, m in ipairs(mats) do
			local normal, ghost
			if m.anim then
				normal = animated_material(m.name, m.anim, skin)
				ghost = ghost_material(m.name, skin)
			elseif m.src then
				normal = static_material(m.src, skin)
				ghost = is_solid(m.src.attrs) and ghost_material(m.name, skin) or normal
			else
				local cs = {}
				for _, c in ipairs(m.vanilla.children) do cs[#cs + 1] = el(c.tag, c.attrs) end
				normal = el("material", ensure_unique(m.vanilla.attrs), cs)
				ghost = is_solid(m.vanilla.attrs) and ghost_material(m.name, skin) or normal
			end
			children[#children + 1] = normal
			ghost_children[#ghost_children + 1] = ghost
		end

		local lines = {}
		render(el("materials", attrs, children), 0, lines)
		local content = table.concat(lines, "\n") .. "\n"
		local config = by_content[content]
		if not config then
			config = p.name
			local k = 1
			while configs[config] do k = k + 1; config = p.name .. "_" .. k end
			by_content[content] = config
			configs[config] = content

			local glines = {}
			render(el("materials", attrs, ghost_children), 0, glines)
			ghost_of[config] = config .. C.GHOST_SUFFIX
			configs[ghost_of[config]] = table.concat(glines, "\n") .. "\n"
		end
		mapping[#mapping + 1] = {
			p.vanilla, config,
			ids = C.ids_of[p.vanilla] or (Idstring and Idstring(p.vanilla)),
		}
		ghost_mapping[#ghost_mapping + 1] = { p.vanilla, ghost_of[config] }

		local anim, base, seen_a, seen_b = {}, {}, {}, {}
		for _, m in ipairs(mats) do
			if m.anim and not seen_a[m.name] then
				seen_a[m.name] = true
				anim[#anim + 1] = m.name
			elseif m.src and retexturable(m.src) and not seen_b[m.src.name] then
				seen_b[m.src.name] = true
				base[#base + 1] = m.src.name
			end
		end
		table.sort(anim)
		table.sort(base)
		retexture[config] = { anim = anim, base = base }
	end

	return { configs = configs, mapping = mapping, ghost_mapping = ghost_mapping, retexture = retexture, animated = animated }
end

function C.ghost_mapping_text(res)
	local out = {}
	for _, m in ipairs(res.ghost_mapping or {}) do out[#out + 1] = m[1] .. " " .. m[2] .. "\n" end
	return table.concat(out)
end

function C.mapping_text(res)
	local out = {}
	for _, m in ipairs(res.mapping) do out[#out + 1] = m[1] .. " " .. m[2] .. "\n" end
	return table.concat(out)
end
