<#
.SYNOPSIS
  Invoke advisor CLI (opencode or codex), driven by .reasonix/config.json advisor.provider.
.NOTES
  When calling from Reasonix run_command, append 2>&1:
    powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "..." 2>&1
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Question
)

# --- Load config ---
$ConfigPath = ".reasonix/config.json"
if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # Advisor config (primary)
    if ($Config.advisor) {
        $Provider       = if ($env:ADVISOR_PROVIDER) { $env:ADVISOR_PROVIDER } else { $Config.advisor.provider }
        $AdvisorModel   = if ($env:ADVISOR_MODEL)   { $env:ADVISOR_MODEL }   else { $Config.advisor.model }
        $AdvisorVariant = if ($env:ADVISOR_VARIANT) { $env:ADVISOR_VARIANT } else { $Config.advisor.variant }
    } else {
        $Provider = "codex"
    }

    # Codex config (fallback / legacy)
    if ($Config.codex) {
        $CodexModel     = $Config.codex.model
        $CodexSandbox   = $Config.codex.sandbox
        $CodexReasoning = $Config.codex.reasoning_effort
        $LogDir         = $Config.codex.log_dir
        $StderrRedirect = $Config.codex.stderr_redirect
    }
} else {
    $Provider       = "codex"
    $CodexModel     = "gpt-5.5"
    $CodexSandbox   = "read-only"
    $CodexReasoning = "medium"
    $LogDir         = ".reasonix/logs"
    $StderrRedirect = $true
}

# --- Validate state file ---
$StateFile = "PROJECT_STATE.md"
if (-not (Test-Path $StateFile)) {
    Write-Error "Missing PROJECT_STATE.md -- create it first."
    exit 1
}

# --- Build prompt ---
$ProjectState = Get-Content $StateFile -Raw -Encoding UTF8
$PromptTemplate = @'
CRITICAL: You are a READ-ONLY advisor. You MUST NOT use ANY tools (grep, read, ls, glob, bash, view, edit, websearch, etc.) to explore files or search the codebase. Answer ONLY from the information provided in this prompt. If the provided information is insufficient, state what additional information you need — do NOT go looking for it yourself. Using tools will waste time and tokens and may cause the session to hang.

---

You are a senior technical advisor reporting to Reasonix (the primary executor of this repository).

Role rules:
- You are NOT the executor. Do NOT propose editing files or running commands.
- You are a pure reasoning engine. Think, then return structured advice.
- All relevant context is provided below. Do NOT explore further.

Return your answer in this exact structure:

decision:
- ...

rationale:
- ...

risks:
- ...

next_steps:
- ...

checks:
- ...

Project state:
___PROJECT_STATE___

User question:
___QUESTION___
'@
$Prompt = $PromptTemplate.Replace('___PROJECT_STATE___', $ProjectState).Replace('___QUESTION___', $Question)

