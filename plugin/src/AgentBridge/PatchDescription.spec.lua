return function()
	local PatchDescription = require(script.Parent.PatchDescription)

	local function createInstanceMap(fromIds)
		return { fromIds = fromIds }
	end

	describe("describe", function()
		it("names added instances through their parent, and nested ones through their new parent", function()
			local folder = Instance.new("Folder")
			folder.Name = "Shared"

			local patch = {
				added = {
					MODULE = { Name = "Module", ClassName = "ModuleScript", Parent = "FOLDER" },
					CHILD = { Name = "Child", ClassName = "Folder", Parent = "MODULE" },
				},
				removed = {},
				updated = {},
			}

			local description = PatchDescription.describe(patch, createInstanceMap({ FOLDER = folder }))

			expect(#description.added).to.equal(2)
			expect(description.added[1].path).to.equal("(new) Module.Child")
			expect(description.added[2].path).to.equal("Shared.Module")
			expect(description.added[2].className).to.equal("ModuleScript")

			folder:Destroy()
		end)

		it("uses captured paths for instances that were removed before it ran", function()
			local gone = Instance.new("ModuleScript")
			gone.Name = "Gone"
			local instanceMap = createInstanceMap({ GONE = gone })
			local patch = { added = {}, removed = { "GONE" }, updated = {} }

			local removedPaths = PatchDescription.capturePaths(patch, instanceMap)
			gone:Destroy()
			instanceMap.fromIds.GONE = nil

			local description = PatchDescription.describe(patch, instanceMap, removedPaths)
			expect(description.removed[1].path).to.equal("Gone")
		end)

		it("lists the properties an update changes, including name and class", function()
			local part = Instance.new("Part")
			part.Name = "Block"
			local patch = {
				added = {},
				removed = {},
				updated = {
					{
						id = "PART",
						changedProperties = { Size = {}, Anchored = {} },
						changedName = "Brick",
					},
				},
			}

			local description = PatchDescription.describe(patch, createInstanceMap({ PART = part }))

			expect(description.updated[1].path).to.equal("Block")
			expect(table.concat(description.updated[1].properties, ",")).to.equal("Anchored,Name,Size")

			part:Destroy()
		end)
	end)

	describe("limit", function()
		it("cuts each list and keeps the full counts", function()
			local description = {
				added = { { path = "a" }, { path = "b" }, { path = "c" } },
				removed = { { path = "d" } },
				updated = {},
			}

			local limited = PatchDescription.limit(description, 2)

			expect(#limited.added).to.equal(2)
			expect(limited.counts.added).to.equal(3)
			expect(limited.counts.removed).to.equal(1)
			expect(limited.truncated).to.equal(true)
		end)

		it("is not truncated when every list fits", function()
			local limited = PatchDescription.limit({ added = { { path = "a" } }, removed = {}, updated = {} }, 5)
			expect(limited.truncated).to.equal(false)
		end)
	end)
end
