@echo off
setlocal EnableDelayedExpansion
set mor_version=0.1

rem default values
set /a is_logi=0
set config_file=requirements.ini

call :read_ini requirements.ini

exit /b

if "%~1" == "" goto print_usage
goto :main

:unarchive <archive> <destination>
if "%~1x" == ".zip" do unzip "%~1" -d "%~2"
goto :eof

:logi
if %is_logi% equ 1 echo %*
goto :eof

:print_usage
echo Usage: mor [ -c requirements.ini] [-d] [-Dvar1=value1 ...] [[@]target1, ...]
goto :eof

:read_ini <config_file.ini>
rem uses zero-space width character as a field separator
setlocal EnableDelayedExpansion
set /a section_count=0
set current_section=[

rem locally remove env variables starting with '['
for /f "usebackq delims== tokens=1" %%l in ( `set [` ) do (
    set %%l=
    echo before: set %%l=
) 2>nul

for /f "usebackq delims=: tokens=1,*" %%l in ( `findstr /n /v ^; "%1"` ) do (
	for /f "usebackq delims==] tokens=1,*" %%a in ( '%%m' ) do (
        echo actual: %%m
		set key=%%a
		if "!key:~0,1!" == "[" (
			set current_section=%%a
            set %%a= 
			echo section set: !current_section!
		) else (
            set [precompiled || (
                echo [precompiled not found, maybe first?
            )
            for /f "usebackq delims== tokens=1,*" %%t in (`set !current_section!`) do (
                set "!current_section!=%%u %%a %%b "
                echo set "!current_section!=%%u %%a %%b "
            )

		)
	)
)
for /f "useback delims== tokens=1,*" %%l in (`set [`) do (
    echo %%l: %%m
)
echo --------------
for /f "tokens=1,2" %%t in ( "!%section%!" ) do (
	echo %%t
	echo %%u
)
endlocal
goto :eof

:main
setlocal
:parse
set arg=%~1
if "%~1" == "" goto :eof
if "%~1" == "-v" (
	echo mor v%mor_version%
	goto :eof
) else if "%arg%" == "-c" (
	set config_file="%~2"
	call :logi -c !config_file!
	shift
) else if "%arg%" == "-d" (
	set /a is_logi=1
) else if "%arg%" == "-D" (
	set d=%~2
	call :logi -D !d!=%~3
	shift
	shift
) else if "%arg:~0,2%" == "-D" (
	set arg=%~1
	set d=%arg:~2%
	call :logi -D!d!=%~2
	shift
) else if "%arg%" == "-" (
	echo mor: invalid argument '-'
) else (
	set targets=%~1
	echo %targets%
)
if "%arg:~0,1%" == "=" echo "= command"

shift
goto parse
endlocal
goto :eof


endlocal
