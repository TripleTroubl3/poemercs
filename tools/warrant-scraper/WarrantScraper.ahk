#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
SetTitleMatchMode 2
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"

; =====================================================================
;  PoE Mercenary Warrant Scraper  (AutoHotkey v2)
;
;  Two modes, matching the two ideas from the poemercs project chat:
;
;   Mode 1 (Shift+F8) - "Snip": triggers Windows Snipping Tool on the
;     mercenary skill panel, OCRs the clip, and copies a scrape-format
;     text listing the SKILL NAMES it found (no supports - icons alone
;     don't carry readable text, so this mode is honest about that limit).
;     Paste the result into the poemercs site's warrant box, then add
;     supports by hand with the icon chips - still saves you hunting down
;     each skill manually.
;
;   Mode 2 (F8) - "Hover-scrape": the more complete one. Screenshots the
;     whole panel once to find each skill row (Windows OCR gives per-line
;     text AND its on-screen position), then for every support-icon slot
;     in that row, moves the mouse there to trigger the GAME'S OWN
;     tooltip (which renders the support's name as real text) and OCRs
;     just that tooltip. This sidesteps trying to visually classify tiny
;     icons - text is what OCR is actually good at - at the cost of a
;     few hundred ms per icon while it hovers each one in turn.
;
;  Output either way is copied to the clipboard as this project's
;  POE-MERC-SCRAPE-v1 format, which the poemercs site auto-detects
;  (same paste box as a real Ctrl+C warrant copy) and fuzzy-matches
;  against known skill/support names - so OCR typos and extra tooltip
;  text around the name are tolerated, not fatal.
;
;  ---------------------------------------------------------------
;  ONE-TIME SETUP
;   1. Install AutoHotkey v2 (https://www.autohotkey.com/).
;   2. In PoE, open the mercenary skill panel you want to scrape.
;      Windowed or Windowed Fullscreen (exclusive fullscreen can block
;      the mouse/keys AHK needs to move and read).
;   3. Double-click this file to run it (it lives in the tray).
;   4. First run opens the calibration wizard automatically. It's also
;      in the tray menu any time ("Setup wizard...") if your UI moves,
;      your resolution changes, or PoE's UI scale slider changes.
;
;  CALIBRATION
;   One key does it all: hover where the wizard asks, press F7 (only
;   works while the wizard window is open). It asks for:
;     1. Top-left corner of the FIRST support icon, Row 1
;     2. Bottom-right corner of that SAME icon (gives icon size)
;     3. Top-left corner of the SECOND support icon, Row 1 (gives spacing)
;     4. Top-left corner of the FIRST support icon, Row 2 (gives row spacing)
;     5. Top-left corner of the whole panel (just above the first skill)
;     6. Bottom-right corner of the whole panel (below the last visible row)
;
;  RUN
;   F8       = Mode 2, full hover-scrape (skills + supports)
;   Shift+F8 = Mode 1, snip + skill names only
;   F10      = Abort at any time
;   Hotkeys are fixed in this version - edit the CONFIG section below to
;   change them (search for "HOTKEY BINDINGS" near the bottom).
;
;  This tool only moves the mouse and reads the screen - it never sends
;  game input beyond hovering, and never touches game memory or files.
;  That said, I'm not able to make a definitive call on any game's
;  automation policy - use your own judgment.
;
; =====================================================================

; ---------------- CONFIG ----------------
PoeWinTitle := "Path of Exile"

MaxSupportsPerRow := 5      ; game max is 5 (SupportCount enum tops out at 3-5)
TooltipHoverDelay := 260    ; ms to wait for a tooltip to render after moving the mouse
TooltipCaptureHalfW := 320  ; tooltip capture box half-width around the cursor
TooltipCaptureHalfH := 220  ; tooltip capture box half-height around the cursor
MinOcrLineLen := 2          ; OCR results shorter than this are treated as "empty slot"
OcrTimeout := 30            ; seconds before a stuck OCR call is abandoned
PreferredOcrLanguage := ""  ; e.g. "ko-KR" - leave blank to auto-pick an English/profile recognizer

ScriptVersion := "2026-08-21"

; ---------------- PERSISTED CALIBRATION ----------------
IniFile := A_ScriptDir "\WarrantScraper.ini"

Slot1TLx := IniRead(IniFile, "cal", "Slot1TLx", "0") + 0
Slot1TLy := IniRead(IniFile, "cal", "Slot1TLy", "0") + 0
Slot1BRx := IniRead(IniFile, "cal", "Slot1BRx", "0") + 0
Slot1BRy := IniRead(IniFile, "cal", "Slot1BRy", "0") + 0
Slot2TLx := IniRead(IniFile, "cal", "Slot2TLx", "0") + 0
Row2TLy  := IniRead(IniFile, "cal", "Row2TLy", "0") + 0
PanelTLx := IniRead(IniFile, "cal", "PanelTLx", "0") + 0
PanelTLy := IniRead(IniFile, "cal", "PanelTLy", "0") + 0
PanelBRx := IniRead(IniFile, "cal", "PanelBRx", "0") + 0
PanelBRy := IniRead(IniFile, "cal", "PanelBRy", "0") + 0

IsCalibrated() {
    global Slot1TLx, Slot1BRx, Slot2TLx, Row2TLy, PanelTLx, PanelBRx
    return Slot1TLx && Slot1BRx && Slot2TLx && Row2TLy && PanelTLx && PanelBRx
}

; derived grid values, recomputed whenever calibration changes
IconW := 0
IconH := 0
XPitch := 0
YPitch := 0
RecomputeGrid() {
    global Slot1TLx, Slot1TLy, Slot1BRx, Slot1BRy, Slot2TLx, Row2TLy
    global IconW, IconH, XPitch, YPitch
    IconW := Abs(Slot1BRx - Slot1TLx)
    IconH := Abs(Slot1BRy - Slot1TLy)
    XPitch := Abs(Slot2TLx - Slot1TLx)
    YPitch := Abs(Row2TLy - Slot1TLy)
}
if IsCalibrated()
    RecomputeGrid()

; ---------------- LONG PATH FIX ----------------
; %TEMP% can resolve to an 8.3 short path (C:\Users\HARDPC~1\...) on some
; systems, which WinRT's path handling can choke on. Expand it once,
; up front - same fix used in the project owner's other PoE OCR tool.
LongPath(path) {
    buf := Buffer(1040, 0)
    len := DllCall("GetLongPathNameW", "Str", path, "Ptr", buf.Ptr, "UInt", 520, "UInt")
    return (len > 0 && len <= 520) ? StrGet(buf, "UTF-16") : path
}
TempDir := LongPath(A_Temp)
ScriptPid := ProcessExist()
OcrHelper := TempDir "\merc-warrant-ocr-" ScriptPid ".ps1"
OcrSession := TempDir "\merc-warrant-ocr-" ScriptPid
OcrPid := 0
Running := false

; ---------------- ACTIVITY LOG ----------------
LogFile := A_ScriptDir "\WarrantScraper.log"
Log(msg) {
    global LogFile
    try {
        size := 0
        try size := FileGetSize(LogFile)
        if (size > 262144) {
            keep := SubStr(FileRead(LogFile, "UTF-8"), -131072)
            FileDelete LogFile
            FileAppend keep, LogFile, "UTF-8"
        }
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", LogFile, "UTF-8"
    }
}
Log("started v" ScriptVersion " | AHK " A_AhkVersion " | Windows " A_OSVersion
    . " | screen " A_ScreenWidth "x" A_ScreenHeight " @ " A_ScreenDPI " DPI")

; =====================================================================
;  POWERSHELL OCR HELPER
;  Adapted from a proven pattern in another PoE OCR
;  tooling: the expensive part (loading the Windows OCR engine) happens
;  ONCE in a long-running "server" process, then each capture is a quick
;  file-signalled round trip instead of paying PowerShell startup +
;  engine load cost per icon (which would make Mode 2's 15-20+ icon
;  hovers painfully slow).
; =====================================================================
OcrPowerShell() {
    return "
(
param(
    [string]$Session,
    [string]$PreferredLanguage = '',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-LongPath([string]$path) {
    Add-Type -Namespace Native -Name Path -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern uint GetLongPathName(string shortPath, System.Text.StringBuilder buffer, uint bufferLength);
'@ -ErrorAction SilentlyContinue
    $buffer = New-Object System.Text.StringBuilder 1040
    $len = [Native.Path]::GetLongPathName($path, $buffer, 1040)
    if ($len -gt 0) { return $buffer.ToString(0, $len) }
    return $path
}
$env:TEMP = Get-LongPath $env:TEMP

Add-Type -AssemblyName System.Drawing

[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]

function Await-Result {
    param([Parameter(Mandatory = $true)]$AsyncOperation, [Parameter(Mandatory = $true)][Type]$ResultType)
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($AsyncOperation))
    $task.Wait()
    return $task.Result
}

function New-OcrEngine {
    param([string]$PreferredLanguage = '')
    $available = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages)

    if (-not [string]::IsNullOrWhiteSpace($PreferredLanguage)) {
        $tag = $PreferredLanguage.Trim()
        $primary = ($tag -split '-', 2)[0]
        foreach ($language in @($available | Where-Object {
            $_.LanguageTag -ieq $tag -or (($_.LanguageTag -split '-', 2)[0]) -ieq $primary
        })) {
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
            if ($null -ne $engine) { return $engine }
        }
        throw "Windows OCR language '$tag' is not installed. Settings > Time & Language > Language & region > add the language > install its 'Optical character recognition' feature."
    }

    foreach ($language in @($available | Where-Object { $_.LanguageTag -eq 'en-US' -or $_.LanguageTag -like 'en-*' } | Sort-Object { if ($_.LanguageTag -eq 'en-US') { 0 } else { 1 } })) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
        if ($null -ne $engine) { return $engine }
    }

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -ne $engine) { return $engine }

    foreach ($language in $available) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
        if ($null -ne $engine) { return $engine }
    }

    throw 'Windows OCR has no installed language. Settings > Time & Language > Language & region > add English (or your PoE client language) > install its "Optical character recognition" feature.'
}

function Invoke-OcrFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Engine)
    $file = Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
    $stream = Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-Result ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            $result = Await-Result ($Engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            return $result.Text
        } finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
        }
    } finally {
        $stream.Dispose()
    }
}

