Explore = Explore or {}

Explore.exploring = nil
Explore.todo = {}
Explore.ignore = {}
Explore.stub_map = {
  [1]  = "north",
  [2]  = "northeast",
  [3]  = "northwest",
  [4]  = "east",
  [5]  = "west",
  [6]  = "south",
  [7]  = "southeast",
  [8]  = "southwest",
  [9]  = "up",
  [10] = "down",
}

Explore.speed = 0.1
Explore.timer_id = nil
Explore.stop = false
Explore.areas = {}
Explore.previous_area = nil
Explore.initial = true
Explore.status = { start = nil, dest = nil, speedwalking = false }
Explore.check_stub_timers = {}
Explore.name = "Explore"
Explore.package_name = "__PKGNAME__"

function Explore:FindTodos()
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
function Explore:FilterRoomsByArea(current_area)
  for room_id in pairs(self.todo) do
    local room_area = getRoomArea(room_id)
    if room_area ~= current_area then
      self.todo[room_id] = nil -- Remove the room if it's not in the current area
    end
  end
end

-- Count the number of areas still valid for exploration
function Explore:CountValidAreas()
  local count = 0
  for area_id, status in pairs(self.areas) do
    if status == true then
      count = count + 1
    end
  end
  return count
end

function Explore:SortAreasById()
  local sorted_areas = {}
  for area_id, _ in pairs(self.areas) do
    table.insert(sorted_areas, area_id)
  end
  table.sort(sorted_areas)
  return sorted_areas
end

-- Find the next valid area with rooms to explore
function Explore:FindNextValidArea()
  for _, area_id in ipairs(self:SortAreasById()) do
    if self.areas[area_id] == true then
      return area_id
    end
  end
  return nil -- No more areas to explore
end

function Explore:StopExplore(canceled)
  self.exploring = false
  self.todo = {}
  self.ignore = {}
  self.status = nil
  self.check_stub_timers = {}
  self.initial = nil
  self.previous_area = nil
  if canceled then
    cecho("\n<red>Exploration canceled.\n")
  else
    cecho("\n<green>Exploration stopped.\n")
  end
  self.areas = {}
  self.timer_id = nil
end

function Explore:Explore()
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

function Explore:DetermineNextRoom()
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
    self:StopExplore(false)
    return
  end

  self.initial = self.initial or true

  local current_room_id = getPlayerRoom()
  if not current_room_id then
    cecho("<red>Could not get current room.\n")
    self:StopExplore(true)
    return
  end

  local stubs = self:GetValidStubs(current_room_id) or {}
  local stub_str = next(stubs)

  local next_room_str = nil
  local current_room_area = getRoomArea(current_room_id)
  if self.previous_area == current_room_area and stub_str then -- we have unexplored stubs in our current room
    local direction = self:GetDirection(stub_str)
    if not direction then
      cecho("<red>Could not get direction for stub " .. stub_str .. "\n")
      self:StopExplore(true)
      return
    end
    self.status = {
      dest = nil,
      start = current_room_id,
      stub = stub_str,
      speedwalking = false,
    }

    cecho("\n<yellow>Exploring the " ..
      direction .. " exit from " .. current_room_id .. " (" .. getRoomName(current_room_id) .. ")\n")

    send(direction, true)
    table.insert(self.check_stub_timers, {
      id = tempTimer(0.40, function() self:CheckStub(current_room_id, tonumber(stub_str)) end),
      room_id = current_room_id,
      stub = stub_str,
    })
  else
    next_room_str = self:FindCandidateRoom()
    if not next_room_str then
      cecho("<red>Could not find next room.\n")
      self:StopExplore(true)
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

function Explore:CheckStub(room_id, stub)
  if not room_id or not stub then
    return true
  end

  local check_room = tonumber(room_id)
  local check_stub = tonumber(stub)
  local check_stubs = getExitStubs1(check_room) or {}
  if not next(check_stubs) then
    return true
  end

  self:RemoveCheckStubTimer(check_room, check_stub) -- Remove the timer for this stub
  for _, v in ipairs(check_stubs) do
    if v == check_stub then
      self:IgnoreStub(check_room, check_stub)
      self:DetermineNextRoom()
      return false
    end
  end

  return true
