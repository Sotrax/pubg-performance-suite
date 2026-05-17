#requires -Version 7
# =============================================================================
#  Test-NpiValueParser.ps1
# =============================================================================
#  Unit-Test fuer den NPI-Wert-Parser aus config\PUBGTweakRegistry.psm1
#  (Bug #1 - Hex/Dezimal-Parser-Fix, v0.32.0-beta).
#
#  Die zu testenden Funktionen werden per PowerShell-AST DIREKT aus dem Modul
#  extrahiert und ausgefuehrt - der Test prueft also exakt den ausgelieferten
#  Code, keine Kopie. Laeuft plattformunabhaengig (kein NPI/Windows noetig).
#
#  Aufruf:  pwsh -File tests/Test-NpiValueParser.ps1
#  Exit 0 = alle Faelle OK, Exit 1 = mindestens ein Fehlschlag.
# =============================================================================
$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot '..' 'config' 'PUBGTweakRegistry.psm1'
if (-not (Test-Path $module)) { throw "Modul nicht gefunden: $module" }

# Write-RegLog stubben - ConvertTo-UInt32Smart loggt Garbage-Faelle darueber.
function Write-RegLog { param($Message, $Level = 'INFO') }

# Die Funktionsdefinitionen per AST aus dem Modul holen.
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    [string](Resolve-Path $module), [ref]$null, [ref]$null)
foreach ($fn in 'ConvertTo-UInt32Smart', 'ConvertFrom-NpiHex') {
    $def = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq $fn
    }, $true)
    if (-not $def) { throw "Funktion '$fn' nicht im Modul gefunden" }
    . ([scriptblock]::Create($def.Extent.Text))
}

$fail = 0

# --- ConvertTo-UInt32Smart: format-unabhaengiges Parsen ----------------------
$smartTests = @(
    @{ In = '1';            Out = 1 }
    @{ In = '0x00000001';   Out = 1 }
    @{ In = '0X1';          Out = 1 }
    @{ In = '0xFFFFFFFF';   Out = 4294967295 }
    @{ In = '4294967295';   Out = 4294967295 }
    @{ In = '0xDEADBEEF';   Out = 3735928559 }
    @{ In = '0';            Out = 0 }
    @{ In = '';             Out = 0 }
    @{ In = $null;          Out = 0 }
    @{ In = '0xGARBAGE';    Out = 0 }
    @{ In = '  0x01  ';     Out = 1 }
)
Write-Host 'ConvertTo-UInt32Smart:'
foreach ($t in $smartTests) {
    $got = ConvertTo-UInt32Smart -Value $t.In -Default 0
    $ok  = ($got -eq $t.Out)
    if (-not $ok) { $fail++ }
    '  [{0}] In={1,-16} Expected={2,-12} Got={3}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }),
        ("'" + $t.In + "'"), $t.Out, $got
}

# --- ConvertFrom-NpiHex: strikt fuer hartkodierte Werte ----------------------
Write-Host 'ConvertFrom-NpiHex:'
$strict = @(
    @{ In = '0x10835000'; Out = 277041152;  Throws = $false }
    @{ In = '0X1';        Out = 1;          Throws = $false }
    @{ In = '0xED';       Out = 237;        Throws = $false }
    @{ In = '';           Out = $null;      Throws = $true  }
    @{ In = '0xGARBAGE';  Out = $null;      Throws = $true  }
)
foreach ($t in $strict) {
    $threw = $false; $got = $null
    try { $got = ConvertFrom-NpiHex $t.In } catch { $threw = $true }
    $ok = if ($t.Throws) { $threw } else { -not $threw -and $got -eq $t.Out }
    if (-not $ok) { $fail++ }
    '  [{0}] In={1,-14} Throws={2,-6} Got={3}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }),
        ("'" + $t.In + "'"), $t.Throws, $got
}

Write-Host ''
if ($fail -gt 0) {
    Write-Host "$fail Fehlschlag(e)." -ForegroundColor Red
    exit 1
}
Write-Host 'Alle Faelle OK.' -ForegroundColor Green
exit 0