# Returns each recognized LINE with its text and screen-relative bounding
# box, not just concatenated text - Mode 2 needs each skill row's Y
# position to know where to hover for that row's support icons.
function Get-OcrLineRects {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Engine)
    $file = Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
    $stream = Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-Result ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            $result = Await-Result ($Engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            $lines = @()
            foreach ($line in $result.Lines) {
                $minX = [double]::MaxValue; $minY = [double]::MaxValue
                $maxX = 0.0; $maxY = 0.0
                foreach ($word in $line.Words) {
                    $r = $word.BoundingRect
                    if ($r.X -lt $minX) { $minX = $r.X }
                    if ($r.Y -lt $minY) { $minY = $r.Y }
                    if (($r.X + $r.Width) -gt $maxX) { $maxX = $r.X + $r.Width }
                    if (($r.Y + $r.Height) -gt $maxY) { $maxY = $r.Y + $r.Height }
                }
                if ($minX -eq [double]::MaxValue) { continue }
                $lines += [pscustomobject]@{ Text = $line.Text; X = $minX; Y = $minY; R = $maxX; B = $maxY }
            }
            return $lines
        } finally {
            if ($null -ne $bitmap) { $bitmap.Dispose() }
        }
    } finally {
        $stream.Dispose()
    }
}

function Save-ScreenRegion {
    param([int]$Left, [int]$Top, [int]$Width, [int]$Height, [string]$Path)
    if ($Width -le 0 -or $Height -le 0) { throw 'Invalid capture region.' }
    $image = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($Left, $Top, 0, 0, $image.Size)
        # Small tooltip/UI text upscales noticeably better for OCR at 2x -
        # cheap insurance against thin PoE UI fonts at typical desktop DPI.
        $scaled = New-Object System.Drawing.Bitmap $image, ($Width * 2), ($Height * 2)
        $scaled.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $scaled.Dispose()
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    return 2  # scale factor used, so callers can map OCR rects back to screen coords
}

