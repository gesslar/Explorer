local input = (matches[2] or ""):trim()
local command, subcommand, value = input:match("^(%S+)%s*(%S*)%s*(.*)$")

local help = Explorer.help.topics.usage

if command == "start" then
  -- Call function to start exploration
  Explorer:Explore()
elseif command == "stop" then
  -- Call function to stop exploration
  if Explorer.exploring then
    Explorer:StopExplore(true, false)
  else
    cecho("<orange>No exploration is in progress.\n")
  end
elseif command == "debug" then
  Explorer.debug = not Explorer.debug
  cecho("<gold>Debug mode " .. (Explorer.debug and "enabled" or "disabled") .. ".\n")
elseif command == "set" then
  if subcommand and value ~= "" then
    Explorer:SetPreference(subcommand, value)
  else
    -- Show current preference settings
    echo(f [[Current {Explorer.config.name} preferences:]] .. "\n\n")
    echo(f [[  Zoom level: {Explorer.prefs.zoom}]] .. "\n")
    echo(f [[  Movement speed: {Explorer.prefs.speed}]] .. "\n")
    echo(f [[  Response timeout: {Explorer.prefs.timeout}]] .. "\n")
    echo(f [[  Show stats: {tostring(Explorer.prefs.stats)}]] .. "\n")
  end
elseif command == "ignore" then
  if subcommand ~= "" then
    Explorer:IgnoreDirection(subcommand, value)
  else
    Explorer:ListIgnored()
  end
elseif command == "unignore" then
  Explorer:UnignoreDirection(subcommand, value)
else
  -- Print out the explore instructions
  helper.print({text = help, styles = Explorer.help_styles})
end
