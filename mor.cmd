@echo off
setlocal
set mor_version=0.6
set root_dir=%cd%\out
for /f %%a in ('copy /Z "%~dpf0" nul') do set "CR=%%a"

rem default values
set /a is_logi=0
set config_file=requirements.ini
set MOR_EXTS_TAR=.tar.gz,.tgz,.zip

if "%~1" == "" if not exist %config_file% goto print_usage
goto :main

:logi
	if %is_logi% equ 1 echo %*
goto :eof

:print_usage
	echo Usage: mor [ -c requirements.ini] [-d] [-Dvar1=value1 ...] [[@]target1, ...]
goto :eof

:read_ini <config_file.ini>
setlocal EnableDelayedExpansion
	set /a section_count=0
	set current_section=[

	rem locally remove env variables starting with '['
	set [ 2>nul && for /f "usebackq delims== tokens=1" %%l in ( `set [` ) do (
		set %%l=
	)

	for /f "eol=; usebackq delims==] tokens=1,*" %%a in (%~1) do (
		set tok=%%~a
		if "!tok:~0,1!" == "[" (
			set current_section=!tok!
			call :logi #!current_section!
		) else (
			set key=!current_section![!tok!]
			set !key!=%%~b
			call :logi # 	[!tok!] "%%~b"
		)
	)

	set wtargets=%targets%
:MOR_TARGETS_START
	for /f "tokens=1*" %%a in ("%wtargets%") do (
		set target=%%~a

		set [!target![ 2>NUL >NUL
		if ERRORLEVEL 1 (
			echo ^> Cannot find target '%%~a'
			exit /b 1
		)

		echo !target!:
		for /f "usebackq tokens=1,2* delims=[]=" %%l in (`set  [!target![`) do (
			if "!target:~0,1!"=="#" (
				echo ^> Target definitions ^(i.e #targets^) cannot be invoked
				exit /b 1
			) else if "!target:~0,1!"=="@" (
				set section=%%~l
				set section=!section:~1!
				call :parse_target !section! %%~m %%~n
				if ERRORLEVEL 1 exit /b !ERRORLEVEL!
			) else (
				call :prime_download %%~l %%~m %%~n
				if ERRORLEVEL 1 exit /b !ERRORLEVEL!
			)
		)

		set wtargets=%%b
		if not [!wtargets!] == [] goto :MOR_TARGETS_START
	)
endlocal DisableDelayedExpansion
goto :eof

:parse_target <section> <target_definition> <value>
setlocal EnableDelayedExpansion
	set section=%1
	set wsections=![#%section%[/]!
:MOR_PARSE_TARGET_START
	for /f "usebackq tokens=1* delims= " %%a in ('!wsections!') do (
		set [%%a[ 2>NUL >NULL
		if ERRORLEVEL 1 (
			echo ^> Cannot find target '%%~a'
			exit /b 1
		)
		for /f "usebackq tokens=1,2,3* delims=[]=" %%e in (`set  [%%a[`) do (
			if "%%~f"=="%~2-%~3" (
				if not defined %%~f_done (
					set %%~f_done=1
					call :prime_download %%e %%~f %%~g || goto :eof
				)
			)
		)

		for /f "usebackq tokens=1,2,3* delims=[]=" %%e in (`set  [%%a[`) do (
			if not defined %%~f_done (
				echo ^> Cannot find key '%%~f'
				exit /b 1
			)
		)
		set wsections=%%b
		if not [%%b] == [] goto :MOR_PARSE_TARGET_START
	)
endlocal DisableDelayedExpansion
goto :eof

:prime_download <section> <target> <url>
setlocal EnableDelayedExpansion
	set current_target_dir="%root_dir%\%1"
	shift
	call :logi Current Target Dir: !current_target_dir!
	if not exist "!current_target_dir!" mkdir "!current_target_dir!"
	:key_value
	if "%~1" == "" goto :eof
	rem TODO Check if this for loop is really necessary
	for %%i in (%2) do set ext=%%~xi
	where /q curl
	if ERRORLEVEL 1 (
		call :download_archive !current_target_dir! %1 %2 !ext!
		if ERRORLEVEL 1 exit /b !ERRORLEVEL!
	) else (
		call :download_archive_curl !current_target_dir! %1 %2 !ext!
		if ERRORLEVEL 1 exit /b !ERRORLEVEL!
	)


	for %%x in (%MOR_EXTS_TAR%) do (
		if "!ext!"=="%%x" (
			call :unzip_archive !current_target_dir! %1 !ext!
			if ERRORLEVEL 1 exit /b !ERRORLEVEL!
			goto :MOR_AFTER_EXTRACT
		)
	)

	:MOR_AFTER_EXTRACT
	shift
	shift
	goto :key_value
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
	exit /b %ERRORLEVEL%
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
setlocal EnableDelayedExpansion
:parse
set arg=%~1
if "%~1" == "" goto :MOR_MAIN_CONTINUE
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
	set targets=%targets% %~1
)
if "%arg:~0,1%" == "=" echo "= command"

shift
goto :parse
:MOR_MAIN_CONTINUE
call :read_ini "%config_file%"
if ERRORLEVEL 1 (
	echo ^^^! Error
	exit /b !ERRORLEVEL!
)
endlocal DisableDelayedExpansion
goto :eof

endlocal