$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Atomic {
    param([string]$Path, [string]$Text)
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, $utf8)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Do-CaptureText {
    param([int]$Left, [int]$Top, [int]$Width, [int]$Height, $Engine)
    $png = Join-Path $env:TEMP "merc-warrant-$PID-$([Guid]::NewGuid().ToString('N')).png"
    try {
        Save-ScreenRegion -Left $Left -Top $Top -Width $Width -Height $Height -Path $png | Out-Null
        return (Invoke-OcrFile $png $Engine)
    } finally {
        Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue
    }
}

function Do-CaptureClipboardImage {
    param($Engine)
    Add-Type -AssemblyName System.Windows.Forms
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $img) { return 'OCR ERROR: no image found on clipboard - did the snip finish?' }
    $png = Join-Path $env:TEMP "merc-warrant-clip-$PID.png"
    try {
        $img.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        return (Invoke-OcrFile $png $Engine)
    } finally {
        $img.Dispose()
        Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue
    }
}

function Do-CaptureLines {
    param([int]$Left, [int]$Top, [int]$Width, [int]$Height, $Engine)
    $png = Join-Path $env:TEMP "merc-warrant-panel-$PID.png"
    try {
        $scale = Save-ScreenRegion -Left $Left -Top $Top -Width $Width -Height $Height -Path $png
        $lines = Get-OcrLineRects -Path $png -Engine $Engine
        # map back from the 2x-upscaled image to real screen coordinates
        $mapped = @($lines | ForEach-Object {
            [pscustomobject]@{
                Text = $_.Text
                X = ($_.X / $scale) + $Left; Y = ($_.Y / $scale) + $Top
                R = ($_.R / $scale) + $Left; B = ($_.B / $scale) + $Top
            }
        })
        if ($mapped.Count -eq 0) { return '[]' }
        $json = ConvertTo-Json -InputObject $mapped -Compress
        if ($mapped.Count -eq 1) { return "[$json]" }
        return $json
    } finally {
        Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue
    }
}

