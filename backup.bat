@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$root = [System.IO.Path]::GetFullPath('%SCRIPT_DIR%');" ^
  "$ignorePath = Join-Path $root '.gitignore';" ^
  "$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss';" ^
  "$zipName = 'server_' + $timestamp + '.zip';" ^
  "$zipPath = Join-Path $root $zipName;" ^
  "$patterns = @();" ^
  "if (Test-Path $ignorePath) {" ^
  "  $patterns = Get-Content $ignorePath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') };" ^
  "}" ^
  "$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {" ^
  "  $full = $_.FullName;" ^
  "  if ($full -eq $zipPath) { return $false };" ^
  "  $relative = $full.Substring($root.Length).TrimStart('\');" ^
  "  foreach ($pattern in $patterns) {" ^
  "    $normalized = $pattern.Replace('/', '\');" ^
  "    if ($normalized.EndsWith('\')) {" ^
  "      $prefix = $normalized.TrimEnd('\') + '\';" ^
  "      if ($relative.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false };" ^
  "      continue;" ^
  "    }" ^
  "    if ($normalized.StartsWith('*')) {" ^
  "      if ($relative -like $normalized) { return $false };" ^
  "      continue;" ^
  "    }" ^
  "    if ($relative -ieq $normalized) { return $false };" ^
  "  }" ^
  "  return $true;" ^
  "};" ^
  "Add-Type -AssemblyName System.IO.Compression;" ^
  "Add-Type -AssemblyName System.IO.Compression.FileSystem;" ^
  "$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create);" ^
  "try {" ^
  "  foreach ($file in $files) {" ^
  "    $entryName = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/');" ^
  "    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null;" ^
  "  }" ^
  "} finally {" ^
  "  $zip.Dispose();" ^
  "}" ^
  "Write-Host ('Created ' + $zipName)"

if errorlevel 1 exit /b %errorlevel%

endlocal
