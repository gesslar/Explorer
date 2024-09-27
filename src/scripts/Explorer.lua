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
  initial = true,
  previous_area = nil,
  status = { start = nil, dest = nil, speedwalking = false },
  step_count = 0,
  stub_to_check = { room_id = nil, stub = nil },
  todo = {},
}

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
    prefs = table.update(defaults, prefs)
  end

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

  if not self.default[key] then
    cecho("Unknown preference " .. key .. "\n")
    return
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

function Explorer:FindTodos()
  self.todo = {}

  local current_room = getPlayerRoom()
  if not current_room then
    return
  end

  -- Populate areas with all known areas by the mapper
  local areas = getAreaTable() or {}
  for _, area_id in pairs(areas) do
    if area_id ~= -1 then
      if self.areas[area_id] == nil then
        self.areas[area_id] = true
      end
    end
  end

  local current_area = getRoomArea(current_room)
  if not current_area then
    return
  end

  -- Mark the current area as active for exploration
  if not self.areas[current_area] then
    self.areas[current_area] = true
  end

  if not self.previous_area then
    self.previous_area = current_area
  end

  local test_area = self.previous_area

  local count = 0
  -- Keep looking for valid rooms to explore across areas
  while not next(self.todo) and self:CountValidAreas() > 0 do
    -- Get rooms in the current area and find valid ones to explore
    local rooms = getRooms() or {}
    for room_id, room_name in pairs(rooms) do
      local room_area = getRoomArea(room_id)
      if room_area and self.areas[room_area] == true and room_area == test_area then
        local valid_stubs = self:GetValidStubs(room_id) or {}
        if next(valid_stubs) then
          self:AddRoom(room_id)
          count = count + 1
        end
      end
    end

    if next(self.todo) then
      self.previous_area = test_area
      break
    end

    -- If no rooms were found, mark the current area as completed and move to the next
    if not next(self.todo) then
      self.areas[test_area] = false        -- Mark area as completed
      test_area = self:FindNextValidArea() -- Find next area with rooms to explore
      if not test_area then
        cecho("<deep_pink>No more areas to explore. Stopping exploration.\n")
        return
      end
    else
      self.previous_area = test_area
    end
  end
end

-- Filters out rooms from the previous area and marks areas as completed if no rooms remain
function Explorer:FilterRoomsByArea(current_area)
  for room_id in pairs(self.todo) do
    local room_area = getRoomArea(room_id)
    if room_area ~= current_area then
      self.todo[room_id] = nil -- Remove the room if it's not in the current area
    end
  end
end

-- Count the number of areas still valid for exploration
function Explorer:CountValidAreas()
  local count = 0
  for area_id, status in pairs(self.areas) do
    if status == true then
      count = count + 1
    end
  end
  return count
end

function Explorer:SortAreasById()
  local sorted_areas = {}
  for area_id, _ in pairs(self.areas) do
    table.insert(sorted_areas, area_id)
  end
  table.sort(sorted_areas)
  return sorted_areas
end

-- Find the next valid area with rooms to explore
function Explorer:FindNextValidArea()
  for _, area_id in ipairs(self:SortAreasById()) do
    if self.areas[area_id] == true then
      return area_id
    end
  end
  return nil -- No more areas to explore
end

function Explorer:StopExplore(canceled, silent)
  printDebug("StopExplore called with canceled: " .. tostring(canceled) .. " and silent: " .. tostring(silent), true)
  self.exploring = false
  self.todo = {}
  self.ignore = {}

  local ignore_str

  if next(self.ignore) then
    ignore_str = "not empty"
  else
    ignore_str = "empty"
  end
  printDebug("=>> Self.ignore = " .. ignore_str)

  self.status = { dest = nil, start = nil, stub = nil, speedwalking = false }
  self.initial = nil
  self.previous_area = nil

  if not silent then
    if canceled then
      cecho("\n<red>Exploration canceled.\n")
    else
      cecho("\n<green>Exploration stopped.\n")
    end
  end

  self.areas = {}
end

