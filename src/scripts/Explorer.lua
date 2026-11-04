-- This is the name of this script, which may be different to the package name
-- which is why we want to have a specific identifier for events that only
-- concern this script and not the package as a whole, if it is included
-- in other packages.
local script_name = "Explorer"
local package_name = "__PKGNAME__"

-- Bootstrap the bundled Glu engine. This is loaded from the package's own
-- resource directory, so make sure that directory is searchable by require()
-- before we ask for it. Doing this defensively means a load failure reports a
-- clear, single error here instead of cascading into misleading
-- "attempt to index global 'Explorer'" errors from every alias and handler.
local _g
do
  local home = getMudletHomeDir():gsub("\\", "/")
  local search = home .. "/?.lua"
  if not package.path:find(search, 1, true) then
    package.path = package.path .. ";" .. search
  end

  local ok, result = pcall(function()
    return require("__PKGNAME__/vendor/Glu-single")(package_name)
  end)

  if not ok or not result then
    cecho(f "<orange_red>[{script_name}] Failed to load the bundled Glu engine; the package cannot start.\n")
    cecho(f "<orange_red>[{script_name}] {tostring(result)}\n")
    return
  end

  _g = result
end

---@class Explorer
---@field areas table                 -- A table of areas remaining to be
---                                      explored
---@field config table                -- Configuration table
---@field default table               -- Default values for preferences
---@field event_handlers string[]     -- Table of event handlers to register
---@field exit_expand table           -- Lookup table for short direction to
---                                      full
---@field exit_short table            -- Lookup table for full direction to
---                                      short
---@field exploring boolean           -- Whether we are currently exploring
---@field ignore table                -- Table of stubs to ignore, by room id.
---                                      This is prefs.ignore, so it is saved
---                                      and kept between runs.
---@field stats_label table           -- Handle to the stats overlay for the
---                                      map
---@field stats_label_arguments table -- Values to use when creating the stats
---                                      label
---@field prefs table                 -- Table to hold user preferences
---@field previous_area string        -- The last area we were in
---@field status table                -- Table to hold current status
---@field stub_map table              -- Lookup table for Mudlet stubs both
---                                      number and string
---@field stub_to_check table         -- Table to hold stub to check, used to
---                                      hold current state and verification
---@field todo table                  -- Table to hold todo list for the current
---                                      exploration decision
---@field debug boolean               -- Whether to print debug messages
---@field g table                     -- Instance of Glu
Explorer = Explorer or {
  config = {
    name = script_name,
    package_name = "__PKGNAME__",
    package_path = getMudletHomeDir() .. "/__PKGNAME__/",
    preferences_file = f[[{script_name}.Preferences.lua]],
  },
  default = {
    zoom = 10,
    speed = 0,
    timeout = 5,
    stats = true,
    ignore = {},
  },
  prefs = {},
  stub_map = {
    north = 1,        northeast = 2,      northwest = 3,      east = 4,
    west = 5,         south = 6,          southeast = 7,      southwest = 8,
    up = 9,           down = 10,          ["in"] = 11,        out = 12,
    [1] = "north",    [2] = "northeast",  [3] = "northwest",  [4] = "east",
    [5] = "west",     [6] = "south",      [7] = "southeast",  [8] = "southwest",
    [9] = "up",       [10] = "down",      [11] = "in",        [12] = "out",
  },
  exit_expand = {
    n = "north",      ne = "northeast", nw = "northwest", e = "east",
    w = "west",       s = "south",      se = "southeast", sw = "southwest",
    u = "up",         d = "down",       ["in"] = "in",    out = "out",
    up = "up",        down = "down",
  },
  exit_short = {
    north = "n",    northeast = "ne", northwest = "nw", east = "e",
    west = "w",     south = "s",      southeast = "se", southwest = "sw",
    up = "up",      down = "down",    ["in"] = "in",    out = "out",
  },
  event_handlers = {
    "sysLoadEvent",
    "sysInstall",
    "sysUninstall",
    "sysDisconnectionEvent",
    "sysSpeedwalkStarted",
    "sysSpeedwalkFinished",
    "sysSpeedwalkPaused",
    "sysSpeedwalkStopped",
    "onSpeedwalkReset",
    "onSpeedwalkFailed",
    "onMoveMap",
    -- For the map label
    "onExplorationStarted",
    "onExplorationStopped",
    "onStubIgnored",
    "onExploreDirection",
    "onDirectionExplored",
    "onDoorChange",
  },
  areas = {},
  exploring = nil,
  ignore = {},
  previous_area = nil,
  status = { start = nil, dest = nil, speedwalking = false, },
  stub_to_check = { room_id = nil, stub = nil },
  todo = {},
  stats_label = nil,
  stats_label_arguments = {
    fgRed = 255, fgGreen = 215, fgBlue = 0,
    foregroundTransparency = 255,
    bgRed = 0, bgGreen = 0, bgBlue = 0,
    backgroundTransparency = 175,
    zoom = 25,
    fontName = "Ubuntu", fontSize = 10,
    showOnTop = true,
    noScaling = true,
    temporary = true
  },
  timers = {},
  debug = false,
  g = _g,
}

