<#
.SYNOPSIS
  Invoke advisor CLI (opencode or codex), driven by .reasonix/config.json advisor.provider.
.NOTES
  Single-model (via run_background):
    powershell -File scripts/ask_codex.ps1 -Mode decide -Question "..." -Context "..."
  Resume session:
    powershell -File scripts/ask_codex.ps1 -Mode discuss -Question "..." -Session ses_abc123
  Dual-model (GLM + GPT-5.5):
    powershell -File scripts/ask_codex.ps1 -Mode decide -Question "..." -Dual
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Question = "",

    [ValidateSet("decide","review","discuss")]
    [string]$Mode = "decide",

    [string]$Context = "",

    [string]$Session = "",

    [switch]$Dual
)

# --- Validate inputs per mode ---
if ($Mode -ne "review" -and $Question.Trim() -eq "") {
    Write-Error "Question is required for '$Mode' mode."
    exit 1
}
if ($Context.Trim() -eq "") {
    Write-Warning "Context is empty. Advisor may not have enough information."
}

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

switch ($Mode) {

    "decide" {
        $PromptTemplate = @'
You are a senior technical advisor helping Reasonix make a design or strategy decision.

You have full read access to this codebase. Use grep, read, and glob freely to explore relevant files, trace dependencies, and gather context. Take as much time as you need — thoroughness matters more than speed.

Rules:
- You are NOT the executor. Do NOT propose bash commands, file edits, or writes.
- Tools allowed: grep, read, glob
- Tools FORBIDDEN: bash, edit, write, websearch, webfetch
- Cite specific file paths and line numbers when referencing code.

Return your answer in this exact structure:

decision: <clear choice with brief justification>
rationale:
- <bullet points citing specific evidence from the context>
risks:
- <what could go wrong with this decision>
next_steps:
- <concrete actions if the decision is accepted>
checks:
- <how to verify the decision was correct later>

---

CONTEXT (prepared by Reasonix):
___CONTEXT___

PROJECT STATE:
___PROJECT_STATE___

DECISION QUESTION:
___QUESTION___
'@
    }

    "review" {
        $PromptTemplate = @'
You are a senior code reviewer. Review code for correctness, hidden coupling, initialization discipline, and gradient flow.

You have full read access to this codebase. Use grep, read, and glob freely to read the changed files, trace callers, check related modules, and verify assumptions. Take as much time as you need.

Rules:
- You are NOT the executor. Do NOT propose bash commands, file edits, or writes.
- Tools allowed: grep, read, glob
- Tools FORBIDDEN: bash, edit, write, websearch, webfetch
- Cite specific file paths and line numbers in findings.
- Focus on logic errors, coupling risks, init/cleanup issues, and gradient-flow problems.
- Ignore style nits unless they mask a real bug.

Return your review in this exact structure:

summary: <approve | changes-requested | comment>

findings:
- file: <path>
  line: <line or range>
  severity: <critical | major | minor | nit>
  category: <logic | coupling | init | gradient | perf | style>
  description: <concrete issue>
  suggestion: <specific fix>

overall_notes:
- <cross-cutting observations or praise>

---

REVIEW CONTEXT (prepared by Reasonix — includes diff, purpose, design decisions, focus areas):
___CONTEXT___

PROJECT STATE:
___PROJECT_STATE___
'@
    }

    "discuss" {
        $PromptTemplate = @'
You are a senior technical collaborator. Reasonix is stuck on a problem and needs your analysis and ideas.

You have full read access to this codebase. Use grep, read, and glob freely to inspect relevant code, check logs, trace execution paths, and form evidence-based hypotheses. Take as much time as you need.

Rules:
- You are NOT the executor. Do NOT propose bash commands, file edits, or writes.
- Tools allowed: grep, read, glob
- Tools FORBIDDEN: bash, edit, write, websearch, webfetch
- Think like a debugger: form hypotheses, identify missing information, suggest next steps.
- Cite specific file paths and line numbers when referencing code.

Return your analysis in this exact structure:

analysis: <free-form analysis of the situation>
key_observations:
- <important facts or constraints from the context>
hypotheses:
- <possible explanations or approaches, ranked by likelihood or merit>
open_questions:
- <what additional information would help narrow this down>
recommendation: <your top suggestion for what to try next>

---

DISCUSSION CONTEXT (prepared by Reasonix — includes problem description, what was tried, key logs, eliminated hypotheses):
___CONTEXT___

PROJECT STATE:
___PROJECT_STATE___

PROBLEM:
___QUESTION___
'@
    }
}

