-- This is the name of this script, which may be different to the package name
-- which is why we want to have a specific identifier for events that only
-- concern this script and not the package as a whole, if it is included
-- in other packages.
local script_name = "Explorer"

---@class Explorer
---@field config table
---@field default table
---@field prefs table
---@field stub_map table
---@field event_handlers string[]
---@field areas table
---@field exploring boolean
---@field ignore table
---@field initial boolean
---@field previous_area string
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
  },
  prefs = {},
  stub_map = {
    north = 1,        northeast = 2,      northwest = 3,      east = 4,
    west = 5,         south = 6,          southeast = 7,      southwest = 8,
    up = 9,           down = 10,          ["in"] = 11,        out = 12,
    northup = 13,     southdown = 14,     southup = 15,       northdown = 16,
    eastup = 17,      westdown = 18,      westup = 19,        eastdown = 20,
    [1] = "north",    [2] = "northeast",  [3] = "northwest",  [4] = "east",
    [5] = "west",     [6] = "south",      [7] = "southeast",  [8] = "southwest",
    [9] = "up",       [10] = "down",      [11] = "in",        [12] = "out",
    [13] = "northup", [14] = "southdown", [15] = "southup",   [16] = "northdown",
    [17] = "eastup",  [18] = "westdown",  [19] = "westup",    [20] = "eastdown",
  },
  event_handlers = {
    "sysLoadEvent",
    "sysUninstall",
    "sysDisconnectionEvent",
    "sysSpeedwalkStarted",
    "sysSpeedwalkFinished",
    "onSpeedwalkReset",
    "onMoveMap",
  },
  areas = {},
  exploring = nil,
  ignore = {},
  initial = nil,
  previous_area = nil,
  status = { start = nil, dest = nil, speedwalking = false },
  step_count = 0,
  stub_to_check = { room_id = nil, stub = nil },
  todo = {},
}