# --- Ensure log directory ---
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# --- Log rotation helper ---
function Rotate-Logs {
    param(
        [string]$LogDirectory,
        [string]$Pattern,
        [int]$KeepCount = 20
    )
    $Files = @(Get-ChildItem -Path (Join-Path $LogDirectory $Pattern) -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($Files.Count -gt $KeepCount) {
        $Files | Select-Object -Skip $KeepCount | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
#  Dispatch: opencode
# ============================================================
function _Sanitize-For-Cli($Text) {
    # Strip non-printable and non-ASCII to avoid CLI/codepage mangling.
    # Em-dash, smart quotes, CJK, etc. are replaced with a safe marker.
    $Safe = $Text -replace '[^\x09\x0A\x0D\x20-\x7E]', '?'
    return $Safe
}

if ($Provider -eq "opencode") {
    $LogFile = Join-Path $LogDir "advisor-$Timestamp.jsonl"

    # Write prompt to temp file; pipe via stdin to avoid CLI encoding loss
    $TempPrompt = [System.IO.Path]::GetTempFileName()
    $SanitizedPrompt = _Sanitize-For-Cli ($Prompt)
    $SanitizedPrompt | Out-File $TempPrompt -Encoding ASCII

    $JsonOutput = Get-Content $TempPrompt -Raw | opencode run --model $AdvisorModel --variant $AdvisorVariant --format json 2>&1
    $ExitCode = $LASTEXITCODE
    Remove-Item $TempPrompt -Force -ErrorAction SilentlyContinue

    if ($ExitCode -eq 0 -and $JsonOutput) {
        # Save raw JSONL log
        $JsonOutput | Out-File $LogFile -Encoding UTF8
        Rotate-Logs -LogDirectory $LogDir -Pattern "advisor-*.jsonl"

        # Parse JSONL: extract type=text events
        $ResponseText = ""
        $TotalTokens = $null
        $Cost = $null
        $Lines = $JsonOutput -split "`n"
        foreach ($Line in $Lines) {
            if ($Line -match '"type":"text"') {
                try {
                    $Obj = $Line | ConvertFrom-Json
                    $ResponseText += $Obj.part.text
                } catch {}
            }
            if ($Line -match '"type":"step_finish"') {
                try {
                    $Obj = $Line | ConvertFrom-Json
                    $TotalTokens = $Obj.part.tokens.total
                    $Cost = $Obj.part.cost
                } catch {}
            }
        }

        if ($ResponseText) {
            $ResponseText.Trim()
        } else {
            Write-Output ""
            Write-Output "---"
            Write-Output "Advisor returned empty response"
            Write-Output "Full log: $LogFile"
            exit 1
        }

        if ($TotalTokens) {
            $CostLine = if ($Cost) { "cost=$Cost" } else { "" }
            Write-Output ""
            Write-Output "[advisor: $AdvisorModel | tokens=$TotalTokens $CostLine | log=$LogFile]"
        }
    } else {
        Write-Output ""
        Write-Output "---"
        Write-Output "Advisor call failed (opencode)"
        Write-Output "Exit code: $ExitCode"
        Write-Output "Full log: $LogFile"
        if ($JsonOutput) { $JsonOutput | Out-File $LogFile -Encoding UTF8 }
        exit $ExitCode
    }

# ============================================================
#  Dispatch: codex (legacy)
# ============================================================
} else {
    $LogFile = Join-Path $LogDir "codex-$Timestamp.log"
    $StdoutFile = [System.IO.Path]::GetTempFileName()

    if ($StderrRedirect) {
        codex exec --skip-git-repo-check --model $CodexModel --sandbox $CodexSandbox -c model_reasoning_effort="$CodexReasoning" $Prompt 2>"$LogFile" | Out-File $StdoutFile -Encoding UTF8
    } else {
        codex exec --skip-git-repo-check --model $CodexModel --sandbox $CodexSandbox -c model_reasoning_effort="$CodexReasoning" $Prompt | Out-File $StdoutFile -Encoding UTF8
    }

    $ExitCode = $LASTEXITCODE
    $Result = Get-Content $StdoutFile -Raw -Encoding UTF8
    Remove-Item $StdoutFile -Force -ErrorAction SilentlyContinue

    if ($ExitCode -eq 0 -and $Result) {
        $Result.Trim()
        Rotate-Logs -LogDirectory $LogDir -Pattern "codex-*.log"
    } else {
        $StderrLog = ""
        if (Test-Path $LogFile) {
            $StderrLog = Get-Content $LogFile -Raw -Encoding UTF8
        }
        Write-Output ""
        Write-Output "---"
        Write-Output "Codex CLI call failed"
        Write-Output "Exit code: $ExitCode"
        if ($StderrLog) {
            Write-Output "Error summary (first 2000 chars):"
            $StderrLog.Substring(0, [Math]::Min(2000, $StderrLog.Length))
        }
        Write-Output "Full log: $LogFile"
        exit $ExitCode
    }
}
