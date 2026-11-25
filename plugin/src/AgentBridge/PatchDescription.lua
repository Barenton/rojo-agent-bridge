--[[
	Describes a patch as lists of instance paths, the form agents read in pendingChanges and
	history.
]]

local PatchDescription = {}

local function fullNameOf(instance: Instance?): string?
	return if instance then instance:GetFullName() else nil
end

local function byPath(a, b)
	return a.path < b.path
end

--[[
	Works on a patch that is still waiting (added instances do not exist yet, so they are named
	through their parent) and on one that was just applied (removed instances are gone, so their
	paths must have been captured beforehand, in `removedPaths`).
]]
function PatchDescription.describe(patch, instanceMap, removedPaths: { [any]: string }?)
	local added, removed, updated = {}, {}, {}

	for id, virtualInstance in patch.added do
		local path = fullNameOf(instanceMap.fromIds[id])
		if path == nil then
			local parentPath = fullNameOf(instanceMap.fromIds[virtualInstance.Parent])
			if parentPath == nil then
				local addedParent = patch.added[virtualInstance.Parent]
				parentPath = if addedParent then "(new) " .. addedParent.Name else "?"
			end
			path = parentPath .. "." .. virtualInstance.Name
		end
		table.insert(added, { path = path, className = virtualInstance.ClassName })
	end

	for _, idOrInstance in patch.removed do
		local path = if removedPaths then removedPaths[idOrInstance] else nil
		if path == nil then
			local instance = if typeof(idOrInstance) == "Instance"
				then idOrInstance
				else instanceMap.fromIds[idOrInstance]
			path = fullNameOf(instance) or tostring(idOrInstance)
		end
		table.insert(removed, { path = path })
	end

	for _, update in patch.updated do
		local properties = {}
		for name in update.changedProperties do
			table.insert(properties, name)
		end
		if update.changedName ~= nil then
			table.insert(properties, "Name")
		end
		if update.changedClassName ~= nil then
			table.insert(properties, "ClassName")
		end
		table.sort(properties)
		table.insert(updated, {
			path = fullNameOf(instanceMap.fromIds[update.id]) or tostring(update.id),
			properties = properties,
		})
	end

	table.sort(added, byPath)
	table.sort(removed, byPath)
	table.sort(updated, byPath)

	return { added = added, removed = removed, updated = updated }
end

-- Paths of the instances a patch removes, read while they still exist.
function PatchDescription.capturePaths(patch, instanceMap): { [any]: string }
	local removedPaths = {}
	for _, idOrInstance in patch.removed do
		local instance = if typeof(idOrInstance) == "Instance" then idOrInstance else instanceMap.fromIds[idOrInstance]
		removedPaths[idOrInstance] = fullNameOf(instance)
	end
	return removedPaths
end

-- A copy of a description with each list cut to `limit` entries, and the full counts.
function PatchDescription.limit(description, limit: number)
	local function head(list)
		return table.move(list, 1, math.min(#list, limit), 1, {})
	end
	return {
		counts = {
			added = #description.added,
			removed = #description.removed,
			updated = #description.updated,
		},
		truncated = #description.added > limit or #description.removed > limit or #description.updated > limit,
		added = head(description.added),
		removed = head(description.removed),
		updated = head(description.updated),
	}
end

return PatchDescription