$engine = New-OcrEngine -PreferredLanguage $PreferredLanguage
$engineTag = ''
try { $engineTag = $engine.RecognizerLanguage.LanguageTag } catch { }
Write-Atomic $OutputPath ('READY|' + $engineTag)

$cmdFile = "$Session.cmd"
while ($true) {
    try {
        if (-not (Test-Path -LiteralPath $cmdFile)) {
            Start-Sleep -Milliseconds 40
            continue
        }
        $line = ([System.IO.File]::ReadAllText($cmdFile, $utf8)).Trim()
        Remove-Item -LiteralPath $cmdFile -Force -ErrorAction SilentlyContinue
        if ($line -eq 'quit') { break }
        $parts = $line.Split('|')
        if ($parts.Count -lt 6) { continue }
        $kind = $parts[0]; $reqId = $parts[1]
        $left = [int]$parts[2]; $top = [int]$parts[3]; $width = [int]$parts[4]; $height = [int]$parts[5]
        try {
            if ($kind -eq 'lines') {
                $result = Do-CaptureLines -Left $left -Top $top -Width $width -Height $height -Engine $engine
            } elseif ($kind -eq 'clipimg') {
                $result = Do-CaptureClipboardImage -Engine $engine
            } else {
                $result = Do-CaptureText -Left $left -Top $top -Width $width -Height $height -Engine $engine
            }
        } catch {
            $result = 'OCR ERROR: ' + $_.Exception.Message
        }
        Write-Atomic "$Session-res-$reqId.txt" $result
    } catch {
        Start-Sleep -Milliseconds 60
    }
}
)"
}

EnsureOcrHelper() {
    global OcrHelper
    try FileDelete OcrHelper
    FileAppend OcrPowerShell(), OcrHelper, "UTF-8"
}

StartOcrServer() {
    global OcrHelper, OcrSession, OcrPid, PreferredOcrLanguage
    if (OcrPid && ProcessExist(OcrPid))
        return
    try FileDelete OcrSession ".ready"
    try FileDelete OcrSession ".cmd"
    EnsureOcrHelper()
    quote := Chr(34)
    languageArg := PreferredOcrLanguage != "" ? " -PreferredLanguage " quote PreferredOcrLanguage quote : ""
    Log("OCR server starting")
    command := "powershell.exe -NoProfile -ExecutionPolicy Bypass -File "
        . quote OcrHelper quote " -Session " quote OcrSession quote
        . languageArg . " -OutputPath " quote OcrSession ".ready" quote
    Run command, , "Hide", &OcrPid
}

WaitOcrReady(timeoutMs) {
    global OcrSession, OcrPid
    started := A_TickCount
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if FileExist(OcrSession ".ready") {
            content := Trim(FileRead(OcrSession ".ready", "UTF-8"), " `t`r`n")
            if (SubStr(content, 1, 5) = "READY") {
                lang := SubStr(content, 7)
                Log("OCR ready in " (A_TickCount - started) "ms | engine " (lang = "" ? "unknown" : lang))
                return "READY"
            }
            return content
        }
        if !ProcessExist(OcrPid)
            return "OCR HELPER ERROR: the helper exited before becoming ready. Check WarrantScraper.log."
        Sleep 50
    }
    return "OCR HELPER ERROR: timed out waiting for Windows OCR to initialize."
}

OcrSendCommand(text) {
    global OcrSession
    try FileDelete OcrSession ".cmd.tmp"
    FileAppend text, OcrSession ".cmd.tmp", "UTF-8"
    try FileMove OcrSession ".cmd.tmp", OcrSession ".cmd", 1
}

