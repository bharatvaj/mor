@echo off
setlocal EnableDelayedExpansion
set mor_version=0.2
set root_dir=%cd%\out\

rem default values
set /a is_logi=0
set config_file=requirements.ini

if "%~1" == "" goto print_usage
goto :main

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
set [ 2>nul && for /f "usebackq delims== tokens=1" %%l in ( `set [` ) do (
	set %%l=
)

for /f "usebackq delims=: tokens=1,*" %%l in ( `findstr /n /v ^; %~1` ) do (
	for /f "usebackq delims==] tokens=1,*" %%a in ( '%%~m' ) do (
		call :logi actual: %%m
		set key=%%~a
		if "!key:~0,1!" == "[" (
			set current_section=%%a
			set %%a= 
			call :logi section set: !current_section!
		) else (
			for /f "usebackq delims== tokens=1,*" %%t in (`set !current_section!`) do (
				set !current_section!=%%u %%a "%%b" 
				call :logi set !current_section!=%%u %%a "%%b" 
			)
		)
	)
)

for /f "usebackq delims==[ tokens=1,*" %%l in (`set [`) do (
	call :prime_download %%l %%~m 
)
endlocal
goto :eof

:prime_download
setlocal EnableDelayedExpansion
set target=%1
shift
for /f %%a in ("%targets%") do (
	if "!target!" == "%%a" (
		set current_target_dir="%root_dir%\%%a"
		call :logi Current Target Dir: !current_target_dir!
		if not exist "!current_target_dir!" mkdir "!current_target_dir!"
		:key_value
		if "%~1" == "" goto :eof
		for %%i in (%2) do set ext=%%~xi
		call :download_archive !current_target_dir! %1 %2 !ext!
		call :unzip_archive !current_target_dir! %1 !ext!
		shift
		shift
		goto :key_value
	)
)
endlocal
goto :eof

:unzip_archive
setlocal
	echo x [%2]
	tar xzf "%1\%2%3" -C %1
endlocal
goto :eof

:download_archive
setlocal
	echo v [%2] %3
	bitsadmin /rawreturn /transfer "mor %2" %3 "%1\%2%4" || (
		echo fatal: Failed while downloading %3
		exit /b
	)
endlocal
goto :eof

:main
setlocal
:parse
set arg=%~1
if "%~1" == "" goto :main_continue
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
:main_continue
call :read_ini "%config_file%"
endlocal
goto :eof

endlocal
