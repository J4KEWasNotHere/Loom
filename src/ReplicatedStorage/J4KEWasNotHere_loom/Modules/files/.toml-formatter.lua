local TomlFormatter = {}

local function navigateTo(result, path: { string })
	local node = result
	for _, key in ipairs(path) do
		if not node[key] then
			node[key] = {}
		end
		node = node[key]
	end
	return node
end

local function parseValue(raw: string): any
	-- Boolean
	if raw == "true" then
		return true
	end
	if raw == "false" then
		return false
	end
	-- Integer (before float, since float pattern is a superset)
	if raw:match("^%-?%d+$") then
		return tonumber(raw)
	end
	-- Float
	if raw:match("^%-?%d+%.%d+") then
		return tonumber(raw)
	end
	-- Quoted string
	return raw:match('^"(.*)"$') or raw:match("^'(.*)'$") or raw
end

-- Helper to unwrap a key if it was explicitly wrapped in quotes
local function cleanKey(key: string): string
	return key:match('^"(.*)"$') or key:match("^'(.*)'$") or key
end

-- Parses path elements out of header segments while respecting quoted strings
local function parsePath(section: string): { string }
	local parts = {}

	local buffer = {}
	local quote: string? = nil

	for i = 1, #section do
		local c = section:sub(i, i)

		if quote then
			if c == quote then
				quote = nil
			else
				table.insert(buffer, c)
			end
		else
			if c == '"' or c == "'" then
				quote = c
			elseif c == "." then
				local part = table.concat(buffer):match("^%s*(.-)%s*$")
				table.insert(parts, part)
				table.clear(buffer)
			else
				table.insert(buffer, c)
			end
		end
	end

	local part = table.concat(buffer):match("^%s*(.-)%s*$")
	if part ~= "" then
		table.insert(parts, part)
	end

	return parts
end

local function stripComment(line: string): string
	local inStr, q = false, nil
	for i = 1, #line do
		local c = line:sub(i, i)
		if inStr then
			if c == q then
				inStr = false
			end
		elseif c == '"' or c == "'" then
			inStr, q = true, c
		elseif c == "#" then
			return line:sub(1, i - 1)
		end
	end
	return line
end

local function parseArray(content: string): { any }
	local arr = {}
	for item in content:gmatch("[^,]+") do
		item = item:match("^%s*(.-)%s*$")
		if item ~= "" then
			table.insert(arr, parseValue(item))
		end
	end
	return arr
end

local function tableToString(tb): string
	if typeof(tb) ~= "table" then
		return ""
	end

	local str = "{\n"
	for key, value in pairs(tb) do
		local valueType = typeof(value)
		local keyStr = tostring(key)
		if typeof(key) == "string" then
			keyStr = string.format("%q", keyStr)
		end
		str = str .. (" "):rep(2) .. "[" .. keyStr .. "] = "
		if valueType == "table" then
			str = str .. tableToString(value)
		elseif valueType == "number" then
			str = str .. value
		else
			str = str .. string.format(`"%s"`, value)
		end
		str = str .. ",\n"
	end
	str = str .. (" "):rep(0) .. "}"
	return str
end

local function parseInlineTable(content: string): { [string]: any }
	local tbl = {}
	for pair in content:gmatch("[^,]+") do
		local k, v = pair:match("^%s*([%w_%-%\"']+)%s*=%s*(.-)%s*$")
		if k and v then
			tbl[cleanKey(k)] = parseValue(v)
		end
	end
	return tbl
end

local function create_toml(tomlData: { [string]: any }, parent: Instance?): ModuleScript
	local m = Instance.new("ModuleScript")
	m.Name = "wally.toml"
	m.Source = ("return %s"):format(tableToString(tomlData))

	m.Parent = (typeof(parent) == "Instance" and parent) or nil
	m:AddTag("_wallytoml")

	return m
end

local function format_toml(str: string): { [string]: any }
	local result = {}
	local lineList = {}
	for line in str:gmatch("[^\n\r]+") do
		table.insert(lineList, line)
	end
	local currentTable = result
	local i = 1
	while i <= #lineList do
		local line = stripComment(lineList[i]):match("^%s*(.-)%s*$")
		if line ~= "" then
			local section = line:match("^%[(.+)%]$")
			if section then
				local parts = parsePath(section)
				currentTable = navigateTo(result, parts)
			else
				local eq = line:find("=", 1, true)
				if eq then
					local key = line:sub(1, eq - 1):match("^%s*(.-)%s*$")
					local valueStr = line:sub(eq + 1):match("^%s*(.-)%s*$")

					if valueStr:sub(1, 1) == "[" then
						-- Handle Arrays
						local arrayContent = valueStr
						while not arrayContent:find("%]") and i < #lineList do
							i += 1
							local next = stripComment(lineList[i]):match("^%s*(.-)%s*$")
							arrayContent ..= " " .. next
						end
						local inner = arrayContent:match("^%[(.-)%]$")
						currentTable[key] = parseArray(inner or "")
					elseif valueStr:sub(1, 1) == "{" then
						-- Handle Inline Tables {...}
						local inlineContent = valueStr
						while not inlineContent:find("}") and i < #lineList do
							i += 1
							local next = stripComment(lineList[i]):match("^%s*(.-)%s*$")
							inlineContent ..= " " .. next
						end
						local inner = inlineContent:match("^%{(.-)%}$")
						currentTable[key] = parseInlineTable(inner or "")
					else
						-- Handle Standard values
						currentTable[key] = parseValue(valueStr)
					end
				end
			end
		end
		i += 1
	end
	return result
end

TomlFormatter.create = create_toml
TomlFormatter.format = format_toml
return TomlFormatter
