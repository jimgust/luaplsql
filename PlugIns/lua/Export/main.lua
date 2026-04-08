-- Pl/Sql Developer Lua Plug-In Addon: Exports


local sys = require("sys")


-- Variables

local AddMenu, rootPath, dirName = ...

local plsql = plsql
local SYS, IDE, SQL = plsql.sys, plsql.ide, plsql.sql

local exports = {}

local CurExportInit, CurExportFinished, CurExportPrepare, CurExportData

local buffer = sys.mem.pointer()

local filename


-- Addon description
local function About()
	return "Exports"
end


local function RegisterExport()

	-- Traverse export directory and collect all formats
	local root = rootPath .. "\\" .. dirName .. "\\"
	local collected = {}

	for name, is_dir in sys.dir(root) do
		if is_dir then
			local chunk, err = loadfile(root .. name .. "\\main.lua")
			if not chunk then
				plsql.ShowMessage(err)
			else
				local title, ext, funcs = chunk(root, name)
				if title then
					collected[#collected + 1] = {title = title, ext = ext, funcs = funcs}
				end
			end
		end
	end

	-- Move Text format to position 1 so it is the default in the Save dialog
	for i, entry in ipairs(collected) do
		if entry.ext == "txt" then
			table.remove(collected, i)
			table.insert(collected, 1, entry)
			break
		end
	end

	-- Build exports table and filter string in final order
	local n, filter = 1, ""
	for _, entry in ipairs(collected) do
		exports[n], n = entry.funcs, n + 1
		filter = filter .. entry.title
			.. " files (*." .. entry.ext .. ")\0"
			.. "*." .. entry.ext .. "\0"
	end

	exports.filter = filter .. "\0\0"
end


local function ExportInit()

	-- Get export filename
	local index
	filename, index = plsql.GetSaveFileName(nil, exports.filter)

	local allocOk = filename and buffer:alloc()

	if not allocOk then
		return false
	end

	local funcs = exports[index]

	CurExportInit     = funcs and funcs[1]
	CurExportFinished = funcs and funcs[2]
	CurExportPrepare  = funcs and funcs[3]
	CurExportData     = funcs and funcs[4]

	if CurExportInit then
		return CurExportInit(buffer, filename)
	end
end


local function ExportFinished()
	if CurExportFinished then
		CurExportFinished()
	end

	-- Write file
	local fd = sys.handle()
	local data = buffer:tostring()
	local createOk = fd:create(filename)
	local writeOk
	if createOk then
		writeOk = fd:write(data)  -- captures only the first return value (boolean)
	end
	fd:close()
	if not (createOk and writeOk) then
		plsql.ShowMessage("Export failed: could not write to " .. tostring(filename))
	end

	buffer:close()

	collectgarbage("collect")
	collectgarbage("collect")
end


local function ExportPrepare()
	if CurExportPrepare then
		return CurExportPrepare()
	end
end


local function ExportData(value)
	if CurExportData then
		return CurExportData(value)
	end
end


return {
	OnActivate,
	OnDeactivate,
	CanClose,
	AfterStart,
	AfterReload,
	OnBrowserChange,
	OnWindowChange,
	OnWindowCreate,
	OnWindowCreated,
	OnWindowClose,
	BeforeExecuteWindow,
	AfterExecuteWindow,
	OnConnectionChange,
	OnWindowConnectionChange,
	OnPopup,
	OnMainMenu,
	OnTemplate,
	OnFileLoaded,
	OnFileSaved,
	About,
	CommandLine,
	RegisterExport,
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}

