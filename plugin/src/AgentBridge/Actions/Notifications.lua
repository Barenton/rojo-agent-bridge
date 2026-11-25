--[[
	The plugin's notifications: reading them, and pressing their buttons (Connect, Forget,
	Restore, Dismiss, ...) as the user would.
]]

local AgentBridge = script.Parent.Parent

local Constants = require(AgentBridge.Constants)
local Util = require(AgentBridge.Util)

-- The buttons a notification shows, in the order it shows them.
local function actionNames(notification): { string }
	local names = {}
	for name in notification.actions or {} do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return notification.actions[a].layoutOrder < notification.actions[b].layoutOrder
	end)
	return names
end

-- Closes a notification the way its component does once it has faded out.
local function close(app, id: number, notification)
	if app.state.notifications[id] == nil then
		return
	end
	app:closeNotification(id)
	if notification.onClose then
		notification.onClose()
	end
end

local actions = {}

actions.notifications = {
	help = "{ limit? } the plugin's recent notifications, newest last; those still showing have an id and their buttons",
	run = function(bridge, args)
		local limit = math.max(1, Util.numberOr(args.limit, Constants.NOTIFICATION_LOG_SIZE))
		local live = bridge.app.state.notifications or {}
		local entries = {}
		for _, entry in Util.tail(bridge.notifications, limit) do
			local notification = if entry.id then live[entry.id] else nil
			table.insert(entries, {
				id = entry.id,
				text = entry.text,
				time = entry.time,
				showing = notification ~= nil,
				actions = if notification then actionNames(notification) else nil,
			})
		end
		return { ok = true, notifications = entries }
	end,
}

actions.notificationAction = {
	help = "{ id, action } press one of a showing notification's buttons",
	run = function(bridge, args)
		local app = bridge.app
		local id = args.id
		local notification = if type(id) == "number" then app.state.notifications[id] else nil
		if notification == nil then
			return Util.fail("no notification with that id is showing; call notifications for the list")
		end
		local button = if type(args.action) == "string" and notification.actions
			then notification.actions[args.action]
			else nil
		if button == nil then
			return Util.fail("that notification has no such button", { actions = actionNames(notification) })
		end

		-- As in the notification component: the button's handler runs, then the notification closes.
		local ran, err = true, nil
		if button.onClick then
			ran, err = pcall(button.onClick)
		end
		close(app, id, notification)
		if not ran then
			return Util.fail("the button's handler failed: " .. tostring(err))
		end
		return { ok = true, id = id, action = args.action }
	end,
}

actions.dismissNotification = {
	help = "{ id } close a showing notification without pressing a button",
	run = function(bridge, args)
		local app = bridge.app
		local id = args.id
		local notification = if type(id) == "number" then app.state.notifications[id] else nil
		if notification == nil then
			return Util.fail("no notification with that id is showing; call notifications for the list")
		end
		close(app, id, notification)
		return { ok = true, id = id }
	end,
}

return actions
