-- Cockpit cycles: Lua device that turns one key binding (a "slot") into a cycle of cockpit
-- buttons, with another action for a long press.
--
-- Each slot has a down command (key pressed) and an up command (key released), bound by the
-- Custom_Keybinds package. Holding the key past the long press threshold runs the slot's
-- long action at once, without waiting for the release; releasing it earlier runs its short
-- action. A slot with no long action runs its short action as soon as the key is pressed.
--
-- An action presses a step: the next one of a cycle, or always the same one. A step is one
-- cockpit button, or a sequence of buttons pressed one after the other (a menu key, then the
-- page in the menu), sequence_step seconds apart.
-- Each cycle remembers its position; slots given the same cycle table share it. Pressing a
-- step through any action also moves every other cycle holding that step to it: after a long
-- press on FCR, a cycle FCR, WPN, TSD goes on with WPN. A sequence is recognised only as the
-- same table, a single button also by its device and command. Buttons pressed with the
-- mouse are not seen.
--
-- The aircraft's buttons and slots are in config/<file>.lua, chosen by aircraft.lua.
-- Everything the device does is written to dcs.log, lines COCKPIT_CYCLES.

local SLOT_COUNT  = 40
local CMD_DOWN    = 3000 -- slot n pressed: CMD_DOWN + n
local CMD_UP      = 3100 -- slot n released: CMD_UP + n (SLOT_COUNT must stay under 100)
-- Seconds of model time between two update() calls. Durations are counted in model time:
-- under time acceleration, a long press is shorter in real time.
local UPDATE_STEP = 0.02

local DEFAULTS = {
	long_press    = 0.5,  -- seconds held before the long action runs
	release_after = 0.1,  -- seconds between pressing a cockpit button and releasing it
	sequence_step = 0.2,  -- seconds between two buttons of a sequence (released in between)
	show_messages = false, -- also show each action on screen
}

local PATH = LockOn_Options.common_script_path.."COCKPIT_CYCLES/"

local dev = GetSelf()
make_default_activity(UPDATE_STEP)

for n = 1, SLOT_COUNT do
	dev:listen_command(CMD_DOWN + n)
	dev:listen_command(CMD_UP + n)
end

local function log_info(message)
	if log and log.write then
		log.write("COCKPIT_CYCLES", log.INFO, message)
	else
		print("COCKPIT_CYCLES: "..message)
	end
end

local function log_error(message)
	if log and log.write then
		log.write("COCKPIT_CYCLES", log.ERROR, message)
	else
		print("COCKPIT_CYCLES: ERROR: "..message)
	end
end

local settings = {}
local slots    = {} -- [n] = {short = action, long = action, held = bool, held_time = s, long_done = bool}
local actions  = {} -- every valid action, to keep the cycles in step
local releases = {} -- buttons pressed and not yet released: {button = button, time_left = s}
local queued   = {} -- buttons of a sequence still to press: {button = button, time_left = s}

local function describe_button(button)
	return string.format("%s (device %s, command %s, %s)",
		tostring(button.label), tostring(button.device), tostring(button.command), tostring(button.method))
end

