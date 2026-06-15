$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\flutter_env.ps1"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $projectRoot

flutter run -d windows
