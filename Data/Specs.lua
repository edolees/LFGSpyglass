-- Spec icons for group members. Blizzard's search result member info gives the class
-- file name and the *localized* spec name; we look up the spec icon through the class's spec list.
--
-- Specs.FindSpec is PURE (unit-tested); Specs.IconFor uses the WoW API and caches results.
local _, ns = ...

local Specs = {}
ns.Specs = Specs

-- Pure: find the entry in specList ({ { name = ..., names = {...}, icon = ... }, ... }) whose
-- name (any gendered variant) equals specName.
function Specs.FindSpec(specList, specName)
	if type(specList) ~= "table" or type(specName) ~= "string" or specName == "" then
		return nil
	end
	for _, spec in ipairs(specList) do
		if spec.name == specName then
			return spec
		end
		for _, name in ipairs(spec.names or {}) do
			if name == specName then
				return spec
			end
		end
	end
	return nil
end

local classIDs -- classFile -> classID
local specsByClass = {} -- classFile -> spec list | false
local iconCache = {} -- "CLASS:specName" -> icon fileID | false

local function ClassID(classFile)
	if not classIDs then
		classIDs = {}
		local getInfo = (C_CreatureInfo and C_CreatureInfo.GetClassInfo) or nil
		for id = 1, 20 do
			local classInfo
			if getInfo then
				local ok, info = pcall(getInfo, id)
				classInfo = ok and info or nil
			end
			local file = classInfo and classInfo.classFile
			if not file and GetClassInfo then
				local ok, _, fileName = pcall(GetClassInfo, id)
				file = ok and fileName or nil
			end
			if file then
				classIDs[file] = id
			end
		end
	end
	return classIDs[classFile]
end

local function SpecList(classFile)
	local cached = specsByClass[classFile]
	if cached ~= nil then
		return cached or nil
	end
	local list = {}
	local classID = ClassID(classFile)
	local numSpecs = 0
	if classID then
		local getNum = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
		local ok, n = pcall(getNum, classID)
		numSpecs = ok and tonumber(n) or 0
	end
	for index = 1, numSpecs do
		local spec = { names = {} }
		-- Spec names can be gendered in some languages: collect every variant.
		for _, gender in ipairs({ false, 2, 3 }) do
			local ok, id, name, _, icon = pcall(GetSpecializationInfoForClassID, classID, index, gender or nil)
			if ok and id then
				spec.id, spec.icon = spec.id or id, spec.icon or icon
				spec.name = spec.name or name
				spec.names[#spec.names + 1] = name
			end
		end
		if spec.id then
			list[#list + 1] = spec
		end
	end
	specsByClass[classFile] = #list > 0 and list or false
	return #list > 0 and list or nil
end

-- Spec icon (fileID) for a member, or nil if unknown.
function Specs.IconFor(classFile, specName)
	if type(classFile) ~= "string" or type(specName) ~= "string" then
		return nil
	end
	local key = classFile .. ":" .. specName
	local cached = iconCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local spec = Specs.FindSpec(SpecList(classFile), specName)
	iconCache[key] = spec and spec.icon or false
	return spec and spec.icon or nil
end
