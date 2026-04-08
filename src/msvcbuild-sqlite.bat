@rem Build SQLite DLLs for LuaJIT / Lua 5.1 (placed in PlugIns\lua\clibs\).
@rem
@rem Run from a Visual Studio Command Prompt inside the src\ directory,
@rem or call it from msvcbuild.bat which already sets up that environment.
@rem Requires PowerShell (built into Windows 10+) for downloading sources.
@rem
@rem Produces:
@rem   ..\PlugIns\lua\clibs\libsqlite3-0.dll  -- SQLite3 C runtime
@rem   ..\PlugIns\lua\clibs\lsqlite351.dll    -- LuaJIT / Lua 5.1 SQLite binding
@rem
@rem Downloaded C sources are cached in sqlite-src\ and re-used on subsequent
@rem builds.  To upgrade, delete the cached .c/.h files, update the version
@rem pins below, then rebuild.

@setlocal

@set LUA=../../luajit-2.0/src

@rem --- Version pins (update here when upgrading) ----------------------------
@rem SQLite amalgamation: https://www.sqlite.org/download.html
@set SQLITE_VER=3470200
@set SQLITE_YEAR=2024
@rem lsqlite3: http://lua.sqlite.org/index.cgi/timeline
@set LSQLITE_REV=fsl09z
@rem --------------------------------------------------------------------------

@set SRCDIR=sqlite-src
@set COMPILE=cl /nologo /c /MD /O2 /W3 /D_CRT_SECURE_NO_DEPRECATE
@set LSLINK=link /nologo

@if not exist %SRCDIR% @mkdir %SRCDIR%

@rem --- Download SQLite amalgamation (skipped when already cached) -----------
@if not exist %SRCDIR%\sqlite3.c (
    @echo Downloading SQLite amalgamation %SQLITE_VER%...
    powershell -Command ^
        "Invoke-WebRequest -UseBasicParsing -Uri 'https://www.sqlite.org/%SQLITE_YEAR%/sqlite-amalgamation-%SQLITE_VER%.zip' -OutFile 'sqlite-amal.zip'; ^
         Expand-Archive -Path 'sqlite-amal.zip' -DestinationPath 'sqlite-amal-tmp' -Force; ^
         Get-ChildItem 'sqlite-amal-tmp' -Recurse -Include 'sqlite3.c','sqlite3.h' | Copy-Item -Destination '%SRCDIR%'; ^
         Remove-Item -Recurse -Force 'sqlite-amal-tmp','sqlite-amal.zip'"
    @if errorlevel 1 goto :END
)

@rem --- Download lsqlite3 source (skipped when already cached) ---------------
@if not exist %SRCDIR%\lsqlite3.c (
    @echo Downloading lsqlite3.c rev %LSQLITE_REV%...
    powershell -Command ^
        "Invoke-WebRequest -UseBasicParsing -Uri 'http://lua.sqlite.org/index.cgi/raw/lsqlite3.c?name=%LSQLITE_REV%' -OutFile '%SRCDIR%\lsqlite3.c'"
    @if errorlevel 1 goto :END
)

@rem --- Build libsqlite3-0.dll (SQLite3 C runtime) ---------------------------
@echo Building libsqlite3-0.dll...
%COMPILE% "/DSQLITE_API=__declspec(dllexport)" %SRCDIR%\sqlite3.c
@if errorlevel 1 goto :END
%LSLINK% /DLL /OUT:libsqlite3-0.dll /IMPLIB:sqlite3.lib sqlite3.obj
@if errorlevel 1 goto :END

@rem --- Build lsqlite351.dll (LuaJIT / Lua 5.1 SQLite binding) ---------------
@echo Building lsqlite351.dll...
%COMPILE% /I%LUA% /I%SRCDIR% /DLUA_BUILD_AS_DLL "/DSQLITE_API=__declspec(dllimport)" %SRCDIR%\lsqlite3.c
@if errorlevel 1 goto :END
%LSLINK% /DLL /OUT:lsqlite351.dll lsqlite3.obj %LUA%\lua51.lib sqlite3.lib
@if errorlevel 1 goto :END

@rem --- Copy DLLs to plugin clibs directory ----------------------------------
@mkdir ..\PlugIns\lua\clibs 2>nul
@move /Y libsqlite3-0.dll ..\PlugIns\lua\clibs
@move /Y lsqlite351.dll ..\PlugIns\lua\clibs

@rem --- Clean up build artifacts ---------------------------------------------
@del sqlite3.obj lsqlite3.obj sqlite3.lib sqlite3.exp 2>nul
@del *.manifest 2>nul

:END
