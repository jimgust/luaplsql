# Copilot Instructions for luaplsql

## What This Project Is

LuaPlSql is a Lua plug-in framework for the [PL/SQL Developer](http://www.allroundautomations.com/plsqldev.html) IDE. It exposes the IDE's plugin API to Lua scripts, enabling addons to be written in Lua rather than C/Delphi.

## Building

Build requires **Visual Studio** (MSVC) and external dependencies checked out as siblings of this repo:

- `../../luajit-2.0/src` — LuaJIT 2.0 source (provides `lua51.lib`, `lua51.dll`)
- LuaSys (`sys.dll`) compiled separately

Run from a **Visual Studio Command Prompt** inside `src/`:

```bat
cd src
msvcbuild.bat
```

This produces:
- `PlugIns/luaplug.dll` — the proxy DLL loaded directly by PL/SQL Developer
- `PlugIns/lua/clibs/luaplsql.dll` — the core C/Lua bridge DLL

To create the installer (requires [Inno Setup](https://jrsoftware.org/isinfo.php)):

```bat
cd deploy
create-installer.bat
```

There are no automated tests or linters.

## Architecture

### Two-DLL Design

PL/SQL Developer loads **`luaplug.dll`** (the proxy). On `IdentifyPlugIn`, the proxy uses `LoadLibrary` to load **`luaplsql.dll`** from `PlugIns/lua/clibs/` and delegates every plugin callback to it. This separation allows `luaplsql.dll` to be reloaded at runtime without restarting PL/SQL Developer (via the "Reload Plug-In" menu item).

### C Layer → Lua Runtime

`luaplsql.c` is the entry point and `#include`s its sub-modules directly (not compiled separately):

```
luaplsql.c
  ├── debug.c        — debug logging macros
  ├── plsql.c        — plsql.* auxiliary Lua API (clipboard, timers, file dialogs, etc.)
  ├── plsql_ide.c    — plsql.ide.* Lua API (editor, windows, connections, browser)
  ├── plsql_sql.c    — plsql.sql.* Lua API (SQL execution)
  └── plsql_sys.c    — plsql.sys.* Lua API (system utilities)
```

On `OnCreate`, the C layer:
1. Creates a new `lua_State`
2. Registers the `plsql` global table (with `.sys`, `.ide`, `.sql` sub-tables)
3. Loads `PlugIns/lua/main.lua`, passing `MAX_ADDONS` and `MAX_MENUS` as args

### Lua Runtime — `PlugIns/lua/main.lua`

`main.lua` is the addon loader. It:
1. Configures `package.cpath` to find C modules in `PlugIns/lua/clibs/`
2. Loads the `sys` LuaSys library globally
3. Populates `plsql.WindowType`, `plsql.WindowClose`, `plsql.FieldType`, etc. as named constants
4. Traverses subdirectories of `PlugIns/lua/` looking for `<AddonName>/main.lua`
5. Loads each addon by calling `chunk(AddMenu, root, addonName)`
6. Collects addon callback tables and multiplexes them; calls all registered addons for each IDE event
7. Returns the unified `addons` dispatch table and menu index map back to the C layer

### Addon Structure

Each addon lives in `PlugIns/lua/<AddonName>/main.lua`. The file receives three upvalues as varargs:

```lua
local AddMenu, rootPath, addonDir = ...
```

It must return **two values**: a callback table and optionally a dependency specifier:

```lua
return {
    OnActivate,      -- [1]
    OnDeactivate,    -- [2]
    CanClose,        -- [3]
    AfterStart,      -- [4]
    AfterReload,     -- [5]
    OnBrowserChange, -- [6]
    OnWindowChange,  -- [7]
    OnWindowCreate,  -- [8]
    OnWindowCreated, -- [9]
    OnWindowClose,   -- [10]
    BeforeExecuteWindow,      -- [11]
    AfterExecuteWindow,       -- [12]
    OnConnectionChange,       -- [13]
    OnWindowConnectionChange, -- [14]
    OnPopup,         -- [15]
    OnMainMenu,      -- [16]
    OnTemplate,      -- [17]
    OnFileLoaded,    -- [18]
    OnFileSaved,     -- [19]
    About,           -- [20]
    CommandLine,     -- [21]
    RegisterExport,  -- [22]
    ExportInit,      -- [23]
    ExportFinished,  -- [24]
    ExportPrepare,   -- [25]
    ExportData       -- [26]
}, optionalDependency
```

**The position in the table is significant** — it maps to the callback enum in `luaplsql.c`. Unused callbacks should be left as `nil` (they are never registered). Passing a variable that is `nil` is acceptable; the framework skips it.

### Menu Registration

Menus are registered via `AddMenu(func, name [, iconPath])` before the addon returns. Menu name format:

- **Classic menu**: `"Lua / Group / Item"` — slash-separated hierarchy under the "Lua" top-level menu
- **Ribbon menu** (PL/SQL Developer v12+): automatically converted from slash-separated names to TAB/GROUP/MENUITEM/ITEM/SUBITEM ribbon descriptors by `main.lua`'s `build_tree`/`build_names` functions

### `plsql` Global API

Available everywhere in Lua addon code:

| Table | Purpose |
|-------|---------|
| `plsql` | Core: `ShowMessage`, `MessageBox`, `RootPath`, `ExePath`, `SetTimer`/`KillTimer`, `SetClipboardText`/`GetClipboardText`, `ShellExecute`, window/key helpers |
| `plsql.ide` | IDE interaction: `Connected`, `GetConnectionInfo`, `SetConnection`, `GetText`, `SetText`, `GetSelectedText`, `InsertText`, `CreateWindow`, `OpenFile`, `SaveFile`, `CloseFile`, `GetCursorY`, `SetCursor`, `LineScroll`, `CommandFeedback`, etc. |
| `plsql.sql` | SQL execution: `Execute`, `First`/`Next`, field access |
| `plsql.sys` | LuaSys: file I/O (`sys.dir`, `sys.handle`), memory, etc. |

Constants defined in `main.lua`: `plsql.WindowType`, `plsql.WindowClose`, `plsql.WindowExecute`, `plsql.PerformCommand`, `plsql.ObjectAction`, `plsql.KeyShift`, `plsql.BeautifierOption`, `plsql.FieldType`, `plsql.KeywordStyle`.

## `plsql.ide` API Reference

All functions return `nil` (0 values) if the underlying IDE function pointer is unavailable.

### Connection
| Function | Arguments | Returns |
|----------|-----------|---------|
| `Connected()` | — | boolean |
| `GetConnectionInfo()` | — | username, password, database |
| `GetConnectAs()` | — | string |
| `SetConnection(usr, pwd, db)` | strings | boolean |
| `SetConnectionAs(usr, pwd, db, connectAs)` | strings | boolean |
| `GetConnectionInfoEx(index)` | number | usr, pwd, db, connectAs, edition, workspace |
| `FindConnection(usr, db [, edition, workspace])` | strings | index |
| `AddConnection(usr, pwd, db, connectAs [, edition, workspace])` | strings | index |
| `ConnectConnection(index)` | number | boolean |
| `SetMainConnection(index)` | number | boolean |
| `GetWindowConnection()` | — | index |
| `SetWindowConnection(index)` | number | boolean |
| `GetConnectionTree(index)` | number | descr, usr, pwd, db, connectAs, edition, workspace, id, parentId |
| `CheckDBVersion(version)` | string | boolean |
| `GetSessionValue(name)` | string | string |

### Window Management
| Function | Arguments | Returns |
|----------|-----------|---------|
| `GetWindowType()` | — | number (`plsql.WindowType.*`) |
| `GetWindowCount()` | — | number |
| `SelectWindow(index)` | number | boolean |
| `ActivateWindow(index)` | number | boolean |
| `IsWindowModified()` | — | boolean |
| `IsWindowRunning()` | — | boolean |
| `WindowPin([pin])` | boolean? | boolean |
| `WindowHasEditor(codeEditor)` | boolean | boolean |
| `CanSaveWindow()` | — | boolean |
| `WindowAllowed(winType, showError)` | number, boolean | boolean |
| `SetWindowCloseAction(action)` | number | — |
| `GetWindowCloseAction()` | — | number |
| `CreateWindow(winType, text, execute)` | number, string, boolean | — |
| `Refresh()` | — | — |

### Editor / Text
| Function | Arguments | Returns |
|----------|-----------|---------|
| `GetText()` | — | string |
| `SetText(text)` | string | boolean |
| `GetSelectedText()` | — | string |
| `InsertText(text)` | string | — |
| `GetCursorWord()` | — | string |
| `GetCursorWordPosition()` | — | number |
| `GetCursorX()` | — | number |
| `GetCursorY()` | — | number |
| `SetCursor(x, y)` | numbers | — |
| `GetSelection()` | — | start, end (char positions) |
| `SetSelection(start, end)` | numbers | — |
| `GetFirstVisibleLine()` | — | number |
| `GetLineCount()` | — | number |
| `LineFromChar(pos)` | number | number |
| `LineIndex(line)` | number | number |
| `LineLength(pos)` | number | number |
| `LineScroll(xOffset, yOffset)` | numbers | — |
| `Undo()` | — | — |
| `EmptyUndoBuffer()` | — | — |
| `SetErrorPosition(line, col)` | numbers | boolean |
| `ClearErrorPositions()` | — | — |
| `SetStatusMessage(text)` | string | boolean |
| `GetEditorHandle()` | — | HWND (number) |

### Files
| Function | Arguments | Returns |
|----------|-----------|---------|
| `OpenFile(winType, filename)` | number, string | boolean |
| `SaveFile()` | — | boolean |
| `Filename()` | — | string |
| `CloseFile([closeAction])` | number? | — |
| `ReloadFile()` | — | boolean |
| `SetFilename(path)` | string | — |
| `GetFileData()` | — | string |
| `FileSaved(filename [, fs, tag])` | strings | — |
| `GetFileTypes(winType)` | number | string |
| `GetDefaultExtension(winType)` | number | string |
| `OpenFileExternal(winType, data, fs, tag, filename)` | mixed | — |

### Object Browser
| Function | Arguments | Returns |
|----------|-----------|---------|
| `GetBrowserInfo()` | — | type, owner, name |
| `GetBrowserItems(node, getItems)` | string, boolean | string |
| `RefreshBrowser(node)` | string | — |
| `GetBrowserFilter(index)` | number | name, where, orderBy, user, active |
| `GetPopupObject()` | — | type, owner, name, subObject |
| `GetPopupBrowserRoot()` | — | string |
| `FirstSelectedObject()` | — | type, owner, name, subObject |
| `NextSelectedObject()` | — | type, owner, name, subObject |
| `GetObjectInfo(object)` | string | type, owner, name, subObject |
| `GetObjectSource(type, owner, name)` | strings | string |
| `GetWindowObject()` | — | type, owner, name, subObject |
| `RefreshObject(type, owner, name, action)` | strings, number | — |
| `ObjectAction(action, type, owner, name)` | strings | boolean |
| `FirstSelectedFile(files, dirs)` | booleans | string |
| `NextSelectedFile()` | — | string |
| `RefreshFileBrowser()` | — | — |

### Menu / UI
| Function | Arguments | Returns |
|----------|-----------|---------|
| `MenuState(index, enabled)` | number, boolean | — |
| `RefreshMenus()` | — | — |
| `SetMenuName(index, name)` | number, string | — |
| `SetMenuCheck(index, checked)` | number, boolean | — |
| `SetMenuVisible(index, visible)` | number, boolean | — |
| `GetMenulayout()` | — | string |
| `CreatePopupItem(index, name, objType)` | number, strings | — |
| `CreateToolButton(index, name, bitmapFile)` | number, strings | — |
| `UseRibbonMenu()` | — | boolean |
| `GetMenuItem(menuName)` | string | number |
| `SelectMenu(menuItem)` | number | boolean |
| `KeyPress(key [, shift])` | numbers | — |

### Preferences
| Function | Arguments | Returns |
|----------|-----------|---------|
| `GetPersonalPrefSets()` | — | string |
| `GetDefaultPrefSets()` | — | string |
| `GetPrefAsString(prefSet, name, default)` | strings | string |
| `GetPrefAsInteger(prefSet, name, default)` | string, string, number | number |
| `GetPrefAsBool(prefSet, name, default)` | string, string, boolean | boolean |
| `SetPrefAsString(prefSet, name, value)` | strings | boolean |
| `SetPrefAsInteger(prefSet, name, value)` | string, string, number | boolean |
| `SetPrefAsBool(prefSet, name, value)` | string, string, boolean | boolean |
| `GetGeneralPref(name)` | string | string |
| `PlugInSetting(setting, value)` | strings | boolean |
| `GetParamString(name)` | string | string |
| `GetParamBool(name)` | string | boolean |

### Misc
| Function | Arguments | Returns |
|----------|-----------|---------|
| `Perform(param)` | number (`plsql.PerformCommand.*`) | boolean |
| `ExecuteSQLReport(sql, title, updateable)` | strings, boolean | boolean |
| `ExecuteTemplate(template, newWindow)` | string, boolean | boolean |
| `TemplatePath()` | — | string |
| `ShowHTML(url, hash, title, id)` | strings | boolean |
| `RefreshHTML(url, id, bringToFront)` | strings, boolean | boolean |
| `ShowDialog(dialog [, param])` | strings | boolean |
| `CommandFeedback(handle, text)` | number, string | — |
| `ResultGridRowCount()` | — | number |
| `ResultGridColCount()` | — | number |
| `ResultGridCell(col, row)` | numbers | string |
| `SplashCreate(progressMax)` | number | — |
| `SplashHide()` | — | — |
| `SplashWrite(text)` | string | — |
| `SplashWriteLn(text)` | string | — |
| `SplashProgress(progress)` | number | — |
| `DebugLog(message)` | string | — |
| `SetBookmark(index, x, y)` | numbers | number |
| `ClearBookmark(index)` | number | — |
| `GotoBookmark(index)` | number | — |
| `GetBookmark(index)` | number | x, y |
| `TabInfo(index)` | number | string |
| `TabIndex(index)` | number | number |
| `GetCustomKeywords()` | — | string |
| `SetCustomKeywords(keywords)` | string | — |
| `SetKeywords(style, keywords)` | number, string | — |
| `ActivateKeywords()` | — | — |
| `Authorized(category, name, subName)` | strings | boolean |
| `WindowAllowed(winType, showError)` | number, boolean | boolean |
| `Authorization()` | — | boolean |
| `AuthorizationItems(category)` | string | string |
| `AddAuthorizationItem(name)` | string | — |
| `GetProcOverloadCount(owner, pkg, proc)` | strings | number |
| `SelectProcOverloading(owner, pkg, proc)` | strings | number |
| `BeautifierOptions()` | — | number (bitmask, `plsql.BeautifierOption.*`) |
| `BeautifyWindow()` | — | boolean |
| `BeautifyText(text)` | string | string |
| `SaveRecoveryFiles()` | — | boolean |
| `GetAppHandle()` | — | number (HANDLE) |
| `GetWindowHandle()` | — | number (HWND) |
| `GetClientHandle()` | — | number (HWND) |
| `GetChildHandle()` | — | number (HWND) |
| `TranslationFile()` | — | string |
| `TranslationLanguage()` | — | string |
| `GetTranslatedMenuLayout()` | — | string |
| `MainFont()` | — | string |
| `TranslateItems(group)` | string | string |
| `TranslateString(id, default, param1, param2)` | strings | string |
| `GetProcEditExtension(objType)` | string | string |
| `GetFileOpenMenu(menuIndex)` | number | name, winType |

## `plsql.sql` API Reference

Field indices are **1-based** in Lua (the C layer adjusts to 0-based internally).

| Function | Arguments | Returns | Notes |
|----------|-----------|---------|-------|
| `Execute(sql)` | string | number | Returns rows affected or cursor handle |
| `FieldCount()` | — | number | Number of result columns |
| `Eof()` | — | boolean | True when past last row |
| `Next()` | — | number | Advance cursor; returns 0 on EOF |
| `Field(index)` | number | string | Value of column at 1-based index |
| `FieldName(index)` | number | string | Column name at 1-based index |
| `FieldIndex(name)` | string | number | 1-based index for named column |
| `FieldType(index)` | number | number | Type constant (`plsql.FieldType.*`) |
| `ErrorMessage()` | — | string | Last SQL error message |
| `UsePlugInSession()` | — | boolean | Switch to plug-in private session |
| `UseDefaultSession()` | — | — | Restore default shared session |
| `CheckConnection()` | — | boolean | Test if connection is active |
| `GetDBMSOutput()` | — | string | Retrieve DBMS_OUTPUT buffer |
| `SetVariable(name, value)` | strings | — | Set a substitution variable |
| `GetVariable(name)` | string | string | Get a substitution variable |
| `ClearVariables()` | — | — | Clear all substitution variables |
| `SetPlugInSession(usr, pwd, db, connectAs)` | strings | boolean | Open a dedicated plug-in session |

**Typical query pattern:**
```lua
SQL.Execute("SELECT id, name FROM my_table WHERE rownum <= 10")
while not SQL.Eof() do
    local id   = SQL.Field(1)
    local name = SQL.Field(2)
    -- process row
    SQL.Next()
end
```

## Export Addon Pattern

The `Export` addon (`PlugIns/lua/Export/`) is a **two-level** structure:

1. **`PlugIns/lua/Export/main.lua`** — the top-level addon. Its `RegisterExport` callback scans subdirectories, loads each sub-addon's `main.lua`, and collects the file-format filter string and function table.

2. **`PlugIns/lua/Export/<Format>/main.lua`** — a sub-addon for one export format. It receives `(rootPath, dirName)` and must return three values:

```lua
return title, extension, {
    ExportInit,      -- [1] function(buffer) → boolean|nil; called first; return false to cancel
    ExportFinished,  -- [2] function(); called when export is complete
    ExportPrepare,   -- [3] function(); called after all column headers, before data rows
    ExportData       -- [4] function(value); called once per cell, headers first then data
}
```

- `title` — display name in the Save dialog filter (e.g. `"RTF"`)
- `extension` — file extension without dot (e.g. `"rtf"`)
- `buffer` passed to `ExportInit` is a `sys.mem.pointer()` object; write to it with `buffer:write(...)`, read with `buffer:getstring()`
- `ExportData` is called row-by-row, column-by-column: all header cells come first (before `ExportPrepare`), then data cells in row-major order
- The `Export/main.lua` handles the Save dialog and file writing; sub-addons only populate the buffer

## Key Conventions

### Lua Compatibility
The C layer includes compatibility shims (in `luaplsql.c`) to support both **Lua 5.1/LuaJIT** and **Lua 5.2**. New C code must maintain this dual compatibility. In Lua code, `setfenv`/`getfenv` are guarded with `if setfenv then` checks.

### C Sub-files Are `#include`d
`debug.c`, `plsql.c`, `plsql_ide.c`, `plsql_sql.c`, `plsql_sys.c` are not standalone compilation units — they are `#include`d into `luaplsql.c`. Functions in these files can access the `g_PlugIn` global and `g_L` state directly.

### Version is Defined Once
All version information lives in `src/version.h` as `APP_VERSION_MAJOR/MINOR/PATCH`. The Inno Setup installer reads it via `#include` preprocessor. Update only `version.h` when bumping versions.

### Addon Callback Return Values
- `CanClose`: return `true` to block IDE close
- `OnWindowClose`: return `WINCLOSE_DEFAULT` (0), `WINCLOSE_CONFIRM` (1), or `WINCLOSE_QUIET` (2)
- `BeforeExecuteWindow`: return `false` to cancel execution
- `About`: return a short description string; the framework concatenates all addon descriptions

### Installation Path
The `PlugIns/` directory is deployed directly into `C:\Program Files\PLSQL Developer\PlugIns\`. The `LUAPLSQL_ROOT` environment variable (set by `luaplug.dll`'s `DllMain`) points to `PlugIns/lua/`.
