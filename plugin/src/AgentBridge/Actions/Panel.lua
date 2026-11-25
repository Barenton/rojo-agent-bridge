--[[
	The Rojo panel: showing or hiding it, as the toolbar button does, and moving between its main
	and settings pages.
]]

local AgentBridge = script.Parent.Parent

local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

-- The settings page is only reachable from these pages, as in the UI.
local SETTINGS_REACHABLE_FROM = {
	NotConnected = true,
	Connected = true,
}

return {
	showPanel = {
		help = '{ visible?, page? = "Main" | "Settings" } open or close the Rojo panel and pick its page',
		run = function(bridge, args)
			local app = bridge.app
			if args.page ~= nil and args.page ~= "Main" and args.page ~= "Settings" then
				return Util.fail('page must be "Main" or "Settings"')
			end

			if type(args.visible) == "boolean" then
				app:setState({ guiEnabled = args.visible })
			end

			local appStatus = app.state.appStatus
			if args.page == "Settings" and appStatus ~= "Settings" then
				if not SETTINGS_REACHABLE_FROM[appStatus] then
					return Util.fail("the settings page is not available while " .. appStatus, Status.report(bridge))
				end
				app.backPage = appStatus
				app:setState({ appStatus = "Settings" })
			elseif args.page == "Main" and appStatus == "Settings" then
				app:setState({ appStatus = app.backPage or "NotConnected" })
			end

			return Status.report(bridge)
		end,
	},
}
