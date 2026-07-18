--[[
	SearchPage.lua

	Lets the user search the Wally registry by keyword and queue a
	result's latest version directly, using wally-search.lua's existing
	`searchPackages` / `pickLatestVersion` helpers.
]]

return function(ctx)
	local Computed = ctx.fusion.Computed
	local unwrap = ctx.fusion.unwrap
	local Value = ctx.fusion.Value
	local Children = ctx.fusion.Children
	local OnChange = ctx.fusion.OnChange
	local Observer = ctx.fusion.Observer

	local Label = ctx.components.Label
	local MainButton = ctx.components.MainButton
	local TextInput = ctx.components.TextInput
	local Seperator = ctx.components.Seperator
	local Paragraph = ctx.components.Paragraph
	local VerticalCollapsibleSection = ctx.components.VerticalCollapsibleSection

	local makeCard = ctx.ui.makeCard
	local makeSectionHeader = ctx.ui.makeSectionHeader

	local wally_search = ctx.modules.wally_search
	local package_instancer = ctx.modules.package_instancer
	local Constants = ctx.modules.Constants

	local splitName = ctx.utils.splitName

	local IsVersionInstalling = ctx.state.IsVersionInstalling
	local SearchQueryText = ctx.state.SearchQueryText
	local SearchResults = ctx.state.SearchResults
	local IsSearchingPackages = ctx.state.IsSearchingPackages
	local SearchStatusText = ctx.state.SearchStatusText
	local DraftIncludeDependencies = ctx.state.DraftIncludeDependencies

	local addQueuedPackage = ctx.actions.addQueuedPackage
	local setPage = ctx.actions.setPage

	local function describeResult(entry)
		local latest = wally_search.pickLatestVersion(entry)
		if not latest or not latest.name then
			return nil
		end

		local scope, pkg = splitName(latest.name)

		return {
			raw = latest.name,
			scope = scope,
			name = pkg,
			version = latest.version,
			description = latest.description,
			license = latest.license,
		}
	end

	local function runSearch()
		local query = unwrap(SearchQueryText)
		if query == "" then
			return
		end
		if IsSearchingPackages:get() then
			return
		end

		IsSearchingPackages:set(true)
		SearchStatusText:set("Searching…")

		local ok, data = wally_search.searchPackages(query)

		local results = {}
		if ok then
			for _, entry in ipairs(data) do
				local described = describeResult(entry)
				if described then
					table.insert(results, described)
				end
			end
		end

		SearchResults:set(results)
		if not ok then
			SearchStatusText:set("Search failed. Check your connection and try again.")
		elseif #results == 0 then
			SearchStatusText:set(('No packages found for "%s".'):format(query))
		else
			SearchStatusText:set(("Found %d package(s)."):format(#results))
		end

		IsSearchingPackages:set(false)
	end

	SearchStatusText:set("Waiting for input..")

	local _yeildingThread = nil
	local _yeildTime = 0.75

	local function cancel(thread: thread): nil
		if typeof(thread) == "thread" and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
		return nil
	end

	local function queuePackage(result, version)
		if IsVersionInstalling:get() then
			return
		end

		local realm, existingSource, existingReference =
			package_instancer.findInstalled(result.scope, result.name, version)

		addQueuedPackage({
			raw = result.raw,
			scope = result.scope,
			package = result.name,
			version = version,
			name = "",
			includeDependencies = unwrap(DraftIncludeDependencies),
			reference = existingReference,
			existingSource = existingSource,
			realm = realm,
		})

		if Constants.warnForLicense then
			Constants.warnForLicense(result.license, result.raw)
		end

		setPage("Queue")
	end

	local function buildResultItem(result)
		local Collapsed = Value(true)
		local Versions = Value(nil) -- nil = not fetched yet, table = fetched (may be empty)
		local requested = false

		local function ensureVersionsLoaded()
			if requested then
				return
			end
			requested = true

			task.spawn(function()
				local ok, versions = wally_search.getPackageDetails(result.scope, result.name)
				if not ok then
					Versions:set({})
					return
				end

				local sorted = {}
				for _, ver in pairs(versions) do
					table.insert(sorted, ver)
				end
				table.sort(sorted, function(a, b)
					return wally_search.compareVersions(a.version, b.version) > 0
				end)
				Versions:set(sorted)
			end)
		end

		Observer(Collapsed):onChange(function()
			if not unwrap(Collapsed) then
				ensureVersionsLoaded()
			end
		end)

		return VerticalCollapsibleSection({
			Text = ("%s/%s"):format(result.scope, result.name),
			Collapsed = Collapsed,
			[Children] = {
				makeCard({
					Paragraph({
						Text = (result.description and result.description ~= "")
								and result.description
							or "No description provided.",
						MaxHeight = 80,
						MinHeight = 20,
						TextColor3 = Color3.fromRGB(200, 200, 200),
					}),
					Label({
						Text = "License: " .. (result.license or "unspecified"),
						TextSize = 12,
						TextColor3 = Color3.fromRGB(160, 160, 160),
					}),
					Computed(function()
						local versions = unwrap(Versions)

						if versions == nil then
							return {
								Label({
									Text = "Loading versions…",
									TextColor3 = Color3.fromRGB(160, 160, 160),
								}),
							}
						end

						if #versions == 0 then
							return {
								MainButton({
									Text = ("Queue %s"):format(result.version),
									Size = UDim2.new(1, 0, 0, 30),
									Enabled = Computed(function()
										return not unwrap(IsVersionInstalling)
									end),
									Activated = function()
										queuePackage(result, result.version)
									end,
								}),
							}
						end

						local rows = {}
						for _, v in ipairs(versions) do
							table.insert(
								rows,
								MainButton({
									Text = ("Queue %s"):format(v.version),
									Size = UDim2.new(1, 0, 0, 26),
									Enabled = Computed(function()
										return not unwrap(IsVersionInstalling)
									end),
									Activated = function()
										queuePackage(result, v.version)
									end,
								})
							)
						end
						return rows
					end, function(instances)
						for _, inst in ipairs(instances or {}) do
							if inst and inst.Destroy then
								inst:Destroy()
							end
						end
					end),
				}),
			},
		})
	end

	return {
		makeCard({
			makeSectionHeader("Search for packages"),
			TextInput({
				Text = SearchQueryText,
				PlaceholderText = 'e.g. "fusion" or "sleitnick/net"',
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				[OnChange("Text")] = function(text)
					if _yeildingThread then
						_yeildingThread = cancel(_yeildingThread)
					end

					SearchQueryText:set(text)

					_yeildingThread = task.delay(_yeildTime, function()
						if unwrap(SearchQueryText) ~= "" then
							_yeildingThread = cancel(_yeildingThread)
							runSearch()
						end
					end)
				end,
			}),
			Label({
				Text = SearchStatusText,
				TextColor3 = Color3.fromRGB(180, 180, 180),
			}),
		}),
		Seperator({}),
		makeCard({
			Computed(function()
				local results = unwrap(SearchResults)
				if #results == 0 then
					return {
						Label({
							Text = "Search the Wally registry above to find packages.",
							TextColor3 = Color3.fromRGB(180, 180, 180),
						}),
					}
				end

				local items = {}
				for _, result in ipairs(results) do
					table.insert(items, buildResultItem(result))
				end
				return items
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