end

function Explore:FindCheckStubTimer(room_id, stub)
  for index, timer in ipairs(self.check_stub_timers) do
    if timer.room_id == room_id and timer.stub == stub then
      return index
    end
  end
  return nil
end

function Explore:RemoveCheckStubTimer(room_id, stub)
  local index = self:FindCheckStubTimer(room_id, stub)
  if index then
    if exists(self.check_stub_timers[index].id, "timer") then
      killTimer(self.check_stub_timers[index].id)
    end
    table.remove(self.check_stub_timers, index)
  end
end

function Explore:GetNextStub(room_id)
  local valid_stubs = self:GetValidStubs(room_id) or {}
  local stub, _ = next(valid_stubs)
  if stub then
    return tonumber(stub)
  end
  return nil
end

function Explore:Remaining()
  local total = 0

  for _, _ in pairs(self.todo) do
    total = total + 1
  end

  return total
end

function Explore:Sleep(s)
  local t = os.clock()
  while (os.clock() - t < s) do
    -- Busy wait
  end
end

function Explore:FindCandidateRoom()
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

function Explore:Arrived(event, current_room_id, previous_room_id)
  if not self.exploring then
    return
  end

  if self.status.speedwalking then
    if event == "mapper_gmcp_received" then
      return
    end
  end

  -- We were speedwalking, but we've arrived at our destination
  if event == "mapper_speedwalk_complete" then
    self.status.speedwalking = false
    self:DetermineNextRoom()
    return
  end

  -- If we're speedwalking, we don't need to do anything
  if self.status.speedwalking then
    return
  end

  -- If we're not speedwalking, we need to check if the stub is still validhome
  if self:CheckStub(self.status.start, tonumber(self.status.stub)) == false then
    return
  end

  local current_room_id = getPlayerRoom()
  if not current_room_id then
    cecho("<red>Arrived: Could not get current room.\n")
    self:StopExplore(true)
    return
  end

  local area_id = getRoomArea(current_room_id)
  if area_id then
    -- setMapZoom(19)
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

function Explore:GetDirection(stub)
  local stub_num = tonumber(stub)
  for k, v in pairs(Mapper.stubs) do
    if k == stub_num then
      return v
    end
  end
  return nil
end

function Explore:AddRoom(room_id)
  if not self.todo then
    self.todo = {}
  end

  if not self.todo[tostring(room_id)] then
    self.todo[tostring(room_id)] = true
  end
end

function Explore:RemoveRoom(room_id)
  if not self.todo then
    return false
  end

  if not self.todo[tostring(room_id)] then
    return false
  end

  self.todo[tostring(room_id)] = nil

  return true
end

function Explore:IgnoreStub(room_id, stub)
  local rid = tostring(room_id)
  local sid = tostring(stub)

  if sid == "0" then
    killTimer(self.timer_id)
    return
  end

  if not self.ignore then
    self.ignore = {}
  end

  if not self.ignore[rid] then
    self.ignore[rid] = {}
  end

  self.ignore[rid][sid] = true
end

function Explore:GetValidStubs(room_id)
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

function Explore:CountValidStubs(room_id)
  local stubs = self:GetValidStubs(room_id) or {}
  local count = 0
  for _, _ in pairs(stubs) do
    count = count + 1
  end
  return count
end

function Explore:Reset(event, exception, reason)
  if not self.exploring then
    return
  end

  if exception then
    self:StopExplore(true)
  end
end

-- Uninstall the exploration
function Explore:Uninstall(event, package)
  if package ~= self.package_name then
    return
  end

  self:StopExplore(false)
  self = nil
end

registerNamedEventHandler(Explore.name, "Explore Arrived", "mapper_speedwalk_complete", "Explore:Arrived");
registerNamedEventHandler(Explore.name, "Explore Moved", "mapper_gmcp_received", "Explore:Arrived");
registerNamedEventHandler(Explore.name, "Explore Reset", "mapper_speedwalk_reset", "Explore:Reset");
registerNamedEventHandler(Explore.name, "sysUninstall", "sysUninstall", "Explore:Uninstall");