; kind: "text" (plain OCR text) or "lines" (JSON array of {Text,X,Y,R,B})
OcrCapture(kind, reqId, left, top, width, height) {
    global OcrSession, OcrPid, OcrTimeout
    resFile := OcrSession "-res-" reqId ".txt"
    try FileDelete resFile
    OcrSendCommand(kind "|" reqId "|" left "|" top "|" width "|" height)
    deadline := A_TickCount + OcrTimeout * 1000
    while (A_TickCount < deadline) {
        if FileExist(resFile) {
            result := FileRead(resFile, "UTF-8")
            try FileDelete resFile
            return result
        }
        if !ProcessExist(OcrPid) {
            Log("OCR helper died mid-capture")
            return ""
        }
        Sleep 30
    }
    Log("OCR capture timed out (kind=" kind ")")
    return ""
}

StopOcrServer() {
    global OcrSession, OcrPid
    if (OcrPid && ProcessExist(OcrPid)) {
        OcrSendCommand("quit")
        deadline := A_TickCount + 2000
        while (ProcessExist(OcrPid) && A_TickCount < deadline)
            Sleep 50
        if ProcessExist(OcrPid)
            try ProcessClose OcrPid
    }
    OcrPid := 0
    try FileDelete OcrSession ".cmd"
    try FileDelete OcrSession ".ready"
}

CleanupOcr(*) {
    global OcrHelper, OcrSession, OcrPid
    if OcrPid && ProcessExist(OcrPid)
        try ProcessClose OcrPid
    try FileDelete OcrHelper
    try FileDelete OcrSession ".cmd"
    try FileDelete OcrSession ".cmd.tmp"
    try FileDelete OcrSession ".ready"
}
OnExit CleanupOcr

; =====================================================================
;  CALIBRATION WIZARD
;  One key (F7) records the current mouse position for whichever step is
;  active, then advances. F7 is only bound while the wizard window exists.
; =====================================================================
WizardGui := 0
WizardStepIndex := 1
WizardBodyCtl := 0
WizardProgressCtl := 0
WizardPoints := Map()  ; step key -> {x, y}

WizardSteps() {
    return [
        Map("key", "Slot1TL", "title", "Step 1 / 6", "body",
            "Hover the TOP-LEFT corner of the FIRST support icon in Row 1`n"
            . "(the leftmost small icon next to the first skill row).`n`nThen press F7."),
        Map("key", "Slot1BR", "title", "Step 2 / 6", "body",
            "Hover the BOTTOM-RIGHT corner of that SAME icon.`n`nThen press F7."),
        Map("key", "Slot2TL", "title", "Step 3 / 6", "body",
            "Hover the TOP-LEFT corner of the SECOND support icon in Row 1`n"
            . "(immediately to the right of the first).`n`nThen press F7."),
        Map("key", "Row2TL", "title", "Step 4 / 6", "body",
            "Hover the TOP-LEFT corner of the FIRST support icon in Row 2`n"
            . "(the next skill row down). If this mercenary only has one row,`n"
            . "hover anywhere one icon-height below Row 1's first icon instead.`n`nThen press F7."),
        Map("key", "PanelTL", "title", "Step 5 / 6", "body",
            "Hover the TOP-LEFT corner of the WHOLE skill panel`n"
            . "(just above and left of the first skill icon/name).`n`nThen press F7."),
        Map("key", "PanelBR", "title", "Step 6 / 6", "body",
            "Hover the BOTTOM-RIGHT corner of the WHOLE skill panel`n"
            . "(below and right of the last visible row).`n`nThen press F7."),
    ]
}

WizardActive() {
    global WizardGui
    return IsObject(WizardGui) && WinExist("ahk_id " WizardGui.Hwnd)
}

ShowWizard(*) {
    global WizardGui, WizardStepIndex, WizardBodyCtl, WizardProgressCtl, WizardPoints
    if WizardActive() {
        WizardGui.Show()
        return
    }
    WizardStepIndex := 1
    WizardPoints := Map()

    WizardGui := Gui("+AlwaysOnTop", "Warrant Scraper - Setup Wizard")
    WizardGui.SetFont("s10", "Segoe UI")
    WizardGui.AddText("w420", "Move your mouse to the described position, keep it still, then press F7.")
    WizardProgressCtl := WizardGui.AddText("w420 cGray", "")
    WizardBodyCtl := WizardGui.AddText("w420 h100", "")
    cancelBtn := WizardGui.AddButton("w100", "Cancel")
    cancelBtn.OnEvent("Click", (*) => WizardGui.Destroy())
    WizardGui.OnEvent("Close", (*) => WizardGui.Destroy())
    WizardGui.OnEvent("Escape", (*) => WizardGui.Destroy())

    RenderWizardStep()
    WizardGui.Show()
}

RenderWizardStep() {
    global WizardStepIndex, WizardBodyCtl, WizardProgressCtl
    steps := WizardSteps()
    step := steps[WizardStepIndex]
    WizardProgressCtl.Text := step["title"]
    WizardBodyCtl.Text := step["body"]
}

