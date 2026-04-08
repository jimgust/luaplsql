-- Pl/Sql Developer Lua Plug-In Addon: Exports: Markdown
--
-- Outputs query results as a GFM-style aligned Markdown table:
--
--   | COL1   | COL2       |
--   |--------|------------|
--   | val1   | val2       |
--   | null   | multi line |


-- Variables

local exportRoot, driverName = ...
local debug_flag = false  -- set to true to enable detailed logging

local logPath = exportRoot and (exportRoot .. (driverName or "Markdown") .. "\\debug.log")
local function log(msg)
	if not debug_flag then return end
	local f = io.open(logPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local Rep, Gsub = string.rep, string.gsub

local out, colCount, curCol, prepared, headers, widths, rows, curRow


-- Escape pipe characters and collapse newlines for Markdown cell content
local function escape(s)
	s = Gsub(s, "\r?\n", " ")  -- newlines not supported in MD table cells
	return (Gsub(s, "|", "\\|"))
end


-- Write one table row:  | val   | val   |
local function writeRow(cells, w)
	local t = {}
	for i = 1, #w do
		local val = escape(cells[i] or "")
		t[i] = val .. Rep(" ", w[i] - #val)
	end
	out:write("| " .. table.concat(t, " | ") .. " |\n")
end


-- Write the separator row:  |--------|------------|
local function writeSep(w)
	local t = {}
	for i = 1, #w do
		t[i] = Rep("-", w[i] + 2)  -- +2 for the spaces around content
	end
	out:write("|" .. table.concat(t, "|") .. "|\n")
end


-- Export lifecycle functions


local function ExportInit(buffer)
	log("ExportInit called")
	out      = buffer
	colCount = 0
	curCol   = 0
	prepared = false
	headers  = {}
	widths   = {}
	rows     = {}
	curRow   = {}
end


local function ExportFinished()
	-- Final pass: update widths from all buffered row data
	for _, row in ipairs(rows) do
		for i = 1, colCount do
			local w = #escape(row[i] or "")
			if w > widths[i] then widths[i] = w end
		end
	end

	log("ExportFinished: rowCount=" .. tostring(#rows) .. " colCount=" .. tostring(colCount))

	-- Render
	writeRow(headers, widths)
	writeSep(widths)
	for _, row in ipairs(rows) do
		writeRow(row, widths)
	end

	out = nil
end


local function ExportPrepare()
	log("ExportPrepare: colCount=" .. tostring(colCount))
	prepared = true
end


local function ExportData(value)
	if value == "" then value = "null" end
	if not prepared then
		colCount = colCount + 1
		headers[colCount] = value
		widths[colCount]  = #escape(value)
		log("Header[" .. colCount .. "]=" .. tostring(value))
	else
		curCol = curCol + 1
		curRow[curCol] = value
		if curCol == colCount then
			local r = #rows  -- count before appending
			if r < 3 or r % 100 == 0 then
				log("Row " .. (r + 1) .. ": col1=" .. tostring(curRow[1]))
			end
			rows[#rows + 1] = curRow
			curRow = {}
			curCol = 0
		end
	end
end


return "Markdown", "md", {
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}
