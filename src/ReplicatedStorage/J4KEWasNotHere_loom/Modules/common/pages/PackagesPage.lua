--[[
	PackagesPage.lua

	Lists every Loom-managed package installation and shows the latest
	available version plus dependency references from the installed graph.
]]

return function(ctx)
	local Computed = ctx.fusion.Computed
	local unwrap = ctx.fusion.unwrap
	local Value = ctx.fusion.Value
	local Children = ctx.fusion.Children

	local Label = ctx.components.Label
	local MainButton = ctx.components.MainButton
	local VerticalCollapsibleSection = ctx.components.VerticalCollapsibleSection

	local makeCard = ctx.ui.makeCard
	local makeSectionHeader = ctx.ui.makeSectionHeader

	local package_instancer = ctx.modules.package_instancer
	local wally_search = ctx.modules.wally_search
	local splitName = ctx.utils.splitName

	local StatusText = ctx.state.StatusText
	local IsVersionInstalling = ctx.state.IsVersionInstalling

	local setPage = ctx.actions.setPage
	local addQueuedPackage = ctx.actions.addQueuedPackage

	local function buildQueueEntry(record, version)
		local scope, package = splitName(record.id)
		if not scope or not package then
			return nil
		end

		return {
			raw = scope .. "/" .. package,
			scope = scope,
			package = package,
			version = version,
			name = "",
			includeDependencies = true,
			realm = record.realm,
		}
	end

	local function queueVersion(record, version)
		if IsVersionInstalling:get() then
			return
		end

		local entry = buildQueueEntry(record, version)
		if not entry then
			return
		end

		local realm, existingSource, existingReference =
			package_instancer.findInstalled(entry.scope, entry.package, version)
		entry.reference = existingReference
		entry.existingSource = existingSource
		entry.realm = realm or entry.realm
		addQueuedPackage(entry)
		setPage("Queue")
	end

	local function describeStatus(record, latestVersion)
		if not record.version or record.version == "" then
			return "missing", Color3.fromRGB(255, 99, 99)
		end

		if latestVersion and wally_search.compareVersions(latestVersion, record.version) > 0 then
			return "update available", Color3.fromRGB(255, 166, 77)
		end

		return "up to date", Color3.fromRGB(110, 235, 160)
	end

	local function getReferenceCounts()
		local counts = {}
		for _, candidate in ipairs(package_instancer.getManagedPackageSummary() or {}) do
			for _, dependency in ipairs(candidate.dependencies or {}) do
				counts[dependency] = (counts[dependency] or 0) + 1
			end
		end
		return counts
	end

	local function loadLatestVersion(record)
		local scope, package = splitName(record.id)
		if not scope or not package then
			return nil, {}
		end

		local ok, _, indexed = wally_search.getPackageDetails(scope, package)
		if not ok then
			return nil, {}
		end

		local sorted = {}
		for _, version in ipairs(indexed or {}) do
			table.insert(sorted, version)
		end
		table.sort(sorted, function(a, b)
			return wally_search.compareVersions(a, b) > 0
		end)

		return sorted[1], sorted
	end

	local function buildVersionRows(record, orderedVersions)
		local rows = {}
		for _, version in ipairs(orderedVersions or {}) do
			table.insert(
				rows,
				MainButton({
					Text = version,
					Size = UDim2.new(1, 0, 0, 28),
					Activated = function()
						queueVersion(record, version)
					end,
				})
			)
		end

		if #rows == 0 then
			return {
				Label({
					Text = "No registry versions were fetched for this package.",
					TextColor3 = Color3.fromRGB(180, 180, 180),
				}),
			}
		end
		return rows
	end

	local function buildDependencyItems(record)
		local counts = getReferenceCounts()
		local rows = {}
		local dependencies = record.dependencies or {}
		if #dependencies == 0 then
			return {
				Label({
					Text = "No dependencies declared for this package.",
					TextColor3 = Color3.fromRGB(180, 180, 180),
				}),
			}
		end

		for _, dependency in ipairs(dependencies) do
			table.insert(
				rows,
				makeCard({
					Label({
						Text = dependency,
						TextSize = 12,
						TextColor3 = Color3.fromRGB(240, 240, 240),
					}),
					Label({
						Text = ("Referenced by %d package(s)"):format(counts[dependency] or 0),
						TextSize = 10,
						TextColor3 = Color3.fromRGB(180, 180, 180),
					}),
				})
			)
		end
		return rows
	end

	local function buildPackageCard(record)
		local latestVersion, orderedVersions = loadLatestVersion(record)
		local statusText, statusColor = describeStatus(record, latestVersion)

		return VerticalCollapsibleSection({
			Text = record.id,
			Collapsed = Value(true),
			[Children] = {
				makeCard({
					Label({
						Text = record.id,
						TextSize = 15,
						TextColor3 = Color3.fromRGB(255, 255, 255),
					}),
					Label({
						Text = ("Installed version: %s"):format(record.version or "missing"),
						TextSize = 12,
						TextColor3 = Color3.fromRGB(210, 210, 210),
					}),
					Label({
						Text = ("Latest available version: %s"):format(
							latestVersion or "unavailable"
						),
						TextSize = 12,
						TextColor3 = Color3.fromRGB(210, 210, 210),
					}),
					Label({
						Text = statusText,
						TextColor3 = statusColor,
						TextSize = 11,
					}),
					MainButton({
						Text = "Update",
						Size = UDim2.new(1, 0, 0, 30),
						Enabled = Computed(function()
							return not unwrap(IsVersionInstalling) and latestVersion ~= nil
						end),
						Activated = function()
							if latestVersion then
								queueVersion(record, latestVersion)
							end
						end,
					}),
					VerticalCollapsibleSection({
						Text = "Change version",
						Collapsed = Value(true),
						[Children] = buildVersionRows(record, orderedVersions),
					}),
					MainButton({
						Text = "Remove",
						Size = UDim2.new(1, 0, 0, 30),
						Activated = function()
							local removed = package_instancer.removePackage(
								record.realm,
								record.id,
								record.version
							)
							StatusText:set(
								removed and "Package removed from Loom."
									or "Package could not be removed."
							)

							if removed then
								setPage("Start")
								setPage("Packages")
							end
						end,
					}),
					VerticalCollapsibleSection({
						Text = "Dependencies",
						Collapsed = Value(true),
						[Children] = buildDependencyItems(record),
					}),
				}),
			},
		})
	end

	local function buildPage()
		local records = package_instancer.getManagedPackageSummary() or {}
		if #records == 0 then
			return {
				Label({
					Text = "No Loom-managed packages are installed yet.",
					TextColor3 = Color3.fromRGB(180, 180, 180),
				}),
			}
		end

		local cards = {}
		for _, record in ipairs(records) do
			if record then
				table.insert(cards, buildPackageCard(record))
			end
		end
		return cards
	end

	return {
		makeCard({
			makeSectionHeader("Installed packages"),
			Label({
				Text = "Every Loom-managed install is listed here with version status and dependencies.",
				TextSize = 12,
				TextColor3 = Color3.fromRGB(180, 180, 180),
			}),
			Computed(function()
				return buildPage()
			end, function(instances)
				for _, inst in ipairs(instances or {}) do
					if inst and inst.Destroy then
						inst:Destroy()
					end
				end
			end),
		}),
	}
end