-- For debugging
local function d(text, colour)
  if _d and Explorer.debug then
    _d(text, { colour = colour or "medium_aquamarine", skip = 1 })
  end
end

function Explorer:Setup(event, package, ...)
  if package and package ~= self.config.package_name then
    return
  end

  -- Let Glu's dependency queue handle the Helper dependency. It filters out
  -- already-installed packages, installs the rest in order, and reports back
  -- through the callback. It returns nothing when there is nothing to install.
  local dependencies = {
    {
      name = "Helper",
      url = "https://github.com/gesslar/Helper/releases/latest/download/Helper.mpackage",
    },
  }

  local queue = self.g.dependency_queue(dependencies, function(success, message)
    -- We were uninstalled while the dependency was downloading.
    if not self.config then return end

    if not success then
      -- f reads locals on the stack, and this runs after the method has returned.
      local name = self.config.name
      cecho(f "<orange_red>[{name}] {message}\n")
      return
    end

    -- The welcome prints through Helper, so it waits until Helper is installed.
    -- A named timer, so that uninstalling cancels it. Uninstalling also wipes self,
    -- which this would otherwise still try to use, such as in a quick reinstall.
    if event == "sysInstall" then
      self:EnableTimer("Welcome", 1, function()
        echo("\n")
        cecho("<gold>Welcome to <b>"..self.config.name.."</b>!<reset>\n")
        echo("\n")
        helper.print({
          text = self.help.topics.usage,
          styles = self.help_styles
        })
      end)
    end
  end)

  if queue then
    queue.start()
  end

  self:LoadPreferences()
end

function Explorer:LoadPreferences()
  -- Store prefs at the profile root (nil package) rather than inside the
  -- package directory, which Mudlet wipes on package reinstall/upgrade.
  self.prefs = self.g.preferences.load(
    nil, self.config.preferences_file, self.default
  )
  self.ignore = self.prefs.ignore
end

function Explorer:SavePreferences()
  self.g.preferences.save(
    nil, self.config.preferences_file, self.prefs
  )
end

function Explorer:SetPreference(key, value)
  if not self.prefs then
    self.prefs = {}
  end

  if key == "zoom" then
    value = tonumber(value)
    if value == nil then return end
    if value < 3 then value = 3 end
  elseif key == "speed" then
    value = tonumber(value)
    if value == nil then return end
    if value < 0.0 then value = 0.0 end
  elseif key == "timeout" then
    value = tonumber(value)
    if value == nil then return end
    if value < 0.1 then value = 0.1 end
  elseif key == "stats" then
    d(f"key = {key}, value = {value}")
    if value == "true" then
      value = true
    elseif value == "false" then
      value = false
    else
      value = self.default.stats
    end
  else
    cecho("Unknown preference " .. key .. "\n")
    return
  end

  self.prefs[key] = value
  self:SavePreferences()
  self:LoadPreferences()
  cecho("Preference " .. key .. " set to " .. tostring(self.prefs[key]) .. ".\n")
end

