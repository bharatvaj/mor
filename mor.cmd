@echo off
setlocal EnableDelayedExpansion
set mor_version=0.4
set root_dir=%cd%\out
for /f %%a in ('copy /Z "%~dpf0" nul') do set "CR=%%a"

rem default values
set /a is_logi=0
set config_file=requirements.ini
set MOR_EXTS_TAR=.tar.gz,.tgz,.zip

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
	if ERRORLEVEL 1 exit /b %ERRORLEVEL%
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
		where /q curl
		if ERRORLEVEL 1 (
			call :download_archive !current_target_dir! %1 %2 !ext! || (
				exit /b %ERRORLEVEL%
			)
		) else (
			call :download_archive_curl !current_target_dir! %1 %2 !ext! || (
				exit /b %ERRORLEVEL%
			)
		)

		if ERRORLEVEL 1 (
			echo ^^^! Error
			exit /b %ERRORLEVEL%
		)

		for %%x in (%MOR_EXTS_TAR%) do (
			if "!ext!"=="%%x" (
				call :unzip_archive !current_target_dir! %1 !ext!
				if ERRORLEVEL 1 (
					echo ^^^! Error
					exit /b %ERRORLEVEL%
				)
				goto :MOR_AFTER_EXTRACT
			)
		)

		:MOR_AFTER_EXTRACT
		shift
		shift
		goto :key_value
	)
)
endlocal
goto :eof

:unzip_archive <download_dir> <file_name> <file_extension>
setlocal
	echo ^| [%~2%~3] %~1\
	tar xzf "%~1\%~2%~3" -C "%~1"
	exit /b %ERRORLEVEL%
endlocal
goto :eof

:download_archive_curl <download_dir> <file_name> <url> <file_extension>
setlocal
	echo v [%2] %3
	curl -Lf "%~3" -o "%~1\%~2%~4" 2>>mor.log
	if ERRORLEVEL 1 (
		echo ^^^! Error
		exit /b %ERRORLEVEL%
	)
	endlocal
goto :eof

:download_archive <download_dir> <file_name> <url> <file_extension>
setlocal
	echo v [%2] %3
	for /f "usebackq" %%i in (`bitsadmin /rawreturn /create "mor:%2"`) do (
		set job_id=%%i
		bitsadmin /rawreturn /addfile "%%i" %3 "%~1\%2%4" >>mor.log
		bitsadmin /setsecurityflags "%%i" 0x0000 >>mor.log
		bitsadmin /setpriority "%%i" HIGH >>mor.log
		bitsadmin /setnoprogresstimeout "%%i" 30 >>mor.log
		bitsadmin /resume "%%i"  >>mor.log
	:mor_download_start
		if "%job_id%" == "" (
			timeout /t 2 >nul
			goto :mor_download_start
		)
		for /f %%f in ('bitsadmin /rawreturn /getstate %job_id%') do (
			set dstate=%%f
		)
		goto :BITS_%dstate% || (
			goto :BITS_TRANSFERRING
		)

		:BITS_CANCELED
		:BITS_SUSPENDED
		:BITS_TRANSIENT_ERROR
		:BITS_ERROR
		:BITS_Unable
			bitsadmin /rawreturn /cancel %job_id% >>mor.log
			setlocal DisableDelayedExpansion
			echo ^^^! Error
			exit /b 1
		goto :eof
		:BITS_TRANSFERRING
		:BITS_CONNECTING
			for /f %%b in ('bitsadmin /rawreturn /getbytestransferred "%job_id%"') do (
				<nul set /p"=%%b!CR!"
			)
		:BITS_CONNECTING
		:BITS_ACKNOWLEDGED
		:BITS_QUEUED
		:BITS_Wait
		:BITS_Wait2
		:BITS_ERWait
			timeout /t 1 >nul
			goto:mor_download_start
		:BITS_TRANSFERRED
			goto :mor_download_end
	:mor_download_end
		bitsadmin /rawreturn /complete "%job_id%" >>mor.log
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
	echo !targets!:
)
if "%arg:~0,1%" == "=" echo "= command"

shift
goto parse
:main_continue
call :read_ini "%config_file%"
if ERRORLEVEL 1 exit /b %ERRORLEVEL%
endlocal
goto :eof

endlocal
:mor_end_program
