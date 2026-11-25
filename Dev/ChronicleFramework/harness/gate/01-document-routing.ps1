#Requires -Version 7.0

# Document routing: ContextState coverage, research categories, Harness script hygiene (BOM + #Requires).
# Sources asserted here: AGENTS.md


# AGENTS.md is an injected work-rules file, not a content document routed through ContextState.
$actualFiles = @(Get-ChildItem -Path $docsRoot -Recurse -File -Filter '*.md' | Where-Object {
    $_.FullName -notmatch '[\\/](TestResults|obj|bin)[\\/]' -and
    $_.FullName -notmatch '[\\/]openspec[\\/]' -and
    $_.FullName -notmatch '[\\/]\.agents[\\/]skills[\\/]openspec-[^\\/]+[\\/]' -and
    $_.FullName -ne (Join-Path $docsRoot 'AGENTS.md')
})
$actualRelativePaths = @($actualFiles | ForEach-Object { $_.FullName.Substring($docsRoot.Length + 1).Replace('/', '\') })
$unexpected = @($actualRelativePaths | Where-Object { $_ -notin $routedPaths })
$missing = @($routedPaths | Where-Object { $_ -notin $actualRelativePaths })
if ($unexpected.Count -gt 0) { throw "Unrouted Markdown files found; add each to ContextState and SYSTEM_INVENTORY routing: $($unexpected -join ', ')" }
if ($missing.Count -gt 0) { throw "Routed Markdown files are missing: $($missing -join ', ')" }
$researchFiles = @($actualRelativePaths | Where-Object { $_ -match '^Research\\[^\\]+\\.+\.md$' })
$researchCategories = @($researchFiles | ForEach-Object { [regex]::Match($_, '^Research\\([^\\]+)\\').Groups[1].Value } | Group-Object)
foreach ($category in $researchCategories) {
    if ($category.Count -gt 1) { throw "Research category '$($category.Name)' has multiple Markdown sources; consolidate unless the user approved a deliberate split." }
}
${activeFiles} = @($actualFiles | Where-Object { $_.FullName -notlike '*\Archive\*' })
$totalBytes = ($actualFiles | Measure-Object Length -Sum).Sum
$defaultReadPaths = @($contextState.defaultRead | ForEach-Object { ([string]$_).Replace('/', '\') })
$defaultReadBytes = ($actualFiles | Where-Object { $_.FullName.Substring($docsRoot.Length + 1).Replace('/', '\') -in $defaultReadPaths } | Measure-Object Length -Sum).Sum
$harnessPowerShellFiles = @(Get-ChildItem -Path $stageRoot -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notlike '*\TestResults\*' })
foreach ($scriptFile in $harnessPowerShellFiles) {
    $scriptBytes = [IO.File]::ReadAllBytes($scriptFile.FullName)
    $hasUtf8Bom = $scriptBytes.Length -ge 3 -and $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
    $hasNonAscii = @($scriptBytes | Where-Object { $_ -ge 0x80 }).Count -gt 0
    if ($hasNonAscii -and -not $hasUtf8Bom) { throw "PowerShell harness source has non-ASCII text without a UTF-8 BOM: $($scriptFile.Name). Keep script literals ASCII or add a BOM." }
    $scriptText = [Text.Encoding]::UTF8.GetString($scriptBytes).TrimStart([char]0xFEFF)
    if ($scriptText -notmatch '(?m)^\s*#Requires\s+-Version\s+7\.0') { throw "Harness PowerShell script does not declare #Requires -Version 7.0: $($scriptFile.Name). The Harness runs on PowerShell 7 only." }
}

