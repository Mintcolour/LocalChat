[CmdletBinding()]
param(
    [switch]$UseLocalEnvironment,
    [ValidateSet('Visual Studio 17 2022', 'Visual Studio 18 2026')]
    [string]$CMakeGenerator
)

$ErrorActionPreference = 'Stop'
if ($UseLocalEnvironment) {
    . (Join-Path $PSScriptRoot 'flutter_env.ps1')
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$cliRoot = Join-Path $projectRoot 'tools/localchat_cli'
$cliBuild = Join-Path $projectRoot 'build/cli'
$bundle = Join-Path $projectRoot 'build/windows/x64/runner/Release'
$releaseDir = Join-Path $projectRoot 'dist'

New-Item -ItemType Directory -Path $cliBuild -Force | Out-Null
Push-Location -LiteralPath $cliRoot
try {
    & dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'CLI dependency resolution failed.' }
    & dart compile exe bin/localchat_cli.dart -o (Join-Path $cliBuild 'localchat-cli.exe')
    if ($LASTEXITCODE -ne 0) { throw 'CLI compilation failed.' }
} finally {
    Pop-Location
}

Push-Location -LiteralPath $projectRoot
try {
    if ($CMakeGenerator) {
        # Generate Flutter's SDK/plugin configuration, then use the explicitly
        # selected toolchain in a separate cache (for example when ATL is absent
        # from the VS installation detected by Flutter).
        & flutter build windows --release --config-only
        if ($LASTEXITCODE -ne 0) { throw 'Windows build configuration failed.' }
        $customBuild = Join-Path $projectRoot ('build/windows-' + $CMakeGenerator.Replace(' ', '-'))
        & cmake -S windows -B $customBuild -G $CMakeGenerator -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
        if ($LASTEXITCODE -ne 0) { throw 'CMake generation failed.' }
        & cmake --build $customBuild --config Release --target INSTALL --parallel 4
        if ($LASTEXITCODE -ne 0) { throw 'Windows client build failed.' }
        $bundle = Join-Path $customBuild 'runner/Release'
    } else {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows client build failed.' }
    }
    Copy-Item -LiteralPath (Join-Path $cliBuild 'localchat-cli.exe') -Destination $bundle
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    $archive = Join-Path $releaseDir 'LocalChat-windows.zip'
    Compress-Archive -LiteralPath $bundle -DestinationPath $archive -Force
    Write-Host "Windows bundle: $bundle"
    Write-Host "Release archive: $archive"
} finally {
    Pop-Location
}
