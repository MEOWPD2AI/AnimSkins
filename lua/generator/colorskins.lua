_G.ColorSkinRT = _G.ColorSkinRT or {}
local CSR = _G.ColorSkinRT

local MOD_PATH = ModPath

local TEX_IMPORTED_DB = "textures/imported/"
local TEX_IMPORTED_DIR = MOD_PATH .. "assets/textures/imported/"

CSR.settings = CSR.settings or {
	max_size = 512,
	scan_dirs = { "assets/mod_overrides/", "mods/" },
	glow_contrast = 1.6,
	glow_brightness = 1.4,
	glow_scale = 0.1,
}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local function u16(s, p) local a, b = s:byte(p, p + 1) return a + b * 256 end
local function u32(s, p) local a, b, c, d = s:byte(p, p + 3) return a + b * 256 + c * 65536 + d * 16777216 end
local function le32(n)
	return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function from565(v)
	local r, g, b = floor(v / 2048) % 32, floor(v / 32) % 64, v % 32
	return r * 8 + floor(r / 4), g * 4 + floor(g / 16), b * 8 + floor(b / 4)
end

local function to565(r, g, b)
	return floor(r / 8) * 2048 + floor(g / 4) * 32 + floor(b / 8)
end

local function clamp255(v)
	if v < 0 then return 0 elseif v > 255 then return 255 end
	return floor(v)
end

local function palette4(c0, c1, four_color_only)
	local r0, g0, b0 = from565(c0)
	local r1, g1, b1 = from565(c1)
	local p = { { r0, g0, b0 }, { r1, g1, b1 } }
	if c0 > c1 or four_color_only then
		p[3] = { floor((2 * r0 + r1) / 3), floor((2 * g0 + g1) / 3), floor((2 * b0 + b1) / 3) }
		p[4] = { floor((r0 + 2 * r1) / 3), floor((g0 + 2 * g1) / 3), floor((b0 + 2 * b1) / 3) }
	else
		p[3] = { floor((r0 + r1) / 2), floor((g0 + g1) / 2), floor((b0 + b1) / 2) }
		p[4] = { 0, 0, 0 }
	end
	return p
end

-- Pixel packing used everywhere: r * 65536 + g * 256 + b

local function mask_info(mask)
	if not mask or mask == 0 then return nil end
	local shift = 0
	while floor(mask / 2 ^ shift) % 2 == 0 do shift = shift + 1 end
	local bits = 0
	while floor(mask / 2 ^ (shift + bits)) % 2 == 1 do bits = bits + 1 end
	return { div = 2 ^ shift, mod = 2 ^ bits, scale = 255 / (2 ^ bits - 1) }
end

local function channel(v, info)
	if not info then return 0 end
	return floor((floor(v / info.div) % info.mod) * info.scale + 0.5)
end

local BLOCK_KIND = {
	DXT1 = { size = 8, color_off = 0, four = false },
	DXT3 = { size = 16, color_off = 8, four = true },
	DXT5 = { size = 16, color_off = 8, four = true },
}

-- DXGI formats found in DX10-style DDS files
local DXGI_BLOCK = { [71] = "DXT1", [72] = "DXT1", [74] = "DXT3", [75] = "DXT3", [77] = "DXT5", [78] = "DXT5" }
-- dxgi -> { bytes per pixel, byte order of r, g, b (1-based), or gray }
local DXGI_RAW = {
	[28] = { 4, 1, 2, 3 }, [29] = { 4, 1, 2, 3 },
	[87] = { 4, 3, 2, 1 }, [91] = { 4, 3, 2, 1 },
	[88] = { 4, 3, 2, 1 }, [93] = { 4, 3, 2, 1 },
	[61] = { 1, 1, 1, 1 },
}

