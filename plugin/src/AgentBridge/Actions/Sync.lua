--[[
	What has been synced in this Studio session, and waiting for the next sync.
]]

local AgentBridge = script.Parent.Parent

local Constants = require(AgentBridge.Constants)
local PatchDescription = require(AgentBridge.PatchDescription)
local Status = require(AgentBridge.Status)
local Util = require(AgentBridge.Util)

local actions = {}

actions.history = {
	help = "{ since?, limit? } patches applied in this Studio session, newest last, with sequence numbers and paths",
	run = function(bridge, args)
		local since = Util.numberOr(args.since, 0)
		local limit = math.max(1, Util.numberOr(args.limit, Constants.DEFAULT_CHANGE_LIMIT))
		local patches = {}
		for _, entry in bridge.history do
			if entry.seq > since then
				local patch = PatchDescription.limit(entry, limit)
				patch.seq = entry.seq
				patch.time = entry.time
				patch.unapplied = entry.unapplied
				table.insert(patches, patch)
			end
		end
		return { ok = true, patchSeq = bridge.patchSeq, patches = patches }
	end,
}

actions.waitForSync = {
	help = "{ since?, timeout?, limit? } wait for a patch newer than `since` (default: the newest now) and return it",
	run = function(bridge, args)
		if Status.current(bridge) ~= "Connected" then
			return Util.fail("not connected", Status.report(bridge))
		end
		local since = Util.numberOr(args.since, bridge.patchSeq)
		local timeout = Util.numberOr(args.timeout, Constants.DEFAULT_TIMEOUT)
		local arrived = Status.waitUntil(function()
			return bridge.patchSeq > since or Status.current(bridge) ~= "Connected"
		end, timeout)

		local result = actions.history.run(bridge, { since = since, limit = args.limit })
		result.timedOut = not arrived
		if Status.current(bridge) ~= "Connected" then
			return Util.fail("the session ended while waiting", result)
		end
		return result
	end,
}

return actions
