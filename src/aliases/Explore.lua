local input = matches[2]:trim()
local command, subcommand, value = input:match("^(%S+)%s*(%S*)%s*(.*)$")

local help = Explorer.help.topics.usage

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
  helper.print({text = help, styles = Explorer.my_styles})
end
