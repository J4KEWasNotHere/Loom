local util = {}

local HttpService = game:GetService("HttpService")

local readers = require("./readers")
local linkedReaders = readers.typs

-- Minor

function util.deepCopy(original: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = util.deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

function util.js2tb(json: any): { [any]: any }
	if typeof(json) ~= "string" then
		return {}
	end
	local ok, result = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok then
		warn(result)
	end

	return (typeof(result) == "table" and result) or {}
end

function util.mixTables(t1: { [any]: any }, t2: { [any]: any }, override: boolean?): { [any]: any }
	local t3 = util.deepCopy(t1)

	if override == true then
		for k, v in pairs(t2) do
			t3[k] = v
		end
	else
		for k, v in pairs(t2) do
			if t3[k] then
				t3[k] = v
			end
		end
	end

	return t3
end

function util.isJs(str: string): boolean
	local ok, _ = pcall(function()
		return HttpService:JSONDecode(str)
	end)

	return ok
end

-- Main

function util.parseJsonProperty(class: string, k: string, v: any): any
	if type(v) == "table" then
		local typ = v.Type
		local val = v.Value

		local reader = linkedReaders[typ] or linkedReaders["any"]
		if not reader then
			reader = linkedReaders[typ] or linkedReaders["any"]
		end
		return reader(k, val)
	end

	local reader = linkedReaders[k] or linkedReaders["any"]
	if not reader then
		reader = linkedReaders["any"]
	end

	return reader(k, v)
end

function util.applyProperties(inst: Instance, properties: { [string]: any }): Instance
	local parsed = {}
	for k, v in pairs(properties) do
		parsed[k] = util.parseJsonProperty(inst.ClassName, k, v)
	end

	for k, v in pairs(parsed) do
		pcall(function()
			inst[k] = v
		end)
	end

	return inst
end

-- Basis

return util
