--selene::unused_variable

local reader = {

	typs = {},
} :: {
	typs: { [string]: (string, any) -> any },
}

local function reg(names: string, func)
	for _, name in ipairs(names:split("/")) do
		reader.typs[name] = func
	end
end

-- lookUps & types variables

local facesLookup = {
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
}

local axesLookup = {
	X = Enum.Axis.X,
	Y = Enum.Axis.Y,
	Z = Enum.Axis.Z,
}

-- Register all types

reg("Color/Color3/ImageColor3/ImageColor", function(classname: string, key)
	local r, g, b = unpack(key)
	return Color3.new(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0)
end)

reg("Axes", function(classname: string, key)
	local axes = Axes.new()

	for _, name in ipairs(key) do
		local axis = axesLookup[name]
		if axis then
			axes[axis.Name] = true
		end
	end

	return axes
end)

reg("Size/Vector3", function(classname: string, key)
	local x, y, z = unpack(key)
	return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
end)

reg("Enum", function(classname: string, key)
	local num = tonumber(key)
	if num then
		return Enum[classname]:FromValue(num)
	end
	return Enum[classname]:FromName(tostring(key))
end)

reg("Bool/bool/boolean", function(classname: string, key)
	return key == "true" or key == true
end)

reg("NumberSequence", function(classname: string, key)
	local keypoints = table.create(#key.keypoints)

	for i, point in ipairs(key.keypoints) do
		keypoints[i] = NumberSequenceKeypoint.new(
			tonumber(point.time) or 0,
			tonumber(point.value) or 0,
			tonumber(point.envelope) or 0
		)
	end

	return NumberSequence.new(keypoints)
end)

reg("PhysicalProperties", function(classname: string, key)
	if key == "Default" then
		return PhysicalProperties.new(0.7, 0.3, 0.5, 0.3, 1, 0.3)
	end

	return PhysicalProperties.new(
		tonumber(key.density) or 0.7,
		tonumber(key.friction) or 0.3,
		tonumber(key.elasticity) or 0.5,
		tonumber(key.frictionWeight) or 0.3,
		tonumber(key.elasticityWeight) or 1,
		tonumber(key.acousticAbsorption) or 0.3
	)
end)

reg("Vector2", function(classname: string, key)
	local x, y = unpack(key)
	return Vector2.new(tonumber(x) or 0, tonumber(y) or 0)
end)

reg("String/Source/Image/ImageContent", function(classname: string, key)
	return tostring(key)
end)

reg("Udim", function(classname: string, key)
	local x, y = unpack(key)
	return UDim.new(tonumber(x) or 0, tonumber(y) or 0)
end)

reg("Udim2", function(classname: string, key)
	local x, y, z, w = unpack(key)
	return UDim2.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, tonumber(w) or 0)
end)

reg("CFrame", function(classname: string, key)
	return CFrame.new(unpack(key))
end)

reg("ColorSequence", function(classname: string, key)
	local keypoints = table.create(#key.keypoints)

	for i, point in ipairs(key.keypoints) do
		local r, g, b = unpack(point.color)

		keypoints[i] = ColorSequenceKeypoint.new(
			tonumber(point.time) or 0,
			Color3.new(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0)
		)
	end

	return ColorSequence.new(keypoints)
end)

reg("BrickColor", function(classname: string, key)
	return BrickColor.new(tonumber(key) or 0)
end)

reg("Faces", function(classname: string, key)
	local faces = Faces.new()

	for _, name in ipairs(key) do
		local face = facesLookup[name]
		if face then
			faces[face.Name] = true
		end
	end

	return faces
end)

reg("any", function(classname: string, key)
	return tonumber(key) or tostring(key)
end)

return reader
