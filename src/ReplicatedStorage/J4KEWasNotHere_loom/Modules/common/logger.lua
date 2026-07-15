local Packages = script.Parent:FindFirstAncestor("Modules").Parent.Packages
local Fusion = require(Packages.Fusion)
local Value = Fusion.Value

local colorFormat = '<font color="%s">%s</font>'
local function color(hex, text)
	return colorFormat:format(hex, text)
end

local COLORS = {
	bracket = "#808080",      -- [Zi[Importer]:
	timestamp = "#9CDCFE",
	filename = "#D4D4D4",
	module = "#4EC994",       -- ModuleScript
	package = "#DCDCAA",      -- package names
	path = "#569CD6",
	size = "#B5CEA8",
	unit = "#7FB0D6",
	status = "#4EC994",       -- compressed, skipped, etc.
	keyword = "#C586C0",
	error = "#F14C4C",
	success = "#4EC994",
	warning = "#CCA700",
}

local function formatLine(line)
	local prefix, body = line:match("^(%[.-%]:?)%s*(.*)$")
	if not prefix then return line end

	prefix = color(COLORS.bracket, prefix)

	-- === Specific patterns from your screenshot ===

	-- Imported ModuleScript
	if body:match("^Imported ModuleScript") then
		local name = body:match('from "([^"]+)"')
		return table.concat({
			prefix, " ",
			color(COLORS.keyword, "Imported "),
			color(COLORS.module, "ModuleScript "),
			'"', color(COLORS.package, name or ""), '"',
		})
	end

	-- Importing from raw... / Importing package
	if body:match("^Importing") then
		local pkg = body:match("Importing from raw%.%.%.") or body:match("Importing%s+(.+)%.%.%.$")
		return table.concat({
			prefix, " ",
			color(COLORS.keyword, "Importing "),
			color(COLORS.package, pkg or body),
			pkg and "..." or "",
		})
	end

	-- Parsed / Done messages
	if body:match("^Parsed") or body:match("^Done") then
		local doneText = body:match("^(Done.-imported)") or body
		return prefix .. " " .. color(COLORS.success, doneText)
	end

	-- Size + status line (e.g. init.lua 1.7 KB (compressed))
	local file, size, status = body:match("^(.-)%s+(%d+%s*%a+)%s+(%b())$")
	if file and size and status then
		local num, unit = size:match("^(%d+)%s*(%a+)$")
		local coloredSize = num and unit 
			and color(COLORS.size, num) .. " " .. color(COLORS.unit, unit)
			or color(COLORS.size, size)

		return table.concat({
			prefix, " ",
			color(COLORS.filename, file),
			" ",
			coloredSize,
			" ",
			color(COLORS.status, status),
		})
	end

	-- Error / warning
	if body:match("Could not resolve") or body:match("error") then
		return prefix .. " " .. color(COLORS.error, body)
	end

	-- Fallback
	return prefix .. " " .. color(COLORS.filename, body)
end

local function formatString(str)
	local lines = string.split(str, "\n")
	local result = {}
	for _, line in ipairs(lines) do
		if line ~= "" then
			table.insert(result, formatLine(line))
		end
	end
	return table.concat(result, "\n")
end

-- Module API
local module = { output = Value(""), raw = Value("") }
module.__index = module

function module:log(...)
	local text = table.concat({...}, " ")
	self.raw:set(self.raw:get() .. text .. "\n")
	self.output:set(formatString(self.raw:get()))
end

function module:clear()
	self.raw:set("")
	self.output:set("")
end

function module.new()
	return setmetatable({
		output = Value(""),
		raw = Value(""),
	}, module)
end

return module