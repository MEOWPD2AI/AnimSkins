dofile(ModPath .. "lua/tuner/core.lua")
dofile(ModPath .. "lua/tuner/reactive.lua")
local T = _G.AnimSkinsTuner

if T._reactive_hud_hooked then return end
T._reactive_hud_hooked = true

local hooked = {}
local function hook(name, fn)
	if type(HUDManager) == "table" and type(HUDManager[name]) == "function" then
		Hooks:PostHook(HUDManager, name, "AnimSkinsTuner_Reactive_" .. name, function(...)
			pcall(fn, ...)
		end)
		table.insert(hooked, name)
	end
end

hook("sync_start_assault", function() T:on_assault(true) end)
hook("sync_end_assault", function() T:on_assault(false) end)
hook("sync_start_anticipation_music", function() T:on_anticipation() end)
