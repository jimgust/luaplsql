-- Pl/Sql Developer Lua Plug-In Addon: Exports: SQLite
--
-- Exports the query result grid as a binary SQLite .db file.
-- Each column is created as TEXT. The table is named "data".
--
-- Dependencies (place in PlugIns/lua/clibs/):
--   lsqlite351.dll   -- LuaJIT/Lua 5.1 binding (MSYS2: mingw-w64-x86_64-lua51-lsqlite3)
--   libsqlite3-0.dll -- SQLite3 C library, runtime dep of lsqlite351.dll (MSYS2: mingw-w64-x86_64-sqlite3)
-- See README.md for license information.


-- Error log: only written on failures
local exportRoot, driverName = ...
local logPath = exportRoot .. (driverName or "SQLite") .. "\\error.log"

local function log(msg)
	local f = io.open(logPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local debug_flag = false  -- set to true to enable detailed logging

local debugLogPath = exportRoot .. (driverName or "SQLite") .. "\\debug.log"
local function dlog(msg)
	if not debug_flag then return end
	local f = io.open(debugLogPath, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
		f:close()
	end
end

local ok, sqlite3 = pcall(require, "lsqlite3")
if not ok then
	log("ERROR: require('lsqlite3') failed: " .. tostring(sqlite3))
	error(sqlite3)  -- re-throw so RegisterExport shows the error
end

local sys_ok, sys = pcall(require, "sys")
if not sys_ok then
	log("ERROR: require('sys') failed: " .. tostring(sys))
	error(sys)
end


-- Variables

local buf, tmpPath, db, stmt
local colCount, curCol, prepared, headers, curRow, rowCount


-- Export lifecycle functions


--
-- ExportInit receives the shared buffer and (via Export/main.lua)
-- the final output filename so we can derive a sibling temp path.
--
local function ExportInit(buffer, finalPath)
	dlog("ExportInit called: finalPath=" .. tostring(finalPath))
	buf      = buffer
	local tmpDir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
	tmpPath  = finalPath
		and (finalPath .. ".sqlite.tmp")
		or  (tmpDir .. "\\luaplsql_sqlite_export.tmp")
	dlog("tmpPath=" .. tostring(tmpPath))

	db = sqlite3.open(tmpPath)
	if not db then
		log("ERROR: sqlite3.open failed for: " .. tmpPath)
		return false
	end
	dlog("sqlite3.open OK: " .. tostring(db))

	local rc
	rc = db:exec("PRAGMA journal_mode = OFF;")
	dlog("PRAGMA journal_mode rc=" .. tostring(rc))
	rc = db:exec("PRAGMA synchronous = OFF;")
	dlog("PRAGMA synchronous rc=" .. tostring(rc))
	rc = db:exec("BEGIN TRANSACTION;")
	dlog("BEGIN TRANSACTION rc=" .. tostring(rc))

	colCount = 0
	curCol   = 0
	prepared = false
	headers  = {}
	curRow   = {}
	rowCount = 0
end


local function ExportFinished()
	dlog("ExportFinished called: rowCount=" .. tostring(rowCount))
	-- Commit and close the database
	if db then
		if stmt then
			local rc = stmt:finalize()
			dlog("stmt:finalize rc=" .. tostring(rc))
			stmt = nil
		end
		local rc = db:exec("COMMIT;")
		dlog("COMMIT rc=" .. tostring(rc))
		rc = db:close()
		dlog("db:close rc=" .. tostring(rc))
		db = nil
	end

	-- Read the binary .db file back into the buffer for the parent to write out
	local fd = sys.handle()
	if fd:open(tmpPath, 'r') then
		local data = fd:read()
		fd:close()
		dlog("fd:read bytes=" .. (data and tostring(#data) or "nil"))
		if data and #data > 0 then
			buf:write(data)
			dlog("buf:write OK")
		else
			log("WARNING: no data read from temp file: " .. tostring(tmpPath))
		end
	else
		log("ERROR: could not open temp file for reading: " .. tostring(tmpPath))
	end

	-- Clean up temp file
	os.remove(tmpPath)

	buf = nil
end


local function ExportPrepare()
	dlog("ExportPrepare: colCount=" .. tostring(colCount))
	-- Build CREATE TABLE statement
	local cols = {}
	for _, name in ipairs(headers) do
		cols[#cols + 1] = '"' .. name:gsub('"', '""') .. '" TEXT'
	end
	local createSQL = 'CREATE TABLE IF NOT EXISTS "data" (' .. table.concat(cols, ", ") .. ");"
	dlog("CREATE TABLE SQL: " .. createSQL)
	local rc = db:exec(createSQL)
	dlog("CREATE TABLE rc=" .. tostring(rc))
	if rc ~= 0 then
		log("ERROR: CREATE TABLE failed rc=" .. tostring(rc))
	end

	-- Prepare INSERT statement with placeholders
	local placeholders = {}
	for i = 1, colCount do placeholders[i] = "?" end
	local insertSQL = 'INSERT INTO "data" VALUES (' .. table.concat(placeholders, ", ") .. ");"
	dlog("Preparing INSERT: " .. insertSQL)
	stmt = db:prepare(insertSQL)
	dlog("db:prepare result=" .. tostring(stmt))
	if not stmt then
		log("ERROR: db:prepare failed for INSERT")
	end

	prepared = true
end


local function ExportData(value)
	if not prepared then
		colCount = colCount + 1
		headers[colCount] = value
		dlog("Header[" .. colCount .. "]=" .. tostring(value))
	else
		curCol = curCol + 1
		-- Map empty strings to nil so SQLite stores a proper NULL
		curRow[curCol] = (value == "" or value == nil) and nil or value
		if curCol == colCount then
			-- Bind and insert the completed row; pcall catches any lsqlite3 errors
			local ok, err = pcall(function()
				stmt:reset()
				for i = 1, colCount do
					if curRow[i] == nil then
						stmt:bind_null(i)
					else
						stmt:bind(i, tostring(curRow[i]))
					end
				end
				stmt:step()
				rowCount = rowCount + 1
				if rowCount <= 3 or rowCount % 100 == 0 then
					dlog("Inserted row " .. rowCount .. ": col1=" .. tostring(curRow[1]))
				end
			end)
			if not ok then
				log("ERROR inserting row " .. (rowCount + 1) .. ": " .. tostring(err))
				error(err)  -- re-raise so call_addons reports it to the user
			end
			curRow = {}
			curCol = 0
		end
	end
end


return "SQLite", "db", {
	ExportInit,
	ExportFinished,
	ExportPrepare,
	ExportData
}
