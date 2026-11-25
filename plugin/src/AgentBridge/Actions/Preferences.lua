--[[
	The settings page, on the same terms as for the user, except for the bridge's own switch.
]]

local AgentBridge = script.Parent.Parent
local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin

local Settings = require(Plugin.Settings)

local SettingsAccess = require(AgentBridge.SettingsAccess)
local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

local function contextOf(bridge)
	return { syncActive = Status.isSyncActive(bridge) }
end

return {
	getSettings = {
		help = "every plugin setting, its value, and what it may be set to",
		run = function(bridge, _args)
			local settings, details = SettingsAccess.describe(contextOf(bridge))
			return { ok = true, settings = settings, details = details }
		end,
	},

	setSetting = {
		help = "{ name, value } change one plugin setting, as the settings page would",
		run = function(bridge, args)
			local value, reason = SettingsAccess.validate(args.name, args.value, contextOf(bridge))
			if reason then
				return Util.fail(reason)
			end

			local name = args.name
			local previous = Settings:get(name)
			if previous ~= value then
				Settings:set(name, value)
				bridge:announce(string.format("an agent set %s to %s.", name, tostring(value)))
			end
			return { ok = true, name = name, value = value, previous = previous }
		end,
	},
}