$Prompt = $PromptTemplate.Replace('___PROJECT_STATE___', $ProjectState).Replace('___QUESTION___', $Question).Replace('___CONTEXT___', $Context)

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
#  Dispatch helpers
# ============================================================
function _Sanitize-For-Cli($Text) {
    $Safe = $Text -replace '[^\x09\x0A\x0D\x20-\x7E]', '?'
    return $Safe
}

function _Run-OpenCode {
    param([string]$Model, [string]$Variant, [string]$PromptText, [string]$SessionId)
    $LogFile = Join-Path $LogDir "advisor-$Timestamp.jsonl"
    $TempPrompt = [System.IO.Path]::GetTempFileName()
    $StdoutFile = [System.IO.Path]::GetTempFileName()
    $StderrFile = Join-Path $LogDir "advisor-$Timestamp-err.log"
    $Sanitized = _Sanitize-For-Cli ($PromptText)
    $Sanitized | Out-File $TempPrompt -Encoding ASCII
    $SessArg = if ($SessionId) { "--session $SessionId" } else { "" }
    cmd /c "type `"$TempPrompt`" | opencode run --model $Model --variant $Variant --format json $SessArg > `"$StdoutFile`" 2> `"$StderrFile`""
    $ExitCode = $LASTEXITCODE
    $JsonOutput = Get-Content $StdoutFile -Raw -Encoding UTF8
    Remove-Item $TempPrompt, $StdoutFile -Force -ErrorAction SilentlyContinue
    return @{ ExitCode = $ExitCode; JsonOutput = $JsonOutput; LogFile = $LogFile }
}

function _Parse-OpenCodeJsonl {
    param([string]$JsonOutput)
    $ResponseText = ""; $TotalTokens = $null; $Cost = $null; $SessionId = $null
    $Lines = $JsonOutput -split "`n"
    foreach ($Line in $Lines) {
        if ($Line -match '"type":"step_start"' -and -not $SessionId) {
            try { $Obj = $Line | ConvertFrom-Json; $SessionId = $Obj.part.sessionID } catch {}
        }
        if ($Line -match '"type":"text"') {
            try { $Obj = $Line | ConvertFrom-Json; $ResponseText += $Obj.part.text } catch {}
        }
        if ($Line -match '"type":"step_finish"') {
            try { $Obj = $Line | ConvertFrom-Json; $TotalTokens = $Obj.part.tokens.total; $Cost = $Obj.part.cost } catch {}
        }
    }
    return @{ Text = $ResponseText; Tokens = $TotalTokens; Cost = $Cost; SessionId = $SessionId }
}

function _Run-Codex {
    param([string]$Model, [string]$Sandbox, [string]$Reasoning, [string]$PromptText)
    $LogFile = Join-Path $LogDir "codex-$Timestamp.log"
    $StdoutFile = [System.IO.Path]::GetTempFileName()
    $TempPrompt = [System.IO.Path]::GetTempFileName()
    $Sanitized = _Sanitize-For-Cli ($PromptText)
    $Sanitized | Out-File $TempPrompt -Encoding ASCII
    if ($StderrRedirect) {
        Get-Content $TempPrompt -Raw | codex exec --skip-git-repo-check --model $Model --sandbox $Sandbox -c model_reasoning_effort="$Reasoning" -c approval_policy="never" - 2>"$LogFile" | Out-File $StdoutFile -Encoding UTF8
    } else {
        Get-Content $TempPrompt -Raw | codex exec --skip-git-repo-check --model $Model --sandbox $Sandbox -c model_reasoning_effort="$Reasoning" -c approval_policy="never" - | Out-File $StdoutFile -Encoding UTF8
    }
    $ExitCode = $LASTEXITCODE
    $Result = Get-Content $StdoutFile -Raw -Encoding UTF8
    Remove-Item $TempPrompt, $StdoutFile -Force -ErrorAction SilentlyContinue
    return @{ ExitCode = $ExitCode; Text = $Result; LogFile = $LogFile }
}

