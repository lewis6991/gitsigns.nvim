$version = '3.8.0'
$archive = Join-Path $env:RUNNER_TEMP "luarocks-$version.zip"
$source = Join-Path $env:RUNNER_TEMP "luarocks-$version"
$install = Join-Path $source 'install.bat'
$prefix = Join-Path $env:GITHUB_WORKSPACE '.luarocks'
$shimDir = Join-Path $prefix 'bin'
$lua = Join-Path $env:GITHUB_WORKSPACE '.lua'

Invoke-WebRequest `
  -Uri "https://github.com/luarocks/luarocks/archive/refs/tags/v$version.zip" `
  -OutFile $archive

Expand-Archive -Path $archive -DestinationPath $env:RUNNER_TEMP

Push-Location $source
& .\install.bat /NOADMIN /SELFCONTAINED /F /Q /P $prefix /LUA $lua /LV 5.1
$status = $LASTEXITCODE
Pop-Location

if ($status -ne 0) {
  exit $status
}

New-Item -ItemType Directory -Force -Path $shimDir | Out-Null

Set-Content -Path (Join-Path $shimDir 'luarocks') -Encoding utf8 -Value @'
#!/usr/bin/env bash
exec "$(dirname "$0")/../luarocks.bat" "$@"
'@

Set-Content -Path (Join-Path $shimDir 'luarocks-admin') -Encoding utf8 -Value @'
#!/usr/bin/env bash
exec "$(dirname "$0")/../luarocks-admin.bat" "$@"
'@
