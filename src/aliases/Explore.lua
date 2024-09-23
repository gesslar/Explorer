local input = matches[2]:trim()
local command, subcommand, value = input:match("^(%S+)%s*(%S*)%s*(.*)$")

local help = [[
Syntax: explore [command]

  explore start - Start exploring
  explore stop - Stop exploring
  explore set - See your current preference settings
  explore set <preference> <value> - Set a preference to a value

  Available preferences:
    speed         - Set the speed of exploration (default: 0.0)
    shuffle_max   - Set the maximum number of steps to take before selecting a
                    random exit stub to explore (default: 100)
    zoom_level    - Set the zoom level of the map during exploration
                    (default: 10)
]]

if command == "start" then
  -- Call function to start exploration
  Explorer:Explore()
elseif command == "stop" then
  -- Call function to stop exploration
  Explorer:StopExplore(true)
  if Mapper.walking then
    Mapper:ResetWalking()
  end
elseif command == "set" then
  if subcommand and value ~= "" then
    Explorer:SetPreferences(subcommand, tonumber(value))
  else
    -- Show current preference settings
    cecho("Current preferences:\n")
    cecho("  Speed: " .. Explorer.prefs.speed .. "\n")
    cecho("  Shuffle Max: " .. Explorer.prefs.shuffle_max .. "\n")
    cecho("  Zoom Level: " .. Explorer.prefs.zoom_level .. "\n")
  end
else
  -- Print out the explore instructions
  cecho(help)
end