WizardSetPressed(*) {
    global WizardStepIndex, WizardPoints, WizardGui
    if !WizardActive()
        return
    steps := WizardSteps()
    step := steps[WizardStepIndex]
    MouseGetPos &mx, &my
    WizardPoints[step["key"]] := { x: mx, y: my }
    Log("wizard: " step["key"] " = " mx "," my)

    if (WizardStepIndex >= steps.Length) {
        SaveWizardResults()
        WizardGui.Destroy()
        MsgBox "Calibration saved. F8 (hover-scrape) and Shift+F8 (snip) are ready to use.", "Warrant Scraper", "Iconi"
        return
    }
    WizardStepIndex += 1
    RenderWizardStep()
}

SaveWizardResults() {
    global WizardPoints, IniFile
    global Slot1TLx, Slot1TLy, Slot1BRx, Slot1BRy, Slot2TLx, Row2TLy, PanelTLx, PanelTLy, PanelBRx, PanelBRy

    Slot1TLx := WizardPoints["Slot1TL"].x, Slot1TLy := WizardPoints["Slot1TL"].y
    Slot1BRx := WizardPoints["Slot1BR"].x, Slot1BRy := WizardPoints["Slot1BR"].y
    Slot2TLx := WizardPoints["Slot2TL"].x
    Row2TLy := WizardPoints["Row2TL"].y
    PanelTLx := WizardPoints["PanelTL"].x, PanelTLy := WizardPoints["PanelTL"].y
    PanelBRx := WizardPoints["PanelBR"].x, PanelBRy := WizardPoints["PanelBR"].y

    IniWrite Slot1TLx, IniFile, "cal", "Slot1TLx"
    IniWrite Slot1TLy, IniFile, "cal", "Slot1TLy"
    IniWrite Slot1BRx, IniFile, "cal", "Slot1BRx"
    IniWrite Slot1BRy, IniFile, "cal", "Slot1BRy"
    IniWrite Slot2TLx, IniFile, "cal", "Slot2TLx"
    IniWrite Row2TLy, IniFile, "cal", "Row2TLy"
    IniWrite PanelTLx, IniFile, "cal", "PanelTLx"
    IniWrite PanelTLy, IniFile, "cal", "PanelTLy"
    IniWrite PanelBRx, IniFile, "cal", "PanelBRx"
    IniWrite PanelBRy, IniFile, "cal", "PanelBRy"

    RecomputeGrid()
    Log("calibration saved | icon " IconW "x" IconH " | pitch " XPitch "," YPitch
        . " | panel " PanelTLx "," PanelTLy " -> " PanelBRx "," PanelBRy)
}

; =====================================================================
;  SMALL HELPERS
; =====================================================================

; Parses the constrained JSON this tool's own PowerShell helper produces
; (a flat array of {"Text":"...","X":n,"Y":n,"R":n,"B":n} objects) - not a
; general-purpose JSON parser, deliberately, since matching only the exact
; shape we control ourselves is far less likely for me to get subtly wrong
; than hand-rolling full JSON parsing untested.
ParseLineRects(json) {
    result := []
    pos := 1
    while (pos := RegExMatch(json, 'O)"Text":"(?<text>(?:[^"\\]|\\.)*)","X":(?<x>-?[\d.]+),"Y":(?<y>-?[\d.]+),"R":(?<r>-?[\d.]+),"B":(?<b>-?[\d.]+)', &m, pos)) {
        text := StrReplace(StrReplace(m["text"], '\"', '"'), "\\", "\")
        result.Push({ text: text, x: m["x"] + 0, y: m["y"] + 0, r: m["r"] + 0, b: m["b"] + 0 })
        pos += m.Len
    }
    return result
}

SortByY(arr) {
    n := arr.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            if (arr[j].y > arr[j + 1].y) {
                tmp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := tmp
            }
        }
    }
    return arr
}

CollapseWhitespace(s) {
    s := Trim(StrReplace(StrReplace(s, "`r", " "), "`n", " "))
    while InStr(s, "  ")
        s := StrReplace(s, "  ", " ")
    return s
}

ShowResultPreview(text, note) {
    previewGui := Gui("+AlwaysOnTop", "Warrant Scraper - Result (already on clipboard)")
    previewGui.SetFont("s10", "Segoe UI")
    previewGui.AddText("w520", note)
    editCtl := previewGui.AddEdit("w520 h300 +Multi +WantReturn", text)
    copyBtn := previewGui.AddButton("w150", "Re-copy to Clipboard")
    copyBtn.OnEvent("Click", (*) => A_Clipboard := editCtl.Text)
    closeBtn := previewGui.AddButton("w100 x+10", "Close")
    closeBtn.OnEvent("Click", (*) => previewGui.Destroy())
    previewGui.OnEvent("Close", (*) => previewGui.Destroy())
    previewGui.Show()
}