function Explorer:IdentifyRoomsToExplore()
  self.todo = {}

  local current_room = getPlayerRoom()
  if not current_room then return end
  local current_area = getRoomArea(current_room)
  if not current_area then return end

  -- Populate areas with all known areas by the mapper
  self:UpdateAreas()

  d(f"Current area = {tostring(current_area)}")
  d(f"Previous area = {tostring(self.previous_area)}")
  if not self.previous_area then self.previous_area = current_area end

  -- Keep looking for valid rooms to explore across areas
  local test_area = self.previous_area
  -- local test_area = current_area
  while table.size(self.todo) == 0 and self:CountValidAreas() > 0 do
    if self.areas[tostring(test_area)] == true then
      -- Get rooms in the current area and find valid ones to explore
      local room_ids = self.g.table.values(getAreaRooms(test_area) or {})

      for _, room_id in ipairs(room_ids) do
        local valid_stubs = self:GetValidStubs(room_id) or {}
        if #valid_stubs > 0 then
          -- We have valid stubs, so we can add the room to the todo list.
          self.todo[#self.todo+1] = room_id
        end
      end
    end

    if #self.todo == 0 then
      self.areas[tostring(test_area)] = false
      ---@diagnostic disable-next-line: cast-local-type
      test_area = self:GetNextArea()
      if not test_area then
        cecho("<deep_pink>No more areas to explore. Stopping exploration.\n")
        return
      end
    else
      self.previous_area = test_area
      break
    end
  end
end

function Explorer:UpdateAreas()
  local areas = getAreaTable() or {}

  for _, area_id in pairs(areas) do
    -- Exclude areas with area_id of -1 ("Default Area")
    if area_id ~= -1 then
      local area_str = tostring(area_id)
      -- Add the area_id to self.areas if it's not already present
      if self.areas[area_str] == nil then
        self.areas[area_str] = true
      end
    end
  end
end

function Explorer:GetValidAreas()
  local valid = {}
  for area_id, state in pairs(self.areas) do
    if state == true then
      valid[#valid+1] = tonumber(area_id)
    end
  end
  return valid
end

function Explorer:GetNextArea()
  local valid_areas = self:GetValidAreas()
  if #valid_areas == 0 then return nil end
  return valid_areas[1]
end

-- Count the number of areas still valid for exploration
function Explorer:CountValidAreas()
  return #self:GetValidAreas()
end

function Explorer:ResetState()
  self.status = { dest = nil, start = nil, stub = nil, speedwalking = false }
  self.exploring = false
  self.todo = {}
  self.previous_area = nil
  self.areas = {}
  self.stub_to_check = nil
end

function Explorer:Explore()
  ---@diagnostic disable-next-line: undefined-global
  if not mudlet or (mudlet and not mudlet.mapper_script) then
    cecho("<red>This script requires the Map Script package to be enabled.\n")
    return
  end

  -- If we are already exploring, return.
  if self.exploring then
    echo("Already exploring. Returning.\n")
    return
  end

  -- Reset the state.
  self:ResetState()

  self.exploring = true

  cecho("\n<green>Exploration started.\n")

  raiseEvent("onExplorationStarted")

  self:ScheduleNextMove()
end

-- Stop exploring and reset the state.
function Explorer:StopExplore(canceled, silent)
  d("StopExplore called")
  local walking = self.status.walk_started

  self:ResetState()

  if not silent then
    if canceled then
      cecho("\n<red>Exploration canceled.\n")
    else
      cecho("\n<green>Exploration stopped.\n")
    end
  end

  deleteAllNamedTimers(self.config.name)

  -- End the walk we started. Left open, Carto refuses the next walk and treats
  -- the next room update as veering off the path, which stops the next run.
  if walking and Carto and Carto.walking then
    Carto:ResetWalking(true, "Exploration stopped.")
  elseif walking and type(map) == "table" and map.stopSpeedwalk then
    map.stopSpeedwalk()
  end

  raiseEvent("onExplorationStopped", canceled, silent)
end

function Explorer:DetermineNextRoom()
  if (self.status and self.status.speedwalking) or not self.exploring then
    return
  end

  local current_room = getPlayerRoom()
  if not current_room then
    cecho("<red>Could not determine your current room.\n")
    self:StopExplore(true, false)
    return
  end
  local current_area = getRoomArea(current_room)
  raiseEvent("onDetermineNextRoom", current_room, current_area)

  self:IdentifyRoomsToExplore()

  if self.exploring and #self.todo == 0 then
    cecho("\n<medium_sea_green>Exploration complete.\n")
    if not table.is_empty(self.ignore) then
      cecho("\n<royal_blue>The following exit stubs were ignored:\n")
      self:PrintIgnored()
    end
    self:StopExplore(false, false)
    return
  end

  local stubs = self:GetValidStubs(current_room) or {}

  d(f"Valid stubs for room {current_room}:")
  for _, stub in ipairs(stubs) do
    d(f"Stub {stub} -> {self.stub_map[tonumber(stub)]}")
  end

  if self.previous_area == current_area and #stubs > 0 then -- we have unexplored stubs in our current room
    local stub = stubs[1]
    local direction = self.stub_map[stub]
    if not direction then
      cecho("<red>Could not get direction for stub " .. stub .. "\n")
      self:StopExplore(true)
      return
    end

    -- Do we have a door in this direction?
    d(f"Checking for a door in the {direction} direction in room {current_room}\n")
    local doors = getDoors(current_room) or {}
    for k, v in pairs(doors) do
      d(f"  door {k} = {v}")
    end
    if #doors == 0 then
      d("No doors in room " .. current_room .. "\n")
    end
    local dir_short = self.exit_short[direction]
    if dir_short then
      -- An open door isn't in the way, so it's the same as having no door.
      if doors[dir_short] and doors[dir_short] ~= 1 then
        cecho(f"<red>Door in the way of {direction} ({dir_short})\n")
        self.status = {
          dest = nil,
          start = current_room,
          stub = stub,
          speedwalking = false,
          door = dir_short,
        }
        d(f"Door in the way of {direction} ({dir_short})\n")
        self:EnableTimer("Check Door", self.prefs.timeout, function() self:CheckDoor() end)

        send(f"open {direction} door", true)
        return
      end
    end
    d(f"No door leading {direction} in room {current_room}\n")
    self.status = {
      dest = nil,
      start = current_room,
      stub = stub,
      speedwalking = false,
    }

    cecho(f"<yellow>Exploring the {direction} exit from {current_room} ({getRoomName(current_room)})\n")
    raiseEvent("onNextRoomDetermined", current_room, current_area)

    self.stub_to_check = { room_id = current_room, stub = stub }

    -- We sent a direction, so we need to arrive before this timer fires.
    -- Arrived cancels it through CheckStub. If it does fire, we didn't get
    -- there and exploration stops.
    d(f"Expecting arrival within {self.prefs.timeout} seconds")
    self:EnableTimer("Check Stub", self.prefs.timeout, function() self:MoveTimedOut() end)

    ---@diagnostic disable-next-line: redundant-parameter
    raiseEvent("onExploreDirection", current_room, direction, stub)
    send(direction, true)
  else
    d("self.status")
    for k, v in pairs(self.status) do
      d(f"  {k} = {v}")
    end
    self.stub_to_check = nil
    local next_room = self:FindCandidateRoom()
    d("next_room = " .. tostring(next_room))
    if not next_room then
      cecho("<red>Could not find next room.\n")
      self:StopExplore(true, false)
      return
    end
    self.status = {
      dest = next_room,
      start = current_room,
      stub = nil,
      speedwalking = true,
    }

    local next_area = getRoomArea(next_room)
    raiseEvent("onNextRoomDetermined", next_room, next_area)

    cecho(f"<yellow>Traveling to room {next_room} from {current_room}\n")
    -- A named timer, so that stopping exploration cancels it.
    self:EnableTimer("Start Speedwalk", self:MoveDelay(), function()
      -- Armed first, so that if anything below fails, the timer still ends this.
      self:ArmSpeedwalkTimeout()

      -- Until now, any walk going on is somebody else's. Set before asking, as a
      -- mapper can finish before gotoRoom returns if it just sends everything.
      self.status.walk_started = true

      -- A mapper reports that it couldn't start before gotoRoom returns. Anything
      -- it reports at any other time is about somebody else's walk.
      self.status.walk_starting = true
      local found = gotoRoom(next_room)
      self.status.walk_starting = false

      -- With no path, the mapper is never asked to walk, so it reports nothing.
      if not found and self.exploring then
        self:StopWalkNotStarted("No path found.")
      end
    end)
  end
end

-- Stop exploring because a move did not take us to a new room.
function Explorer:StopBlocked(room_id, stub)
  local direction = self.stub_map[tonumber(stub)]
  cecho(f"<red>Could not move {direction} from room {room_id}. Stopping exploration.\n")
  self:StopExplore(true, false)
end

-- Stop exploring because a speedwalk did not take us to its destination.
function Explorer:StopSpeedwalkFailed()
  local dest = self.status.dest
  local room_id = getPlayerRoom()
  cecho(f"<red>Speedwalk to room {dest} ended in room {room_id}. Stopping exploration.\n")
  self:StopExplore(true, false)
end

-- Stop exploring because our speedwalk never started. Any walk still running
-- isn't ours, so this leaves it alone.
function Explorer:StopWalkNotStarted(reason)
  local dest = self.status.dest

  self.status.walk_started = false
  cecho(f"<red>Could not walk to room {dest}: {reason} Stopping exploration.\n")
  self:StopExplore(true, false)
end

-- Restart the speedwalk's timer. Every room change during the walk restarts this.
-- Carto times its own steps and raises onSpeedwalkReset when one fails, and has a
-- setting for how long that is. Other mappers, such as generic_mapper, raise
-- nothing when a step is blocked, so this is how we find out.
function Explorer:ArmSpeedwalkTimeout()
  if Carto then return end

  self:EnableTimer("Speedwalk Timeout", self:MapperStepDelay() + self.prefs.timeout, function()
    if self.status.speedwalking then self:StopSpeedwalkFailed() end
  end)
end

-- The longest generic_mapper waits between steps. speedwalk_random adds up to the
-- delay again.
function Explorer:MapperStepDelay()
  local configs = type(map) == "table" and map.configs
  if not configs then return 0 end

  local delay = configs.speedwalk_delay or 0

  return configs.speedwalk_random and delay * 2 or delay
end

-- We are done speedwalking, so we can determine the next room to explore.
function Explorer:SpeedwalkArrived()
  deleteNamedTimer(self.config.name, "Speedwalk Timeout")
  self.status.speedwalking = false
  self.status.walk_started = false
  self:ScheduleNextMove()
end

-- We sent a direction and never arrived.
function Explorer:MoveTimedOut()
  local check = self.stub_to_check
  if not check or not check.stub then return end

  self:StopBlocked(check.room_id, check.stub)
end

-- Called on arrival. Cancels the arrival timer and looks for the stub in the
-- room that we have left. If it is still a stub, then the move didn't go where
-- we sent it, so exploration stops.
function Explorer:CheckStub()
  if not self.stub_to_check then return true end

  local room_id, stub = self.stub_to_check.room_id, self.stub_to_check.stub
  d(f"Checking for stub {stub} ({self.stub_map[tonumber(stub)]}) in room {room_id}")

  self:DisableTimer("Check Stub")

  if not room_id or not stub then return true end
  local check_stubs = getExitStubs1(room_id) or {}
  local cs = table.concat(check_stubs, ",")
  if table.is_empty(check_stubs) then return true end

  self.stub_to_check = { room_id = nil, stub = nil }
  d(f"Stub for this room {room_id}")
  d(cs)
  if table.index_of(check_stubs, stub) then
    d(f"Stub {stub} ({self.stub_map[tonumber(stub)]}) is still a stub, stopping")
    self:StopBlocked(room_id, stub)
    return false
  end

  return true
end

function Explorer:CheckDoor()
  d("CheckDoor")

  self:DisableTimer("Check Door")

  local room_id = self.status.start
  local dir_short = self.status.door

  if not room_id or not dir_short then return end

  local doors = getDoors(room_id) or {}

  -- We suddenly don't have a door anymore? ??? ???
  local door_status = doors[dir_short]
  if door_status == nil then
    cecho(f"<red>[CheckDoor] No {dir_short} door in room {room_id} has vanished!\n")
    self:DetermineNextRoom()
    return
  end

  d(f"The {dir_short} door in room {room_id} is {door_status}")

  -- Whew, we still have the door. Let's check its status to see if it
  -- is open yet.
  if door_status ~= 1 then
    -- Oh well, was this a stub? If so, let's ignore it and move on.
    local stub = self.status.stub
    if stub then
      d(f"Ignoring stub {stub} in room {room_id} because it is still closed.")
      self:IgnoreStub(room_id, stub)
    end
    self:DetermineNextRoom()
    return
  end

  -- Ok, the door is open. We can move through it.
  local dir_full = self.exit_expand[dir_short]

  self.status = {
    dest = nil,
    start = getPlayerRoom(),
    stub = self.status.stub,
    speedwalking = false,
  }
  self.stub_to_check = { room_id = room_id, stub = self.status.stub }
  self:EnableTimer("Check Stub", self.prefs.timeout, function() self:MoveTimedOut() end)

  self.dir_start = getEpoch()

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onExploreDirection", room_id, dir_full, self.status.stub)
  send(dir_full, true)
end

-- Returns false if the stub was already ignored.
function Explorer:IgnoreStub(room_id, stub)
  local rid = tostring(room_id)

  if not self.ignore[rid] then self.ignore[rid] = {} end
  if table.index_of(self.ignore[rid], stub) then return false end

  table.insert(self.ignore[rid], stub)
  self:SavePreferences()

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onStubIgnored", room_id, stub, self.stub_map[tonumber(stub)])

  return true
end

-- Returns false if the stub wasn't ignored.
function Explorer:UnignoreStub(room_id, stub)
  local rid = tostring(room_id)
  local index = self.ignore[rid] and table.index_of(self.ignore[rid], stub)

  if not index then return false end

  table.remove(self.ignore[rid], index)
  if #self.ignore[rid] == 0 then self.ignore[rid] = nil end
  self:SavePreferences()

  return true
end

-- Turn what was typed into a room and a stub. The room defaults to the one we
-- are in. It can be given because a move that fails can leave us somewhere other
-- than the room with the stub.
function Explorer:ResolveStub(direction, room)
  local name = (direction or ""):lower()
  name = self.exit_expand[name] or name

  local stub = self.stub_map[name]
  if not stub then
    cecho(f"<red>Unknown direction '{direction}'.\n")
    return
  end

  local room_id
  if room and room ~= "" then
    room_id = tonumber(room)
  else
    room_id = getPlayerRoom()
  end

  if not room_id then
    cecho("<red>Could not determine which room you mean.\n")
    return
  end

  return room_id, stub, name
end

function Explorer:IgnoreDirection(direction, room)
  local room_id, stub, name = self:ResolveStub(direction, room)
  if not room_id then return end

  if not table.index_of(getExitStubs1(room_id) or {}, stub) then
    cecho(f"<orange>Room {room_id} has no {name} exit stub.\n")
  elseif self:IgnoreStub(room_id, stub) then
    cecho(f"<green>Ignoring the {name} exit stub in room {room_id}.\n")
  else
    cecho(f"<orange>The {name} exit stub in room {room_id} is already ignored.\n")
  end
end

function Explorer:UnignoreDirection(direction, room)
  local room_id, stub, name = self:ResolveStub(direction, room)
  if not room_id then return end

  if self:UnignoreStub(room_id, stub) then
    cecho(f"<green>No longer ignoring the {name} exit stub in room {room_id}.\n")
  else
    cecho(f"<orange>The {name} exit stub in room {room_id} is not ignored.\n")
  end
end

function Explorer:PrintIgnored()
  for room_id, stubs in pairs(self.ignore) do
    -- The list outlives the map, so the room may have been deleted since.
    local room_name = getRoomName(tonumber(room_id)) or "unknown"
    for _, stub in ipairs(stubs) do
      echo("  Room " .. room_id .. " (" .. room_name .. ") " ..
        "-> " .. stub .. " (" .. self.stub_map[tonumber(stub)] .. ")\n")
    end
  end
end

function Explorer:ListIgnored()
  if table.is_empty(self.ignore) then
    echo("No exit stubs are being ignored.\n")
    return
  end

  echo("Ignored exit stubs:\n")
  self:PrintIgnored()
end

function Explorer:GetValidStubs(room_id)
  local stub_status = self:GetStubStatus(room_id)
  local valid_stubs = {}
  for stub, status in pairs(stub_status) do
    if status then
      valid_stubs[#valid_stubs + 1] = stub
    end
  end
  return valid_stubs
end

function Explorer:GetStubStatus(room_id)
  local stubs = getExitStubs1(room_id) or {}
  local result = {}

  local room_str = tostring(room_id)
  if self.ignore[room_str] then
    for _, stub in ipairs(stubs) do
      result[stub] = not table.index_of(self.ignore[room_str], stub)
    end
  else
    for _, stub in ipairs(stubs) do
      result[stub] = true
    end
  end

  return result
end

function Explorer:ScheduleNextMove()
  if not self.exploring then return end
  if self.status.speedwalking == true then return end

  self.dir_start = getEpoch()
  self:EnableTimer("Determine Next Room", self:MoveDelay(), function()
    self:DetermineNextRoom()
  end)
end

-- How long to wait before a move. A speed of 0 still waits a moment.
function Explorer:MoveDelay()
  local speed = self.prefs.speed

  return speed ~= 0 and speed or 0.025
end

-- Find the closest room on the todo list. IdentifyRoomsToExplore has just built
-- that list, so every room on it has a stub to explore.
function Explorer:FindCandidateRoom()
  local room_id = getPlayerRoom()
  if not room_id then return nil end

  local cheapest_room, cheapest_cost = nil, math.huge

  for _, candidate in ipairs(self.todo) do
    local found, cost = getPath(room_id, candidate)
    if found and cost > -1 and cost < cheapest_cost then
      cheapest_room, cheapest_cost = candidate, cost
    end
  end

  d(f"Cheapest path from {room_id} is to room {tostring(cheapest_room)}, cost {cheapest_cost}")

  return cheapest_room
end

function Explorer:Arrived(event, current_room_id)
  if not self.exploring then return end

  d(f"event = {event}")

  self:UpdateLabel()

  -- We haved moved into a new room
  if event == "onMoveMap" then
    -- We are speedwalking, so this only shows that the walk is still going.
    if self.status.speedwalking == true then
      if self.status.walk_finished and current_room_id == self.status.dest then
        self:SpeedwalkArrived()
      elseif self.status.walk_started then
        self:ArmSpeedwalkTimeout()
      end
      return
    end
    -- We are waiting on a door check
    if self.status.door then return end
  elseif event == "onDoorChange" then
    return
  elseif event == "sysSpeedwalkFinished" then
    if not self.status.walk_started then return end

    if getPlayerRoom() == self.status.dest then
      self:SpeedwalkArrived()
      return
    end

    -- Carto raises this when a walk is over, so being elsewhere means it failed.
    if Carto then
      self:StopSpeedwalkFailed()
      return
    end

    -- generic_mapper raises this when it has sent the last step, which hasn't
    -- landed yet. The timer decides if it ever does.
    self.status.walk_finished = true
    self:ArmSpeedwalkTimeout()
    return
  end

  -- An update for the room we tried to leave. With the stub still there, the
  -- move may just be on its way, so the arrival timer decides. With the stub
  -- gone, the exit was mapped back to this room, and that counts as arriving.
  if self.status.stub and current_room_id == self.status.start then
    local stubs = getExitStubs1(current_room_id) or {}
    if table.index_of(stubs, self.status.stub) then return end
  end

  -- This basically serves to stop the timer so that it doesn't go off.
  -- We did arrive, so clearly we were not blocked. It shouldn't return true,
  -- because we moved.
  d(f"Checking stub {self.stub_map[self.status.stub]} ({self.status.stub}) for room {current_room_id}")
  if self:CheckStub() == false then
    return
  end
  d(f"Stub {self.stub_map[self.status.stub]} ({self.status.stub}) is not a stub, continuing")

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onDirectionExplored", current_room_id, self.status.start, self.stub_map[self.status.stub])

  local area_id = getRoomArea(current_room_id)
  if area_id then
    setMapZoom(math.max(3, self.prefs.zoom or self.default.zoom))
    -- setGridMode(area_id, true)
  end

  -- If we wanted into a new area, we want to return to the previous area.
  -- DetermineNextRoom calls IdentifyRoomsToExplore, which will return
  -- to the previous area if we have haven't explored it all.
--[[
  if area_id ~= self.previous_area then
    self:DetermineNextRoom()
    return
  end
]]
  -- If we have no valid stubs, we can remove the room from the todo list.
  local valid_stubs = self:GetValidStubs(current_room_id) or {}

  if #valid_stubs == 0 then
    local index = table.index_of(self.todo, current_room_id)
    if index then
      table.remove(self.todo, index)
    end
  end

  -- Determine the next room to explore and start moving there.
  d("Scheduling next move")
  self:ScheduleNextMove()
end

function Explorer:Reset(event, exception, reason)
  if not self.exploring then return end

  if exception and self.status.walk_started then self:StopExplore(true, false) end
end

function Explorer:SpeedwalkStarted(event)
  if not self.exploring then return end

  cecho(f"<yellow>Speedwalking started from {self.status.start} to {self.status.dest}\n")
end

-- While a walk is paused the character can go elsewhere, and resuming finds a new
-- path from there, so we can't count on where it ends up or when.
function Explorer:SpeedwalkPaused()
  if not self.exploring or not self.status.walk_started then return end

  cecho("<red>The speedwalk was paused. Stopping exploration.\n")
  self:StopExplore(true, false)
end

-- The mapper couldn't start a walk. Somebody else trying to walk during ours gets
-- this too, with "You are already walking!", and ours carries on.
function Explorer:SpeedwalkFailed(reason)
  if not self.exploring or not self.status.walk_starting then return end

  self:StopWalkNotStarted(reason)
end

-- Somebody stopped the walk we are waiting on.
function Explorer:SpeedwalkStopped()
  if not self.exploring or not self.status.walk_started then return end

  cecho("<red>The speedwalk was stopped. Stopping exploration.\n")
  self:StopExplore(true, false)
end

-- Process uninstallation tasks.
function Explorer:Uninstall(event, package)
  if package ~= self.config.package_name then
    return
  end

  if self.exploring then self:StopExplore(false, false) end

  deleteAllNamedEventHandlers(self.config.name)
  deleteAllNamedTimers(self.config.name)

  for k in pairs(self) do
    self[k] = nil
  end

---@diagnostic disable-next-line: assign-type-mismatch
  Explorer = nil
end

function Explorer:Disconnect(event)
  if self.exploring == true then self:StopExplore(false, false) end
end

function Explorer:EventHandler(event, ...)
  if event == "sysLoadEvent" or event == "sysInstall" then
    self:Setup(event, ...)
  elseif event == "onMoveMap" then
    self:Arrived(event, ...)
  elseif event == "sysSpeedwalkStarted" then
    self:SpeedwalkStarted(event)
  elseif event == "sysSpeedwalkFinished" then
    self:Arrived(event, ...)
  elseif event == "sysSpeedwalkPaused" then
    self:SpeedwalkPaused()
  elseif event == "sysSpeedwalkStopped" then
    self:SpeedwalkStopped()
  elseif event == "onSpeedwalkReset" then
    self:Reset(event, ...)
  elseif event == "onSpeedwalkFailed" then
    self:SpeedwalkFailed(...)
  elseif event == "sysUninstall" then
    self:Uninstall(event, ...)
  elseif event == "sysDisconnectionEvent" then
    self:Disconnect(event)
  elseif event == "onStubIgnored" then
    self:StubIgnored(...)
  elseif event == "onExploreDirection" then
    self:ExploreDirection(...)
  elseif event == "onDirectionExplored" then
    self:DirectionExplored(...)
  elseif event == "onExplorationStarted" then
    self:ExplorationStarted()
  elseif event == "onExplorationStopped" then
    self:ExplorationStopped(...)
  elseif event == "onDoorChange" then
    self:Arrived(event, ...)
    self:DoorChange(...)
  end
end

function Explorer:SetupEventHandlers()
  -- Registered event handlers
  local registered_handlers = getNamedEventHandlers(self.config.name) or {}
  -- Register persistent event handlers
  for _, event in ipairs(self.event_handlers) do
    local handler = self.config.name .. "." .. event
    if not registered_handlers[handler] then
      local result, err = registerNamedEventHandler(self.config.name, handler, event,
      function(...) self:EventHandler(...) end)
      if not result then
        cecho("<orange_red>Failed to register event handler for " .. event .. "\n")
      end
    end
  end
end

Explorer:SetupEventHandlers()

-- ----------------------------------------------------------------------------
-- Map label stuff
-- ----------------------------------------------------------------------------

function Explorer:DeleteMapLabel()
  if self.stats_label then
    deleteMapLabel(self.stats_label.area_id, self.stats_label.label_id)
    -- Mudlet reuses label ids, so this one could belong to another label later.
    self.stats_label = nil
  end
end

function Explorer:ExplorationStarted()
  self.explore_timings = {}
  self.explore_start = os.time()
  self:DeleteMapLabel()
  self:UpdateLabel()
end

function Explorer:ExplorationStopped(canceled, silent)
  self:DeleteMapLabel()
  self.exits_ignored = nil
  self.exits_explored = nil
end

function Explorer:StubIgnored(room_id, stub, direction)
  -- A stub can be ignored by hand between runs, when there is no label.
  if not self.exploring then return end

  self.exits_ignored = self.exits_ignored and self.exits_ignored + 1 or 1
  self:UpdateLabel()
end

function Explorer:CountStubs()
  local count = 0
  for _, room_id in ipairs(self.todo) do
    local stubs = self:GetValidStubs(room_id) or {}
    count = count + #stubs
  end
  return count
end

function Explorer:UpdateLabel()
  self:DeleteMapLabel()

  if self.prefs.stats == false then return end

  local room_id = getPlayerRoom()
  if not room_id then return end

  local area_id = getRoomArea(room_id)
  local x, y, z = getRoomCoordinates(room_id)

  local found = self.exits_explored and self.exits_explored or 0
  local ignore = self.exits_ignored and self.exits_ignored or 0
  local area_name = getRoomAreaName(area_id)
  local todo_count = #self.todo
  local todo_stubs = self:CountStubs()
  local started = self.explore_start
  local elapsed = os.time() - started

  local average = 0
  for _, timing in ipairs(self.explore_timings) do
    average = average + timing
  end

  if #self.explore_timings > 0 then
    average = average / #self.explore_timings
  end

  local average_string = string.format("%.3f", average)

  local text =
         f "{area_name} ({area_id})\n"
         .. f "Rooms to finish: {todo_count}\n"
         .. f "Exits to explore: {todo_stubs}\n"
         .. f "--------------------------\n"
         .. f "Exits explored: {found}\n"
         .. f "Exits ignored: {ignore}\n"
         .. f "Exploration time: {self.g.date.shms(elapsed, true)}\n"
         .. f "Average speed: {average_string}s"

  local map_label_id =
      createMapLabel(area_id,
        text,
        x, y, z,
        self.stats_label_arguments.fgRed,
        self.stats_label_arguments.fgGreen,
        self.stats_label_arguments.fgBlue,
        self.stats_label_arguments.bgRed,
        self.stats_label_arguments.bgGreen,
        self.stats_label_arguments.bgBlue,
        self.stats_label_arguments.zoom,
        self.stats_label_arguments.fontSize,
        self.stats_label_arguments.showOnTop,
        self.stats_label_arguments.noScaling,
        self.stats_label_arguments.fontName,
        self.stats_label_arguments.foregroundTransparency,
        self.stats_label_arguments.backgroundTransparency,
        self.stats_label_arguments.temporary
      )

  self.stats_label = {
    area_id = area_id,
    label_id = map_label_id,
  }
end

function Explorer:ExploreDirection(current_room_id, start_room_id, stub)
  -- self.dir_start = getEpoch()
end

function Explorer:DirectionExplored(current_room_id, start_room_id, stub)
  local duration = getEpoch() - self.dir_start

  self.explore_timings[#self.explore_timings + 1] = duration
  self.exits_explored = self.exits_explored and self.exits_explored + 1 or 1
  self:UpdateLabel()
end

-- Go through as soon as the mapper says the door is open, rather than waiting for
-- the timer, which is there for mappers that don't say, and doors that don't open.
function Explorer:DoorChange(room_id, door_command, status, old_status)
  -- We're not exploring.
  if not self.exploring then return end
  -- We're not waiting on a door check.
  if not self.status.door then return end
  -- It's some other door.
  if room_id ~= self.status.start or door_command ~= self.status.door then return end

  -- The door is open and it wasn't before.
  if status == 1 and status ~= old_status then
    self:CheckDoor()
  end
end


-- ----------------------------------------------------------------------------
-- Timers
-- ----------------------------------------------------------------------------

-- Always starts fresh. Resuming a stopped timer would keep its old interval, so
-- a changed preference wouldn't apply.
function Explorer:EnableTimer(name, interval, callback)
  d(f"Enabling timer {name} with interval {interval}")
  deleteNamedTimer(self.config.name, name)
  registerNamedTimer(self.config.name, name, interval, callback, false)
end

function Explorer:DisableTimer(name)
  if table.index_of(getNamedTimers(self.config.name), name) then
    d(f"Disabling timer {name}")
    stopNamedTimer(self.config.name, name)
  end
end

-- ----------------------------------------------------------------------------
-- Help
-- ----------------------------------------------------------------------------

Explorer.help_styles = {
  h1 = "gold",
}

Explorer.help = {
  name = Explorer.config.name,
  topics = {
    usage = f[[
<h1><u>{Explorer.config.name}</u></h1>

Syntax: <b>explore</b> [<b>command</b>]

  <b>explore</b> - See this help text.
  <b>explore start</b> - Start exploring.
  <b>explore stop</b> - Stop exploring.
  <b>explore set</b> - See your current preference settings.
  <b>explore set</b> <<b>preference</b>> <<b>value</b>> - Set a preference to a value.
  <b>explore ignore</b> - See the exit stubs being ignored.
  <b>explore ignore</b> <<b>direction</b>> [<<b>room</b>>] - Ignore an exit stub. The room defaults
                to the one you are in.
  <b>explore unignore</b> <<b>direction</b>> [<<b>room</b>>] - Stop ignoring an exit stub.

  Available preferences:
    <b>zoom</b>     - Set the zoom level of the map during exploration
                (default: <i>{Explorer.default.zoom}</i>).
    <b>speed</b>     - Set the speed of movement during exploration
                (default: <i>{Explorer.default.speed}</i>).
    <b>timeout</b>   - Set how many seconds to wait for a move or door to respond
                before giving up on it (default: <i>{Explorer.default.timeout}</i>).
    <b>stats</b>     - Show exploration statistics during exploration
                (default: <i>{Explorer.default.stats}</i>).
]],
  }
}
