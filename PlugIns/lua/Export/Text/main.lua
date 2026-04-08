-- Pl/Sql Developer Lua Plug-In Addon: Exports: Text
--
-- Lua port of Pretty-Groovy.txt.groovy
-- Outputs query results as a fixed-width ASCII table:
--
--   +-------+----------+
--   |COL1   |COL2      |
--   +-------+----------+
--   |val1   |val2      |
--   +-------+----------+


-- Variables

local exportRoot, driverName = ...
local debug_flag = false  -- set to true to enable detailed logging

local logPath = exportRoot and (exportRoot .. (driverName or "Text") .. "\\debug.log")
local function log(msg)
	if not debug_flag then return end
	local f = io.open(logPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local Rep = string.rep

local out, headers, widths, rows, curRow, colCount, prepared


-- Return the length of the longest line within a (possibly multi-line) string
local function maxLineLen(s)
	local max = 0
	-- append sentinel newline so every line (including last) is captured
	for line in (s .. "\n"):gmatch("([^\n]*)\n") do
		if #line > max then max = #line end
	end
	return max
end


-- Build a separator row:  +------+----------+
local function sepLine(w)
	local t = {"+"}
	for i = 1, #w do
		t[#t + 1] = Rep("-", w[i]) .. "+"
	end
	return table.concat(t) .. "\n"
end


-- Render one logical row (which may contain multi-line cells) as output lines.
-- Writes directly to out.
local function writeDataRow(cells, w)
	-- Split each cell into lines
	local split = {}
	local maxLines = 1
	for i = 1, #w do
		local cellLines = {}
		for line in ((cells[i] or "") .. "\n"):gmatch("([^\n]*)\n") do
			cellLines[#cellLines + 1] = line
		end
		split[i] = cellLines
		if #cellLines > maxLines then maxLines = #cellLines end
	end

	-- Write each output line of this row
	for l = 1, maxLines do
		local t = {"|"}
		for i = 1, #w do
			local val = split[i][l] or ""
			t[#t + 1] = val .. Rep(" ", w[i] - #val) .. "|"
		end
		out:write(table.concat(t) .. "\n")
	end
end


-- Export lifecycle functions


--
-- First call after an export request.
--
local function ExportInit(buffer)
	log("ExportInit called")
	out      = buffer
	headers  = {}
	widths   = {}
	rows     = {}
	curRow   = {}
	colCount = 0
	prepared = false
end


--
-- Done, everything is exported. Compute final widths and render the table.
--
local function ExportFinished()
	-- Update widths from buffered data rows
	for _, row in ipairs(rows) do
		for i = 1, colCount do
			local w = maxLineLen(row[i] or "")
			if w > widths[i] then widths[i] = w end
		end
	end

	log("ExportFinished: rowCount=" .. tostring(#rows) .. " colCount=" .. tostring(colCount))

	-- Render
	out:write(sepLine(widths))
	writeDataRow(headers, widths)
	out:write(sepLine(widths))
	for _, row in ipairs(rows) do
		writeDataRow(row, widths)
	end
	out:write(sepLine(widths))

	out = nil
end


--
-- Signals transition from column headers to data rows.
--
local function ExportPrepare()
	log("ExportPrepare: colCount=" .. tostring(colCount))
	prepared = true
end


--
-- One cell value: column header name before ExportPrepare, row data after.
--
local function ExportData(value)
	if value == "" then value = "null" end
	if not prepared then
		colCount = colCount + 1
		headers[colCount] = value
		widths[colCount]  = maxLineLen(value)
		log("Header[" .. colCount .. "]=" .. tostring(value))
	else
		local col = #curRow + 1
		curRow[col] = value
		if col == colCount then
			local r = #rows
			if r < 3 or r % 100 == 0 then
				log("Row " .. (r + 1) .. ": col1=" .. tostring(curRow[1]))
			end
			rows[#rows + 1] = curRow
			curRow = {}
		end
	end
end


return "Text files", "txt", {
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}
