-- Cockpit cycles, AH-64D: page cycles of the two MPDs, for both seats.
-- Run by device.lua, inside the cycles device. Returns the settings and the slots.
--
-- Each MPD has seven commands, all stepping through the same page cycle on a short press:
--   FCR > WPN > TSD > VID > ENG > ASE > FCR...
-- They differ only by what a long press does: nothing (the page then changes as soon as the
-- key is pressed), or go straight to FCR, WPN, TSD, VID, ENG or ASE. The pilot picks one of
-- them in Options > Controls; the commands of an MPD share their cycle position.
--
-- FCR, WPN, TSD and VID have their own button around the MPD. ENG and ASE have none: they
-- are reached through the menu, M (B1) then B2 for ENG, M then L3 for ASE (MPD_MENU.lua).
-- A/C is not used for ENG: it may open another A/C page (FLT, FUEL...), likely the last one
-- shown (not checked in game).
--
-- No cockpit Lua function tells which seat is in use (none found in DCS's scripts on
-- 2026-11-14), so each seat has its own command numbers: its input files (AH-64D_PLT,
-- AH-64D_CPG in dcs-community-keybinds) send them, and they press that seat's MPDs, as a
-- mouse click would (performClickableAction).
-- Slots, in the order of the Custom_Keybinds commands; in each MPD: no hold, then hold FCR,
-- WPN, TSD, VID, ENG, ASE.
--   pilot:  1-7 left MPD, 8-14 right MPD
--   gunner: 21-27 left MPD, 28-34 right MPD

dofile(LockOn_Options.script_path.."devices.lua")      -- devices.*
dofile(LockOn_Options.script_path.."command_defs.lua") -- mpd_commands.*

local SEATS = {
	{first = 1, left = devices.MFD_PLT_LEFT, right = devices.MFD_PLT_RIGHT, name = "pilot"},
	{first = 21, left = devices.MFD_CPG_LEFT, right = devices.MFD_CPG_RIGHT, name = "gunner"},
}

-- Page buttons around an MPD.
local PAGES = {
	FCR = mpd_commands.FCR,
	WPN = mpd_commands.WPN,
	TSD = mpd_commands.TSD,
	VID = mpd_commands.VID,
}

-- Pages of the menu: the menu key, then the page's key in the menu.
local MENU_KEY = mpd_commands.B1
local MENU_PAGES = {
	ENG = mpd_commands.B2,
	ASE = mpd_commands.L3,
}

-- Short press, both MPDs.
local CYCLE = {"FCR", "WPN", "TSD", "VID", "ENG", "ASE"}

-- Long press, in the order of the commands.
local HOLD = {"FCR", "WPN", "TSD", "VID", "ENG", "ASE"}

local slots = {}

-- Adds the slots of one MPD, from slot number first.
local function add_mpd(device, name, first)
	local function button(command, label)
		return {device = device, command = command, method = "click", label = label}
	end
	local steps = {}
	for page, command in pairs(PAGES) do
		steps[page] = button(command, name.." "..page)
	end
	for page, command in pairs(MENU_PAGES) do
		steps[page] = {
			sequence = {button(MENU_KEY, name.." M"), button(command, name.." menu "..page)},
			label = name.." "..page,
		}
	end
	-- One action table for all the slots of the MPD: they share the cycle position.
	local cycle = {}
	for _, page in ipairs(CYCLE) do
		cycle[#cycle + 1] = steps[page]
	end
	local next_page = {cycle = cycle}
	slots[first] = {short = next_page}
	for i, page in ipairs(HOLD) do
		slots[first + i] = {short = next_page, long = {press = steps[page]}}
	end
end

-- Slot numbers are the command numbers DCS keeps the pilots' bindings under: never renumber.
-- Pilot 6-7 and 13-14 were long presses on COM and A/C until 2026-11-14, never distributed:
-- reused for ENG and ASE on 2026-11-15.
for _, seat in ipairs(SEATS) do
	add_mpd(seat.left, seat.name.." left MPD", seat.first)
	add_mpd(seat.right, seat.name.." right MPD", seat.first + 7)
end

return {
	description = "pilot commands on the pilot's MPDs, gunner commands on the gunner's",
	long_press = 0.5,
	-- Between M and the page key of ENG and ASE; to settle in game.
	sequence_step = 0.2,
	-- true shows each press on screen (dcs.log always has it); settled in game on 2026-11-14.
	show_messages = false,
	slots = slots,
}
