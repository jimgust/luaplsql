# SQLite Export

Exports query results as a binary SQLite `.db` file. Each column is stored as `TEXT`. The table is named `data`.

## Dependencies

Two DLLs are required in `PlugIns\lua\clibs\` — they are already included in this repository:

| File | Description | Source |
|---|---|---|
| `lsqlite351.dll` | Lua 5.1 / LuaJIT binding (`require("lsqlite3")`) | MSYS2 `mingw-w64-x86_64-lua51-lsqlite3 0.9.6-2` |
| `libsqlite3-0.dll` | SQLite3 C library (runtime dependency of lsqlite351.dll) | MSYS2 `mingw-w64-x86_64-sqlite3 3.52.0-1` |

Both are pre-built MinGW64 Windows x64 DLLs. They only depend on `KERNEL32.dll` and `msvcrt.dll`, which are always present on Windows — no additional runtimes required.

### Licenses

- **sqlite3** (`libsqlite3-0.dll`): Public domain — see `LICENSE-sqlite3.txt`
- **lsqlite3** (`lsqlite351.dll`): MIT License — see `LICENSE-lsqlite3.txt`

## Schema

The exported database contains a single table:

```sql
CREATE TABLE data (
  COL1 TEXT,
  COL2 TEXT,
  ...
)
```

- All columns are `TEXT` — Oracle type information is not available through the export API
- NULL values in the source data are stored as proper SQL `NULL` (not the string `"null"`)
- Column names are taken as-is from Oracle (typically uppercase)

## Usage

Open the resulting `.db` file with any SQLite client:

```sh
sqlite3 export.db "SELECT * FROM data LIMIT 10;"
```

Or use a GUI tool such as [DB Browser for SQLite](https://sqlitebrowser.org/).

## Notes

- The export writes to a temporary file alongside the output path, then reads it back. The temp file is automatically deleted after export.
- To rename the table from `data`, open the `.db` file and run: `ALTER TABLE data RENAME TO my_table;`
