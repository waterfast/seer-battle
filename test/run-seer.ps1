param(
    [switch]$Auto,
    [switch]$Pvp,
    [string]$Lua
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not $Lua) {
    $runtime = Get-Command lua55 -ErrorAction SilentlyContinue
    if ($runtime) {
        $Lua = $runtime.Source
    } else {
        throw '需要 Lua 5.5。请安装 lua55 并加入 PATH，或通过 -Lua 参数指定可执行文件路径。'
    }
}
if (-not (Test-Path -LiteralPath $Lua -PathType Leaf)) {
    throw '需要 Lua 5.5。请通过 -Lua 参数指定 lua55.exe 的路径。'
}

$battleArguments = @((Join-Path $PSScriptRoot 'seer_battle.lua'))
if ($Auto) {
    $battleArguments += '--auto'
} elseif ($Pvp) {
    $battleArguments += '--pvp'
}
& $Lua @battleArguments
exit $LASTEXITCODE
