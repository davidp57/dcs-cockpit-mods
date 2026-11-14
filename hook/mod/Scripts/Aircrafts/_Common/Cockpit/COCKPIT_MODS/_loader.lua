-- Cockpit mods hook: loads the declaration file of each cockpit mod installed next to it.
--
-- One line added to KNEEBOARD/declare_kneeboard_device.lua runs this file. That file is
-- loaded by most modules from their device_init.lua, so this runs there too, with the
-- module's creators and indicators tables. Each mod drops one file in this folder,
-- COCKPIT_MODS/<NAME>.lua, which declares its devices (and decides itself whether the
-- aircraft is one of its own). Several mods can then share the kneeboard file, which Open
-- Mod Manager only lets one package replace.
--
-- Files whose name starts with "_" belong to the hook and are not loaded as mods.
-- One mod failing to load is written to dcs.log and does not stop the others.

local FOLDER = LockOn_Options.common_script_path.."COCKPIT_MODS/"

-- When lfs cannot be used here, only these files are tried; a missing one is skipped.
-- Keep in step with the mods that drop a file in this folder.
local KNOWN_MODS = {
	"COCKPIT_CYCLES.lua",
	"IFR_CURTAIN.lua",
}

local function log_info(message)
	if log and log.write then
		log.write("COCKPIT_MODS", log.INFO, message)
	else
		print("COCKPIT_MODS: "..message)
	end
end

-- Returns the sorted .lua files of the folder, or nil and the reason lfs cannot be used.
-- No ED device_init.lua uses lfs (checked on 2026-11-14), so it may be missing here.
local function list_folder()
	local lfs_module = lfs
	if type(lfs_module) ~= "table" then
		if type(require) ~= "function" then
			return nil, "no require"
		end
		local ok, loaded = pcall(require, "lfs")
		if not ok then
			return nil, "require(\"lfs\") failed: "..tostring(loaded)
		end
		lfs_module = loaded
	end
	if type(lfs_module) ~= "table" or type(lfs_module.dir) ~= "function" then
		return nil, "lfs has no dir()"
	end
	local ok, names = pcall(function()
		local found = {}
		for name in lfs_module.dir(FOLDER) do
			if string.sub(name, 1, 1) ~= "_" and string.lower(string.sub(name, -4)) == ".lua" then
				found[#found + 1] = name
			end
		end
		return found
	end)
	if not ok then
		return nil, "lfs.dir failed: "..tostring(names)
	end
	table.sort(names)
	return names
end

local names, reason = list_folder()
if names then
	log_info("folder listed with lfs, "..#names.." mod(s): "..table.concat(names, ", "))
else
	names = KNOWN_MODS
	log_info("lfs not usable here ("..tostring(reason).."), trying the known mods: "..table.concat(names, ", "))
end

-- Runs one declaration file. With loadfile, a file that cannot be read (from the known list:
-- a mod that is not installed) is told apart from a mod that fails while declaring.
local function load_mod(name)
	local path = FOLDER..name
	if type(loadfile) ~= "function" then
		local ok, run_error = pcall(dofile, path)
		return ok and "loaded" or ("not loaded: "..tostring(run_error))
	end
	local chunk, load_error = loadfile(path)
	if not chunk then
		return "not loaded ("..tostring(load_error)..")"
	end
	local ok, run_error = pcall(chunk)
	return ok and "loaded" or ("ERROR while declaring: "..tostring(run_error))
end

for _, name in ipairs(names) do
	log_info(name..": "..load_mod(name))
end
