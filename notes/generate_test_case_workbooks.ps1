$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$storyPath = Join-Path $root 'requirements\user_stories.md'
$assignee = 'qa.tester@example.com'
$headers = @(
    'Test ID',
    'Summary',
    'Test Type',
    'Description',
    'Priority',
    'Assignee(email)',
    'Precondition',
    'Action',
    'Expected Results',
    'Status',
    'Defects'
)

function New-TestCase {
    param(
        [string]$Id,
        [string]$Summary,
        [string]$Type,
        [string]$Description,
        [string]$Priority,
        [string]$Precondition,
        [string]$Action,
        [string]$Expected
    )

    [pscustomobject]@{
        'Test ID' = $Id
        'Summary' = $Summary
        'Test Type' = $Type
        'Description' = $Description
        'Priority' = $Priority
        'Assignee(email)' = $assignee
        'Precondition' = $Precondition
        'Action' = $Action
        'Expected Results' = $Expected
        'Status' = 'Not Run'
        'Defects' = ''
    }
}

function Get-Category {
    param([string]$Section)

    switch -Regex ($Section) {
        'Accessibility' { 'ui'; break }
        'Performance|Reliability' { 'performance'; break }
        'Security|Privacy' { 'security'; break }
        default { 'functional'; break }
    }
}

function Get-Priority {
    param([string]$Section, [string]$Story, [string]$Type)

    if ($Type -eq 'Negative') { return 'High' }
    if ($Section -match 'Checkout|Ticket Selection|Security|Performance|Ticket Listing|Pricing') { return 'High' }
    if ($Section -match 'Accessibility|Account|Trust') { return 'Medium' }
    if ($Story -match 'payment|checkout|personal|session|availability|price|secure|error|blocked|prevent') { return 'High' }
    return 'Medium'
}

function Get-Topic {
    param([string]$Story)

    $text = $Story -replace '^-\s*As an? [^,]+,\s*I want to\s*', ''
    $text = $text -replace '\s+so that\s+.*$', ''
    $text = $text.Trim('. ')
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Validate user story behavior' }
    return ($text.Substring(0, 1).ToUpper() + $text.Substring(1))
}

function Get-PositiveAction {
    param([string]$Section, [string]$Topic)

    "Open the event page, perform the user action for '$Topic', and observe the resulting page behavior."
}

function Get-NegativeAction {
    param([string]$Section, [string]$Topic)

    switch -Regex ($Section) {
        'Search' { "Enter invalid, empty, special-character, and no-result values while testing '$Topic'." }
        'Ticket Selection|Checkout' { "Attempt '$Topic' with unavailable inventory, expired session, repeated clicks, or interrupted network." }
        'Pricing|Currency' { "Attempt '$Topic' with unsupported currency, stale price, changed price, or malformed pricing state." }
        'Language' { "Attempt '$Topic' with unsupported language, missing translation, long translated text, or RTL locale." }
        'Account' { "Attempt '$Topic' while logged out, with expired session, or after returning from authentication." }
        'Accessibility' { "Attempt '$Topic' using keyboard only, high zoom, screen reader inspection, and mobile touch constraints." }
        'Performance' { "Attempt '$Topic' under slow network, repeated actions, large inventory, and delayed API responses." }
        'Security' { "Attempt '$Topic' using tampered parameters, injection payloads, unauthorized access, or manipulated client state." }
        default { "Attempt '$Topic' with invalid state, missing data, stale page content, refresh, and browser back/forward navigation." }
    }
}

function Get-PositiveExpected {
    param([string]$Topic)

    "The page supports '$Topic' correctly, displays accurate information, and lets the user continue without unexpected errors."
}

function Get-NegativeExpected {
    param([string]$Section, [string]$Topic)

    switch -Regex ($Section) {
        'Security' { "The system rejects unsafe or unauthorized behavior for '$Topic' without exposing sensitive data." }
        'Performance' { "The page handles the degraded condition for '$Topic' gracefully without freezing, duplicate actions, or data corruption." }
        'Accessibility' { "The interface remains operable and understandable for '$Topic' without overlap, focus loss, or inaccessible controls." }
        default { "The system handles the invalid condition for '$Topic' safely with a clear message and no broken layout or incorrect purchase state." }
    }
}

