-- Pl/Sql Developer Lua Plug-In Addon: Exports: JSON


-- Variables

local exportRoot, driverName = ...
local debug_flag = false  -- set to true to enable detailed logging

local logPath = exportRoot and (exportRoot .. (driverName or "JSON") .. "\\debug.log")
local function log(msg)
	if not debug_flag then return end
	local f = io.open(logPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local Gsub = string.gsub

local out, colCount, curCol, prepared, headers, row, rowCount


-- Escape a string value for JSON output
local escapes = {
	['"']  = '\\"',
	['\\'] = '\\\\',
	['\n'] = '\\n',
	['\r'] = '\\r',
	['\t'] = '\\t',
}

local function JsonEscape(s)
	return (Gsub(s, '["\\\n\r\t]', escapes))
end

local function JsonValue(s)
	if s == '' then
		return 'null'
	end
	return '"' .. JsonEscape(s) .. '"'
end


-- Write the completed row as a JSON object
local function WriteRow()
	if rowCount > 0 then
		out:write(',\n')
	end
	out:write('  {\n')
	for i = 1, colCount do
		out:write('    "' .. headers[i] .. '": ' .. JsonValue(row[i]))
		if i < colCount then
			out:write(',')
		end
		out:write('\n')
	end
	out:write('  }')
	rowCount = rowCount + 1
end


-- Export lifecycle functions


--
-- First call after an export request.
-- Return false to cancel the export.
--
local function ExportInit(buffer)
	log("ExportInit called")
	out      = buffer
	colCount = 0
	curCol   = 0
	prepared = false
	headers  = {}
	row      = {}
	rowCount = 0
end


--
-- Done, everything is exported.
--
local function ExportFinished()
	out:write('\n]')
	log("ExportFinished: rowCount=" .. tostring(rowCount))
	out = nil
end


--
-- Called after all column headers have been received via ExportData.
-- Values received via ExportData before this call are column headers;
-- values received after are row data.
--
local function ExportPrepare()
	log("ExportPrepare: colCount=" .. tostring(colCount))
	out:write('[')
	prepared = true
end


--
-- One cell of data: column header names before ExportPrepare, row values after.
--
local function ExportData(value)
	if not prepared then
		colCount = colCount + 1
		headers[colCount] = value
		log("Header[" .. colCount .. "]=" .. tostring(value))
	else
		curCol = curCol + 1
		row[curCol] = value
		if curCol == colCount then
			if rowCount < 3 or rowCount % 100 == 0 then
				log("Row " .. (rowCount + 1) .. ": col1=" .. tostring(row[1]))
			end
			WriteRow()
			curCol = 0
		end
	end
end


return "JSON", "json", {
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}
