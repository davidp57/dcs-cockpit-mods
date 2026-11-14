-- Cockpit cycles: declares the Lua device.
-- Loaded from COCKPIT_MODS/COCKPIT_CYCLES.lua by the cockpit mods hook, which runs from
-- declare_kneeboard_device.lua, so inside each module's device_init.lua.
-- Does nothing for an aircraft missing from aircraft.lua, or whose device id is taken.

local COCKPIT_CYCLES_DEVICE_ID = 251

local path = LockOn_Options.common_script_path.."COCKPIT_CYCLES/"

local function log_info(message)
	if log and log.write then
		log.write("COCKPIT_CYCLES", log.INFO, message)
	else
		print("COCKPIT_CYCLES: "..message)
	end
end

local entry = dofile(path.."aircraft.lua").find(LockOn_Options.script_path)

if entry then
	if not creators then
		creators = {}
	end
	if creators[COCKPIT_CYCLES_DEVICE_ID] then
		log_info("device id "..COCKPIT_CYCLES_DEVICE_ID.." already taken, cycles not declared")
	else
		creators[COCKPIT_CYCLES_DEVICE_ID] = {"avLuaDevice", path.."device.lua"}
		log_info("declared as device "..COCKPIT_CYCLES_DEVICE_ID.." ("..entry.match..")")
	end
end
