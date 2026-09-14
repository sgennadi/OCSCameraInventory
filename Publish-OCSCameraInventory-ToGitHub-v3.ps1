param(
    [string]$RepoName = "OCSCameraInventory",
    [string]$Owner = "sgennadi",
    [ValidateSet("public", "private")]
    [string]$Visibility = "public",
    [string]$SourcePath = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

Require-Command -Name "git"
Require-Command -Name "gh"

$resolvedSource = Resolve-Path -LiteralPath $SourcePath
$SourcePath = $resolvedSource.Path
$repoFullName = "$Owner/$RepoName"

Write-Host "Checking GitHub authentication..."
& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

Write-Host ""
Write-Host "Repository: $repoFullName"
Write-Host "Source:     $SourcePath"
Write-Host ""

# Create .gitignore only if the project does not already contain one.
$gitIgnorePath = Join-Path $SourcePath ".gitignore"

if (-not (Test-Path -LiteralPath $gitIgnorePath)) {
    $gitIgnoreLines = @(
        "# Visual Studio",
        ".vs/",
        "*.user",
        "*.suo",
        "",
        "# Build output",
        "build-output/",
        "bin/",
        "obj/",
        "Debug/",
        "Release/",
        "",
        "# Compiler/intermediate files",
        "*.obj",
        "*.pdb",
        "*.ilk",
        "*.exp",
        "*.lib",
        "*.tlog",
        "*.lastbuildstate",
        "",
        "# Temporary files",
        "*.tmp",
        "*.log",
        "Thumbs.db",
        "Desktop.ini"
    )

    Set-Content -LiteralPath $gitIgnorePath -Value $gitIgnoreLines -Encoding UTF8
    Write-Host "Created .gitignore"
}

# Keep an existing README.md unchanged.
# Create a small README only if the project has none.
$readmePath = Join-Path $SourcePath "README.md"

if (-not (Test-Path -LiteralPath $readmePath)) {
    $folderName = Split-Path -Leaf $SourcePath

    $readmeLines = @(
        "# $RepoName",
        "",
        "Native camera inventory project for OCS Inventory NG.",
        "",
        "Source project folder:",
        "",
        "    $folderName",
        "",
        "The project inventories physical USB cameras/webcams in OCS Inventory NG.",
        "",
        "## Logitech C920",
        "",
        "USB vendor/product IDs:",
        "",
        "    VID_046D",
        "    PID_082D",
        "",
        "## Notes",
        "",
        "This repository contains the project source, build/install scripts, and SQL queries."
    )

    Set-Content -LiteralPath $readmePath -Value $readmeLines -Encoding UTF8
    Write-Host "Created README.md"
}

Push-Location -LiteralPath $SourcePath

try {
    if (-not (Test-Path -LiteralPath ".git")) {
        Write-Host "Initializing Git repository..."
        & git init

        if ($LASTEXITCODE -ne 0) {
            throw "git init failed."
        }
    }

    # Force the local branch name to main.
    $branch = (& git branch --show-current 2>$null | Select-Object -First 1)

    if ([string]::IsNullOrWhiteSpace($branch)) {
        & git checkout -b main

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create branch 'main'."
        }
    }
    elseif ($branch.Trim() -ne "main") {
        & git branch -M main

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to rename the current branch to 'main'."
        }
    }

    Write-Host "Adding project files..."
    & git add -A

    if ($LASTEXITCODE -ne 0) {
        throw "git add failed."
    }

    $changes = @(& git status --porcelain)

    if ($changes.Count -gt 0) {
        $gitName = (& git config user.name 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($gitName)) {
            & git config user.name $Owner
        }

        $gitEmail = (& git config user.email 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($gitEmail)) {
            & git config user.email "$Owner@users.noreply.github.com"
        }

        Write-Host "Creating commit..."
        & git commit -m "Initial OCS Camera Inventory project"

        if ($LASTEXITCODE -ne 0) {
            throw "git commit failed."
        }
    }
    else {
        Write-Host "No new local changes to commit."
    }

    & gh repo view $repoFullName 1>$null 2>$null
    $repoExists = ($LASTEXITCODE -eq 0)

    if (-not $repoExists) {
        Write-Host ""
        Write-Host "Creating GitHub repository $repoFullName..."

        if ($Visibility -eq "private") {
            & gh repo create $repoFullName --private --source=. --remote=origin --push
        }
        else {
            & gh repo create $repoFullName --public --source=. --remote=origin --push
        }

        if ($LASTEXITCODE -ne 0) {
            throw "GitHub repository creation or initial push failed."
        }
    }
    else {
        Write-Host ""
        Write-Host "GitHub repository already exists: $repoFullName"

        $origin = (& git remote get-url origin 2>$null | Select-Object -First 1)

        if ([string]::IsNullOrWhiteSpace($origin)) {
            & git remote add origin "https://github.com/$repoFullName.git"

            if ($LASTEXITCODE -ne 0) {
                throw "Unable to add GitHub remote 'origin'."
            }
        }
        elseif ($origin -notmatch [regex]::Escape("$Owner/$RepoName")) {
            Write-Host "Updating origin remote..."
            & git remote set-url origin "https://github.com/$repoFullName.git"

            if ($LASTEXITCODE -ne 0) {
                throw "Unable to update GitHub remote 'origin'."
            }
        }

        Write-Host "Pushing main branch..."
        & git push -u origin main

        if ($LASTEXITCODE -ne 0) {
            throw "git push failed. Check whether the remote repository already contains a different commit history."
        }
    }

    Write-Host ""
    Write-Host "DONE"
    Write-Host "https://github.com/$repoFullName"
}
finally {
    Pop-Location
}
