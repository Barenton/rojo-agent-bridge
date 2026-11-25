--[[
	Questions about the bridge itself: what it can do, what it is doing, what it was asked.
]]

local AgentBridge = script.Parent.Parent

local Constants = require(AgentBridge.Constants)
local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

return {
	help = {
		help = "this list",
		run = function(_bridge, _args)
			-- Required lazily: the registry requires this module while it is being built.
			local Actions = require(script.Parent)
			return { ok = true, actions = Actions.help, bridgeVersion = Constants.BRIDGE_VERSION }
		end,
	},

	status = {
		help = "what the plugin and its session are doing",
		run = function(bridge, _args)
			return Status.report(bridge)
		end,
	},

	activity = {
		help = "{ limit? } what was asked of this bridge, newest last",
		run = function(bridge, args)
			local limit = math.max(1, Util.numberOr(args.limit, Constants.ACTIVITY_LOG_SIZE))
			return { ok = true, activity = Util.tail(bridge.activity, limit) }
		end,
	},
}
