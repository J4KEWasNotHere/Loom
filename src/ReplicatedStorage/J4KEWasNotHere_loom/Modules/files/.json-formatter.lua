--!strict

local JsonFormatter = {}
local HttpService = game:GetService("HttpService")

local function serialize(value: any, depth: number): string
	local valueType = typeof(value)
	if valueType == "string" then
		return string.format("%q", value)
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	elseif valueType ~= "table" then
		error(("Unsupported JSON value type: %s"):format(valueType))
	end

	local keyCount = 0
	local maxIndex = 0
	local isArray = true
	for key in pairs(value) do
		keyCount += 1
		if typeof(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			isArray = false
		else
			maxIndex = math.max(maxIndex, key)
		end
	end
	isArray = isArray and keyCount == maxIndex

	local indent = string.rep("\t", depth)
	local childIndent = string.rep("\t", depth + 1)
	local entries = {}
	if isArray then
		for index = 1, maxIndex do
			table.insert(entries, childIndent .. serialize(value[index], depth + 1))
		end
	else
		local keys = {}
		for key in pairs(value) do
			if typeof(key) ~= "string" then
				error(("Unsupported JSON object key type: %s"):format(typeof(key)))
			end
			table.insert(keys, key)
		end
		table.sort(keys)

		for _, key in ipairs(keys) do
			table.insert(
				entries,
				("%s[%s] = %s"):format(
					childIndent,
					string.format("%q", key),
					serialize(value[key], depth + 1)
				)
			)
		end
	end

	if #entries == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(entries, ",\n") .. "\n" .. indent .. "}"
end

function JsonFormatter.format(json: string): { [string]: any }
	assert(typeof(json) == "string", "JSON input must be a string")
	assert(json:match("^%s*{"), "JSON root must be an object")

	local result = HttpService:JSONDecode(json)
	assert(typeof(result) == "table", "JSON root must decode to an object")

	return result
end

function JsonFormatter.toLuau(json: string): string
	return "return " .. serialize(JsonFormatter.format(json), 0)
end

return JsonFormatter
