-- Pl/Sql Developer Lua Plug-In Addon: Exports: SQL*Loader
--
-- Outputs a self-contained SQL*Loader control file (.ctl) with data
-- embedded inline using INFILE * / BEGINDATA.
--
-- Usage: sqlldr userid=user/pass@db control=export.ctl
--
-- Generated format:
--
--   OPTIONS (ROWS=5000)
--   LOAD DATA
--   INFILE *
--   BADFILE 'export.bad'
--   DISCARDFILE 'export.dsc'
--   INTO TABLE TABLE_NAME
--   APPEND
--   FIELDS TERMINATED BY '|' OPTIONALLY ENCLOSED BY '"'
--   TRAILING NULLCOLS
--   (
--     COL1,
--     COL2
--   )
--   BEGINDATA
--   val1|val2
--   |null_col


-- Variables

local exportRoot, driverName = ...
local debug_flag = false  -- set to true to enable detailed logging

local logPath = exportRoot and (exportRoot .. (driverName or "SqlLdr") .. "\\debug.log")
local function log(msg)
	if not debug_flag then return end
	local f = io.open(logPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local Gsub = string.gsub

local out, badFile, dscFile, colCount, curCol, prepared, headers, rows, curRow


-- Quote a value if it contains the delimiter, quotes, or newlines.
-- Empty string means NULL (sqlldr treats empty field as NULL).
local function formatValue(s)
	if s == "" then
		return ""
	end
	-- Escape embedded double-quotes by doubling them
	local escaped = Gsub(s, '"', '""')
	-- Quote if contains pipe, double-quote, newline or carriage return
	if escaped:find('[|\"\r\n]') then
		return '"' .. escaped .. '"'
	end
	return s
end


-- Export lifecycle functions


local function ExportInit(buffer, finalPath)
	out      = buffer
	local base = (finalPath or "export"):gsub("%.[^.\\/:]*$", "")
	badFile  = base .. ".bad"
	dscFile  = base .. ".dsc"
	log("ExportInit: finalPath=" .. tostring(finalPath))
	log("ExportInit: badFile=" .. tostring(badFile) .. "  dscFile=" .. tostring(dscFile))
	colCount = 0
	curCol   = 0
	prepared = false
	headers  = {}
	rows     = {}
	curRow   = {}
end


local function ExportFinished()
	log("ExportFinished: rowCount=" .. tostring(#rows) .. " colCount=" .. tostring(colCount))
	-- Write control file header
	out:write("OPTIONS (ROWS=5000)\n")
	out:write("LOAD DATA\n")
	out:write("INFILE *\n")
	out:write("BADFILE '" .. badFile .. "'\n")
	out:write("DISCARDFILE '" .. dscFile .. "'\n")
	out:write("INTO TABLE TABLE_NAME\n")
	out:write("APPEND\n")
	out:write("FIELDS TERMINATED BY '|' OPTIONALLY ENCLOSED BY '\"'\n")
	out:write("TRAILING NULLCOLS\n")
	out:write("(\n")
	for i, name in ipairs(headers) do
		local comma = (i < colCount) and "," or ""
		out:write("  " .. name .. comma .. "\n")
	end
	out:write(")\n")
	out:write("BEGINDATA\n")

	-- Write data rows
	for _, row in ipairs(rows) do
		local cells = {}
		for i = 1, colCount do
			cells[i] = formatValue(row[i] or "")
		end
		out:write(table.concat(cells, "|") .. "\n")
	end

	out = nil
end


local function ExportPrepare()
	log("ExportPrepare: colCount=" .. tostring(colCount))
	prepared = true
end


local function ExportData(value)
	if not prepared then
		colCount = colCount + 1
		headers[colCount] = value
		log("Header[" .. colCount .. "]=" .. tostring(value))
	else
		curCol = curCol + 1
		curRow[curCol] = value
		if curCol == colCount then
			local r = #rows
			if r < 3 or r % 100 == 0 then
				log("Row " .. (r + 1) .. ": col1=" .. tostring(curRow[1]))
			end
			rows[#rows + 1] = curRow
			curRow = {}
			curCol = 0
		end
	end
end


return "SQL*Loader", "ctl", {
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}
