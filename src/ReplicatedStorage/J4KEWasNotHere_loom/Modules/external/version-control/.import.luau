--!strict
--!native

local module = {}

local SerializationService = game:GetService("SerializationService") -- i nearly created a new parser for rbxm(x) files..
local SupportedExtenstions = { "rbxm", "rbxmx" }

-- Utility

local function getExt(name: string): string
	return name:match("^.*%.(%w+)$") or ""
end

local function comp(str: string, ...: string?): string
	return table.concat({ str, ... }, " ")
end

-- Function

return function(file: File | string, parent: Instance?): (boolean, { Instance } | any)
	if not file then
		return false, "No file provided"
	end
	if typeof(file) == "Instance" and file:IsA("File") then
		local ext = getExt(file.Name):lower()
		if not table.find(SupportedExtenstions, ext) then
			return false, comp("Unsupported file type, supported extentions:", unpack(SupportedExtenstions))
		end
	end

	local insts = nil
	local success, result = pcall(function()
		local content = typeof(file) == "Instance" and file:GetBinaryContents() or tostring(file)

		local contentBuffer = buffer.fromstring(content)
		insts = SerializationService:DeserializeInstancesAsync(contentBuffer)

		if typeof(parent) == "Instance" then
			for _, inst in insts do
				inst.Parent = parent
			end
		end

		return true, insts
	end)

	return success, insts or result
end
