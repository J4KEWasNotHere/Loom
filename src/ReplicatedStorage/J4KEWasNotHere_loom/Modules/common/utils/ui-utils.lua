--[[
	ui-utils.lua

	Small Fusion UI builders shared by every page (the rounded card
	container and the small section-header label). These need `New`,
	`Children`, and the `Label` component, so this module is a factory:
	call it once with those dependencies and it hands back the builders.
]]

return function(New, Children, Label)
	local UiUtils = {}

	function UiUtils.makeCard(contents, y: NumberRange?)
		return New("Frame")({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0.7,
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BorderSizePixel = 0,
			[Children] = {
				New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
				New("UIPadding")({
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
				}),
				New("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				New("UISizeConstraint")({
					MaxSize = Vector2.new(9999, y and y.Max or 9999),
					MinSize = Vector2.new(0, y and y.Min or 0),
				}),
				table.unpack(contents),
			},
		})
	end

	-- Small muted-white label used as a header within a card/section.
	function UiUtils.makeSectionHeader(text)
		return Label({
			Text = text,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextSize = 14,
		})
	end

	function UiUtils.makeScrollFrame(contents, size: UDim2?)
		return New("ScrollingFrame")({
			Size = size or UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.fromScale(0, 0),
			[Children] = {
				New("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				New("UIPadding")({
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
				table.unpack(contents),
			},
		})
	end

	return UiUtils
end
