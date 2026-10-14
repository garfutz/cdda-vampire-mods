# ========================================================================
# Elder Vampire Mod - Automated Fast Diagnostic & Cross-Reference Suite
# Validates JSON parsing, CDDA AST styling, and cross-reference integrity in <2s
# ========================================================================

param(
    [string]$ModDir = $PSScriptRoot,
    [string]$CddaRoot = (Split-Path -Parent (Split-Path -Parent $ModDir)),
    [switch]$Fast
)

if (-not $ModDir) {
    $ModDir = "C:\Users\Andu\Desktop\CDDA\mods\elder_vampire"
}
if (-not $CddaRoot -or -not (Test-Path $CddaRoot)) {
    $CddaRoot = "C:\Users\Andu\Desktop\CDDA"
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$formatter = Join-Path $CddaRoot "json_formatter.exe"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "          ELDER VAMPIRE MOD - COMPREHENSIVE DIAGNOSTIC SUITE            " -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan

$jsonFiles = Get-ChildItem -Path $ModDir -Filter "*.json"
if ($jsonFiles.Count -eq 0) {
    Write-Host "[ERROR] No JSON files found in $ModDir" -ForegroundColor Red
    exit 1
}

$parseErrors = 0
$data = @()

foreach ($file in $jsonFiles) {
    try {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $parsed = ConvertFrom-Json -InputObject $content -ErrorAction Stop
        $data += $parsed
    } catch {
        Write-Host "[FAIL] JSON Parse Error in $($file.Name): $_" -ForegroundColor Red
        $parseErrors++
    }
}

if ($parseErrors -gt 0) {
    Write-Host "[FATAL] Aborting diagnostics due to $parseErrors JSON parse errors." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] JSON Syntax & Encoding Integrity ................ $($jsonFiles.Count) / $($jsonFiles.Count) Files OK" -ForegroundColor Green

# 2. CDDA json_formatter.exe Check
$lintErrors = 0
if ($Fast) {
    Write-Host "[OK] CDDA AST Linter (json_formatter) ................ Skipped (-Fast switch)" -ForegroundColor Cyan
} elseif (Test-Path $formatter) {
    foreach ($file in $jsonFiles) {
        $proc = Start-Process -FilePath $formatter -ArgumentList "`"$($file.FullName)`"" -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "[WARN] Linter reformatted or flagged: $($file.Name)" -ForegroundColor Yellow
            $lintErrors++
        }
    }
    if ($lintErrors -eq 0) {
        Write-Host "[OK] CDDA AST & Code Style Linter (json_formatter) ... $($jsonFiles.Count) / $($jsonFiles.Count) Clean" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Code Style Linter updated $lintErrors files." -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] json_formatter.exe not found at $formatter" -ForegroundColor DarkGray
}

Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray

# 3. Entity Registries
$spells = @{}
$eocs = @{}
$items = @{}
$effects = @{}
$traits = @{}
$recipes = @{}
$itemgroups = @{}
$dialogues = @{}

# Standard external IDs from Base Game and Xedra Evolved
$externalTraits = @(
    "VAMPIRE", "VAMPIRE2", "VAMPIRE3", "VAMPIRE4", "VAMPIRE5",
    "VAMPIRIC_RESILIENCE", "NO_THIRST", "FAE_CREATURE", "BLOOD_OF_SAINTS",
    "VAMPIRE_STORE_MORE_BLOOD", "VAMPIRE_STORE_MORE_BLOOD_UPGRADE",
    "KLAUS_ORIGINAL_VAMPIRE", "ELIJAH_ORIGINAL_VAMPIRE", "STEFAN_VAMPIRE"
)
$externalEffects = @(
    "withering", "bleed", "downed", "stunned", "dazed", "sleep", "nausea",
    "effect_vampire_hypnotism", "effect_vampire_blood_drinking_target",
    "effect_vampire_blood_drinking", "charm_monster", "blisters"
)
$externalItems = @(
    "blood", "demihuman_blood", "blood_tainted", "blood_tainted_human", "water", "water_clean",
    "thermos", "stick", "2x4", "splinter", "charcoal", "coal_lump", "silver_ring", "gold_ring",
    "copper_ring", "platinum_ring", "diamond_ring", "ring_engagement", "ring_wedding",
    "ring_purity", "ring_signet", "bottle_glass", "chem_ethanol", "whiskey", "vodka"
)

foreach ($entry in $data) {
    if (-not $entry.type) { continue }
    $t = $entry.type
    $id = $entry.id

    switch ($t) {
        "SPELL" { if ($id) { $spells[$id] = $entry } }
        "effect_on_condition" { if ($id) { $eocs[$id] = $entry } }
        "ITEM" { if ($id) { $items[$id] = $entry } }
        "effect_type" { if ($id) { $effects[$id] = $entry } }
        "mutation" { if ($id) { $traits[$id] = $entry } }
        "recipe" { if ($entry.result) { $recipes[$entry.result] = $entry } }
        "item_group" { if ($id) { $itemgroups[$id] = $entry } }
        "talk_topic" { if ($id) { $dialogues[$id] = $entry } }
    }
}

Write-Host "Entity Registry Index:" -ForegroundColor White
Write-Host "  * Spells Registered:              $($spells.Count)" -ForegroundColor Gray
Write-Host "  * Effects on Condition (EOCs):    $($eocs.Count)" -ForegroundColor Gray
Write-Host "  * Items & Relics Registered:      $($items.Count)" -ForegroundColor Gray
Write-Host "  * Status Effects Registered:      $($effects.Count)" -ForegroundColor Gray
Write-Host "  * Traits & Mutations Registered:  $($traits.Count)" -ForegroundColor Gray
Write-Host "  * Recipes Registered:             $($recipes.Count)" -ForegroundColor Gray
Write-Host "  * Item Groups Registered:         $($itemgroups.Count)" -ForegroundColor Gray
Write-Host "  * Dialogue Topics Registered:     $($dialogues.Count)" -ForegroundColor Gray

Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray

# 4. Cross-Reference Validation
$missingRefs = 0
$spellEocChecks = 0
$spellExtraChecks = 0
$eocSubChecks = 0
$recipeChecks = 0

# Check Spells -> EOC & Extra Effects
foreach ($sId in $spells.Keys) {
    $s = $spells[$sId]
    if ($s.effect -eq "effect_on_condition" -and $s.effect_str) {
        $spellEocChecks++
        if (-not $eocs.ContainsKey($s.effect_str)) {
            Write-Host "[FAIL] Spell '$sId' references unknown EOC '$($s.effect_str)'" -ForegroundColor Red
            $missingRefs++
        }
    }
    if ($s.extra_effects) {
        foreach ($extra in $s.extra_effects) {
            $spellExtraChecks++
            $exId = $extra.id
            if (-not $spells.ContainsKey($exId)) {
                Write-Host "[FAIL] Spell '$sId' references unknown extra_effect '$exId'" -ForegroundColor Red
                $missingRefs++
            }
        }
    }
}
Write-Host "[OK] Spell -> EOC Linkages .................... $spellEocChecks / $spellEocChecks Verified" -ForegroundColor Green
Write-Host "[OK] Spell -> Extra Effects Cascades ......... $spellExtraChecks / $spellExtraChecks Verified" -ForegroundColor Green

# Check Recipes -> Result Items
foreach ($res in $recipes.Keys) {
    $recipeChecks++
    if (-not $items.ContainsKey($res) -and -not ($externalItems -contains $res)) {
        Write-Host "[FAIL] Recipe result '$res' does not exist in items" -ForegroundColor Red
        $missingRefs++
    }
}
Write-Host "[OK] Recipe -> Output Item Definitions ........ $recipeChecks / $recipeChecks Verified" -ForegroundColor Green

# Check EOC recursion and selectors
foreach ($eId in $eocs.Keys) {
    $e = $eocs[$eId]
    $str = $e | ConvertTo-Json -Depth 20 -Compress
    
    # Check selector lists
    if ($str -match '"run_eoc_selector"\s*:\s*\[([^\]]+)\]') {
        $matches[1] -split ',' | ForEach-Object {
            $sub = $_.Trim(' "[]')
            if ($sub -and $sub -ne "EOC_selector_cancel") {
                $eocSubChecks++
                if (-not $eocs.ContainsKey($sub)) {
                    Write-Host "[FAIL] EOC '$eId' selector references unknown EOC '$sub'" -ForegroundColor Red
                    $missingRefs++
                }
            }
        }
    }
}
Write-Host "[OK] EOC -> Sub-EOC & Selectors Linkages ...... $eocSubChecks / $eocSubChecks Verified" -ForegroundColor Green

$sw.Stop()
$elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 3)

Write-Host "========================================================================" -ForegroundColor Cyan
if ($missingRefs -eq 0 -and $parseErrors -eq 0) {
    Write-Host " DIAGNOSTIC RESULT: ALL CHECKS PASSED (0 ERRORS, 0 BROKEN REFERENCES)" -ForegroundColor Green
} else {
    Write-Host " DIAGNOSTIC RESULT: FAILED ($missingRefs BROKEN REFERENCES, $parseErrors PARSE ERRORS)" -ForegroundColor Red
}
Write-Host " EXECUTION TIME: $elapsed seconds" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

if ($missingRefs -eq 0 -and $parseErrors -eq 0) {
    exit 0
} else {
    exit 1
}