function Explorer:Explore()
  if not mudlet or (mudlet and not mudlet.mapper_script) then
    cecho("<red>This script requires the Map Script package to be enabled.\n")
    return
  end

  if self.exploring then
    echo("Already exploring. Returning.\n")
    return
  end

  self.todo = {}
  self.ignore = {}
  self.initial = true
  self.previous_area = nil
  self.exploring = true

  self:DetermineNextRoom()
end

function Explorer:DetermineNextRoom()
  if (self.status and self.status.speedwalking) or not self.exploring then
    return
  end

  self:FindTodos()

  if self.exploring and not next(self.todo) then
    cecho("\n<medium_sea_green>Exploration complete.\n")
    if next(self.ignore) then
      echo("\n")
      cecho("<royal_blue>The following exit stubs were not explored as we could " ..
        "not move through them:\n")
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

  self.initial = self.initial or true

  local current_room_id = getPlayerRoom()
  if not current_room_id then
    cecho("<red>Could not get current room.\n")
    self:StopExplore(true, false)
    return
  end

  local valid_stubs = self:GetValidStubs(current_room_id) or {}
  local stubs = table.keys(valid_stubs) or {}
  local current_room_area = getRoomArea(current_room_id)

  if self.previous_area == current_room_area and #stubs > 0 then -- we have unexplored stubs in our current room
    local stub

    if self.prefs.shuffle > 0 then
      self.step_count = self.step_count + 1
      if self.step_count > self.prefs.shuffle then
        if #stubs > 1 then
          local random_index = math.random(2, #stubs)
          stub = tonumber(stubs[random_index])
        else
          stub = tonumber(stubs[1])
        end
        self.step_count = 0
      else
        stub = tonumber(stubs[1])
      end
    else
      stub = tonumber(stubs[1])
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

    cecho("\n<yellow>Exploring the " .. direction .. " exit from " .. current_room_id .. " (" .. getRoomName(current_room_id) .. ")\n")

    self.stub_to_check = { room_id = current_room_id, stub = stub }
    send(direction, true)
    if table.index_of(getNamedTimers(self.config.name)) then
      resumeNamedTimer(self.config.name, "Check Stub")
    else
      registerNamedTimer(self.config.name, "Check Stub", 1, function() self:CheckStub(true) end)
    end
  else
    next_room_str = self:FindCandidateRoom()
    if not next_room_str then
      cecho("<red>Could not find next room.\n")
      self:StopExplore(true, false)
      return
    end
    self.status = {
      dest = next_room_str,
      start = current_room_id,
      stub = nil,
      speedwalking = true,
    }
    cecho("\n<yellow>Traveling to room " .. next_room_str .. "\n");
    gotoRoom(next_room_str)
  end
end

function Explorer:CheckStub(force_next_room)
  if not self.stub_to_check then
    return true
  end

  local room_id, stub = self.stub_to_check.room_id, self.stub_to_check.stub

  local check_stubs = getExitStubs1(room_id) or {}
  if not next(check_stubs) then
    return true
  end

  local result = true
  self.stub_to_check = { room_id = nil, stub = nil }
  if table.index_of(getNamedTimers(self.config.name), "Check Stub") then
    stopNamedTimer(self.config.name, "Check Stub")
  end

  for _, v in ipairs(check_stubs) do
    if v == stub then
      self:IgnoreStub(room_id, stub)
      result = false
      break
    end
  end

  if force_next_room == true then
    self:DetermineNextRoom()
  end

  return result
end

function Explorer:FindCandidateRoom()
  local valid_stubs
  local cheapest_path = { cost = 99999999, room_id = nil }

  local room_id = getPlayerRoom()
  if not room_id then
    return
  end

  for current_room_id, _ in pairs(self.todo) do
    local test = current_room_id
    valid_stubs = self:GetValidStubs(test) or {}
    if next(valid_stubs) then
      for stub, _ in pairs(valid_stubs) do
        local result, cost = getPath(room_id, test)
        if result then
          if cost < cheapest_path.cost then
            cheapest_path = { cost = cost, room_id = test }
          end
        end
      end
    else
      self:RemoveRoom(test)
    end
  end

  return cheapest_path.room_id
end

function Explorer:Arrived(event, current_room_id)
  if not self.exploring then return end

  if event == "onMoveMap" then
    if self.status.speedwalking then
      return
    end
  elseif event == "sysSpeedwalkFinished" then
    if not self.status.speedwalking then
      return
    end
    self.status.speedwalking = false
    self:DetermineNextRoom()
    return
  end

  if self:CheckStub(false) == false then
    return
  end

  local area_id = getRoomArea(current_room_id)
  if area_id then
    setMapZoom(self.prefs.zoom)
  end

  if area_id ~= self.previous_area then
    self:DetermineNextRoom()
    return
  end

  if self.status.start and current_room_id == self.status.start and not self.initial then
    self:IgnoreStub(current_room_id, self.status.stub)
    if not next(self:GetValidStubs(current_room_id)) then
      self:RemoveRoom(current_room_id)
    end
  end

  self:DetermineNextRoom()
end

function Explorer:AddRoom(room_id)
  if not self.todo then
    self.todo = {}
  end

  if not self.todo[tostring(room_id)] then
    self.todo[tostring(room_id)] = true
  end
end

function Explorer:RemoveRoom(room_id)
  if not self.todo then
    return false
  end

  if not self.todo[tostring(room_id)] then
    return false
  end

  self.todo[tostring(room_id)] = nil

  return true
end

function Explorer:IgnoreStub(room_id, stub)
  local rid = tostring(room_id)
  local sid = tostring(stub)

  if not self.ignore then
    self.ignore = {}
  end

  if not self.ignore[rid] then
    self.ignore[rid] = {}
  end

  self.ignore[rid][sid] = true
end

function Explorer:GetValidStubs(room_id)
  local stubs = getExitStubs1(room_id) or {}

  if not next(stubs) then
    return {}
  end

  local valid_stubs = {}
  local test = tostring(room_id)

  if self.ignore and self.ignore[test] then
    for _, stub in ipairs(stubs) do
      local stub_str = tostring(stub)
      if not self.ignore[test][stub_str] then
        valid_stubs[stub_str] = true
      end
    end
  else
    for _, stub in ipairs(stubs) do
      local stub_str = tostring(stub)
      valid_stubs[stub_str] = true
    end
  end

  return valid_stubs
end

function Explorer:CountValidStubs(room_id)
  local stubs = self:GetValidStubs(room_id) or {}
  local count = 0
  for _, _ in pairs(stubs) do
    count = count + 1
  end
  return count
end

function Explorer:Reset(event, exception, reason)
  if not self.exploring then
    return
  end

  if exception then
    self:StopExplore(true, false)
  end
end

function Explorer:SpeedwalkStarted(event)
  cecho("\n<yellow>Speedwalking started.\n")
end

-- Uninstall the exploration
function Explorer:Uninstall(event, package)
  if package ~= self.package_name then
    return
  end

  self:StopExplore(false, false)
  Explorer = nil
end

function Explorer:Disconnect(event)
  -- printDebug("z", true)

  local ignore_str

  if next(self.ignore) then
    ignore_str = "not empty"
  else
    ignore_str = "empty"
  end
  printDebug("=>> Self.ignore = " .. ignore_str)

  if self.exploring == true then
    self:StopExplore(false, false)
  end

  if next(self.ignore) then
    ignore_str = "not empty"
  else
    ignore_str = "empty"
  end
  printDebug("=>>> Self.ignore = " .. ignore_str)
  printDebug("=>>> Self.ignore printing")
  for room_id, stubs in pairs(self.ignore) do
    for stub, _ in pairs(stubs) do
      printDebug("  Room " .. room_id .. " (" .. getRoomName(room_id) .. ") " ..
        "-> " .. stub .. " (" .. self.stub_map[tonumber(stub)] .. ")")
    end
  end
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

registerNamedEventHandler(script_name, "Profile Loaded", "sysLoadEvent", "Explorer:Setup", false)
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
