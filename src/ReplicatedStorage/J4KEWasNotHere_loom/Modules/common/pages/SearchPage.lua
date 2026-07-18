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

	local Label = ctx.components.Label
	local MainButton = ctx.components.MainButton
	local TextInput = ctx.components.TextInput
	local Seperator = ctx.components.Seperator
	local Paragraph = ctx.components.Paragraph
	local VerticalCollapsibleSection = ctx.components.VerticalCollapsibleSection

	local makeCard = ctx.ui.makeCard
	local makeSectionHeader = ctx.ui.makeSectionHeader

	local wally_search = ctx.modules.wally_search
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

	-- Turns a raw `/package-search` entry into the flat shape the UI needs.
	local function describeResult(entry)
		local latest = wally_search.pickLatestVersion(entry)
		if not latest or not latest.name then
			return nil
		end
		return {
			name = latest.name,
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
			SearchStatusText:set(("No packages found for \"%s\"."):format(query))
		else
			SearchStatusText:set(("Found %d package(s)."):format(#results))
		end

		IsSearchingPackages:set(false)
	end

	return {
		makeCard({
			makeSectionHeader("Search for packages"),
			TextInput({
				Text = SearchQueryText,
				PlaceholderText = "e.g. \"fusion\" or \"sleitnick/net\"",
				Enabled = Computed(function()
					return not unwrap(IsVersionInstalling)
				end),
				[OnChange("Text")] = function(text)
					SearchQueryText:set(text)
				end,
			}),
			MainButton({
				Text = Computed(function()
					return unwrap(IsSearchingPackages) and "Searching…" or "Search"
				end),
				Size = UDim2.new(1, 0, 0, 34),
				Enabled = Computed(function()
					return not unwrap(IsSearchingPackages)
						and not unwrap(IsVersionInstalling)
						and unwrap(SearchQueryText) ~= ""
				end),
				Activated = runSearch,
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
					table.insert(
						items,
						VerticalCollapsibleSection({
							Text = ("%s @%s"):format(result.name, result.version),
							Collapsed = Value(true),
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
									MainButton({
										Text = ("Queue %s"):format(result.version),
										Size = UDim2.new(1, 0, 0, 30),
										Enabled = Computed(function()
											return not unwrap(IsVersionInstalling)
										end),
										Activated = function()
											if IsVersionInstalling:get() then
												return
											end

											local scope, pkg = splitName(result.name)

											addQueuedPackage({
												raw = result.name,
												scope = scope,
												package = pkg,
												version = result.version,
												name = "",
												includeDependencies = unwrap(DraftIncludeDependencies),
											})

											if Constants.warnForLicense then
												Constants.warnForLicense(result.license, result.name)
											end

											setPage("Queue")
										end,
									}),
								}),
							},
						})
					)
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
