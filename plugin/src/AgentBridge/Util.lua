--[[
	Small helpers shared by the agent bridge's modules.
]]

local Util = {}

-- Every action answers with a table; a failed one carries `ok = false` and an `error` message,
-- next to whatever else is useful to the caller (usually the current status).
function Util.fail(message: string, result: { [string]: any }?)
	local failed = result or {}
	failed.ok = false
	failed.error = message
	return failed
end

function Util.numberOr(value: any, default: number): number
	return if type(value) == "number" then value else default
end

function Util.pushCapped(list: { any }, item: any, cap: number)
	table.insert(list, item)
	if #list > cap then
		table.remove(list, 1)
	end
end

function Util.tail(list: { any }, count: number): { any }
	return table.move(list, math.max(1, #list - count + 1), #list, 1, {})
end

return Util
