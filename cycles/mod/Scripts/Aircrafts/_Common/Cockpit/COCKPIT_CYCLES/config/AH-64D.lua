-- Cockpit cycles, AH-64D: page cycles of the two MPDs, for both seats.
-- Run by device.lua, inside the cycles device. Returns the settings and the slots.
--
-- Each MPD has five commands, all stepping through the same page cycle on a short press:
--   FCR > WPN > TSD > VID > A/C > FCR... (every page with its own button, except COM)
-- They differ only by what a long press does: nothing (the page then changes as soon as the
-- key is pressed), or go straight to FCR, WPN, TSD or VID. The pilot picks one of them in
-- Options > Controls; the commands of an MPD share their cycle position.
--
-- No cockpit Lua function tells which seat is in use (none found in DCS's scripts on
-- 2026-11-14), so each seat has its own command numbers: its input files (AH-64D_PLT,
-- AH-64D_CPG in dcs-community-keybinds) send them, and they press that seat's MPDs, as a
-- mouse click would (performClickableAction).
-- Slots, in the order of the Custom_Keybinds commands; in each MPD: no hold, then hold FCR,
-- WPN, TSD, VID.
--   pilot:  1-5 left MPD, 8-12 right MPD
--   gunner: 21-25 left MPD, 28-32 right MPD

dofile(LockOn_Options.script_path.."devices.lua")      -- devices.*
dofile(LockOn_Options.script_path.."command_defs.lua") -- mpd_commands.*

local SEATS = {
	{first = 1, left = devices.MFD_PLT_LEFT, right = devices.MFD_PLT_RIGHT, name = "pilot"},
	{first = 21, left = devices.MFD_CPG_LEFT, right = devices.MFD_CPG_RIGHT, name = "gunner"},
}

-- Page buttons of an MPD.
local PAGES = {
	FCR = mpd_commands.FCR,
	WPN = mpd_commands.WPN,
	TSD = mpd_commands.TSD,
	VID = mpd_commands.VID,
	["A/C"] = mpd_commands.AC,
}

-- Short press, both MPDs.
local CYCLE = {"FCR", "WPN", "TSD", "VID", "A/C"}

-- Long press, in the order of the commands.
local HOLD = {"FCR", "WPN", "TSD", "VID"}

local slots = {}

-- Adds the slots of one MPD, from slot number first.
local function add_mpd(device, name, first)
	local buttons = {}
	for page, command in pairs(PAGES) do
		buttons[page] = {device = device, command = command, method = "click", label = name.." "..page}
	end
	-- One action table for all the slots of the MPD: they share the cycle position.
	local cycle = {}
	for _, page in ipairs(CYCLE) do
		cycle[#cycle + 1] = buttons[page]
	end
	local next_page = {cycle = cycle}
	slots[first] = {short = next_page}
	for i, page in ipairs(HOLD) do
		slots[first + i] = {short = next_page, long = {press = buttons[page]}}
	end
end

-- Slot numbers are the command numbers DCS keeps the pilots' bindings under: never renumber.
-- Pilot 6-7 and 13-14 were long presses on COM and A/C, dropped on 2026-11-14.
for _, seat in ipairs(SEATS) do
	add_mpd(seat.left, seat.name.." left MPD", seat.first)
	add_mpd(seat.right, seat.name.." right MPD", seat.first + 7)
end

return {
	description = "pilot commands on the pilot's MPDs, gunner commands on the gunner's",
	long_press = 0.5,
	-- On screen while trying it out; set to false once settled.
	show_messages = true,
	slots = slots,
}