local function decode_blocks(data, w, h, step, kind, base)
	local bs = BLOCK_KIND[kind]
	local ow, oh = ceil(w / step), ceil(h / step)
	local bxn, byn = max(1, ceil(w / 4)), max(1, ceil(h / 4))
	if #data < base - 1 + bxn * byn * bs.size then
		return nil, "file is truncated (not enough pixel data)"
	end
	local px = {}
	for by = 0, byn - 1 do
		for bx = 0, bxn - 1 do
			local o = base + (by * bxn + bx) * bs.size + bs.color_off
			local pal = palette4(u16(data, o), u16(data, o + 2), bs.four)
			local idx = u32(data, o + 4)
			for i = 0, 15 do
				local x, y = bx * 4 + i % 4, by * 4 + floor(i / 4)
				if x < w and y < h and x % step == 0 and y % step == 0 then
					local c = pal[floor(idx / 4 ^ i) % 4 + 1]
					px[(y / step) * ow + (x / step) + 1] = c[1] * 65536 + c[2] * 256 + c[3]
				end
			end
		end
	end
	return { w = ow, h = oh, px = px }
end

-- Uncompressed: `bpp` bytes per pixel; `getrgb(v)` turns the little-endian pixel value into r, g, b
local function decode_raw(data, w, h, step, bpp, base, getrgb)
	if #data < base - 1 + w * h * bpp then
		return nil, "file is truncated (not enough pixel data)"
	end
	local ow, oh = ceil(w / step), ceil(h / step)
	local px = {}
	for y = 0, h - 1, step do
		for x = 0, w - 1, step do
			local o = base + (y * w + x) * bpp
			local v, mul = 0, 1
			for k = 0, bpp - 1 do
				v = v + data:byte(o + k) * mul
				mul = mul * 256
			end
			local r, g, b = getrgb(v)
			px[(y / step) * ow + (x / step) + 1] = r * 65536 + g * 256 + b
		end
	end
	return { w = ow, h = oh, px = px }
end

function CSR.decode_dds(data, step)
	step = step or 1
	if not data or #data < 128 or data:sub(1, 4) ~= "DDS " then
		return nil, "not a DDS file"
	end
	local h, w = u32(data, 13), u32(data, 17)
	if w < 1 or h < 1 or w > 16384 or h > 16384 then
		return nil, "bad DDS size " .. tostring(w) .. "x" .. tostring(h)
	end
	local pf_flags = u32(data, 81)
	local fourcc = data:sub(85, 88)

	if BLOCK_KIND[fourcc] then
		return decode_blocks(data, w, h, step, fourcc, 129)
	end

	if fourcc == "DX10" then
		if #data < 148 then return nil, "file is truncated" end
		local dxgi = u32(data, 129)
		if DXGI_BLOCK[dxgi] then
			return decode_blocks(data, w, h, step, DXGI_BLOCK[dxgi], 149)
		end
		local raw = DXGI_RAW[dxgi]
		if raw then
			local bpp, ri, gi, bi = raw[1], raw[2], raw[3], raw[4]
			return decode_raw(data, w, h, step, bpp, 149, function(v)
				local function byte(i) return floor(v / 256 ^ (i - 1)) % 256 end
				return byte(ri), byte(gi), byte(bi)
			end)
		end
		return nil, "DX10 format " .. dxgi .. " is not supported (BC7/BC6/BC5 etc). Re-save the texture as DXT1, DXT5 or uncompressed"
	end

	-- Legacy uncompressed formats (no FourCC)
	if floor(pf_flags / 64) % 2 == 1 or floor(pf_flags / 131072) % 2 == 1 then
		local bits = u32(data, 89)
		if bits ~= 8 and bits ~= 16 and bits ~= 24 and bits ~= 32 then
			return nil, "unsupported uncompressed bit depth " .. bits
		end
		local rm, gm, bm = mask_info(u32(data, 93)), mask_info(u32(data, 97)), mask_info(u32(data, 101))
		if floor(pf_flags / 131072) % 2 == 1 then
			-- luminance
			-- some tools write a mask that does not fit the bit depth; then the whole value is the luminance
			local fits = u32(data, 93) > 0 and u32(data, 93) < 2 ^ bits
			return decode_raw(data, w, h, step, bits / 8, 129, function(v)
				local l
				if fits then
					l = channel(v, rm)
				else
					l = floor((v % 2 ^ bits) * 255 / (2 ^ bits - 1) + 0.5)
				end
				return l, l, l
			end)
		end
		if not (rm and gm and bm) then return nil, "uncompressed DDS has no colour masks" end
		return decode_raw(data, w, h, step, bits / 8, 129, function(v)
			return channel(v, rm), channel(v, gm), channel(v, bm)
		end)
	end

	local shown = fourcc:gsub("[^%w]", "?")
	return nil, "unsupported DDS format '" .. shown .. "'"
