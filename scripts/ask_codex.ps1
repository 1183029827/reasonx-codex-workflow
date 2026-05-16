<#
.SYNOPSIS
  调用 Codex CLI 顾问。
.NOTES
  在 Reasonix 的 run_command 环境中调用时，必须附加 2>&1：
    powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "..." 2>&1
  这是因为 PowerShell 启动时和 codex CLI 初始化时写入 stderr 的日志
  会导致 run_command 工具超时；2>&1 在进程级别合并流以绕过此问题。
  脚本内部已用 2>"$LogFile" 将 codex exec 的 stderr 额外保存到日志文件。
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Question
)

# --- Load config ---
$ConfigPath = ".reasonix/config.json"
if (Test-Path $ConfigPath) {
    $Config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $DefaultModel = $Config.codex.model
    $DefaultSandbox = $Config.codex.sandbox
    $LogDir = $Config.codex.log_dir
    $StderrRedirect = $Config.codex.stderr_redirect
    $DefaultReasoning = $Config.codex.reasoning_effort
} else {
    $DefaultModel = "gpt-5.5"
    $DefaultSandbox = "read-only"
    $LogDir = ".reasonix/logs"
    $StderrRedirect = $true
    $DefaultReasoning = "medium"
}

# Env vars override config
$Model = if ($env:CODEX_MODEL) { $env:CODEX_MODEL } else { $DefaultModel }
$Sandbox = if ($env:CODEX_SANDBOX) { $env:CODEX_SANDBOX } else { $DefaultSandbox }
$ReasoningEffort = if ($env:CODEX_REASONING_EFFORT) { $env:CODEX_REASONING_EFFORT } else { $DefaultReasoning }

# --- Validate state file ---
$StateFile = "PROJECT_STATE.md"
if (-not (Test-Path $StateFile)) {
    Write-Error "Missing PROJECT_STATE.md"
    exit 1
}

# --- Build prompt ---
$ProjectState = Get-Content $StateFile -Raw -Encoding UTF8
$Prompt = @"
You are Codex acting as a senior advisor.

You are NOT the primary executor for this repository.
Reasonix is the primary controller.
Do not assume you can edit files or run project commands.
Do not propose destructive shell commands unless explicitly necessary.

Return the answer in this exact structure:

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
$ProjectState

User question:
$Question
"@

# --- Execute Codex CLI with stderr capture ---
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "codex-$Timestamp.log"
$StdoutFile = [System.IO.Path]::GetTempFileName()

if ($StderrRedirect) {
    codex exec --skip-git-repo-check --model $Model --sandbox $Sandbox -c model_reasoning_effort="$ReasoningEffort" $Prompt 2>"$LogFile" | Out-File $StdoutFile -Encoding UTF8
} else {
    codex exec --skip-git-repo-check --model $Model --sandbox $Sandbox -c model_reasoning_effort="$ReasoningEffort" $Prompt | Out-File $StdoutFile -Encoding UTF8
}

$ExitCode = $LASTEXITCODE
$Result = Get-Content $StdoutFile -Raw -Encoding UTF8
Remove-Item $StdoutFile -Force -ErrorAction SilentlyContinue

if ($ExitCode -eq 0 -and $Result) {
    # Success: output clean result
    $Result.Trim()
} else {
    # Failure: output structured error
    $StderrLog = ""
    if (Test-Path $LogFile) {
        $StderrLog = Get-Content $LogFile -Raw -Encoding UTF8
    }
    Write-Output ""
    Write-Output "---"
    Write-Output "Codex CLI 调用失败"
    Write-Output "退出码: $ExitCode"
    if ($StderrLog) {
        Write-Output "错误摘要 (前 2000 字符):"
        $StderrLog.Substring(0, [Math]::Min(2000, $StderrLog.Length))
    }
    Write-Output "完整日志: $LogFile"
    exit $ExitCode
}
