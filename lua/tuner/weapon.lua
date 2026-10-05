dofile(ModPath .. "lua/tuner/core.lua")
dofile(ModPath .. "lua/tuner/reactive.lua")
dofile(ModPath .. "lua/tuner/light.lua")
local T = _G.AnimSkinsTuner

if not T._fire_wrapped and type(RaycastWeaponBase) == "table" and type(RaycastWeaponBase.fire) == "function" then
	T._fire_wrapped = true
	local fire = RaycastWeaponBase.fire
	function RaycastWeaponBase:fire(...)
		local result = fire(self, ...)
		if result then
			pcall(T.on_shot, T, self)
		end
		return result
	end
	end
