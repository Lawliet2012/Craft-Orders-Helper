param(
    [string]$AddonDir = "CraftOrdersHelper",
    [string]$PackageMeta = ".pkgmeta"
)

$ErrorActionPreference = "Stop"

function Assert-Valid {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$addonPath = Join-Path $root $AddonDir
$tocPath = Join-Path $addonPath "$AddonDir.toc"
$pkgmetaPath = Join-Path $root $PackageMeta

Assert-Valid (Test-Path -LiteralPath $addonPath -PathType Container) "Missing addon directory: $AddonDir"
Assert-Valid (Test-Path -LiteralPath $tocPath -PathType Leaf) "The TOC file must be named $AddonDir.toc inside $AddonDir."
Assert-Valid (Test-Path -LiteralPath $pkgmetaPath -PathType Leaf) "Missing package metadata file: $PackageMeta"

$tocLines = Get-Content -LiteralPath $tocPath
$metadata = @{}
$payloadFiles = New-Object System.Collections.Generic.List[string]

foreach ($line in $tocLines) {
    if ($line -match '^##\s*([^:]+):\s*(.*)$') {
        $metadata[$matches[1].Trim()] = $matches[2].Trim()
        continue
    }

    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
        continue
    }

    $payloadFiles.Add($trimmed)
}

foreach ($field in @("Interface", "Title", "Notes", "Author", "Version")) {
    Assert-Valid $metadata.ContainsKey($field) "Missing TOC metadata: ## $field"
    Assert-Valid ($metadata[$field] -ne "") "Empty TOC metadata: ## $field"
}

Assert-Valid ($metadata["Title"] -eq $AddonDir) "TOC title should match addon/package name ($AddonDir)."
Assert-Valid ($metadata["Version"] -match '^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$') "TOC version should be semver-like, for example 1.4.2."

$interfaces = $metadata["Interface"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
Assert-Valid ($interfaces.Count -gt 0) "TOC Interface must contain at least one interface number."
foreach ($interface in $interfaces) {
    Assert-Valid ($interface -match '^\d+$') "Invalid TOC Interface value: $interface"
}

Assert-Valid ($payloadFiles.Count -gt 0) "TOC does not list any files to load."
foreach ($file in $payloadFiles) {
    $normalized = $file -replace '/', [IO.Path]::DirectorySeparatorChar
    $payloadPath = Join-Path $addonPath $normalized
    Assert-Valid (Test-Path -LiteralPath $payloadPath -PathType Leaf) "TOC references a missing file: $file"
}

if ($metadata.ContainsKey("IconTexture")) {
    $iconTexture = $metadata["IconTexture"]
    $addonPrefix = "Interface\AddOns\$AddonDir\"
    Assert-Valid $iconTexture.StartsWith($addonPrefix) "IconTexture should point inside Interface\AddOns\$AddonDir."
    $iconRelative = $iconTexture.Substring($addonPrefix.Length)
    $iconBase = Join-Path $addonPath ($iconRelative -replace '\\', [IO.Path]::DirectorySeparatorChar)
    $iconExists = (Test-Path -LiteralPath "$iconBase.tga" -PathType Leaf) -or (Test-Path -LiteralPath "$iconBase.blp" -PathType Leaf)
    Assert-Valid $iconExists "IconTexture references a missing .tga or .blp file: $iconTexture"
}

$pkgmeta = Get-Content -Raw -LiteralPath $pkgmetaPath
Assert-Valid ($pkgmeta -match "(?m)^\s*package-as:\s*$([regex]::Escape($AddonDir))\s*$") ".pkgmeta package-as must be $AddonDir."
Assert-Valid ($pkgmeta -match "(?m)^\s*$([regex]::Escape("$AddonDir/$AddonDir")):\s*$([regex]::Escape($AddonDir))\s*$") ".pkgmeta must move the nested addon folder into the package root."
foreach ($ignored in @(".github", "docs", "scripts")) {
    Assert-Valid ($pkgmeta -match "(?m)^\s*-\s*$([regex]::Escape($ignored))\s*$") ".pkgmeta should ignore $ignored so development files are not shipped."
}

if ($env:GITHUB_REF_TYPE -eq "tag" -and $env:GITHUB_REF_NAME) {
    $tagVersion = $env:GITHUB_REF_NAME -replace '^v', ''
    Assert-Valid ($metadata["Version"] -eq $tagVersion) "Tag $($env:GITHUB_REF_NAME) does not match TOC version $($metadata["Version"])."
}

Write-Host "Addon metadata validation passed for $AddonDir $($metadata["Version"])."