; =====================================================================
;  MODE 1 - SNIP + SKILL NAMES ONLY
; =====================================================================
ModeSnip(*) {
    global Running, MinOcrLineLen
    if Running {
        FlashToolTip("Already running - press F10 to abort.")
        return
    }
    Running := true
    Log("Mode 1 (snip) starting")
    try {
        StartOcrServer()
        readyState := WaitOcrReady(15000)
        if (readyState != "READY") {
            MsgBox readyState, "Warrant Scraper - OCR error", "Iconx"
            return
        }

        ToolTip "Opening Windows Snip & Sketch - select the skill panel area..."
        startSeq := DllCall("GetClipboardSequenceNumber", "UInt")
        Send "#+s"  ; Win+Shift+S

        deadline := A_TickCount + 120000  ; 2 minutes to make the selection
        changed := false
        while (A_TickCount < deadline) {
            if !Running
                break
            curSeq := DllCall("GetClipboardSequenceNumber", "UInt")
            if (curSeq != startSeq) {
                changed := true
                break
            }
            Sleep 150
        }
        ToolTip()
        if !Running {
            Log("Mode 1 aborted by user")
            return
        }
        if !changed {
            MsgBox "No snip detected within 2 minutes - nothing was copied.", "Warrant Scraper", "Iconi"
            return
        }

        ToolTip "Reading clipboard image..."
        text := OcrCapture("clipimg", "snip", 0, 0, 0, 0)
        ToolTip()
        if (SubStr(text, 1, 10) = "OCR ERROR:") {
            MsgBox text, "Warrant Scraper - OCR error", "Iconx"
            return
        }

        ; Mode 1 only reliably gets skill NAMES (plain readable text in the
        ; panel) - icons carry no readable text, so no supports come from
        ; this mode. Every non-trivial line is included as a candidate;
        ; the poemercs site's fuzzy matcher discards ones that don't
        ; resolve to a real skill (level/attribute text etc.), so a little
        ; extra noise here is fine.
        output := "POE-MERC-SCRAPE-v1`n"
        skillCount := 0
        for line in StrSplit(text, "`n", "`r") {
            trimmed := Trim(line)
            if (StrLen(trimmed) >= MinOcrLineLen) {
                output .= "SKILL: " trimmed "`n"
                skillCount += 1
            }
        }

        A_Clipboard := output
        Log("Mode 1 done | " skillCount " candidate line(s)")
        ShowResultPreview(output, skillCount " line(s) found. No supports in this mode - add those with the site's"
            . " icon chips after applying. Extra non-skill lines are harmless; the site's fuzzy matcher ignores"
            . " what doesn't resolve, or delete them below before pasting.")
    } finally {
        Running := false
        ToolTip()
    }
}