function Write-Workbook {
    param(
        [string]$Path,
        [object[]]$Rows,
        [string]$SheetName
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    try {
        $workbook = $excel.Workbooks.Add()
        $sheet = $workbook.Worksheets.Item(1)
        $sheet.Name = $SheetName

        for ($column = 0; $column -lt $headers.Count; $column++) {
            $cell = $sheet.Cells.Item(1, $column + 1)
            $cell.Value2 = $headers[$column]
            $cell.Font.Bold = $true
            $cell.Interior.ColorIndex = 37
        }

        for ($row = 0; $row -lt $Rows.Count; $row++) {
            for ($column = 0; $column -lt $headers.Count; $column++) {
                $sheet.Cells.Item($row + 2, $column + 1).Value2 = [string]$Rows[$row].($headers[$column])
            }
        }

        $range = $sheet.UsedRange
        $range.WrapText = $true
        $range.VerticalAlignment = -4160
        $range.Borders.LineStyle = 1
        $widths = @(13, 38, 13, 52, 12, 24, 44, 54, 58, 12, 18)
        for ($i = 0; $i -lt $widths.Count; $i++) {
            $sheet.Columns.Item($i + 1).ColumnWidth = $widths[$i]
        }
        $sheet.ListObjects.Add(1, $range, $null, 1) | Out-Null
        $workbook.SaveAs($Path, 51)
        $workbook.Close($true)
    }
    finally {
        try {
            if ($workbook) {
                $workbook.Close($false)
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
            }
        }
        catch {}
        try {
            if ($sheet) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) | Out-Null
            }
        }
        catch {}
        try {
            $excel.Quit()
        }
        catch {}
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

$buckets = @{
    functional = New-Object System.Collections.ArrayList
    ui = New-Object System.Collections.ArrayList
    security = New-Object System.Collections.ArrayList
    performance = New-Object System.Collections.ArrayList
}
$counters = @{
    functional = 0
    ui = 0
    security = 0
    performance = 0
}
$prefixes = @{
    functional = 'FUNC'
    ui = 'UI'
    security = 'SEC'
    performance = 'PERF'
}

$section = ''
foreach ($line in Get-Content -LiteralPath $storyPath) {
    if ($line -match '^##\s+(.+)$') {
        $section = $Matches[1]
        continue
    }
    if ($line -notmatch '^-\s+As ') {
        continue
    }

    $category = Get-Category $section
    $topic = Get-Topic $line
    $precondition = "Business requirements and user story section '$section' are available. Test page is accessible."

    foreach ($type in @('Positive', 'Negative')) {
        $counters[$category]++
        $id = '{0}-{1:D3}' -f $prefixes[$category], $counters[$category]
        $summaryPrefix = if ($type -eq 'Positive') { 'Verify' } else { 'Validate failure handling for' }
        $action = if ($type -eq 'Positive') { Get-PositiveAction $section $topic } else { Get-NegativeAction $section $topic }
        $expected = if ($type -eq 'Positive') { Get-PositiveExpected $topic } else { Get-NegativeExpected $section $topic }
        $description = "$type test case derived from user story: $($line.TrimStart('-').Trim())"
        $priority = Get-Priority $section $line $type

        [void]$buckets[$category].Add((New-TestCase $id "$summaryPrefix $topic" $type $description $priority $precondition $action $expected))
    }
}

$manualCases = @(
    (New-TestCase 'FUNC-M001' 'Verify bug report format fields' 'Positive' 'Verify bug report template includes fields needed by developers and stakeholders.' 'Medium' 'Test report requirements are available.' 'Create a sample bug report using the agreed format.' 'Bug report includes title, severity, priority, environment, steps, expected result, actual result, evidence, and status.'),
    (New-TestCase 'FUNC-M002' 'Validate missing evidence in bug report' 'Negative' 'Verify incomplete bug reports are identified before sharing.' 'Medium' 'Bug report draft exists.' 'Review a bug report without screenshots or reproduction evidence.' 'Report is flagged as incomplete and evidence is requested.'),
    (New-TestCase 'UI-M001' 'Verify screenshot evidence is readable' 'Positive' 'Verify captured screenshots can support test evidence.' 'Low' 'Screenshots are saved in the screenshots folder.' 'Open desktop and mobile screenshots.' 'Screenshots are readable and show relevant UI states.'),
    (New-TestCase 'SEC-M001' 'Validate sensitive data is excluded from screenshots' 'Negative' 'Verify screenshots do not expose credentials, payment data, or personal data.' 'High' 'Screenshots are available.' 'Review all screenshots before report attachment.' 'No sensitive data is present in attached evidence.'),
    (New-TestCase 'PERF-M001' 'Verify full-page capture does not timeout' 'Positive' 'Verify full-page screenshot capture can complete for long ticket pages.' 'Low' 'Screenshot tooling is available.' 'Capture desktop and mobile full-page screenshots.' 'Capture completes and image files are valid.')
)

foreach ($case in $manualCases) {
    $category = switch -Regex ($case.'Test ID') {
        '^UI' { 'ui'; break }
        '^SEC' { 'security'; break }
        '^PERF' { 'performance'; break }
        default { 'functional'; break }
    }
    [void]$buckets[$category].Add($case)
}

Write-Workbook (Join-Path $root 'test-cases\functional\functional_test_cases.xlsx') $buckets.functional 'Functional Test Cases'
Write-Workbook (Join-Path $root 'test-cases\ui\ui_test_cases.xlsx') $buckets.ui 'UI Test Cases'
Write-Workbook (Join-Path $root 'test-cases\security\security_test_cases.xlsx') $buckets.security 'Security Test Cases'
Write-Workbook (Join-Path $root 'test-cases\performance\performance_test_cases.xlsx') $buckets.performance 'Performance Test Cases'

Get-ChildItem -Path (Join-Path $root 'test-cases') -Recurse -Filter '*.xlsx' |
    Sort-Object FullName |
    Select-Object FullName, Length, LastWriteTime
