-- This is the name of this script, which may be different to the package name
-- which is why we want to have a specific identifier for events that only
-- concern this script and not the package as a whole, if it is included
-- in other packages.
local script_name = "Explorer"
print("hi there from " .. script_name)

local _g = Glu and Glu(script_name) or nil

display(_g)

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
---@field ignore table                -- Table of stubs to ignore
---@field initial boolean             -- Whether we are in the initial state
---                                      (first room)
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
    shuffle = 0,
    zoom = 10,
    speed = 0,
    stats = true,
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
  },
  exit_short = {
    north = "n",    northeast = "ne", northwest = "nw", east = "e",
    west = "w",     south = "s",      southeast = "se", southwest = "sw",
    up = "d",       down = "u",       ["in"] = "out",   out = "in",
  },
  event_handlers = {
    "sysLoadEvent",
    "sysUninstall",
    "sysDisconnectionEvent",
    "sysSpeedwalkStarted",
    "sysSpeedwalkFinished",
    "onSpeedwalkReset",
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
  initial = nil,
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

  if not table.index_of(getPackages(), "Helper") then
    cecho(f "<gold><b>{self.config.name} is installing dependent <b>Helper</b> package.\n")
    installPackage(
      "https://github.com/gesslar/Helper/releases/latest/download/Helper.mpackage"
    )
  end

  self:LoadPreferences()

  if event == "sysInstall" then
    tempTimer(1, function()
      echo("\n")
      cecho("<gold>Welcome to <b>"..self.config.name.."</b>!<reset>\n")
      echo("\n")
      helper.print({
        text = self.help.topics.usage,
        styles = self.help_styles
      })
    end)
  end
end

function Explorer:LoadPreferences()
  local path = self.config.package_path .. self.config.preferences_file
  local defaults = self.default
  local prefs = self.prefs or {}

  if io.exists(path) then
    prefs = self.default
    table.load(path, prefs)
    ---@diagnostic disable-next-line: cast-local-type
    prefs = table.update(defaults, prefs)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  self.prefs = prefs

  if not self.prefs.shuffle then
    self.prefs.shuffle = self.default.shuffle
  end
  if not self.prefs.zoom then
    self.prefs.zoom = self.default.zoom
  end
  if not self.prefs.speed then
    self.prefs.speed = self.default.speed
  end
  if not self.prefs.stats then
    self.prefs.stats = self.default.stats
  end
end

function Explorer:SavePreferences()
  local path = self.config.package_path .. self.config.preferences_file
  table.save(path, self.prefs)
end

function Explorer:SetPreference(key, value)
  if not self.prefs then
    self.prefs = {}
  end

  if key == "shuffle" then
    value = tonumber(value)
  elseif key == "speed" then
    value = tonumber(value)
  elseif key == "zoom" then
    value = tonumber(value)
  elseif key == "speed" then
    value = tonumber(value)
    if value < 0.0 then value = 0.0 end
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
  self.ignore = {}
  self.previous_area = nil
  self.areas = {}
  self.initial = nil
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

  for n = 1, 10 do
    d("=========================================================\n", "orange")
  end

  raiseEvent("onExplorationStarted")

  self:ScheduleNextMove()
end

-- Stop exploring and reset the state.
function Explorer:StopExplore(canceled, silent)
  d("StopExplore called")
  self:ResetState()

  if not silent then
    if canceled then
      cecho("\n<red>Exploration canceled.\n")
    else
      cecho("\n<green>Exploration stopped.\n")
    end
  end

  deleteAllNamedTimers(self.config.name)
  local next_timer = self.next_move_timer
  if next_timer and exists(next_timer, "timer") then
    killTimer(next_timer)
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
      cecho("\n<royal_blue>The following exit stubs were not explored as we "
        .. "could not move through them:\n")
      for room_id, stubs in pairs(self.ignore) do
        for _, stub in ipairs(stubs) do
          echo("  Room " .. room_id .. " (" .. getRoomName(room_id) .. ") " ..
            "-> " .. stub .. " (" .. self.stub_map[tonumber(stub)] .. ")\n")
        end
      end
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
      if doors[dir_short] then
        cecho(f"<red>Door in the way of {direction} ({dir_short})\n")
        self.status = {
          dest = nil,
          start = current_room,
          stub = stub,
          speedwalking = false,
          door = dir_short,
        }
        d(f"Door in the way of {direction} ({dir_short})\n")
        self:EnableTimer("Check Door", 1, function() self:CheckDoor() end)

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
    self.initial = self.initial == nil and true or false

    d("Initial = " .. tostring(self.initial))
    -- If this is the initial move, then we don't need to check for stubs.
    -- since we haven't moved yet.
    --if self.initial == false then
      -- We need to schedule a check for the stub we moved through to see
      -- if it is still a stub. This is how we know if we were blocked from
      -- moving through it, since the mapping script should have converted
      -- to an exit in that case.
      -- But we don't do this on the first room, because it's not a movement
      -- and we didn't go through any exit so we don't need to check.
      d(f"Checking stub in 1 second")
      self:EnableTimer("Check Stub", 1, function() self:CheckStub(true) end)
    --end

    ---@diagnostic disable-next-line: redundant-parameter
    raiseEvent("onExploreDirection", current_room, direction, stub)
    send(direction, true)
  else
    self.initial = false
    d("self.status")
    for k, v in pairs(self.status) do
      d(f"  {k} = {v}")
    end
    self.stub_to_check = nil
    local next_room = self:FindCandidateRoom()
    d("next_room = " .. tostring(next_room))
    if not next_room then
      cecho("<red>Could not find next room.\n")
      -- cecho("<red>Trying again.\n")
      -- self.previous_area = nil
      -- return
      -- self:DetermineNextRoom()
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
    tempTimer(self.prefs.speed, function()
      gotoRoom(next_room)
    end)
  end
end

-- Check to see if we have moved by looking for the stub in the room that
-- we have left. If it is still a stub, then we have not moved and we
-- should add it to our ignore list so that we don't try to move through
-- it again.
function Explorer:CheckStub(force_next_room)
  if not self.stub_to_check then return true end

  local room_id, stub = unpack(self.g.table.values(self.stub_to_check))
  d(f"Checking for stub {stub} ({self.stub_map[tonumber(stub)]}) in room {room_id}")

  self:DisableTimer("Check Stub")

  if not room_id or not stub then return true end
  local check_stubs = getExitStubs1(room_id) or {}
  local cs = table.concat(check_stubs, ",")
  if table.is_empty(check_stubs) then return true end

  local result = true
  self.stub_to_check = { room_id = nil, stub = nil }
  d(f"Stub for this room {room_id}")
  d(cs)
  if table.index_of(check_stubs, stub) then
    d(f"Stub {stub} ({self.stub_map[tonumber(stub)]}) is still a stub, removing from todo list")
    self:IgnoreStub(room_id, stub)
    result = false
  end

  d(f"Force next room = {tostring(force_next_room)}")

  if force_next_room == true then
    self:DetermineNextRoom()
  end

  return result
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
  self:EnableTimer("Check Stub", self.prefs.speed, function() self:CheckStub() end)

  self.dir_start = getEpoch()

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onExploreDirection", room_id, dir_full, self.stub_map[tonumber(self.status.stub)])
  send(dir_full, true)
end

function Explorer:IgnoreStub(room_id, stub)
  local rid = tostring(room_id)

  if not self.ignore then self.ignore = {} end
  if not self.ignore[rid] then self.ignore[rid] = {} end

  table.insert(self.ignore[rid], stub)

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onStubIgnored", room_id, stub, self.stub_map[tonumber(stub)])
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

  self.prefs.speed = self.prefs.speed ~= 0 and self.prefs.speed or 0.01
  d(f"Scheduling next move in {self.prefs.speed} seconds")
  self:EnableTimer("Determine Next Room", self.prefs.speed, function()
    self:DetermineNextRoom()
  end)
end

function Explorer:FindCandidateRoom()
  local valid_stubs
  local cheapest_path = { cost = math.huge, room_id = nil }

  local room_id = getPlayerRoom()
  d(f"Finding candidate room for room {tostring(room_id)}")
  if not room_id then return nil end

  d(f"We definitely have a room id = {tostring(room_id)}")

  for index, current_room_id in ipairs(self.todo) do
    local test = current_room_id
    valid_stubs = self:GetValidStubs(test) or {}
    d(f"valid_stubs for room {test}")
    if #valid_stubs == 0 then
      d(f"No valid stubs for room {test}, removing from todo list")
      table.remove(self.todo, index)
    else
      for _, stub in ipairs(valid_stubs) do
        local result, cost = getPath(room_id, test)
        d(f"result = {result}")
        d(f"cost = {tostring(cost)}")
        if result then
          if cost > -1 and cost < cheapest_path.cost then
            cheapest_path = { cost = cost, room_id = test }
          end
        end
      end
    end
  end

  d(f"Cheapest path is to room {tostring(cheapest_path.room_id)}")
  d(f"Cost = {tostring(cheapest_path.cost)}")

  return cheapest_path.room_id
end

function Explorer:Arrived(event, current_room_id)
  if not self.exploring then return end

  d(f"event = {event}")

  self:UpdateLabel()

  -- We haved moved into a new room
  if event == "onMoveMap" then
    -- We are speedwalking, so we don't really care.
    if self.status.speedwalking == true then return end
    -- We are waiting on a door check
    if self.status.door then return end
  elseif event == "onDoorChange" then
    return
  elseif event == "sysSpeedwalkFinished" then
    -- We are done speedwalking, so we can determine the next room to explore.
    if self.status.speedwalking == false then return end
    self.status.speedwalking = false
    self:ScheduleNextMove()
    return
  end

  ---@diagnostic disable-next-line: redundant-parameter
  raiseEvent("onDirectionExplored", current_room_id, self.status.start, self.stub_map[self.status.stub])

  -- This basically serves to stop the timer so that it doesn't go off.
  -- We did arrive, so clearly we were not blocked. It shouldn't return true,
  -- because we moved.
  --
  -- Don't force a move from CheckStub, we will do that below.
  -- if self.initial == false then
    -- self:StopExplore(true, false)
    d(f"Checking stub {self.stub_map[self.status.stub]} ({self.status.stub}) for room {current_room_id}")
    if self:CheckStub(false) == false then
      d(f"Stub {self.stub_map[self.status.stub]} ({self.status.stub}) is still a stub, removing from todo list")
      return
    end
    d(f"Stub {self.stub_map[self.status.stub]} ({self.status.stub}) is not a stub, continuing")
  -- else
    -- self.initial = false
  -- end

  local area_id = getRoomArea(current_room_id)
  if area_id then
    setMapZoom(self.prefs.zoom)
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

  if current_room_id == self.status.start and not self.initial then
    d(f"Ignoring stub {self.stub_map[self.status.stub]} ({self.status.stub}) in room {current_room_id}")
    self:IgnoreStub(current_room_id, self.status.stub)
    valid_stubs = self:GetValidStubs(current_room_id) or {}
    if #valid_stubs == 0 then
      local index = table.index_of(self.todo, current_room_id)
      if index then
        table.remove(self.todo, index)
      end
    end
  end

  -- Determine the next room to explore and start moving there.
  d("Scheduling next move")
  self:ScheduleNextMove()
end

function Explorer:Reset(event, exception, reason)
  if not self.exploring then return end

  if exception then self:StopExplore(true, false) end
end

function Explorer:SpeedwalkStarted(event)
  cecho(f"<yellow>Speedwalking started from {self.status.start} to {self.status.dest}\n")
end

-- Process uninstallation tasks.
function Explorer:Uninstall(event, package)
  if package ~= self.config.package_name then
    return
  end

  self:StopExplore(false, false)

  deleteAllNamedEventHandlers(self.config.name)
  deleteAllNamedTimers(self.config.name)

  for k in pairs(self) do
    self[k] = nil
  end

  Explorer = nil
end

function Explorer:Disconnect(event)
  local ignore_str

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
  elseif event == "onSpeedwalkReset" then
    self:Reset(event, ...)
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
    -- self:DoorChange(...)
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

registerNamedEventHandler(script_name, "Profile Loaded", "sysLoadEvent", "Explorer:Setup", true)
registerNamedEventHandler(script_name, "Package Installed", "sysInstall", "Explorer:Setup", true)
Explorer:SetupEventHandlers()

-- ----------------------------------------------------------------------------
-- Map label stuff
-- ----------------------------------------------------------------------------

function Explorer:DeleteMapLabel()
  if self.stats_label then
    deleteMapLabel(self.stats_label.area_id, self.stats_label.label_id)
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
  local map_label = self.stats_label or {}

  self:DeleteMapLabel()

  if self.prefs.stats == false then return end

  local room_id = getPlayerRoom()
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
  average = average / #self.explore_timings
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
  self.dir_start = getEpoch()
end

function Explorer:DirectionExplored(current_room_id, start_room_id, stub)
  local duration = getEpoch() - self.dir_start
  self.explore_timings[#self.explore_timings+1] = duration

  self.exits_explored = self.exits_explored and self.exits_explored + 1 or 1
  self:UpdateLabel()
end

--[[
function Explorer:DoorChange(room_id, door_command, status, old_status)
  -- We're not exploring.
  if not self.exploring then return end
  -- We're not waiting on a door check.
  if not self.status.door then return end

  -- The door is open and it wasn't before.
  if status == 1 and status ~= old_status then
    self:CheckDoor()
  end
end
]]


-- ----------------------------------------------------------------------------
-- Timers
-- ----------------------------------------------------------------------------

function Explorer:EnableTimer(name, interval, callback)
  if table.index_of(getNamedTimers(self.config.name), name) then
    d(f"Resuming timer {name}")
    resumeNamedTimer(self.config.name, name)
  else
    d(f"Enabling timer {name} with interval {interval}")
    registerNamedTimer(self.config.name, name, interval, callback, false)
  end
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

  Available preferences:
    <b>shuffle</b>   - Set the maximum number of steps to take before selecting a
                random exit stub to explore (default: <i>{Explorer.default.shuffle}</i>).
    <b>zoom</b>      - Set the zoom level of the map during exploration
                (default: <i>{Explorer.default.zoom}</i>).
    <b>speed</b>     - Set the speed of movement during exploration
                (default: <i>{Explorer.default.speed}</i>).
    <b>stats</b>     - Show exploration statistics during exploration
                (default: <i>{Explorer.default.stats}</i>).
]],
  }
}