; =====================================================================
;  MODE 2 - HOVER-SCRAPE (skills + supports)
; =====================================================================
ModeHoverScrape(*) {
    global PoeWinTitle, PanelTLx, PanelTLy, PanelBRx, PanelBRy
    global Slot1TLx, IconW, XPitch, MaxSupportsPerRow
    global TooltipHoverDelay, TooltipCaptureHalfW, TooltipCaptureHalfH, MinOcrLineLen
    global Running

    if Running {
        FlashToolTip("Already running - press F10 to abort.")
        return
    }
    if !IsCalibrated() {
        MsgBox "Not calibrated yet. Run the setup wizard first (tray icon > Setup wizard).", "Warrant Scraper", "Iconi"
        return
    }

    Running := true
    Log("Mode 2 (hover-scrape) starting")
    try {
        if !WinExist(PoeWinTitle) {
            MsgBox "Path of Exile window not found (looking for a title containing '" PoeWinTitle "').`n`n"
                . "Edit PoeWinTitle near the top of this script if your window title differs.",
                "Warrant Scraper", "Iconx"
            return
        }
        WinActivate PoeWinTitle
        Sleep 200

        StartOcrServer()
        readyState := WaitOcrReady(15000)
        if (readyState != "READY") {
            MsgBox readyState, "Warrant Scraper - OCR error", "Iconx"
            return
        }

        ToolTip "Reading skill panel..."
        panelW := PanelBRx - PanelTLx
        panelH := PanelBRy - PanelTLy
        linesJson := OcrCapture("lines", "panel", PanelTLx, PanelTLy, panelW, panelH)
        if (linesJson = "" || SubStr(linesJson, 1, 10) = "OCR ERROR:") {
            ToolTip()
            MsgBox "Couldn't read the panel: " (linesJson = "" ? "(no response from OCR helper)" : linesJson),
                "Warrant Scraper - OCR error", "Iconx"
            return
        }
        lines := ParseLineRects(linesJson)

        ; Skill-name lines sit left of the support-icon column - keep
        ; lines whose right edge is left of the first support slot, with a
        ; small margin for OCR bounding-box imprecision.
        skillColumnLimit := Slot1TLx - 10
        skillLines := []
        for line in lines {
            if (line.r < skillColumnLimit && Trim(line.text) != "")
                skillLines.Push(line)
        }
        skillLines := SortByY(skillLines)

        if (skillLines.Length = 0) {
            ToolTip()
            MsgBox "No skill-name text found left of the support column.`n`n"
                . "The panel region or the Row-1-Slot-1 calibration point is likely off - "
                . "try the setup wizard again, or widen the panel's top-left point further left.",
                "Warrant Scraper", "Iconx"
            return
        }

        output := "POE-MERC-SCRAPE-v1`n"
        rowCount := 0
        supportCount := 0

        for line in skillLines {
            if !Running
                break
            rowCount += 1
            rowY := (line.y + line.b) / 2
            output .= "SKILL: " Trim(line.text) "`n"
            ToolTip "Row " rowCount "/" skillLines.Length ": " Trim(line.text) " - reading supports..."

            loop MaxSupportsPerRow {
                if !Running
                    break
                slotIndex := A_Index - 1
                hx := Round(Slot1TLx + IconW / 2 + slotIndex * XPitch)
                hy := Round(rowY)
                MouseMove hx, hy, 0
                Sleep TooltipHoverDelay

                cx1 := hx - TooltipCaptureHalfW
                cy1 := hy - 40
                cw := TooltipCaptureHalfW * 2
                ch := TooltipCaptureHalfH * 2
                reqId := "s" rowCount "_" A_Index
                text := OcrCapture("text", reqId, cx1, cy1, cw, ch)

                if (SubStr(text, 1, 10) = "OCR ERROR:") {
                    Log("slot capture error (row " rowCount " slot " A_Index "): " text)
                    break
                }
                cleaned := CollapseWhitespace(text)

                if (StrLen(cleaned) < MinOcrLineLen) {
                    ; empty slot - icons are left-packed with no gaps, so
                    ; nothing further right in this row either
                    break
                }
                output .= "SUPPORT-RAW: " cleaned "`n"
                supportCount += 1
            }
        }

        ToolTip()
        if !Running {
            Log("Mode 2 aborted by user")
            return
        }

        A_Clipboard := output
        Log("Mode 2 done | " rowCount " rows | " supportCount " supports")
        ShowResultPreview(output, rowCount " skill row(s), " supportCount " support(s) read. Low-confidence matches"
            . " get flagged on the poemercs site after pasting - double check those against what you actually see"
            . " in-game.")
    } finally {
        Running := false
        ToolTip()
    }
}

AbortRun(*) {
    global Running
    if Running {
        Running := false
        Log("abort requested")
        FlashToolTip("Aborting...")
    }
}

FlashToolTip(msg) {
    ToolTip msg
    SetTimer () => ToolTip(), -1500
}

; =====================================================================
;  HOTKEY BINDINGS
; =====================================================================
F8::ModeHoverScrape()
+F8::ModeSnip()
F10::AbortRun()
F7:: {
    if WizardActive()
        WizardSetPressed()
}

; =====================================================================
;  TRAY MENU
; =====================================================================
A_TrayMenu.Delete()
A_TrayMenu.Add("Hover-scrape now (F8)", ModeHoverScrape)
A_TrayMenu.Add("Snip skill names now (Shift+F8)", ModeSnip)
A_TrayMenu.Add()
A_TrayMenu.Add("Setup wizard...", ShowWizard)
A_TrayMenu.Add("Open log file", (*) => Run(LogFile))
A_TrayMenu.Add("Open config file (.ini)", (*) => (FileExist(IniFile) ? Run(IniFile) : MsgBox("No config yet - run the setup wizard first.")))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Hover-scrape now (F8)"
A_IconTip := "PoE Mercenary Warrant Scraper`nF8 = hover-scrape, Shift+F8 = snip, F10 = abort"

if !IsCalibrated() {
    Log("not calibrated - opening wizard on first run")
    SetTimer ShowWizard, -300
}