# ============================================================
#  Dual mode: run both opencode and codex
# ============================================================
if ($Dual) {
    # --- OpenCode (GLM) ---
    $OC = _Run-OpenCode -Model $AdvisorModel -Variant $AdvisorVariant -PromptText $Prompt -SessionId $Session
    $OCResult = $null
    if ($OC.ExitCode -eq 0 -and $OC.JsonOutput) {
        $OC.JsonOutput | Out-File $OC.LogFile -Encoding UTF8
        Rotate-Logs -LogDirectory $LogDir -Pattern "advisor-*.jsonl"
        $OCResult = _Parse-OpenCodeJsonl -JsonOutput $OC.JsonOutput
    }

    # --- Codex (GPT-5.5) ---
    $CX = _Run-Codex -Model $CodexModel -Sandbox $CodexSandbox -Reasoning $CodexReasoning -PromptText $Prompt
    if ($CX.ExitCode -eq 0) { Rotate-Logs -LogDirectory $LogDir -Pattern "codex-*.log" }

    # --- Output ---
    Write-Output "=== GLM 5.1 (opencode) ==="
    if ($OCResult -and $OCResult.Text) {
        Write-Output $OCResult.Text.Trim()
    } else {
        Write-Output "(no response - exit code $($OC.ExitCode))"
    }
    if ($OCResult.Tokens) {
        $CL = if ($OCResult.Cost) { "cost=$($OCResult.Cost)" } else { "" }
        $SL = if ($OCResult.SessionId) { " session=$($OCResult.SessionId)" } else { "" }
        Write-Output "[advisor: $AdvisorModel | tokens=$($OCResult.Tokens) $CL |$SL log=$($OC.LogFile)]"
    }
    Write-Output ""
    Write-Output "=== GPT-5.5 (codex) ==="
    if ($CX.ExitCode -eq 0 -and $CX.Text) {
        Write-Output $CX.Text.Trim()
    } else {
        Write-Output "(no response - exit code $($CX.ExitCode))"
    }
    Write-Output ""
    Write-Output "[codex: $CodexModel | log=$($CX.LogFile)]"
    exit 0
}

# ============================================================
#  Single-mode dispatch: opencode
# ============================================================
if ($Provider -eq "opencode") {
    $OC = _Run-OpenCode -Model $AdvisorModel -Variant $AdvisorVariant -PromptText $Prompt -SessionId $Session

    if ($OC.ExitCode -eq 0 -and $OC.JsonOutput) {
        $OC.JsonOutput | Out-File $OC.LogFile -Encoding UTF8
        Rotate-Logs -LogDirectory $LogDir -Pattern "advisor-*.jsonl"
        $Result = _Parse-OpenCodeJsonl -JsonOutput $OC.JsonOutput

        if ($Result.Text) {
            Write-Output $Result.Text.Trim()
        } else {
            Write-Output ""
            Write-Output "---"
            Write-Output "Advisor returned empty response"
            Write-Output "Full log: $($OC.LogFile)"
            exit 1
        }

        if ($Result.Tokens) {
            $CostLine = if ($Result.Cost) { "cost=$($Result.Cost)" } else { "" }
            $SessionLine = if ($Result.SessionId) { " session=$($Result.SessionId)" } else { "" }
            Write-Output ""
            Write-Output "[advisor: $AdvisorModel | tokens=$($Result.Tokens) $CostLine |$SessionLine log=$($OC.LogFile)]"
        }
    } else {
        Write-Output ""
        Write-Output "---"
        Write-Output "Advisor call failed (opencode)"
        Write-Output "Exit code: $($OC.ExitCode)"
        Write-Output "Full log: $($OC.LogFile)"
        if ($OC.JsonOutput) { $OC.JsonOutput | Out-File $OC.LogFile -Encoding UTF8 }
        exit $OC.ExitCode
    }

# ============================================================
#  Dispatch: codex (legacy)
# ============================================================
} else {
    $CX = _Run-Codex -Model $CodexModel -Sandbox $CodexSandbox -Reasoning $CodexReasoning -PromptText $Prompt

    if ($CX.ExitCode -eq 0 -and $CX.Text) {
        Write-Output $CX.Text.Trim()
        Rotate-Logs -LogDirectory $LogDir -Pattern "codex-*.log"
    } else {
        $StderrLog = ""
        if (Test-Path $CX.LogFile) {
            $StderrLog = Get-Content $CX.LogFile -Raw -Encoding UTF8
        }
        Write-Output ""
        Write-Output "---"
        Write-Output "Codex CLI call failed"
        Write-Output "Exit code: $($CX.ExitCode)"
        if ($StderrLog) {
            Write-Output "Error summary (first 2000 chars):"
            $StderrLog.Substring(0, [Math]::Min(2000, $StderrLog.Length))
        }
        Write-Output "Full log: $($CX.LogFile)"
        exit $CX.ExitCode
    }
}
