-- Cockpit cycles: the aircraft that get the cycles, and the file that sets their slots.
-- Read by declare.lua (an aircraft missing here gets no cycles device at all) and by
-- device.lua, which runs config/<config>.lua.
--
-- Each aircraft is matched against its module's cockpit script path
-- ("AH-64D" for Mods/aircraft/AH-64D/Cockpit/Scripts/), as plain text.
local aircraft = {
	{match = "AH-64D", config = "AH-64D.lua"},
}

local function find(script_path)
	for _, entry in ipairs(aircraft) do
		if string.find(script_path or "", entry.match, 1, true) then
			return entry
		end
	end
	return nil
end

return {find = find}