end

local function resample(src, dw, dh)
	if src.w == dw and src.h == dh then return src.px end
	local out, sw, sh, sp = {}, src.w, src.h, src.px
	for y = 0, dh - 1 do
		local fy = (y + 0.5) * sh / dh - 0.5
		local y0 = floor(fy); local ty = fy - y0
		local ya, yb = min(max(y0, 0), sh - 1), min(max(y0 + 1, 0), sh - 1)
		for x = 0, dw - 1 do
			local fx = (x + 0.5) * sw / dw - 0.5
			local x0 = floor(fx); local tx = fx - x0
			local xa, xb = min(max(x0, 0), sw - 1), min(max(x0 + 1, 0), sw - 1)
			local p00, p10 = sp[ya * sw + xa + 1], sp[ya * sw + xb + 1]
			local p01, p11 = sp[yb * sw + xa + 1], sp[yb * sw + xb + 1]
			local w00, w10, w01, w11 = (1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty
			local r = floor(p00 / 65536) * w00 + floor(p10 / 65536) * w10 + floor(p01 / 65536) * w01 + floor(p11 / 65536) * w11
			local g = (floor(p00 / 256) % 256) * w00 + (floor(p10 / 256) % 256) * w10 + (floor(p01 / 256) % 256) * w01 + (floor(p11 / 256) % 256) * w11
			local b = (p00 % 256) * w00 + (p10 % 256) * w10 + (p01 % 256) * w01 + (p11 % 256) * w11
			out[y * dw + x + 1] = floor(r + 0.5) * 65536 + floor(g + 0.5) * 256 + floor(b + 0.5)
		end
	end
	return out
end

local function luma(p)
	local r, g, b = floor(p / 65536), floor(p / 256) % 256, p % 256
	return floor((r * 19595 + g * 38470 + b * 7471 + 32768) / 65536)
end

local function make_glow(diffuse, contrast, brightness)
	contrast = contrast or CSR.settings.glow_contrast
	brightness = brightness or CSR.settings.glow_brightness
	local w, h = diffuse.w, diffuse.h
	local lsum = 0
	for i = 1, w * h do
		lsum = lsum + luma(diffuse.px[i])
	end
	local mean = floor(lsum / (w * h) + 0.5)
	local glow = {}
	for i = 1, w * h do
		local p = diffuse.px[i]
		local r, g, b = floor(p / 65536), floor(p / 256) % 256, p % 256
		r = clamp255(clamp255(mean + (r - mean) * contrast) * brightness)
		g = clamp255(clamp255(mean + (g - mean) * contrast) * brightness)
		b = clamp255(clamp255(mean + (b - mean) * contrast) * brightness)
		glow[i] = r * 65536 + g * 256 + b
	end
	return { w = w, h = h, px = glow }
end

-- pattern * gradient (colour skin). With no gradient the pattern itself is the colour (plain image skin).
function CSR.compose(pattern, gradient, contrast, brightness)
	local w, h = pattern.w, pattern.h
	if not gradient then
		local copy = {}
		for i = 1, w * h do copy[i] = pattern.px[i] end
		local diffuse = { w = w, h = h, px = copy }
		return diffuse, make_glow(diffuse, contrast, brightness)
	end
	local grad = resample(gradient, w, h)
	local diffuse = {}
	for i = 1, w * h do
		local l = luma(pattern.px[i])
		local g = grad[i]
		local r = floor((floor(g / 65536) * l + 127) / 255)
		local gg = floor((floor(g / 256) % 256 * l + 127) / 255)
		local b = floor(((g % 256) * l + 127) / 255)
		diffuse[i] = r * 65536 + gg * 256 + b
	end
	local d = { w = w, h = h, px = diffuse }
	return d, make_glow(d, contrast, brightness)
end

CSR.TILE_SIZE = 512
CSR.BLEND_WIDTH = 16

function CSR.tile_blend(img, size, bw)
	size = size or CSR.TILE_SIZE
	bw = bw or floor(CSR.BLEND_WIDTH * size / 512)
	local r = floor(bw / 2)
	local px = resample(img, size, size)

	if r > 0 then
		local function blur_axis(horizontal)
			local line = {}
			local n = 2 * r + 1
			for a = 0, size - 1 do
				for c = 0, size - 1 do
					line[c + 1] = horizontal and px[a * size + c + 1] or px[c * size + a + 1]
				end
				for c = 0, size - 1 do
					if c < r or c >= size - r then
						local sr, sg, sb = 0, 0, 0
						for d = -r, r do
							local p = line[(c + d) % size + 1]
							sr = sr + floor(p / 65536)
							sg = sg + floor(p / 256) % 256
							sb = sb + p % 256
						end
						local v = floor(sr / n + 0.5) * 65536 + floor(sg / n + 0.5) * 256 + floor(sb / n + 0.5)
						if horizontal then px[a * size + c + 1] = v else px[c * size + a + 1] = v end
					end
				end
			end
		end
		blur_axis(true)
		blur_axis(false)
	end

	return { w = size, h = size, px = px }
end

function CSR.scale_rgb(img, factor)
	local px = {}
	for i = 1, img.w * img.h do
		local p = img.px[i]
		local r = floor(floor(p / 65536) * factor + 0.5)
		local g = floor((floor(p / 256) % 256) * factor + 0.5)
		local b = floor((p % 256) * factor + 0.5)
		px[i] = r * 65536 + g * 256 + b
	end
	return { w = img.w, h = img.h, px = px }
end

function CSR.encode_dxt1(img)
	local w, h, px = img.w, img.h, img.px
	local bxn, byn = max(1, ceil(w / 4)), max(1, ceil(h / 4))
	local blocks, n = {}, 0
	local rs, gs, bs = {}, {}, {}
	for by = 0, byn - 1 do
		for bx = 0, bxn - 1 do
			local r0, g0, b0, r1, g1, b1 = 255, 255, 255, 0, 0, 0
			for i = 0, 15 do
				local x, y = min(bx * 4 + i % 4, w - 1), min(by * 4 + floor(i / 4), h - 1)
				local p = px[y * w + x + 1]
				local r, g, b = floor(p / 65536), floor(p / 256) % 256, p % 256
				rs[i], gs[i], bs[i] = r, g, b
				if r < r0 then r0 = r end; if r > r1 then r1 = r end
				if g < g0 then g0 = g end; if g > g1 then g1 = g end
				if b < b0 then b0 = b end; if b > b1 then b1 = b end
			end
			local c0, c1 = to565(r1, g1, b1), to565(r0, g0, b0)
			local indices = 0
			if c0 == c1 then

			else
				if c0 < c1 then c0, c1 = c1, c0 end
				local pal = palette4(c0, c1, false)
				for i = 0, 15 do
					local best, bd = 0, math.huge
					for k = 1, 4 do
						local d = (rs[i] - pal[k][1]) ^ 2 + (gs[i] - pal[k][2]) ^ 2 + (bs[i] - pal[k][3]) ^ 2
						if d < bd then bd, best = d, k - 1 end
					end
					indices = indices + best * 4 ^ i
				end
			end
			n = n + 1
			blocks[n] = string.char(c0 % 256, floor(c0 / 256), c1 % 256, floor(c1 / 256)) .. le32(indices)
		end
	end
	local body = table.concat(blocks)
	local header = "DDS " .. le32(124) .. le32(0x81007) .. le32(h) .. le32(w) .. le32(#body) .. le32(0) .. le32(0)
		.. string.rep("\0", 44) .. le32(32) .. le32(4) .. "DXT1" .. string.rep("\0", 20)
		.. le32(0x1000) .. string.rep("\0", 16)
	return header .. body
end

-- ---------------------------------------------------------------------------------------------
-- See-through scroll frames
-- The additive see-through shader cannot scroll a texture, so the pattern is moved in steps by
-- swapping between FRAME_COUNT pre-shifted copies of the skin (<glow>_f00 .. _f47, see core.lua).
-- Same layout as the bundled skins: FRAME_SIZE x FRAME_SIZE DXT1, frame i = the image moved right
-- by i / FRAME_COUNT of its width (wrapping around), so the last frame is one step before frame 0.
-- ---------------------------------------------------------------------------------------------
CSR.FRAME_COUNT = 48
CSR.FRAME_SIZE = 256

-- Box-filter a square image down to size x size (resample() when it does not divide evenly)
function CSR.downscale(img, size)
	if img.w == size and img.h == size then return img end
	local f = img.w / size
	if img.w ~= img.h or f ~= floor(f) or f < 1 then
		return { w = size, h = size, px = resample(img, size, size) }
	end
	local out, n, sw, sp = {}, f * f, img.w, img.px
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local sr, sg, sb = 0, 0, 0
			for dy = 0, f - 1 do
				local row = (y * f + dy) * sw + x * f
				for dx = 1, f do
					local p = sp[row + dx]
					sr = sr + floor(p / 65536)
					sg = sg + floor(p / 256) % 256
					sb = sb + p % 256
				end
			end
			out[y * size + x + 1] = floor(sr / n + 0.5) * 65536 + floor(sg / n + 0.5) * 256 + floor(sb / n + 0.5)
		end
	end
	return { w = size, h = size, px = out }
end

-- Copy of img moved right by `shift` pixels (fractions are blended), wrapping around the edge.
-- r, g, b are the img channels as flat arrays (so they are only split once for all frames).
local function shift_columns(img, r, g, b, shift)
	local w, h = img.w, img.h
	local whole = floor(shift)
	local frac = shift - whole
	local out = {}
	for y = 0, h - 1 do
		local row = y * w
		for x = 0, w - 1 do
			local ia = row + (x - whole) % w + 1
			if frac < 1e-6 then
				out[row + x + 1] = r[ia] * 65536 + g[ia] * 256 + b[ia]
			else
				local ib = row + (x - whole - 1) % w + 1
				out[row + x + 1] = floor(r[ia] + (r[ib] - r[ia]) * frac + 0.5) * 65536
					+ floor(g[ia] + (g[ib] - g[ia]) * frac + 0.5) * 256
					+ floor(b[ia] + (b[ib] - b[ia]) * frac + 0.5)
			end
		end
	end
	return { w = w, h = h, px = out }
end

-- Yields each frame image in turn: callback(index, image)
function CSR.each_frame(glow, callback)
	local small = CSR.downscale(glow, CSR.FRAME_SIZE)
	local r, g, b = {}, {}, {}
	for i = 1, small.w * small.h do
		local p = small.px[i]
		r[i], g[i], b[i] = floor(p / 65536), floor(p / 256) % 256, p % 256
	end
	for i = 0, CSR.FRAME_COUNT - 1 do
		local img = small
		if i > 0 then
			img = shift_columns(small, r, g, b, i * small.w / CSR.FRAME_COUNT)
		end
		callback(i, img)
	end
end

local function attr(s, name)
	return (" " .. s):match("%s" .. name .. '%s*=%s*"([^"]*)"')
end

function CSR.parse_main(text)
	text = text:gsub("<!%-%-.-%-%->", "")
	local res = { skins = {}, files = {} }
	for attrs, body in text:gmatch("<AddFiles%s*([^>]*)>(.-)</AddFiles>") do
		local dir = (attr(attrs, "directory") or ""):gsub("\\", "/")
		for tag, a in body:gmatch("<(%w+)%s+([^>]-)/?>") do
			if tag == "texture" or tag == "dds" then
				local name = attr(a, "path")
				if name then res.files[name] = dir end
			end
		end
	end
	for attrs, body in text:gmatch("<WeaponSkin%s+([^>]*)>(.-)</WeaponSkin>") do
		if attr(attrs, "is_a_color_skin") == "true" then
			local cd = body:match("<color_skin_data%s+([^>]-)/?>")
			local pattern, gradient = cd and attr(cd, "pattern_default"), cd and attr(cd, "gradient_default")
			if pattern and gradient then
				table.insert(res.skins, { id = attr(attrs, "id"), pattern = pattern, gradient = gradient })
			end
		end
	end
	return res
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() return true end
	return false
end

local function read_all(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local d = f:read("*all")
	f:close()
	return d
end

local function find_recursive(dir, name, depth)
	if depth < 0 then return nil end
	for _, f in ipairs(file.GetFiles(dir) or {}) do
		if f == name then return dir .. f end
	end
	for _, d in ipairs(file.GetDirectories(dir) or {}) do
		local hit = find_recursive(dir .. d .. "/", name, depth - 1)
		if hit then return hit end
	end
end

function CSR.resolve_texture(main_dir, directory, name)
	if directory ~= "" and directory:sub(-1) ~= "/" then directory = directory .. "/" end
	for _, ext in ipairs({ ".dds", ".texture" }) do
		local p = main_dir .. directory .. name .. ext
		if exists(p) then return p end
	end
	for _, ext in ipairs({ ".dds", ".texture" }) do
		local hit = find_recursive(main_dir, name:match("[^/]+$") .. ext, 4)
		if hit then return hit end
	end
end

-- Folders where loose .dds files are picked up as skins.
--   name.dds                    -> the image is used as the skin colour as-is
--   name.dds + name_gradient.dds -> colour skin: name.dds is the pattern, the gradient colours it
-- Files ending in _gradient / _grad are only ever used as the gradient of the skin they belong to.
function CSR.custom_dirs()
	return { MOD_PATH .. "custom_skins/", SavePath .. "animskins_custom/" }
end

local GRADIENT_SUFFIXES = { "_gradient", "_grad" }

function CSR:find_loose_skins(seen, found)
	for _, dir in ipairs(CSR.custom_dirs()) do
		if file.DirectoryExists(dir) then
			local files = file.GetFiles(dir) or {}
			local have = {}
			for _, f in ipairs(files) do have[f:lower()] = f end

			for _, f in ipairs(files) do
				local stem, ext = f:match("^(.*)%.(%w+)$")
				ext = ext and ext:lower()
				if stem and (ext == "dds" or ext == "texture") then
					local is_gradient = false
					for _, suf in ipairs(GRADIENT_SUFFIXES) do
						if stem:lower():sub(-#suf) == suf then is_gradient = true end
					end
					if not is_gradient then
						local gradient
						for _, suf in ipairs(GRADIENT_SUFFIXES) do
							for _, e in ipairs({ "dds", "texture" }) do
								local hit = have[(stem .. suf .. "." .. e):lower()]
								if hit and not gradient then gradient = dir .. hit end
							end
						end
						local id = "custom_" .. stem
						if not seen[id] then
							seen[id] = true
							table.insert(found, {
								id = id, pattern = dir .. f, gradient = gradient, mod = "custom", loose = true,
							})
						end
					end
				end
			end
		end
	end
end

function CSR:find_color_skins()
	local found, seen = {}, {}
	for _, root in ipairs(self.settings.scan_dirs) do
		for _, mod in ipairs(file.GetDirectories(root) or {}) do
			local main_dir = root .. mod .. "/"
			local text = read_all(main_dir .. "main.xml")
			if text then
				local parsed = CSR.parse_main(text)
				for _, skin in ipairs(parsed.skins) do
					local pp = CSR.resolve_texture(main_dir, parsed.files[skin.pattern] or "", skin.pattern)
					local gp = CSR.resolve_texture(main_dir, parsed.files[skin.gradient] or "", skin.gradient)
					if pp and gp then
						if not seen[skin.id] then
							seen[skin.id] = true
							table.insert(found, { id = skin.id, pattern = pp, gradient = gp, mod = mod })
						end
					end
				end
			end
		end
	end
	self:find_loose_skins(seen, found)
	return found
end

function CSR.sanitize(id)
	return (tostring(id):lower():gsub("[^%w_]", "_"))
end

function CSR:names(skin)
	local key = CSR.sanitize(skin.id)
	return {
		key = key,
		id = "imported_" .. key,
		name = "Imported: " .. tostring(skin.id),
		base_name = TEX_IMPORTED_DB .. key .. "_df",
		glow_name = TEX_IMPORTED_DB .. key .. "_il",
		base_file = TEX_IMPORTED_DIR .. key .. "_df.texture",
		glow_file = TEX_IMPORTED_DIR .. key .. "_il.texture",
		-- see-through scroll frames: <glow_name>_f00 .. _f47 (core.lua builds the same names)
		frame_name = function(i) return (TEX_IMPORTED_DB .. key .. "_il_f%02d"):format(i) end,
		frame_file = function(i) return (TEX_IMPORTED_DIR .. key .. "_il_f%02d.texture"):format(i) end,
		frame_key = function(i) return (key .. "_il_f%02d.texture"):format(i) end,
	}
end

-- true when all the see-through scroll frames of a skin are on disk
function CSR:frames_present(names)
	for i = 0, CSR.FRAME_COUNT - 1 do
		local f = io.open(names.frame_file(i), "rb")
		if not f then return false end
		f:close()
	end
	return true
end

function CSR:generate(skin)
	local names = self:names(skin)
	local step = 1
	local pdata = read_all(skin.pattern)
	local gdata = skin.gradient and read_all(skin.gradient)
	if not pdata then
		return nil, "cannot read " .. tostring(skin.pattern)
	end
	if skin.gradient and not gdata then
		return nil, "cannot read " .. tostring(skin.gradient)
	end
	if #pdata < 128 or pdata:sub(1, 4) ~= "DDS " then
		return nil, "pattern is not a DDS file"
	end
	local ph, pw = u32(pdata, 13), u32(pdata, 17)
	while max(pw, ph) / step > self.settings.max_size do step = step * 2 end

	local ok, pattern, e1 = pcall(CSR.decode_dds, pdata, step)
	if not ok then return nil, "pattern: " .. tostring(pattern) end
	if not pattern then return nil, "pattern: " .. tostring(e1) end

	local gradient
	if gdata then
		local ok2, g, e2 = pcall(CSR.decode_dds, gdata, 1)
		if not ok2 then return nil, "gradient: " .. tostring(g) end
		if not g then return nil, "gradient: " .. tostring(e2) end
		gradient = g
	end

	local ok3, diffuse, glow = pcall(CSR.compose, pattern, gradient)
	if not ok3 then return nil, "compose failed: " .. tostring(diffuse) end

	local ok4, err = pcall(function()
		-- One file only: the image at full brightness is the glow texture. The base (diffuse) slot uses the
		-- built-in black texture, and the darkening is done at runtime (glow_scale on il_multiplier),
		-- so no second, pre-darkened texture is created.
		glow = CSR.tile_blend(diffuse)
		local function write(path, img)
			local f = assert(io.open(path, "wb"))
			f:write(CSR.encode_dxt1(img))
			f:close()
		end
		write(names.glow_file, glow)
	end)
	if not ok4 then return nil, "write failed: " .. tostring(err) end

	-- The 48 shifted copies that let the see-through weapon scroll. If this part fails the skin itself
	-- is still fine (it just will not scroll while see-through), so it is reported but not fatal.
	local ok5, err5 = pcall(function()
		CSR.each_frame(glow, function(i, img)
			local f = assert(io.open(names.frame_file(i), "wb"))
			f:write(CSR.encode_dxt1(img))
			f:close()
		end)
	end)
	if not ok5 then
		if log then pcall(log, "[AnimSkins] scroll frames failed for " .. tostring(skin.id) .. ": " .. tostring(err5)) end
		for i = 0, CSR.FRAME_COUNT - 1 do os.remove(names.frame_file(i)) end
		names.frames_error = tostring(err5)
	end
	return names
end
