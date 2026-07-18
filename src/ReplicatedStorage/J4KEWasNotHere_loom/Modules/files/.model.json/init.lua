-- rojo-instancer.lua

local RojoInstancer = {}
local util = require("@self/util")
local ext = "%.model%.json$"

-- Create a new instance from a Rojo JSON string or table.
RojoInstancer.create = function(key: string?, rjs: string | { [string]: any }): Instance
	local parsed = util.js2tb(rjs) or rjs
	assert(typeof(parsed) == "table", "Invalid data")

	local _path = parsed["$path"] or parsed["Path"]
	local class = parsed["$className"] or parsed["ClassName"]
	local properties = parsed["$properties"] or parsed["Properties"]
	local children = parsed["$children"] or parsed["Children"]

	local inst = Instance.new(class)

	pcall(function()
		inst.Name = key and tostring(key) or inst.Name
	end)

	if typeof(properties) == "table" then
		util.applyProperties(inst, properties)
	end

	if typeof(children) == "table" then
		for key, child in children do
			local c = RojoInstancer.create(key, child)
			c.Parent = inst
		end
	end

	return inst
end

RojoInstancer.add = function(rjs: string | { [string]: any })
	return RojoInstancer.create(nil, rjs)
end

RojoInstancer.fromFile = function(file: File): Instance
	assert(file:IsA("File"), "Argument must be a File instance")
	assert(file.Name:match(ext), "File is not a .model.json file")

	local name = file.Name:gsub(ext, "")
	local raw = file:GetBinaryContents()
	local inst = RojoInstancer.create(name, raw)

	return inst
end

return RojoInstancer :: {
	create: (key: string?, rjs: string | { [string]: any }) -> Instance,
	add: (rjs: string | { [string]: any }) -> Instance,
	fromFile: (file: File) -> Instance,
}
