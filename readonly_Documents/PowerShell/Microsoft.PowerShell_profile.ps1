# Important constants
$NVIM = "C:\Users\TheLa\AppData\Local\nvim"
$ALACRITTY = "C:\Users\TheLa\AppData\Roaming\alacritty\alacritty.toml"
$HISTORY = "$env:USERPROFILE\Documents\PowerShell\.pwsh_dir_history"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:TERM = "xterm-256color"
$env:ASAN_SYMBOLIZER_PATH = "C:\Program Files\LLVM\bin\llvm-symbolizer.exe"
$env:ASAN_OPTIONS = "color=always,verbosity=1,abort_on_error=1"
$env:LC_ALL = "C.UTF-8"

function Compile-And-Run {
	param(
		[string]$path,
		[string[]]$arguments,
		[switch]$CompileOnly
	)

	if (-not (Test-Path $path)) {
		Write-Host "File not found: $path"
		return $false
	}

	$absPath = if ([System.IO.Path]::IsPathRooted($path)) { 
		$path
	} else {
		Join-Path (Get-Location) $path 
	}

	$sourceFolder = Split-Path $absPath
	$sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($absPath)

	$outputFolder = Join-Path $sourceFolder $sourceBase
	if (-not (Test-Path $outputFolder)) {
		New-Item -ItemType Directory -Path $outputFolder | Out-Null
	}

	$out = Join-Path $outputFolder "a.exe"

	clang++ -std=c++23 -g -Wall -Wextra -pedantic $absPath -o $out #-fsanitize=address

	if ($?) {
		if ($CompileOnly) {
			if ($arguments) {
				Write-Host "Warning: Arguments are ignored in compile-only mode (-c)" -ForegroundColor Yellow
			}
			Write-Host "Compilation successful" -ForegroundColor Green
		} else {
			if ($arguments) {
				& $out $arguments
			} else {
				& $out
			}
		}
		return $true
	}

	return $false
}

function Qlang {
param(
		[Parameter(Position=0)]
		[string]$path,
		[Parameter(ValueFromRemainingArguments=$true)]
		[string[]]$arguments
	)

	if (-not $path) {
		Write-Host "Enter a C++ source file and optional arguments (or 'exit' to quit):"
		while ($true) {
			$userInput = Read-Host "Qlang>"
			if ($userInput -eq "exit") {
				break
			}

			$parts = $userInput -split ' '
			$sourcePath = $parts[0]
			# Check for -c flag in interactive mode
			$compileOnly = $parts -contains "-c"
			$cmdArgs = $parts | Where-Object { $_ -ne "-c" -and $_ -ne $sourcePath }

			Compile-And-Run -path $sourcePath -arguments $cmdArgs -CompileOnly:$compileOnly
		}
		return
	}

	# Check for -c flag in command line mode
	$compileOnly = $arguments -contains "-c"
	$filteredArgs = $arguments | Where-Object { $_ -ne "-c" }
	Compile-And-Run -path $path -arguments $filteredArgs -CompileOnly:$compileOnly
}

function Locate {
param(
		[string]$Name
	)

	$cmd = Get-Command $Name -ErrorAction SilentlyContinue
	if ($cmd) {
		$cmd | Select-Object -ExpandProperty Source
	} else {
		Write-Host "$Name not found in PATH."
	}
}

function Clean-Path {
param(
		[ValidateSet("User","Machine")]
		[string]$Target = "User"  # Choose whether to clean user or system PATH
	)

	# Determine target
	$envTarget = if ($Target -eq "User") { [EnvironmentVariableTarget]::User } else { [EnvironmentVariableTarget]::Machine }

	# Get current PATH
	$currentPath = [Environment]::GetEnvironmentVariable("PATH", $envTarget)
	$paths = $currentPath -split ';'

	# Separate existing vs missing
	$existing = $paths | Where-Object { Test-Path $_ }
	$missing = $paths | Where-Object { -not (Test-Path $_) }

	# Update PATH with existing only
	$newPath = ($existing -join ';')
	[Environment]::SetEnvironmentVariable("PATH", $newPath, $envTarget)

	# Output results
	Write-Host "Cleaned PATH ($Target):"
	Write-Host "`n✅ Existing paths:"
	$existing | ForEach-Object { Write-Host $_ }

	if ($missing) {
		Write-Host "`n❌ Removed paths:"
		$missing | ForEach-Object { Write-Host $_ }
	} else {
		Write-Host "`nNo paths were removed."
	}
}

function Setup-MSVC {
	cmd /c '"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 && powershell'
}

Set-Alias -Name vcvarsall -Value Setup-MSVC
Function ln {
param(
		[string]$Target,
		[string]$Link
	)

	# Create symbolic link
	New-Item -ItemType SymbolicLink -Path $Link -Target $Target
}

function Set-Update-Location($path){
	if ($path.EndsWith("\..")) {
		$path = Split-Path -Path $path | Split-Path
	}
	$historyFile = $HISTORY
	$maxHistorySize = 20  # Keep last 100 directories

	$recentDirs = @()
	if (Test-Path $historyFile) {
		$recentDirs = Get-Content $historyFile
	}

	# Add new directory and remove duplicates
	$recentDirs = @($path) + ($recentDirs | Where-Object { $_ -ne $path })

	# Keep only the most recent entries
	$recentDirs = $recentDirs | Select-Object -First $maxHistorySize

	# Save to file
	$recentDirs | Set-Content $historyFile

	Set-Location $path
}
function Test-IsAbsolutePath {
param([string]$Path)

	# Check if path starts with a drive letter (like C:) or UNC path (\\server)
	return [System.IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\')
}

function c($path) {
	# If it's a relative path, convert it to absolute
	if (-not (Test-IsAbsolutePath $path)) {
		$path = Join-Path (Get-Location) $path
	}

	if (Test-Path $path -PathType Container) {
		Set-Update-Location $path
	}
	else {
		# If it's a file, navigate to its containing directory
		$parentPath = Split-Path -Path $path
		Write-Host "Path is a file. Navigating to containing directory." -ForegroundColor Yellow
		Set-Update-Location $parentPath
	}
}
# Function to select recent directories
function sr {
	# File to store directory history
	$historyFile = $HISTORY

	# Create history file if it doesn't exist
	if (-not (Test-Path $historyFile)) {
		New-Item -Path $historyFile -ItemType File
	}

	# Read existing history
	$recentDirs = @()
	if (Test-Path $historyFile) {
		$recentDirs = Get-Content $historyFile
	}

	# Display recent directories using fzf
	$selection = $recentDirs | fzf
	if ($selection) {
		Set-Location $selection
	}
}

# Modified sd function to track directory changes and handle '..' properly
function sd {
param([string]$currentPath = (Get-Location).Path)
	while ($true) {
		$dirs = @("..")
		$subDirs = Get-ChildItem -Path $currentPath -Directory -Recurse -Depth 2 | Select-Object -ExpandProperty FullName
		$dirs += $subDirs

		$result = $dirs | fzf --expect=tab,enter
		if (-not $result) { break }
		$key = $result[0]
		$selection = $result[1]

		if ($selection -eq "..") {
			if ($key -eq "enter") {
				Set-Update-Location((Get-Item $currentPath).Parent.FullName)
				break
			} else {
				$currentPath = (Get-Item $currentPath).Parent.FullName
			}
		}
		else {
			$newPath = $selection
			if ($key -eq "tab") {
				$currentPath = $newPath
				continue
			}
			elseif ($key -eq "enter") {
				Set-Update-Location($newPath)
				break
			}
		}
	}
}

Set-PSReadLineKeyHandler -Key Tab -Function AcceptSuggestion

