--[[
	The confirmation page: reading what a sync would change, and accepting, rejecting or aborting.
]]

local Rojo = script:FindFirstAncestor("Rojo")
local Plugin = Rojo.Plugin
local AgentBridge = script.Parent.Parent

local Assets = require(Plugin.Assets)
local Settings = require(Plugin.Settings)

local Constants = require(AgentBridge.Constants)
local PatchDescription = require(AgentBridge.PatchDescription)
local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

local CHOICES = { "Accept", "Reject", "Abort" }

local actions = {}

actions.pendingChanges = {
	help = "{ limit? } what a waiting confirmation would add, remove and update",
	run = function(bridge, args)
		local pending = bridge.pendingPatch
		if Status.current(bridge) ~= "Confirming" or pending == nil then
			return Util.fail("nothing is waiting for confirmation", Status.report(bridge))
		end

		local limit = math.max(1, Util.numberOr(args.limit, Constants.DEFAULT_CHANGE_LIMIT))
		local result = PatchDescription.limit(pending, limit)
		result.ok = true
		result.status = "Confirming"
		result.projectName = pending.projectName
		return result
	end,
}

actions.confirm = {
	help = '{ choice = "Accept" | "Reject" | "Abort", timeout? } answer a waiting confirmation',
	run = function(bridge, args)
		local app = bridge.app
		local choice = args.choice
		if table.find(CHOICES, choice) == nil then
			return Util.fail('choice must be "Accept", "Reject" or "Abort"')
		end
		if Status.current(bridge) ~= "Confirming" then
			return Util.fail("nothing is waiting for confirmation", Status.report(bridge))
		end
		-- The page only offers Reject with two-way sync, because only then can Studio's version win.
		if choice == "Reject" and not Settings:get("twoWaySync") then
			return Util.fail("Reject needs two-way sync to be enabled", Status.report(bridge))
		end

		local timeout = Util.numberOr(args.timeout, Constants.DEFAULT_TIMEOUT)
		app.confirmationBindable:Fire(choice)
		local settled = Status.waitFor(bridge, function(current)
			return current ~= "Confirming" and current ~= "Connecting"
		end, timeout)

		bridge:announce(string.format("an agent answered the confirmation with %s.", choice))
		if choice == "Abort" and settled then
			-- Rojo reports an abort as an error. For the caller it is the outcome it asked for, so
			-- leave the error page as the user would.
			if app.state.appStatus == "Error" then
				app:setState({
					appStatus = "NotConnected",
					toolbarIcon = Assets.Images.PluginButton,
				})
			end
			local result = Status.report(bridge)
			result.aborted = true
			return result
		end
		return Status.outcome(bridge, settled, timeout)
	end,
}

return actions
