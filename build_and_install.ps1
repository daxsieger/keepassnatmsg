<#
.SYNOPSIS
    Compila e installa il plugin KeePassNatMsg per KeePass 2.x

.DESCRIPTION
    Questo script:
    1. Verifica i prerequisiti (MSBuild, KeePass installato)
    2. Copia KeePass.exe nella cartella build (se necessario)
    3. Compila la solution in modalità Release
    4. Copia i file del plugin nella cartella Plugins di KeePass

.PARAMETER Configuration
    Configurazione di build (Debug o Release). Default: Release

.PARAMETER SkipInstall
    Se specificato, compila senza installare

.EXAMPLE
    .\build_and_install.ps1
    
.EXAMPLE
    .\build_and_install.ps1 -Configuration Debug -SkipInstall
#>

param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

# Colori per output
function Write-Step { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[X] $msg" -ForegroundColor Red }

# Percorsi
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SolutionPath = Join-Path $ScriptDir "KeePassNatMsg.sln"
$BuildDir = Join-Path $ScriptDir "build"
$OutputDir = Join-Path $ScriptDir "KeePassNatMsg\bin\$Configuration"

# Percorsi KeePass
$KeePassPaths = @(
    "$env:ProgramFiles\KeePass Password Safe 2",
    "${env:ProgramFiles(x86)}\KeePass Password Safe 2",
    "$env:LOCALAPPDATA\KeePass Password Safe 2"
)

# Trova MSBuild
$MSBuildPaths = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
)

Write-Host @"

  _  __          ____               _   _       _   __  __           
 | |/ /___  ___ |  _ \ __ _ ___ ___| \ | | __ _| |_|  \/  |___  __ _ 
 | ' // _ \/ _ \| |_) / _` / __/ __|  \| |/ _` | __| |\/| / __|/ _` |
 | . \  __/  __/|  __/ (_| \__ \__ \ |\  | (_| | |_| |  | \__ \ (_| |
 |_|\_\___|\___|_|   \__,_|___/___/_| \_|\__,_|\__|_|  |_|___/\__, |
                                                              |___/ 
  Build & Install Script
"@ -ForegroundColor Magenta

# 1. Trova MSBuild
Write-Step "Ricerca MSBuild"
$MSBuild = $null
foreach ($path in $MSBuildPaths) {
    if (Test-Path $path) {
        $MSBuild = $path
        Write-Success "Trovato: $path"
        break
    }
}
if (-not $MSBuild) {
    Write-Err "MSBuild non trovato. Installa Visual Studio Build Tools."
    exit 1
}

# 2. Trova KeePass
Write-Step "Ricerca KeePass"
$KeePassDir = $null
foreach ($path in $KeePassPaths) {
    $exePath = Join-Path $path "KeePass.exe"
    if (Test-Path $exePath) {
        $KeePassDir = $path
        Write-Success "Trovato: $path"
        break
    }
}
if (-not $KeePassDir) {
    Write-Err "KeePass non trovato. Installalo prima di procedere."
    exit 1
}

$KeePassExe = Join-Path $KeePassDir "KeePass.exe"
$PluginsDir = Join-Path $KeePassDir "Plugins"

# 3. Prepara cartella build con KeePass.exe
Write-Step "Preparazione riferimenti"
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    Write-Success "Creata cartella build"
}

$BuildKeePassExe = Join-Path $BuildDir "KeePass.exe"
if (-not (Test-Path $BuildKeePassExe)) {
    Copy-Item $KeePassExe -Destination $BuildDir
    Write-Success "Copiato KeePass.exe in build/"
} else {
    Write-Success "KeePass.exe già presente in build/"
}

# 4. Compila
Write-Step "Compilazione ($Configuration)"
$buildArgs = @(
    $SolutionPath,
    "/p:Configuration=$Configuration",
    "/t:Rebuild",
    "/v:minimal",
    "/nologo"
)

& $MSBuild @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Err "Compilazione fallita!"
    exit 1
}
Write-Success "Compilazione completata"

# 5. Verifica output
Write-Step "Verifica output"
$RequiredFiles = @(
    "KeePassNatMsg.dll",
    "Newtonsoft.Json.dll"
)

$MissingFiles = @()
foreach ($file in $RequiredFiles) {
    $filePath = Join-Path $OutputDir $file
    if (-not (Test-Path $filePath)) {
        $MissingFiles += $file
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Err "File mancanti: $($MissingFiles -join ', ')"
    exit 1
}

Write-Success "Tutti i file presenti in: $OutputDir"
Get-ChildItem $OutputDir | ForEach-Object {
    Write-Host "  - $($_.Name) ($([math]::Round($_.Length/1KB, 1)) KB)" -ForegroundColor Gray
}

# 6. Installa
if ($SkipInstall) {
    Write-Warn "Installazione saltata (-SkipInstall)"
} else {
    Write-Step "Installazione plugin"
    
    # Verifica se KeePass è in esecuzione
    $keepassProcess = Get-Process -Name "KeePass" -ErrorAction SilentlyContinue
    if ($keepassProcess) {
        Write-Warn "KeePass è in esecuzione. Chiuderlo per procedere."
        $response = Read-Host "Vuoi chiudere KeePass ora? (S/N)"
        if ($response -match "^[SsYy]") {
            $keepassProcess | Stop-Process -Force
            Start-Sleep -Seconds 2
            Write-Success "KeePass chiuso"
        } else {
            Write-Warn "Installazione annullata"
            exit 0
        }
    }
    
    # Crea cartella Plugins se non esiste
    if (-not (Test-Path $PluginsDir)) {
        New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null
        Write-Success "Creata cartella Plugins"
    }
    
    # Copia file
    $FilesToCopy = @(
        "KeePassNatMsg.dll",
        "Newtonsoft.Json.dll",
        "Mono.Posix.dll"  # Opzionale, per compatibilità Linux/Mac
    )
    
    foreach ($file in $FilesToCopy) {
        $srcPath = Join-Path $OutputDir $file
        if (Test-Path $srcPath) {
            $dstPath = Join-Path $PluginsDir $file
            Copy-Item $srcPath -Destination $dstPath -Force
            Write-Success "Copiato: $file"
        }
    }
    
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Plugin installato con successo!" -ForegroundColor Green
    Write-Host "  Percorso: $PluginsDir" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    # Chiedi se avviare KeePass
    $response = Read-Host "`nVuoi avviare KeePass ora? (S/N)"
    if ($response -match "^[SsYy]") {
        Start-Process $KeePassExe
        Write-Success "KeePass avviato"
    }
}

Write-Host "`nOperazione completata.`n" -ForegroundColor Cyan
