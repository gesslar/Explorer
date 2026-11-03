describe("Explorer", function()
  local NORTH, EAST, SOUTH = 1, 4, 6

  local real = {}
  local sent, printed, events, timers, delayed, walks, labels, helped
  local area_id
  local created_rooms
  local player_room

  -- Replace a global for the length of one spec.
  local function shim(name, fn)
    if real[name] == nil then real[name] = _G[name] end
    _G[name] = fn
  end

  local function output()
    return table.concat(printed)
  end

  local function fired(name)
    local found = {}
    for _, event in ipairs(events) do
      if event[1] == name then found[#found + 1] = event end
    end
    return found
  end

  local function prefs_on_disk()
    local saved = {}
    table.load(getMudletHomeDir() .. "/" .. Explorer.config.preferences_file, saved)
    return saved
  end

  local function room(stubs)
    local id = createRoomID()
    addRoom(id)
    setRoomArea(id, area_id)
    setRoomName(id, "Room " .. id)
    setRoomCoordinates(id, id, 0, 0)
    for _, stub in ipairs(stubs or {}) do
      setExitStub(id, stub, true)
    end
    created_rooms[#created_rooms + 1] = id
    return id
  end

  -- centerview doesn't set the player's room without a map widget, which a
  -- headless Mudlet doesn't have.
  local function stand_in(id)
    player_room = id
  end

  local function start()
    Explorer:Explore()
    assert.is_true(Explorer.exploring)
  end

  -- Leave a run waiting on the move it has just sent.
  local function moving_north_from(id)
    stand_in(id)
    start()
    Explorer:DetermineNextRoom()
    assert.are.equal("north", sent[#sent])
  end

  before_each(function()
    sent, printed, events, timers, delayed, walks, labels, helped = {}, {}, {}, {}, {}, {}, {}, {}
    created_rooms = {}
    player_room = nil

    shim("getPlayerRoom", function() return player_room end)
    shim("send", function(command) sent[#sent + 1] = command end)
    shim("echo", function(text) printed[#printed + 1] = text end)
    shim("cecho", function(text) printed[#printed + 1] = text end)
    shim("gotoRoom", function(id)
      walks[#walks + 1] = id
      return true
    end)
    shim("setMapZoom", function() end)
    shim("tempTimer", function(_, callback)
      delayed[#delayed + 1] = callback
      return #delayed
    end)
    -- Named timers never fire by themselves here. Specs fire them by hand. These
    -- can't call through, as Mudlet builds named timers on top of tempTimer.
    shim("registerNamedTimer", function(_, name, interval, callback)
      timers[name] = { interval = interval, callback = callback }
      return true
    end)
    shim("deleteNamedTimer", function(_, name)
      timers[name] = nil
      return true
    end)
    shim("stopNamedTimer", function(_, name)
      if timers[name] then timers[name].stopped = true end
      return true
    end)
    shim("getNamedTimers", function()
      local names = {}
      for name in pairs(timers) do names[#names + 1] = name end
      return names
    end)
    shim("deleteAllNamedTimers", function() timers = {} end)
    local raise = raiseEvent
    shim("raiseEvent", function(name, ...)
      events[#events + 1] = { name, ... }
      return raise(name, ...)
    end)
    shim("createMapLabel", function(_, text)
      labels[#labels + 1] = text
      return #labels
    end)
    shim("deleteMapLabel", function() end)
    shim("helper", { print = function(options) helped[#helped + 1] = options end })

    mudlet = mudlet or {}
    mudlet.mapper_script = true

    area_id = addAreaName("ExplorerTest" .. getEpoch())

    os.remove(getMudletHomeDir() .. "/" .. Explorer.config.preferences_file)
    Explorer:LoadPreferences()
    Explorer:ResetState()
    Explorer.stats_label = nil
  end)

  after_each(function()
    Explorer:ResetState()

    for name, fn in pairs(real) do _G[name] = fn end
    real = {}
    _G.Carto = nil
    _G.map = nil

    for _, id in ipairs(created_rooms) do deleteRoom(id) end
    deleteArea(area_id)
    os.remove(getMudletHomeDir() .. "/" .. Explorer.config.preferences_file)
  end)

  -- ==========================================================================
  -- Alias
  -- ==========================================================================

  describe("the explore alias", function()
    it("should show the help for a bare explore", function()
      expandAlias("explore", false)
      assert.are.equal(1, #helped)
    end)

    it("should leave other commands starting with explore alone", function()
      expandAlias("explored", false)
      assert.are.equal(0, #helped)
      assert.is_falsy(Explorer.exploring)
    end)

    it("should start and stop exploring", function()
      local id = room({ NORTH })
      stand_in(id)

      expandAlias("explore start", false)
      assert.is_true(Explorer.exploring)

      expandAlias("explore stop", false)
      assert.is_false(Explorer.exploring)
    end)
  end)

  -- ==========================================================================
  -- Ignoring
  -- ==========================================================================

  describe("explore ignore", function()
    local id

    before_each(function()
      id = room({ NORTH, EAST })
      stand_in(id)
    end)

    it("should ignore a stub in the current room and save it", function()
      expandAlias("explore ignore north", false)

      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])
      assert.are.same({ NORTH }, prefs_on_disk().ignore[tostring(id)])
    end)

    it("should accept short directions", function()
      expandAlias("explore ignore e", false)
      assert.are.same({ EAST }, Explorer.ignore[tostring(id)])
    end)

    it("should accept another room", function()
      local other = room({ SOUTH })
      expandAlias("explore ignore south " .. other, false)

      assert.are.same({ SOUTH }, Explorer.ignore[tostring(other)])
      assert.is_nil(Explorer.ignore[tostring(id)])
    end)

    it("should not ignore a stub twice", function()
      expandAlias("explore ignore north", false)
      expandAlias("explore ignore north", false)

      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])
      assert.is_truthy(output():find("already ignored", 1, true))
    end)

    it("should refuse a direction with no stub", function()
      expandAlias("explore ignore west", false)

      assert.is_nil(Explorer.ignore[tostring(id)])
      assert.is_truthy(output():find("no west exit stub", 1, true))
    end)

    it("should refuse an unknown direction", function()
      expandAlias("explore ignore sideways", false)

      assert.is_true(table.is_empty(Explorer.ignore))
      assert.is_truthy(output():find("Unknown direction 'sideways'", 1, true))
    end)

    it("should refuse a room that isn't a number", function()
      expandAlias("explore ignore north nowhere", false)

      assert.is_true(table.is_empty(Explorer.ignore))
      assert.is_truthy(output():find("which room", 1, true))
    end)

    it("should raise onStubIgnored outside of a run without an error", function()
      expandAlias("explore ignore north", false)

      local raised = fired("onStubIgnored")
      assert.are.equal(1, #raised)
      assert.are.same({ "onStubIgnored", id, NORTH, "north" }, raised[1])
      assert.are.equal(0, #labels)
    end)

    it("should list what is ignored", function()
      expandAlias("explore ignore north", false)
      printed = {}

      expandAlias("explore ignore", false)

      assert.is_truthy(output():find("Room " .. id, 1, true))
      assert.is_truthy(output():find("(north)", 1, true))
    end)

    it("should say when nothing is ignored", function()
      expandAlias("explore ignore", false)
      assert.is_truthy(output():find("No exit stubs", 1, true))
    end)

    it("should list a room that has since been deleted", function()
      Explorer.ignore["999999"] = { NORTH }

      expandAlias("explore ignore", false)

      assert.is_truthy(output():find("Room 999999 (unknown)", 1, true))
    end)

    it("should survive a new run and a reload", function()
      expandAlias("explore ignore north", false)

      Explorer:ResetState()
      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])

      Explorer:LoadPreferences()
      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])
    end)

    it("should survive setting a preference", function()
      expandAlias("explore ignore north", false)
      Explorer:SetPreference("zoom", "5")

      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])
      assert.are.equal(Explorer.prefs.ignore, Explorer.ignore)
    end)

    it("should leave the stub out of the valid stubs", function()
      expandAlias("explore ignore north", false)
      assert.are.same({ EAST }, Explorer:GetValidStubs(id))
    end)
  end)

  describe("explore unignore", function()
    local id

    before_each(function()
      id = room({ NORTH, EAST })
      stand_in(id)
      expandAlias("explore ignore north", false)
      expandAlias("explore ignore east", false)
      printed = {}
    end)

    it("should stop ignoring a stub and save it", function()
      expandAlias("explore unignore north", false)

      assert.are.same({ EAST }, Explorer.ignore[tostring(id)])
      assert.are.same({ EAST }, prefs_on_disk().ignore[tostring(id)])
    end)

    it("should drop a room with nothing left", function()
      expandAlias("explore unignore north", false)
      expandAlias("explore unignore east", false)

      assert.is_nil(Explorer.ignore[tostring(id)])
      assert.is_true(table.is_empty(Explorer.ignore))
    end)

    it("should say when the stub wasn't ignored", function()
      expandAlias("explore unignore south", false)
      assert.is_truthy(output():find("is not ignored", 1, true))
    end)

    it("should need a direction", function()
      expandAlias("explore unignore", false)
      assert.is_truthy(output():find("Unknown direction", 1, true))
    end)
  end)

  -- ==========================================================================
  -- Preferences
  -- ==========================================================================

  describe("preferences", function()
    it("should no longer know shuffle", function()
      Explorer:SetPreference("shuffle", "3")

      assert.is_nil(Explorer.prefs.shuffle)
      assert.is_truthy(output():find("Unknown preference", 1, true))
    end)

    it("should set the timeout", function()
      Explorer:SetPreference("timeout", "2.5")
      assert.are.equal(2.5, Explorer.prefs.timeout)
    end)

    it("should ignore a timeout that isn't a number", function()
      Explorer:SetPreference("timeout", "soon")
      assert.are.equal(Explorer.default.timeout, Explorer.prefs.timeout)
    end)

    it("should keep the timeout above nothing", function()
      Explorer:SetPreference("timeout", "0")
      assert.are.equal(0.1, Explorer.prefs.timeout)
    end)

    it("should not change a speed of 0 by moving", function()
      Explorer.prefs.speed = 0

      assert.are.equal(0.025, Explorer:MoveDelay())
      assert.are.equal(0, Explorer.prefs.speed)
    end)
  end)

  -- ==========================================================================
  -- Moving through a stub
  -- ==========================================================================

  describe("moving through a stub", function()
    local from, to

    before_each(function()
      from = room({ NORTH })
      to = room()
    end)

    it("should arm the arrival timer with the timeout", function()
      Explorer.prefs.timeout = 2.5
      moving_north_from(from)

      assert.are.equal(2.5, timers["Check Stub"].interval)
    end)

    it("should use a changed timeout on the next move", function()
      moving_north_from(from)
      assert.are.equal(Explorer.default.timeout, timers["Check Stub"].interval)

      Explorer.prefs.timeout = 4
      Explorer.status.speedwalking = false
      Explorer:DetermineNextRoom()

      assert.are.equal(4, timers["Check Stub"].interval)
    end)

    it("should stop when the arrival timer fires", function()
      moving_north_from(from)

      timers["Check Stub"].callback()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("Could not move north", 1, true))
    end)

    it("should not stop on an update for the room it is leaving", function()
      moving_north_from(from)

      raiseEvent("onMoveMap", from)

      assert.is_true(Explorer.exploring)
      assert.is_not_nil(Explorer.stub_to_check.stub)
      assert.are.equal(0, #fired("onDirectionExplored"))
    end)

    it("should count an exit that loops back once the stub is gone", function()
      moving_north_from(from)
      setExitStub(from, NORTH, false)

      raiseEvent("onMoveMap", from)

      assert.is_true(Explorer.exploring)
      assert.are.equal(1, #fired("onDirectionExplored"))
    end)

    it("should raise onDirectionExplored on a confirmed arrival", function()
      moving_north_from(from)
      setExitStub(from, NORTH, false)
      stand_in(to)

      raiseEvent("onMoveMap", to)

      assert.is_true(Explorer.exploring)
      local raised = fired("onDirectionExplored")
      assert.are.equal(1, #raised)
      assert.are.same({ "onDirectionExplored", to, from, "north" }, raised[1])
    end)

    it("should stop without raising onDirectionExplored if the stub is still there", function()
      setExitStub(from, EAST, true)
      moving_north_from(from)
      stand_in(to)

      raiseEvent("onMoveMap", to)

      assert.is_false(Explorer.exploring)
      assert.are.equal(0, #fired("onDirectionExplored"))
    end)

    it("should not act on the last run's stub", function()
      moving_north_from(from)
      timers["Check Stub"].callback()

      assert.is_nil(Explorer.stub_to_check)
      start()
      raiseEvent("onMoveMap", from)

      assert.is_true(Explorer.exploring)
    end)

    it("should raise onExploreDirection with the direction and stub", function()
      moving_north_from(from)

      assert.are.same(
        { "onExploreDirection", from, "north", NORTH },
        fired("onExploreDirection")[1]
      )
    end)

    it("should skip an ignored stub", function()
      setExitStub(from, EAST, true)
      stand_in(from)
      expandAlias("explore ignore north", false)

      start()
      Explorer:DetermineNextRoom()

      assert.are.equal("east", sent[#sent])
    end)

    it("should finish when only ignored stubs are left, and keep them", function()
      stand_in(from)
      expandAlias("explore ignore north", false)

      start()
      Explorer:DetermineNextRoom()

      assert.is_false(Explorer.exploring)
      assert.are.equal(0, #sent)
      assert.is_truthy(output():find("were ignored", 1, true))
      assert.are.same({ NORTH }, Explorer.ignore[tostring(from)])
    end)
  end)

  -- ==========================================================================
  -- Doors on a stub
  -- ==========================================================================

  describe("a door on a stub", function()
    local id

    before_each(function()
      id = room({ NORTH })
      stand_in(id)
    end)

    it("should open it and wait the timeout", function()
      setDoor(id, "n", 2)
      Explorer.prefs.timeout = 3
      start()

      Explorer:DetermineNextRoom()

      assert.are.equal("open north door", sent[#sent])
      assert.are.equal(3, timers["Check Door"].interval)
    end)

    it("should go through once it is open, passing the stub number", function()
      setDoor(id, "n", 2)
      start()
      Explorer:DetermineNextRoom()
      setDoor(id, "n", 1)

      Explorer:CheckDoor()

      assert.are.equal("north", sent[#sent])
      assert.are.same(
        { "onExploreDirection", id, "north", NORTH },
        fired("onExploreDirection")[1]
      )
    end)

    it("should ignore the stub, and remember it, if it stays closed", function()
      setDoor(id, "n", 2)
      start()
      Explorer:DetermineNextRoom()

      Explorer:CheckDoor()

      assert.are.same({ NORTH }, Explorer.ignore[tostring(id)])
      assert.are.same({ NORTH }, prefs_on_disk().ignore[tostring(id)])
    end)

    it("should go through right away when told the door opened", function()
      setDoor(id, "n", 2)
      start()
      Explorer:DetermineNextRoom()
      setDoor(id, "n", 1)

      raiseEvent("onDoorChange", id, "n", 1, 2)

      assert.are.same({ "open north door", "north" }, sent)
      assert.is_nil(Explorer.status.door)
      assert.is_true(timers["Check Door"].stopped)
    end)

    it("should keep waiting when told about another door", function()
      local other = room()
      setDoor(id, "n", 2)
      start()
      Explorer:DetermineNextRoom()

      raiseEvent("onDoorChange", id, "e", 1, 2)
      raiseEvent("onDoorChange", other, "n", 1, 2)

      assert.are.same({ "open north door" }, sent)
      assert.are.equal("n", Explorer.status.door)
    end)

    it("should keep waiting when told the door closed or locked", function()
      setDoor(id, "n", 2)
      start()
      Explorer:DetermineNextRoom()

      raiseEvent("onDoorChange", id, "n", 3, 2)

      assert.are.same({ "open north door" }, sent)
      assert.are.equal("n", Explorer.status.door)
    end)

    it("should walk straight through a door that is already open", function()
      setDoor(id, "n", 1)
      start()

      Explorer:DetermineNextRoom()

      assert.are.same({ "north" }, sent)
      assert.is_nil(Explorer.status.door)
      assert.is_nil(timers["Check Door"])
      assert.is_not_nil(timers["Check Stub"])
    end)

    it("should still fall back to the timer without being told", function()
      setDoor(id, "n", 2)
      Explorer.prefs.timeout = 3
      start()
      Explorer:DetermineNextRoom()
      setDoor(id, "n", 1)

      timers["Check Door"].callback()

      assert.are.same({ "open north door", "north" }, sent)
    end)

    it("should not care about doors outside of a run", function()
      raiseEvent("onDoorChange", id, "n", 1, 2)
      assert.are.equal(0, #sent)
    end)
  end)

  -- ==========================================================================
  -- Choosing a room to walk to
  -- ==========================================================================

  describe("FindCandidateRoom", function()
    local here, near, far, cut_off

    before_each(function()
      here = room()
      near = room({ EAST, SOUTH })
      far = room({ EAST })
      cut_off = room({ EAST })
      setExit(here, near, "north")
      setExit(near, far, "north")
      stand_in(here)
    end)

    it("should pick the closest reachable room", function()
      Explorer.todo = { far, cut_off, near }
      assert.are.equal(near, Explorer:FindCandidateRoom())
    end)

    it("should find nothing when no room can be reached", function()
      Explorer.todo = { cut_off }
      assert.is_nil(Explorer:FindCandidateRoom())
    end)

    it("should find a path once per room, however many stubs it has", function()
      local get_path, calls = getPath, 0
      shim("getPath", function(...)
        calls = calls + 1
        return get_path(...)
      end)

      Explorer.todo = { near, far }
      Explorer:FindCandidateRoom()

      assert.are.equal(2, calls)
    end)
  end)

  -- ==========================================================================
  -- Speedwalking
  -- ==========================================================================

  describe("speedwalking", function()
    local here, middle, dest

    -- Leave a run waiting to start its walk from here to dest.
    local function walk_scheduled()
      stand_in(here)
      start()
      Explorer:DetermineNextRoom()
      assert.are.equal(dest, Explorer.status.dest)
      assert.are.equal(1, #delayed)
    end

    before_each(function()
      here = room()
      middle = room()
      dest = room({ EAST })
      setExit(here, middle, "north")
      setExit(middle, dest, "north")
    end)

    it("should walk to the room with a stub", function()
      walk_scheduled()
      delayed[1]()

      assert.are.same({ dest }, walks)
    end)

    it("should not walk if exploration stopped during the delay", function()
      walk_scheduled()
      Explorer:StopExplore(true, true)

      delayed[1]()

      assert.are.equal(0, #walks)
      assert.are.equal(0, #sent)
    end)

    it("should leave the timing of a walk to Carto", function()
      _G.Carto = { walking = true }
      walk_scheduled()

      delayed[1]()
      raiseEvent("onMoveMap", middle)

      assert.is_nil(timers["Speedwalk Timeout"])
      assert.is_true(Explorer.exploring)
    end)

    it("should stop if the mapper can't start the walk", function()
      shim("gotoRoom", function()
        raiseEvent("onSpeedwalkFailed", "No exits found.")
        return true
      end)
      walk_scheduled()

      delayed[1]()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("Could not walk to room " .. dest .. ": No exits found.", 1, true))
    end)

    it("should stop if there is no path for the mapper to walk", function()
      shim("gotoRoom", function() return nil, "no path found" end)
      walk_scheduled()

      delayed[1]()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("Could not walk to room " .. dest .. ": No path found.", 1, true))
    end)

    it("should leave a walk that isn't its own running if it can't start", function()
      local reset = false
      _G.Carto = { walking = true, ResetWalking = function() reset = true end }
      shim("gotoRoom", function()
        raiseEvent("onSpeedwalkFailed", "You are already walking!")
        return true
      end)
      walk_scheduled()

      delayed[1]()

      assert.is_false(Explorer.exploring)
      assert.is_false(reset)
      assert.is_truthy(output():find("You are already walking!", 1, true))
    end)

    it("should carry on if somebody else can't walk during its walk", function()
      _G.Carto = { walking = true, ResetWalking = function() end }
      walk_scheduled()
      delayed[1]()
      printed = {}

      raiseEvent("onSpeedwalkFailed", "You are already walking!")

      assert.is_true(Explorer.exploring)
      assert.is_true(Explorer.status.speedwalking)
      assert.are.equal("", output())
    end)

    it("should carry on if somebody else can't walk before its walk starts", function()
      walk_scheduled()

      raiseEvent("onSpeedwalkFailed", "No exits found.")

      assert.is_true(Explorer.exploring)
    end)

    it("should not care about a failed walk outside of a run", function()
      raiseEvent("onSpeedwalkFailed", "No exits found.")
      assert.are.equal("", output())
    end)

    it("should stop if Carto finishes somewhere else", function()
      _G.Carto = { walking = true, ResetWalking = function() end }
      walk_scheduled()
      delayed[1]()
      stand_in(middle)

      raiseEvent("sysSpeedwalkFinished")

      assert.is_false(Explorer.exploring)
    end)

    it("should allow for generic_mapper's delay and its randomness", function()
      _G.map = { configs = { speedwalk_delay = 1, speedwalk_random = true } }
      Explorer.prefs.timeout = 2.5
      walk_scheduled()

      delayed[1]()

      assert.are.equal(4.5, timers["Speedwalk Timeout"].interval)
    end)

    it("should allow for generic_mapper's delay without randomness", function()
      _G.map = { configs = { speedwalk_delay = 1, speedwalk_random = false } }
      Explorer.prefs.timeout = 2.5
      walk_scheduled()

      delayed[1]()

      assert.are.equal(3.5, timers["Speedwalk Timeout"].interval)
    end)

    it("should wait for the last step after generic_mapper finishes", function()
      _G.map = { configs = {} }
      walk_scheduled()
      delayed[1]()
      stand_in(middle)

      raiseEvent("sysSpeedwalkFinished")

      assert.is_true(Explorer.exploring)
      assert.is_true(Explorer.status.speedwalking)

      -- A room along the way isn't the end of it.
      raiseEvent("onMoveMap", middle)
      assert.is_true(Explorer.status.speedwalking)

      stand_in(dest)
      raiseEvent("onMoveMap", dest)

      assert.is_true(Explorer.exploring)
      assert.is_false(Explorer.status.speedwalking)
      assert.is_nil(timers["Speedwalk Timeout"])
      assert.is_not_nil(timers["Determine Next Room"])
    end)

    it("should stop if the last step never lands after generic_mapper finishes", function()
      _G.map = { configs = {} }
      walk_scheduled()
      delayed[1]()
      stand_in(middle)
      raiseEvent("sysSpeedwalkFinished")

      timers["Speedwalk Timeout"].callback()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("ended in room", 1, true))
    end)

    it("should stop generic_mapper's walk when exploration stops", function()
      local stopped = 0
      _G.map = { configs = {}, stopSpeedwalk = function() stopped = stopped + 1 end }
      walk_scheduled()
      delayed[1]()

      Explorer:StopExplore(true, true)

      assert.are.equal(1, stopped)
    end)

    it("should leave generic_mapper alone if it wasn't walking", function()
      local stopped = 0
      _G.map = { configs = {}, stopSpeedwalk = function() stopped = stopped + 1 end }
      stand_in(here)
      start()

      Explorer:StopExplore(true, true)

      assert.are.equal(0, stopped)
    end)

    it("should stop if somebody stops the walk", function()
      walk_scheduled()
      delayed[1]()

      raiseEvent("sysSpeedwalkStopped")

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("was stopped", 1, true))
    end)

    it("should not care about a stopped walk when it isn't walking", function()
      stand_in(here)
      start()
      printed = {}

      raiseEvent("sysSpeedwalkStopped")

      assert.is_true(Explorer.exploring)
      assert.are.equal("", output())
    end)

    it("should stop if the walk times out", function()
      walk_scheduled()
      delayed[1]()

      timers["Speedwalk Timeout"].callback()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("ended in room", 1, true))
    end)

    it("should leave the doors on the route to the mapper", function()
      setDoor(here, "n", 2)
      setDoor(middle, "n", 2)
      walk_scheduled()
      delayed[1]()
      stand_in(middle)

      raiseEvent("onMoveMap", middle)

      assert.are.equal(0, #sent)
      assert.are.same({ dest }, walks)
    end)

    it("should carry on if the walk finishes at the destination", function()
      walk_scheduled()
      delayed[1]()
      stand_in(dest)

      raiseEvent("sysSpeedwalkFinished")

      assert.is_true(Explorer.exploring)
      assert.is_false(Explorer.status.speedwalking)
      assert.is_not_nil(timers["Determine Next Room"])
    end)

    it("should end the mapper's walk when exploration stops", function()
      local reset
      _G.Carto = {
        walking = true,
        ResetWalking = function(_, exception) reset = exception end,
      }
      walk_scheduled()
      delayed[1]()

      Explorer:StopExplore(true, true)

      assert.is_true(reset)
    end)

    it("should leave a walk it didn't start alone", function()
      local reset = false
      _G.Carto = {
        walking = true,
        ResetWalking = function() reset = true end,
      }
      stand_in(here)
      start()

      Explorer:StopExplore(true, true)

      assert.is_false(reset)
    end)

    it("should stop on an exception from the mapper", function()
      walk_scheduled()
      raiseEvent("onSpeedwalkReset", true, "You have veered off the expected path.")
      assert.is_false(Explorer.exploring)
    end)

    it("should stop and end the walk if the mapper pauses it", function()
      local reset
      _G.Carto = {
        walking = true,
        ResetWalking = function(_, exception) reset = exception end,
      }
      walk_scheduled()
      delayed[1]()

      raiseEvent("sysSpeedwalkPaused")

      assert.is_false(Explorer.exploring)
      assert.is_true(reset)
      assert.is_truthy(output():find("was paused", 1, true))
    end)

    it("should not care about a pause when it isn't walking", function()
      stand_in(here)
      start()
      printed = {}

      raiseEvent("sysSpeedwalkPaused")

      assert.is_true(Explorer.exploring)
      assert.are.equal("", output())
    end)

    it("should say nothing about walks outside of a run", function()
      raiseEvent("sysSpeedwalkStarted")
      assert.are.equal("", output())
    end)
  end)

  -- ==========================================================================
  -- Timers
  -- ==========================================================================

  describe("EnableTimer", function()
    local name = "Spec Timer"

    -- These use Mudlet's own named timers rather than the ones faked above.
    before_each(function()
      for _, global in ipairs({
        "registerNamedTimer", "deleteNamedTimer", "stopNamedTimer",
        "getNamedTimers", "deleteAllNamedTimers", "tempTimer",
      }) do
        _G[global] = real[global]
      end
    end)

    after_each(function()
      deleteNamedTimer(Explorer.config.name, name)
    end)

    it("should start a timer that doesn't exist yet", function()
      Explorer:EnableTimer(name, 60, function() end)

      assert.is_truthy(table.index_of(getNamedTimers(Explorer.config.name), name))
    end)

    it("should fire the callback of the latest call", function()
      local fired_with

      Explorer:EnableTimer(name, 60, function() fired_with = "first" end)
      Explorer:DisableTimer(name)
      Explorer:EnableTimer(name, 0.01, function() fired_with = "second" end)
      pumpEvents(100)

      assert.are.equal("second", fired_with)
    end)
  end)

  -- ==========================================================================
  -- Map label
  -- ==========================================================================

  describe("the map label", function()
    local id

    before_each(function()
      id = room({ NORTH })
      stand_in(id)
    end)

    it("should show an average of 0 before anything is explored", function()
      start()

      assert.is_truthy(labels[#labels]:find("Average speed: 0.000s", 1, true))
    end)

    it("should not keep the id of a label it deleted", function()
      start()
      assert.is_not_nil(Explorer.stats_label)

      Explorer:StopExplore(true, true)

      assert.is_nil(Explorer.stats_label)
    end)

    it("should stop cleanly when the current room isn't known", function()
      stand_in(nil)

      Explorer:Explore()
      assert.are.equal(0, #labels)

      Explorer:DetermineNextRoom()

      assert.is_false(Explorer.exploring)
      assert.is_truthy(output():find("Could not determine your current room", 1, true))
    end)

    it("should stay away when stats are off", function()
      Explorer.prefs.stats = false
      start()

      assert.are.equal(0, #labels)
    end)
  end)
end)