---@param t table
---@return table
local function values(t)
  local result = {}
  for _,v in pairs(t) do
    result[#result+1] = v
  end
  return result
end

---@param t table
---@param fn function
---@param ... any
---@return table
local function map(t, fn, ...)
  local result = {}
  for k, v in pairs(t) do
    result[k] = fn(k, v, ...)
  end
  return result
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
  else
    cecho("Unknown preference " .. key .. "\n")
    return
  end

  self.prefs[key] = value
  self:SavePreferences()
  self:LoadPreferences()
  cecho("Preference " .. key .. " set to " .. value .. ".\n")
end

function Explorer:IdentifyRoomsToExplore()
  self.todo = {}

  local current_room = getPlayerRoom()
  if not current_room then return end
  local current_area = getRoomArea(current_room)
  if not current_area then return end

  -- Populate areas with all known areas by the mapper
  self:UpdateAreas()

  if not self.previous_area then self.previous_area = current_area end

  -- Keep looking for valid rooms to explore across areas
  local test_area = self.previous_area
  while table.size(self.todo) == 0 and self:CountValidAreas() > 0 do
    if self.areas[tostring(test_area)] == true then
      -- Get rooms in the current area and find valid ones to explore
      local room_ids = values(getAreaRooms(test_area) or {})

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
      local valid_areas = self:GetValidAreas()
      if table.size(valid_areas) > 0 then
        test_area = valid_areas[1]
      else
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

  raiseEvent("onExplorationStarted")

  self:DetermineNextRoom()
end

-- Stop exploring and reset the state.
function Explorer:StopExplore(canceled, silent)
  self:ResetState()

  if not silent then
    if canceled then
      cecho("\n<red>Exploration canceled.\n")
    else
      cecho("\n<green>Exploration stopped.\n")
    end
  end

  deleteAllNamedTimers(self.config.name)
  raiseEvent("onExplorationStopped", canceled, silent)
end

function Explorer:DetermineNextRoom()
  if (self.status and self.status.speedwalking) or not self.exploring then
    return
  end

  raiseEvent("onDetermineNextRoom", getPlayerRoom(), getRoomArea(getPlayerRoom()))

  self:IdentifyRoomsToExplore()

  if self.exploring and #self.todo == 0 then
    cecho("\n<medium_sea_green>Exploration complete.\n")
    if not table.is_empty(self.ignore) then
      cecho("\n<royal_blue>The following exit stubs were not explored as we "
        .. "could not move through them:\n")

      for room_id, stubs in pairs(self.ignore) do
        for stub, _ in pairs(stubs) do
          echo("  Room " .. room_id .. " (" .. getRoomName(room_id) .. ") " ..
            "-> " .. stub .. " (" .. self.stub_map[tonumber(stub)] .. ")\n")
        end
      end
    end
    self:StopExplore(false, false)
    return
  end

  local current_room_id = getPlayerRoom()
  if not current_room_id then
    cecho("<red>Could not determine your current room.\n")
    self:StopExplore(true, false)
    return
  end

  local stubs = self:GetValidStubs(current_room_id) or {}
  local current_room_area = getRoomArea(current_room_id)

  raiseEvent("onNextRoomDetermined", current_room_id, current_room_area)

  if self.previous_area == current_room_area and #stubs > 0 then -- we have unexplored stubs in our current room
    local stub

    if self.prefs.shuffle > 0 then
      self.step_count = self.step_count + 1
      if self.step_count > self.prefs.shuffle then
        if #stubs > 1 then
          local random_index = math.random(2, #stubs)
          stub = stubs[random_index]
        else
          stub = stubs[1]
        end
        self.step_count = 0
      else
        stub = stubs[1]
      end
    else
      stub = stubs[1]
    end

    local direction = self.stub_map[stub]
    if not direction then
      cecho("<red>Could not get direction for stub " .. stub .. "\n")
      self:StopExplore(true)
      return
    end
    self.status = {
      dest = nil,
      start = current_room_id,
      stub = stub,
      speedwalking = false,
    }

    cecho(f"<yellow>Exploring the {direction} exit from {current_room_id} ({getRoomName(current_room_id)})\n")

    self.stub_to_check = { room_id = current_room_id, stub = stub }
    self.initial = self.initial == nil and true or false

    -- If this is the initial move, then we don't need to check for stubs.
    -- since we haven't moved yet.
    if self.initial == false then
      -- We need to schedule a check for the stub we moved through to see
      -- if it is still a stub. This is how we know if we were blocked from
      -- moving through it, since the mapping script should have converted
      -- to an exit in that case.
      if table.index_of(getNamedTimers(self.config.name), "Check Stub") then
        resumeNamedTimer(self.config.name, "Check Stub")
      else
        registerNamedTimer(self.config.name, "Check Stub", 0.5, function() self:CheckStub(true) end)
      end
    end

    raiseEvent("onExploreDirection", current_room_id, direction)

    send(direction, true)
  else
    local next_room_id = self:FindCandidateRoom()
    if not next_room_id then
      cecho("<red>Could not find next room.\n")
      self:StopExplore(true, false)
      return
    end
    self.status = {
      dest = next_room_id,
      start = current_room_id,
      stub = nil,
      speedwalking = true,
    }
    cecho(f"<yellow>Traveling to room {next_room_id}\n")
    gotoRoom(next_room_id)
  end
end

-- Check to see if we have moved by looking for the stub in the room that
-- we have left. If it is still a stub, then we have not moved and we
-- should add it to our ignore list so that we don't try to move through
-- it again.
function Explorer:CheckStub(force_next_room)
  if table.index_of(getNamedTimers(self.config.name), "Check Stub") then
    stopNamedTimer(self.config.name, "Check Stub")
  end

  if not self.stub_to_check then return true end

  ---@diagnostic disable-next-line: deprecated
  local room_id, stub = unpack(values(self.stub_to_check))
  local check_stubs = getExitStubs1(room_id) or {}
  local cs = table.concat(check_stubs, ",")
  if table.is_empty(check_stubs) then return true end

  local result = true
  self.stub_to_check = { room_id = nil, stub = nil }

  if table.index_of(check_stubs, stub) then
    self:IgnoreStub(room_id, stub)
    result = false
  end

  if force_next_room == true then
    self:DetermineNextRoom()
  end

  return result
end

function Explorer:IgnoreStub(room_id, stub)
  local rid = tostring(room_id)

  if not self.ignore then self.ignore = {} end
  if not self.ignore[rid] then self.ignore[rid] = {} end

  table.insert(self.ignore[rid], stub)
end

function Explorer:GetValidStubs(room_id)
  local stubs = getExitStubs1(room_id) or {}

  if not next(stubs) then return {} end

  local valid_stubs = {}
  local room_str = tostring(room_id)

  if self.ignore[room_str] then
    for _, stub in ipairs(stubs) do
      if not table.index_of(self.ignore[room_str], stub) then
        valid_stubs[#valid_stubs+1] = stub
      end
    end
  else
    valid_stubs = stubs
  end

  return valid_stubs
end

function Explorer:FindCandidateRoom()
  local valid_stubs
  local cheapest_path = { cost = math.huge, room_id = nil }

  local room_id = getPlayerRoom()
  if not room_id then return nil end

  for index, current_room_id in ipairs(self.todo) do
    local test = current_room_id
    valid_stubs = self:GetValidStubs(test) or {}
    if #valid_stubs == 0 then
      table.remove(self.todo, index)
    else
      for _, stub in ipairs(valid_stubs) do
        local result, cost = getPath(room_id, test)
        if result and cost < cheapest_path.cost then
          cheapest_path = { cost = cost, room_id = test }
        end
      end
    end
  end

  return tonumber(cheapest_path.room_id)
end

function Explorer:Arrived(event, current_room_id)
  if not self.exploring then return end

  -- We haved moved into a new room
  if event == "onMoveMap" then
    -- We are speedwalking, so we don't really care.
    if self.status.speedwalking == true then return end
  elseif event == "sysSpeedwalkFinished" then
    -- We are done speedwalking, so we can determine the next room to explore.
    if self.status.speedwalking == false then return end
    self.status.speedwalking = false
    self:DetermineNextRoom()
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
    if self:CheckStub(false) == false then
      return
    end
  -- else
    -- self.initial = false
  -- end

  local area_id = getRoomArea(current_room_id)
  if area_id then
    setMapZoom(self.prefs.zoom)
  end

  -- If we wanted into a new area, we want to return to the previous area.
  -- DetermineNextRoom calls IdentifyRoomsToExplore, which will return
  -- to the previous area if we have haven't explored it all.
  if area_id ~= self.previous_area then
    self:DetermineNextRoom()
    return
  end

  -- If we have no valid stubs, we can remove the room from the todo list.
  local valid_stubs = self:GetValidStubs(current_room_id) or {}

  if #valid_stubs == 0 then
    local index = table.index_of(self.todo, current_room_id)
    if index then
      table.remove(self.todo, index)
    end
  end

  if current_room_id == self.status.start and not self.initial then
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
  self:DetermineNextRoom()
end

function Explorer:Reset(event, exception, reason)
  if not self.exploring then return end

  if exception then self:StopExplore(true, false) end
end

function Explorer:SpeedwalkStarted(event)
  cecho("\n<yellow>Speedwalking started.\n")
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
]],
  }
}
