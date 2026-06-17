local input = matches[2]:trim()
local command, subcommand, value = input:match("^(%S+)%s*(%S*)%s*(.*)$")

local help = Explorer.help.topics.usage

if command == "start" then
  -- Call function to start exploration
  Explorer:Explore()
elseif command == "stop" then
  -- Call function to stop exploration
  Explorer:StopExplore(true, false)
elseif command == "debug" then
  Explorer.debug = not Explorer.debug
  cecho("<gold>Debug mode " .. (Explorer.debug and "enabled" or "disabled") .. ".\n")
elseif command == "set" then
  if subcommand and value ~= "" then
    Explorer:SetPreference(subcommand, value)
  else
    -- Show current preference settings
    echo(f [[Current {Explorer.config.name} preferences:]] .. "\n\n")
    echo(f [[  Shuffle interval: {Explorer.prefs.shuffle}]] .. "\n")
    echo(f [[  Zoom level: {Explorer.prefs.zoom}]] .. "\n")
    echo(f [[  Movement speed: {Explorer.prefs.speed}]] .. "\n")
    echo(f [[  Show stats: {tostring(Explorer.prefs.stats)}]] .. "\n")
  end
else
  -- Print out the explore instructions
  helper.print({text = help, styles = Explorer.help_styles})
end
