--[[
	Every action the bridge answers, gathered from one module per part of the plugin.

	Each module returns a table of actions by name, each with a one-line `help` and a
	`run(bridge, args)` function that returns a result table.
]]

local GROUPS = {
	require(script.Info),
	require(script.Session),
	require(script.Confirmation),
	require(script.Sync),
	require(script.Panel),
	require(script.Preferences),
	require(script.Notifications),
}

local handlers = {}
local help = {}

for _, group in GROUPS do
	for name, action in group do
		-- Two modules defining one name would silently drop one of them.
		assert(handlers[name] == nil, "agent bridge action defined twice: " .. name)
		handlers[name] = action.run
		help[name] = action.help
	end
end

return {
	handlers = handlers,
	help = help,
}