-- A step is a button, or {sequence = {button, ...}, label = text}.
local function describe(step)
	if step.sequence then
		local names = {}
		for _, button in ipairs(step.sequence) do
			names[#names + 1] = describe_button(button)
		end
		return tostring(step.label).." ["..table.concat(names, ", ").."]"
	end
	return describe_button(step)
end

-- Returns an error text for a button the device cannot press, nil when it looks right.
local function check_button(button)
	if type(button) ~= "table" then
		return "not a button table"
	end
	if type(button.device) ~= "number" then
		return "no device number (a wrong name in devices.* gives nil)"
	end
	if type(button.command) ~= "number" then
		return "no command number (a wrong name in the command table gives nil)"
	end
	if button.method ~= "click" and button.method ~= "command" then
		return "method must be \"click\" or \"command\", not "..tostring(button.method)
	end
	return nil
end

-- Returns an error text for a step the device cannot press, nil when it looks right.
local function check_step(step)
	if type(step) == "table" and step.sequence ~= nil then
		if type(step.sequence) ~= "table" or #step.sequence == 0 then
			return "empty sequence"
		end
		for i, button in ipairs(step.sequence) do
			local problem = check_button(button)
			if problem then
				return "sequence button "..i.." ("..tostring(type(button) == "table" and button.label)..") "..problem
			end
		end
		return nil
	end
	return check_button(step)
end

-- Returns the action ready to run, or nil after writing why it cannot be used.
local function check_action(action, where)
	if action == nil then
		return nil
	end
	if type(action) ~= "table" then
		log_error(where..": not an action table, ignored")
		return nil
	end
	-- One action table shared by several slots: checked once, one cycle position for all.
	if action.checked ~= nil then
		log_info(where..": same as "..action.checked_where)
		return action.checked and action or nil
	end
	action.checked, action.checked_where = false, where
	local steps
	if action.cycle ~= nil then
		if type(action.cycle) ~= "table" or #action.cycle == 0 then
			log_error(where..": empty cycle, ignored")
			return nil
		end
		steps = action.cycle
	elseif action.press ~= nil then
		steps = {action.press}
	else
		log_error(where..": neither cycle nor press, ignored")
		return nil
	end
	for i, step in ipairs(steps) do
		local problem = check_step(step)
		if problem then
			log_error(where..": step "..i.." ("..tostring(type(step) == "table" and step.label)..") "..problem..", action ignored")
			return nil
		end
	end
	action.position = 0
	action.checked = true
	actions[#actions + 1] = action
	local names = {}
	for _, step in ipairs(steps) do
		names[#names + 1] = describe(step)
	end
	log_info(where..": "..(action.cycle and "cycle " or "press ")..table.concat(names, " > "))
	return action
end

local function load_config()
	local entry = dofile(PATH.."aircraft.lua").find(LockOn_Options.script_path)
	if not entry then
		log_error("no entry in aircraft.lua for "..tostring(LockOn_Options.script_path))
		return
	end
	local ok, config = pcall(dofile, PATH.."config/"..entry.config)
	if not ok then
		log_error("config/"..entry.config.." failed: "..tostring(config))
		return
	end
	if type(config) ~= "table" then
		log_error("config/"..entry.config.." does not return a table")
		return
	end
	for name, value in pairs(DEFAULTS) do
		if config[name] == nil then
			settings[name] = value
		elseif type(config[name]) ~= type(value) then
			log_error(name.." must be a "..type(value)..", not "..tostring(config[name])..": "..tostring(value).." used")
			settings[name] = value
		else
			settings[name] = config[name]
		end
	end
	log_info(string.format("config/%s for %s: long press %.2f s, %s",
		entry.config, tostring(LockOn_Options.script_path), settings.long_press,
		tostring(config.description or "no description")))
	local configured = 0
	for n = 1, SLOT_COUNT do
		local slot_config = (config.slots or {})[n]
		if slot_config then
			local slot = {
				short = check_action(slot_config.short, "slot "..n.." short"),
				long  = check_action(slot_config.long, "slot "..n.." long"),
				held = false, held_time = 0, long_done = false,
			}
			if slot.short or slot.long then
				slots[n] = slot
				configured = configured + 1
			end
		end
	end
	log_info(configured.." slot(s) ready")
end

local function send(button, value)
	local target = GetDevice(button.device)
	if not target then
		return false, "no device "..tostring(button.device).." in this cockpit"
	end
	if button.method == "command" then
		return pcall(function() target:SetCommand(button.command, value) end)
	end
	return pcall(function() target:performClickableAction(button.command, value) end)
end

local function release(index)
	local pending = table.remove(releases, index)
	local ok, problem = send(pending.button, 0)
	if not ok then
		log_error("releasing "..describe_button(pending.button).." failed: "..tostring(problem))
	end
end

local function press_button(button)
	-- Pressed again before being released: release it first.
	for i = #releases, 1, -1 do
		local pending = releases[i].button
		if pending.device == button.device and pending.command == button.command then
			release(i)
		end
	end
	local ok, problem = send(button, 1)
	if not ok then
		log_error("pressing "..describe_button(button).." failed: "..tostring(problem))
		return false
	end
	releases[#releases + 1] = {button = button, time_left = settings.release_after}
	return true
end

-- Presses a step: its first button now, the other buttons of a sequence later, from update().
-- While a sequence is still running on the same device, the new step waits for its end,
-- sequence_step after its last button. Cutting it short would leave the device halfway: on
-- the AH-64D, a menu opened by M, where pressing M again opens DMS instead.
local function press(step)
	local buttons = step.sequence or {step}
	local wait = nil
	for _, pending in ipairs(queued) do
		if pending.button.device == buttons[1].device and (wait == nil or pending.time_left > wait) then
			wait = pending.time_left
		end
	end
	if wait then
		wait = wait + settings.sequence_step
		for i, button in ipairs(buttons) do
			queued[#queued + 1] = {button = button, time_left = wait + (i - 1) * settings.sequence_step}
		end
		log_info("device "..tostring(buttons[1].device).." busy with a sequence: "..describe(step)..string.format(" in %.2f s", wait))
		return true
	end
	if not press_button(buttons[1]) then
		return false
	end
	for i = 2, #buttons do
		queued[#queued + 1] = {button = buttons[i], time_left = (i - 1) * settings.sequence_step}
	end
	return true
end

local function same_step(a, b)
	if a == b then
		return true
	end
	return not a.sequence and not b.sequence and a.device == b.device and a.command == b.command
end

-- Moves every other cycle holding the step to it.
local function follow(step, source)
	for _, action in ipairs(actions) do
		if action ~= source and action.cycle then
			for i, other in ipairs(action.cycle) do
				if same_step(other, step) then
					action.position = i
					break
				end
			end
		end
	end
end

local function run(n, kind)
	local slot = slots[n]
	local action = slot[kind]
	if not action then
		return
	end
	local step
	if action.cycle then
		action.position = action.position % #action.cycle + 1
		step = action.cycle[action.position]
	else
		step = action.press
	end
	local ok = press(step)
	if ok then
		follow(step, action)
	end
	local text = string.format("slot %d %s (held %.2f s): %s%s", n, kind, slot.held_time,
		describe(step), ok and "" or " FAILED")
	log_info(text)
	if settings.show_messages then
		print_message_to_user("Cockpit cycles: "..tostring(step.label)..(ok and "" or " (failed, see dcs.log)"))
	end
end

local function on_down(n)
	local slot = slots[n]
	if not slot then
		log_info("slot "..n.." pressed, no action for this aircraft")
		return
	end
	-- Already held: its release was lost (focus lost while holding the key, say). Take this
	-- press as a new one rather than ignore it.
	slot.held = true
	slot.held_time = 0
	if slot.long then
		slot.long_done = false
	else
		slot.long_done = true
		run(n, "short")
	end
end

local function on_up(n)
	local slot = slots[n]
	if not slot or not slot.held then
		return
	end
	slot.held = false
	if not slot.long_done then
		run(n, "short")
	end
end

function post_initialize()
	local ok, problem = pcall(load_config)
	if not ok then
		log_error("loading the config failed: "..tostring(problem))
	end
end

function SetCommand(command, value)
	if command > CMD_DOWN and command <= CMD_DOWN + SLOT_COUNT then
		on_down(command - CMD_DOWN)
	elseif command > CMD_UP and command <= CMD_UP + SLOT_COUNT then
		on_up(command - CMD_UP)
	end
end

function update()
	for n, slot in pairs(slots) do
		if slot.held and not slot.long_done then
			slot.held_time = slot.held_time + UPDATE_STEP
			if slot.held_time >= settings.long_press then
				slot.long_done = true
				run(n, "long")
			end
		end
	end
	for i = #releases, 1, -1 do
		local pending = releases[i]
		pending.time_left = pending.time_left - UPDATE_STEP
		if pending.time_left <= 0 then
			release(i)
		end
	end
	-- After the releases, so that the previous button of a sequence is released first (with
	-- sequence_step longer than release_after). Due buttons are taken out of the queue, then
	-- pressed in their order.
	local due = {}
	for i = #queued, 1, -1 do
		local pending = queued[i]
		pending.time_left = pending.time_left - UPDATE_STEP
		if pending.time_left <= 0 then
			table.insert(due, 1, table.remove(queued, i))
		end
	end
	for _, pending in ipairs(due) do
		local ok = press_button(pending.button)
		log_info("sequence: "..describe_button(pending.button)..(ok and "" or " FAILED"))
	end
end

need_to_be_closed = false
