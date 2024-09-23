local input = matches[2]:trim()
local command, subcommand, value = input:match("^(%S+)%s*(%S*)%s*(.*)$")

local help = [[
Syntax: explore [command]

  explore start - Start exploring
  explore stop - Stop exploring
  explore set - See your current preference settings
  explore set <preference> <value> - Set a preference to a value

  Available preferences:
    shuffle   - Set the maximum number of steps to take before selecting a
                random exit stub to explore (default: 100)
    zoom      - Set the zoom level of the map during exploration
                (default: 10)
]]

if command == "start" then
  -- Call function to start exploration
  Explorer:Explore()
elseif command == "stop" then
  -- Call function to stop exploration
  Explorer:StopExplore(true)
elseif command == "set" then
  if subcommand and value ~= "" then
    Explorer:SetPreference(subcommand, value)
  else
    -- Show current preference settings
    cecho("Current preferences:\n")
    cecho("  Shuffle: " .. Explorer.prefs.shuffle .. "\n")
    cecho("  Zoom Level: " .. Explorer.prefs.zoom .. "\n")
  end
else
  -- Print out the explore instructions
  cecho(help)
end
