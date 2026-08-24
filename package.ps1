# package.ps1 — Flutter 一键出包脚本 (Windows)
# ----------------------------------------------------------------------------
# 支持目标:
#   apk   Android 安装包 (按 ABI 拆分)
#   exe   Windows 安装包 (flutter build windows + Inno Setup 打包为安装程序；
#         若没装 Inno Setup，则退化为 Release 文件夹的便携 ZIP)
#
# 用法 (在 Flutter 项目根目录, PowerShell 中):
#   .\package.ps1 all      # 出 apk + exe
#   .\package.ps1 apk      # 只出 Android APK
#   .\package.ps1 exe      # 只出 Windows EXE / 安装包
#   .\package.ps1 clean    # 清掉 build/ 与 dist/
#   .\package.ps1 -Help    # 看这个
#
# 出包位置: 项目根目录下的 dist/<app>-<版本>-<平台>.{apk,exe,zip}
# ----------------------------------------------------------------------------

param(
  [string]$Target = "all",
  [switch]$Help
)

$ErrorActionPreference = "Stop"

# ====== 可改配置区 ======
$OutputDir    = if ($env:OUTPUT_DIR)    { $env:OUTPUT_DIR }    else { "dist" }
$AppName      = if ($env:APP_NAME)      { $env:APP_NAME }      else { "" }
$Version      = if ($env:VERSION)       { $env:VERSION }       else { "" }
$BuildNumber  = if ($env:BUILD_NUMBER)  { $env:BUILD_NUMBER }  else { "" }
# ========================

function Log  { Write-Host "[OK]   $args" -ForegroundColor Green }
function Info { Write-Host "[..]   $args" -ForegroundColor Blue }
function Warn { Write-Host "[!!]   $args" -ForegroundColor Yellow }
function Die  { Write-Host "[XX]   $args" -ForegroundColor Red; exit 1 }

if ($Help) {
  Get-Content $MyInvocation.MyCommand.Path | Select-Object -First 22
  exit 0
}

if (-not (Test-Path "pubspec.yaml")) { Die "当前目录不是 Flutter 项目，请把 package.ps1 放到项目根目录再跑。" }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Die "找不到 flutter 命令，请先安装 Flutter 并加入 PATH。" }

function Read-Meta {
  if (-not $AppName) {
    $n = (Get-Content pubspec.yaml | Where-Object { $_ -match '^name:' } | Select-Object -First 1) -replace '^name:\s*',''
    $script:AppName = $n.Trim()
  }
  if (-not $Version) {
    $pv = (Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' } | Select-Object -First 1) -replace '^version:\s*',''
    $script:Version = ($pv -split '\+')[0].Trim()
    if (-not $BuildNumber) { $parts = $pv -split '\+'; if ($parts.Count -gt 1) { $script:BuildNumber = $parts[1].Trim() } }
  }
  Info "项目: $AppName  版本: $Version$(if($BuildNumber){"+$BuildNumber"})  (系统: Windows)"
}

function Build-APK {
  Info "构建 Android APK (按 ABI 拆分) ..."
  flutter build apk --release --split-per-abi
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  $found = $false
  Get-ChildItem build/app/outputs/flutter-apk/*.apk | ForEach-Object {
    $f = $_.FullName
    $arch = if ($f -match "arm64-v8a") { "arm64" } elseif ($f -match "armeabi-v7a") { "armeabi" } elseif ($f -match "x86_64") { "x86_64" } else { "universal" }
    $dst = "$OutputDir/$AppName-$Version-android-$arch.apk"
    Copy-Item $f $dst
    Log "APK($arch) -> $dst"
    $found = $true
  }
  if (-not $found) { Die "没找到 build/app/outputs/flutter-apk/*.apk" }
}

function Build-EXE {
  Info "构建 Windows EXE ..."
  flutter build windows --release
  $rel = "build/windows/x64/runner/Release"
  if (-not (Test-Path "$rel/*.exe")) { Die "没找到 $rel/*.exe" }
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

  # 先出一个便携 ZIP (永远可用)
  $zip = "$OutputDir/$AppName-$Version-windows-portable.zip"
  Compress-Archive -Path "$rel/*" -DestinationPath $zip -Force
  Log "便携包 -> $zip"

  # 若有 Inno Setup，再出安装程序 exe
  $iscc = Get-Command iscc -ErrorAction SilentlyContinue
  if ($iscc) {
    Info "检测到 Inno Setup，生成安装程序 ..."
    $iss = "$OutputDir/build.iss"
    $appNameEsc = $AppName
    @"
[Setup]
AppName=$appNameEsc
AppVersion=$Version
DefaultDirName={pf}\$appNameEsc
DefaultGroupName=$appNameEsc
OutputDir=$((Get-Location)/$OutputDir)
OutputBaseFilename=$appNameEsc-$Version-windows-setup
Compression=lzma2
SolidCompression=yes

[Files]
Source="$((Get-Location)/$rel)/*"; DestDir="{app}"; Flags=recursesubdirs

[Icons]
Name="{group}\$appNameEsc"; Filename="{app}\$appNameEsc.exe"
Name="{autoprograms}\$appNameEsc"; Filename="{app}\$appNameEsc.exe"
"@ | Set-Content -Encoding UTF8 $iss
    & $iscc.Path $iss | Out-Null
    $setup = "$OutputDir/$appNameEsc-$Version-windows-setup.exe"
    if (Test-Path $setup) { Log "安装包 -> $setup" } else { Warn "Inno Setup 编译未完成，已保留便携 ZIP。" }
  } else {
    Warn "未安装 Inno Setup (choco install innosetup)，已退化为便携 ZIP。装了后重跑 .\package.ps1 exe 即可出安装程序。"
  }
}

function Clean {
  Info "清理 build/ 与 $OutputDir/ ..."
  Remove-Item -Recurse -Force build, $OutputDir -ErrorAction SilentlyContinue
  Log "已清理"
}

Read-Meta
switch ($Target) {
  "all"  { Build-APK; Build-EXE }
  "apk"  { Build-APK }
  "exe"  { Build-EXE }
  "clean"{ Clean }
  default { Die "未知目标: $Target  (使用 .\package.ps1 -Help 查看用法)" }
}
Log "全部完成。出包目录: $OutputDir/"
