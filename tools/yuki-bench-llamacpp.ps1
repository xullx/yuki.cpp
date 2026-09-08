[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [string]$Name = "manual",

    [int]$PromptTokens = 0,

    # llama-bench accepts comma-separated values, e.g.:
    #   "128"
    #   "128,512,2048,8192"
    [string]$GenTokens = "0",

    [int]$Repetitions = 3,

    [int]$Batch = 4096,

    [int]$UBatch = 4096,

    [string]$Threads = "32",

    [string]$GpuLayers = "99",

    [string]$CpuMoe = "0",

    [string]$CpuMask = "0x0",

    [int]$CpuStrict = 0,

    [int]$Poll = 50,

    [ValidateSet("auto", "on", "off")]
    [string]$FlashAttention = "auto",

    [string]$KvK = "f16",

    [string]$KvV = "f16",

    [string]$Device = "auto",

    [string]$LoadMode = "auto",

    [int]$NoKvOffload = 0,

    [int]$NoOpOffload = 0,

    [int]$NoHost = 0,

    [string]$Numa = "",

    [string]$RunPath = "",

    [switch]$VerboseBench
)


$ErrorActionPreference = "Stop"


# ============================================================
# CONSTANTS
# ============================================================

$Script:BenchRoot = "C:\Yuki\benchmarks"

$Script:SystemProfile = Join-Path `
    $Script:BenchRoot `
    "system-profile.json"

$Script:Llama = "C:\Yuki\bin\brain\llama.exe"

$Script:Model = `
    "C:\Yuki\models\brain\LFM2.5-8B-A1B-Q4_K_M.gguf"

$Script:Actions = `
    "C:\Yuki\launch\yuki-actions.ps1"

$Script:BrainPort = 8084

$Script:BackendProfileId = `
    "llamacpp-vulkan-rx6800"


# ============================================================
# HELP
# ============================================================

function Show-Help {

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK HARNESS"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host ""
    Write-Host "  help"
    Write-Host "      Show this help."
    Write-Host ""
    Write-Host "  start"
    Write-Host "      Start a detached llama.cpp benchmark."
    Write-Host ""
    Write-Host "  status"
    Write-Host "      Show status for a run."
    Write-Host ""
    Write-Host "  show"
    Write-Host "      Show parsed benchmark results and memory data."
    Write-Host ""
    Write-Host "  list"
    Write-Host "      List recent llama.cpp benchmark runs."
    Write-Host ""
    Write-Host "  repair"
    Write-Host "      Reparse an existing bench.json without rerunning."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host ""
    Write-Host '  & .\yuki-bench-llamacpp.ps1 start `'
    Write-Host '      -Name "pp2048" `'
    Write-Host '      -PromptTokens 2048 `'
    Write-Host '      -GenTokens "0" `'
    Write-Host '      -Batch 2048 `'
    Write-Host '      -UBatch 2048'
    Write-Host ""
    Write-Host '  & .\yuki-bench-llamacpp.ps1 status'
    Write-Host ""
    Write-Host '  & .\yuki-bench-llamacpp.ps1 show'
    Write-Host ""
    Write-Host '  & .\yuki-bench-llamacpp.ps1 repair `'
    Write-Host '      -RunPath "C:\Yuki\benchmarks\runs\<run>"'
    Write-Host ""
    Write-Host "Backend profile:"
    Write-Host "  $Script:BackendProfileId"
    Write-Host ""
    Write-Host "This harness is specifically for llama.cpp."
    Write-Host "============================================================"
}


# ============================================================
# JSON HELPERS
# ============================================================

function Write-JsonFile {

    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Object |
        ConvertTo-Json -Depth 30 |
        Set-Content `
            -Path $Path `
            -Encoding UTF8
}


function Read-JsonFile {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    return (
        Get-Content $Path -Raw |
        ConvertFrom-Json
    )
}


function Set-ObjectProperty {

    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Value
    )

    $property = $Object.PSObject.Properties[$Name]

    if ($null -ne $property) {

        $Object.$Name = $Value
    }
    else {

        $Object |
            Add-Member `
                -NotePropertyName $Name `
                -NotePropertyValue $Value
    }
}


# ============================================================
# RUN LOCATION
# ============================================================

function Get-LatestRun {

    $runsPath = Join-Path $Script:BenchRoot "runs"

    if (-not (Test-Path $runsPath)) {
        return $null
    }

    return (
        Get-ChildItem $runsPath -Directory |
        Where-Object {
            Test-Path (
                Join-Path $_.FullName "run.json"
            )
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    )
}


function Resolve-RunPath {

    param(
        [string]$RequestedPath
    )

    if ($RequestedPath) {

        if (-not (Test-Path $RequestedPath)) {
            throw "Run path does not exist: $RequestedPath"
        }

        return (
            Get-Item $RequestedPath
        ).FullName
    }

    $latest = Get-LatestRun

    if ($null -eq $latest) {
        throw "No benchmark runs found."
    }

    return $latest.FullName
}


# ============================================================
# STATUS
# ============================================================

function Write-RunStatus {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$State,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        $EngineExitCode = $null,

        [string]$ParserState = "not_run",

        [string]$ParserError = ""
    )

    $status = [ordered]@{
        state            = $State
        message          = $Message
        engine_exit_code = $EngineExitCode
        parser_state     = $ParserState
        parser_error     = $ParserError
        worker_pid       = $PID
        updated_at       = (Get-Date).ToString("o")
    }

    Write-JsonFile `
        -Object $status `
        -Path $Path
}


# ============================================================
# LLAMA-BENCH JSON PARSER
# ============================================================

function Parse-BenchJson {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "bench.json not found: $Path"
    }

    if ((Get-Item $Path).Length -eq 0) {
        throw "bench.json is empty."
    }

    # Deliberately use the same parsing form that successfully
    # repaired the earlier decode benchmark.
    $rows = @(
        ConvertFrom-Json (
            Get-Content $Path -Raw
        )
    )

    if ($rows.Count -eq 0) {
        throw "bench.json contains no top-level benchmark rows."
    }

    $measurements = @()

    foreach ($row in $rows) {

        if ($null -eq $row.avg_ts) {
            continue
        }

        $nPrompt = 0
        $nGen = 0

        if ($null -ne $row.n_prompt) {
            $nPrompt = [int64]$row.n_prompt
        }

        if ($null -ne $row.n_gen) {
            $nGen = [int64]$row.n_gen
        }

        $kind = "unknown"

        if (
            $nPrompt -gt 0 -and
            $nGen -eq 0
        ) {
            $kind = "pp"
        }
        elseif (
            $nPrompt -eq 0 -and
            $nGen -gt 0
        ) {
            $kind = "tg"
        }
        elseif (
            $nPrompt -gt 0 -and
            $nGen -gt 0
        ) {
            $kind = "pg"
        }

        $measurement = [pscustomobject]@{
            kind           = $kind

            n_prompt       = $nPrompt
            n_gen          = $nGen

            avg_ts         = [math]::Round(
                [double]$row.avg_ts,
                4
            )

            stddev_ts      = [math]::Round(
                [double]$row.stddev_ts,
                4
            )

            avg_ns         = $row.avg_ns
            stddev_ns      = $row.stddev_ns

            n_batch        = $row.n_batch
            n_ubatch       = $row.n_ubatch
            n_threads      = $row.n_threads
            n_gpu_layers   = $row.n_gpu_layers
            n_cpu_moe      = $row.n_cpu_moe

            cpu_mask       = $row.cpu_mask
            cpu_strict     = $row.cpu_strict
            poll           = $row.poll

            type_k         = $row.type_k
            type_v         = $row.type_v

            flash_attn     = $row.flash_attn
            no_kv_offload  = $row.no_kv_offload
            no_op_offload  = $row.no_op_offload

            backends       = $row.backends
            devices        = $row.devices

            build_commit   = $row.build_commit
            build_number   = $row.build_number

            cpu_info       = $row.cpu_info
            gpu_info       = $row.gpu_info

            model_type     = $row.model_type
            model_size     = $row.model_size
            model_n_params = $row.model_n_params

            samples_ts     = @($row.samples_ts)
            samples_ns     = @($row.samples_ns)
        }

        $measurements += $measurement
    }

    if ($measurements.Count -eq 0) {

        throw (
            "llama-bench completed, but no rows with " +
            "avg_ts were found."
        )
    }

    return $measurements
}


# ============================================================
# MEMORY / FALLBACK PARSER
# ============================================================

function Parse-MemoryLog {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $summary = [ordered]@{
        initial_gpu_free_mib = $null

        full_gpu_offload     = $null
        offloaded_layers     = $null
        total_layers         = $null

        cpu_mapped_model_mib = $null
        gpu_model_mib        = $null

        gpu_kv_mib           = $null
        gpu_recurrent_mib    = $null

        gpu_compute_mib      = $null
        host_compute_mib     = $null

        pinned_memory_failure = $false
        allocation_failure    = $false
        gpu_fallback           = $false

        raw_lines              = @()
    }

    if (-not (Test-Path $Path)) {
        return [pscustomobject]$summary
    }

    $interesting = @(
        Get-Content $Path |
        Select-String -Pattern `
            "buffer size|KV self size|compute buffer|offloaded|MiB free|GiB free|OutOfDeviceMemory|pinned memory|allocation failed" |
        ForEach-Object {
            $_.Line
        }
    )

    $summary.raw_lines = $interesting

    foreach ($line in $interesting) {

        if (
            $line -match
            '(\d+(?:\.\d+)?)\s+MiB free'
        ) {
            $summary.initial_gpu_free_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'offloaded\s+(\d+)/(\d+)\s+layers to GPU'
        ) {
            $summary.offloaded_layers = [int]$Matches[1]
            $summary.total_layers = [int]$Matches[2]

            $summary.full_gpu_offload = (
                $summary.offloaded_layers -eq
                $summary.total_layers
            )
        }

        if (
            $line -match
            'CPU_Mapped model buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.cpu_mapped_model_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Vulkan0 model buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.gpu_model_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Vulkan0 KV buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.gpu_kv_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Vulkan0 RS buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.gpu_recurrent_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Vulkan0 compute buffer size\s*(?:is|=|of)?\s*([\d.]+)\s+MiB'
        ) {
            $summary.gpu_compute_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Vulkan_Host compute buffer size\s*(?:is|=|of)?\s*([\d.]+)\s+MiB'
        ) {
            $summary.host_compute_mib = [double]$Matches[1]
        }

        if (
            $line -match
            'Failed to allocate pinned memory'
        ) {
            $summary.pinned_memory_failure = $true
        }

        if (
            $line -match
            'OutOfDeviceMemory|allocation failed'
        ) {
            $summary.allocation_failure = $true
        }
    }

    $summary.gpu_fallback = (
        $summary.pinned_memory_failure -or
        $summary.allocation_failure
    )

    return [pscustomobject]$summary
}


# ============================================================
# RESULT UPDATE
# ============================================================

function Update-RunFromFiles {

    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDirectory,

        [switch]$Repair
    )

    $runFile = Join-Path $RunDirectory "run.json"
    $benchFile = Join-Path $RunDirectory "bench.json"

    $benchErr = Join-Path `
        $RunDirectory `
        "bench-stderr.log"

    if (-not (Test-Path $benchErr)) {

        # Legacy runs used other stderr names.
        $candidate = Get-ChildItem `
            $RunDirectory `
            -File `
            -Filter "*stderr*.log" `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($candidate) {
            $benchErr = $candidate.FullName
        }
    }

    $run = Read-JsonFile $runFile

    if (
        $null -eq
        $run.PSObject.Properties["result"]
    ) {

        $run |
            Add-Member `
                -NotePropertyName "result" `
                -NotePropertyValue ([pscustomobject]@{})
    }

    $parserState = "not_run"
    $parserError = ""
    $measurements = @()

    try {

        $measurements = @(
            Parse-BenchJson $benchFile
        )

        $parserState = "complete"
    }
    catch {

        $parserState = "parser_error"

        $parserError = (
            $_.Exception.Message +
            "`n" +
            $_.ScriptStackTrace
        )
    }

    $memory = Parse-MemoryLog $benchErr

    Set-ObjectProperty `
        $run.result `
        "parser_state" `
        $parserState

    Set-ObjectProperty `
        $run.result `
        "parser_error" `
        $parserError

    Set-ObjectProperty `
        $run.result `
        "measurements" `
        $measurements

    Set-ObjectProperty `
        $run.result `
        "memory" `
        $memory

    Set-ObjectProperty `
        $run.result `
        "gpu_fallback" `
        $memory.gpu_fallback

    Set-ObjectProperty `
        $run.result `
        "last_parsed_at" `
        (Get-Date).ToString("o")

    if ($Repair) {

        Set-ObjectProperty `
            $run.result `
            "repair_performed" `
            $true

        Set-ObjectProperty `
            $run.result `
            "repair_time" `
            (Get-Date).ToString("o")
    }

    Write-JsonFile `
        -Object $run `
        -Path $runFile

    return [pscustomobject]@{
        run          = $run
        parser_state = $parserState
        parser_error = $parserError
        measurements = $measurements
        memory       = $memory
    }
}


# ============================================================
# BUILD LLAMA ARGUMENTS
# ============================================================

function Build-LlamaArguments {

    param(
        $Parameters
    )

    $args = @(
        "bench"

        "-m"
        $Script:Model

        "-p"
        ([string]$Parameters.prompt_tokens)

        "-n"
        ([string]$Parameters.gen_tokens)

        "-r"
        ([string]$Parameters.repetitions)

        "-ngl"
        ([string]$Parameters.gpu_layers)

        "-ncmoe"
        ([string]$Parameters.cpu_moe)

        "-t"
        ([string]$Parameters.threads)

        "-C"
        ([string]$Parameters.cpu_mask)

        "--cpu-strict"
        ([string]$Parameters.cpu_strict)

        "--poll"
        ([string]$Parameters.poll)

        "-b"
        ([string]$Parameters.batch)

        "-ub"
        ([string]$Parameters.ubatch)

        "-ctk"
        ([string]$Parameters.kv_k)

        "-ctv"
        ([string]$Parameters.kv_v)

        "-fa"
        ([string]$Parameters.flash_attention)

        "-dev"
        ([string]$Parameters.device)

        "-lm"
        ([string]$Parameters.load_mode)

        "-nkvo"
        ([string]$Parameters.no_kv_offload)

        "-nopo"
        ([string]$Parameters.no_op_offload)

        "--no-host"
        ([string]$Parameters.no_host)
    )

    if ($Parameters.numa) {

        $args += @(
            "--numa"
            ([string]$Parameters.numa)
        )
    }

    if ($Parameters.verbose) {
        $args += "-v"
    }

    $args += @(
        "-o"
        "json"
    )

    return $args
}


# ============================================================
# START ASYNC BENCHMARK
# ============================================================

function Start-Benchmark {

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Join-Path $Script:BenchRoot "runs") |
        Out-Null

    $safeName = (
        $Name -replace
        '[^A-Za-z0-9._-]',
        '-'
    ).Trim("-")

    if (-not $safeName) {
        $safeName = "manual"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $runDirectory = Join-Path `
        (Join-Path $Script:BenchRoot "runs") `
        "$timestamp-llamacpp-$safeName"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $runDirectory |
        Out-Null

    $statusFile = Join-Path `
        $runDirectory `
        "status.json"

    $runFile = Join-Path `
        $runDirectory `
        "run.json"

    $systemHash = $null

    if (Test-Path $Script:SystemProfile) {

        $systemHash = (
            Get-FileHash `
                $Script:SystemProfile `
                -Algorithm SHA256
        ).Hash
    }

    $harnessHash = (
        Get-FileHash `
            $PSCommandPath `
            -Algorithm SHA256
    ).Hash

    $parameters = [ordered]@{
        prompt_tokens     = $PromptTokens
        gen_tokens        = $GenTokens

        repetitions       = $Repetitions

        batch             = $Batch
        ubatch            = $UBatch

        threads           = $Threads
        gpu_layers        = $GpuLayers
        cpu_moe           = $CpuMoe

        cpu_mask          = $CpuMask
        cpu_strict        = $CpuStrict
        poll              = $Poll

        kv_k              = $KvK
        kv_v              = $KvV

        flash_attention   = $FlashAttention

        device            = $Device
        load_mode         = $LoadMode

        no_kv_offload     = $NoKvOffload
        no_op_offload     = $NoOpOffload
        no_host           = $NoHost

        numa              = $Numa

        verbose           = [bool]$VerboseBench
    }

    $argumentPreview = Build-LlamaArguments `
        ([pscustomobject]$parameters)

    $run = [ordered]@{

        schema = "yuki-llamacpp-benchmark-run-v2"

        created_at = (Get-Date).ToString("o")

        name = $safeName

        backend_profile = [ordered]@{
            id      = $Script:BackendProfileId
            family  = "llama.cpp"
            backend = "Vulkan"
        }

        system_profile = [ordered]@{
            path   = $Script:SystemProfile
            sha256 = $systemHash
        }

        harness = [ordered]@{
            path   = $PSCommandPath
            sha256 = $harnessHash
        }

        executable = $Script:Llama
        model      = $Script:Model

        parameters = $parameters

        exact_arguments = $argumentPreview

        files = [ordered]@{
            bench_json = (
                Join-Path $runDirectory "bench.json"
            )

            bench_stderr = (
                Join-Path $runDirectory "bench-stderr.log"
            )

            worker_stdout = (
                Join-Path $runDirectory "worker-out.log"
            )

            worker_stderr = (
                Join-Path $runDirectory "worker-err.log"
            )
        }

        result = [ordered]@{
            engine_state    = "queued"
            engine_exit_code = $null

            parser_state    = "not_run"
            parser_error    = ""

            wall_seconds    = $null

            gpu_fallback    = $null

            measurements    = @()

            memory          = $null
        }
    }

    Write-JsonFile `
        -Object $run `
        -Path $runFile

    Write-RunStatus `
        -Path $statusFile `
        -State "queued" `
        -Message "Benchmark queued." `
        -EngineExitCode $null `
        -ParserState "not_run"

    $workerOut = Join-Path `
        $runDirectory `
        "worker-out.log"

    $workerErr = Join-Path `
        $runDirectory `
        "worker-err.log"

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy"
            "Bypass"
            "-File"
            "`"$PSCommandPath`""
            "worker"
            "-RunPath"
            "`"$runDirectory`""
        ) `
        -RedirectStandardOutput $workerOut `
        -RedirectStandardError $workerErr `
        -PassThru `
        -WindowStyle Hidden

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK STARTED"
    Write-Host "============================================================"
    Write-Host "Runner PID: $($process.Id)"
    Write-Host "Run:        $runDirectory"
    Write-Host "Status:     $statusFile"
    Write-Host ""
    Write-Host "Detached benchmark started."
    Write-Host "GPT-Bridge does not need to wait for completion."
    Write-Host "============================================================"
}


# ============================================================
# BENCHMARK WORKER
# ============================================================

function Invoke-BenchmarkWorker {

    if (-not $RunPath) {
        throw "worker requires -RunPath"
    }

    $runDirectory = Resolve-RunPath $RunPath

    $runFile = Join-Path `
        $runDirectory `
        "run.json"

    $statusFile = Join-Path `
        $runDirectory `
        "status.json"

    $benchFile = Join-Path `
        $runDirectory `
        "bench.json"

    $benchErr = Join-Path `
        $runDirectory `
        "bench-stderr.log"

    $run = Read-JsonFile $runFile

    $brain = $null

    $engineExitCode = $null
    $engineState = "not_started"

    $parserState = "not_run"
    $parserError = ""

    $wallSeconds = $null

    try {

        Write-RunStatus `
            -Path $statusFile `
            -State "preparing" `
            -Message "Stopping YUKI Brain." `
            -EngineExitCode $null `
            -ParserState "not_run"

        $brain = Get-CimInstance Win32_Process |
            Where-Object {
                $_.ExecutablePath -and
                $_.ExecutablePath -ieq $Script:Llama -and
                $_.CommandLine -match (
                    '(?:^|\s)--port(?:\s+|=)' +
                    $Script:BrainPort +
                    '(?:\s|$)'
                )
            } |
            Select-Object -First 1

        if ($brain) {

            Stop-Process `
                -Id $brain.ProcessId `
                -Force

            Start-Sleep 2
        }

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_running" `
            -Message "llama-bench is running." `
            -EngineExitCode $null `
            -ParserState "not_run"

        Set-ObjectProperty `
            $run.result `
            "engine_state" `
            "running"

        Write-JsonFile `
            -Object $run `
            -Path $runFile

        $arguments = Build-LlamaArguments `
            $run.parameters

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Non-zero llama.cpp exit codes are captured through
        # LASTEXITCODE. They do not become parser errors.
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        & $Script:Llama @arguments `
            2> $benchErr |
            Set-Content `
                -Path $benchFile `
                -Encoding UTF8

        $engineExitCode = $LASTEXITCODE

        $ErrorActionPreference = $oldPreference

        $sw.Stop()

        $wallSeconds = [math]::Round(
            $sw.Elapsed.TotalSeconds,
            3
        )

        if ($engineExitCode -eq 0) {
            $engineState = "complete"
        }
        else {
            $engineState = "failed"
        }

        Set-ObjectProperty `
            $run.result `
            "engine_state" `
            $engineState

        Set-ObjectProperty `
            $run.result `
            "engine_exit_code" `
            $engineExitCode

        Set-ObjectProperty `
            $run.result `
            "wall_seconds" `
            $wallSeconds

        Write-JsonFile `
            -Object $run `
            -Path $runFile


        # ----------------------------------------------------
        # PARSE ONLY AFTER ENGINE COMPLETION
        # ----------------------------------------------------

        if ($engineExitCode -eq 0) {

            try {

                $parsed = Update-RunFromFiles `
                    -RunDirectory $runDirectory

                $parserState = $parsed.parser_state
                $parserError = $parsed.parser_error
            }
            catch {

                $parserState = "parser_error"

                $parserError = (
                    $_.Exception.Message +
                    "`n" +
                    $_.ScriptStackTrace
                )

                $run = Read-JsonFile $runFile

                Set-ObjectProperty `
                    $run.result `
                    "parser_state" `
                    $parserState

                Set-ObjectProperty `
                    $run.result `
                    "parser_error" `
                    $parserError

                Write-JsonFile `
                    -Object $run `
                    -Path $runFile
            }
        }


        # ----------------------------------------------------
        # FINAL STATUS
        # ----------------------------------------------------

        if ($engineExitCode -ne 0) {

            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_failed" `
                -Message (
                    "llama-bench exited with code " +
                    $engineExitCode
                ) `
                -EngineExitCode $engineExitCode `
                -ParserState "not_run"
        }
        elseif ($parserState -eq "complete") {

            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_complete" `
                -Message (
                    "Engine complete; parser complete."
                ) `
                -EngineExitCode 0 `
                -ParserState "complete"
        }
        else {

            # CRITICAL DESIGN:
            #
            # A successful GPU benchmark is NOT marked failed
            # because the metadata parser had an issue.
            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_complete" `
                -Message (
                    "Engine complete; parser error. " +
                    "Raw benchmark data is preserved."
                ) `
                -EngineExitCode 0 `
                -ParserState "parser_error" `
                -ParserError $parserError
        }
    }
    catch {

        $fatalError = (
            $_.Exception.Message +
            "`n" +
            $_.ScriptStackTrace
        )

        try {

            $run = Read-JsonFile $runFile

            Set-ObjectProperty `
                $run.result `
                "engine_state" `
                "harness_error"

            Set-ObjectProperty `
                $run.result `
                "harness_error" `
                $fatalError

            Write-JsonFile `
                -Object $run `
                -Path $runFile
        }
        catch {
        }

        Write-RunStatus `
            -Path $statusFile `
            -State "harness_error" `
            -Message $_.Exception.Message `
            -EngineExitCode $engineExitCode `
            -ParserState $parserState `
            -ParserError $parserError
    }
    finally {

        try {

            . $Script:Actions

            Start-Brain

            Start-Sleep 3
        }
        catch {

            $restoreLog = Join-Path `
                $runDirectory `
                "brain-restore-error.log"

            $_ |
                Out-String |
                Set-Content `
                    $restoreLog `
                    -Encoding UTF8
        }
    }
}


# ============================================================
# STATUS COMMAND
# ============================================================

function Show-Status {

    $runDirectory = Resolve-RunPath $RunPath

    $statusFile = Join-Path `
        $runDirectory `
        "status.json"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK STATUS"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host ""

    if (Test-Path $statusFile) {
        Get-Content $statusFile
    }
    else {
        Write-Host "status.json not found."
    }

    Write-Host "============================================================"
}


# ============================================================
# SHOW COMMAND
# ============================================================

function Show-Run {

    $runDirectory = Resolve-RunPath $RunPath

    $runFile = Join-Path `
        $runDirectory `
        "run.json"

    $statusFile = Join-Path `
        $runDirectory `
        "status.json"

    $run = Read-JsonFile $runFile

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK RESULT"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host ""

    if (Test-Path $statusFile) {

        $status = Read-JsonFile $statusFile

        Write-Host "State:        $($status.state)"
        Write-Host "Parser:       $($status.parser_state)"
        Write-Host "Engine exit:  $($status.engine_exit_code)"

        if ($status.parser_error) {

            Write-Host ""
            Write-Host "Parser error:" -ForegroundColor Yellow
            Write-Host $status.parser_error
        }
    }

    Write-Host ""
    Write-Host "=== MEASUREMENTS ===" -ForegroundColor Cyan

    $measurements = @()

    if (
        $run.result -and
        $run.result.PSObject.Properties["measurements"]
    ) {
        $measurements = @(
            $run.result.measurements
        )
    }

    if ($measurements.Count -gt 0) {

        $measurements |
            Select-Object `
                kind,
                n_prompt,
                n_gen,
                avg_ts,
                stddev_ts,
                n_batch,
                n_ubatch,
                n_threads,
                n_gpu_layers |
            Format-Table -AutoSize
    }
    else {

        Write-Host "No parsed measurements."
    }

    if (
        $run.result -and
        $run.result.PSObject.Properties["memory"] -and
        $run.result.memory
    ) {

        Write-Host ""
        Write-Host "=== MEMORY ===" -ForegroundColor Cyan

        $run.result.memory |
            Select-Object `
                initial_gpu_free_mib,
                full_gpu_offload,
                offloaded_layers,
                total_layers,
                gpu_model_mib,
                gpu_kv_mib,
                gpu_recurrent_mib,
                gpu_compute_mib,
                host_compute_mib,
                pinned_memory_failure,
                allocation_failure,
                gpu_fallback |
            Format-List
    }

    Write-Host "============================================================"
}


# ============================================================
# LIST COMMAND
# ============================================================

function Show-RunList {

    $runsPath = Join-Path `
        $Script:BenchRoot `
        "runs"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "RECENT YUKI LLAMA.CPP RUNS"
    Write-Host "============================================================"

    if (-not (Test-Path $runsPath)) {

        Write-Host "No runs directory."
        return
    }

    $items = @()

    foreach (
        $dir in (
            Get-ChildItem $runsPath -Directory |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20
        )
    ) {

        $statusFile = Join-Path `
            $dir.FullName `
            "status.json"

        $state = ""
        $parser = ""
        $message = ""

        if (Test-Path $statusFile) {

            try {

                $status = Read-JsonFile $statusFile

                $state = $status.state
                $parser = $status.parser_state
                $message = $status.message
            }
            catch {

                $state = "status_parse_error"
            }
        }

        $items += [pscustomobject]@{
            run     = $dir.Name
            state   = $state
            parser  = $parser
            message = $message
        }
    }

    $items |
        Format-Table -AutoSize

    Write-Host "============================================================"
}


# ============================================================
# REPAIR COMMAND
# ============================================================

function Repair-Run {

    $runDirectory = Resolve-RunPath $RunPath

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP RUN REPAIR"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host ""

    $parsed = Update-RunFromFiles `
        -RunDirectory $runDirectory `
        -Repair

    $statusFile = Join-Path `
        $runDirectory `
        "status.json"

    if ($parsed.parser_state -eq "complete") {

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_complete" `
            -Message (
                "Existing benchmark reparsed successfully."
            ) `
            -EngineExitCode 0 `
            -ParserState "complete"

        Write-Host "Parser: COMPLETE" `
            -ForegroundColor Green

        Write-Host ""

        $parsed.measurements |
            Select-Object `
                kind,
                n_prompt,
                n_gen,
                avg_ts,
                stddev_ts,
                n_batch,
                n_ubatch,
                n_threads,
                n_gpu_layers |
            Format-Table -AutoSize
    }
    else {

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_complete" `
            -Message (
                "Raw benchmark exists; parser still has an error."
            ) `
            -EngineExitCode 0 `
            -ParserState "parser_error" `
            -ParserError $parsed.parser_error

        Write-Host "Parser: ERROR" `
            -ForegroundColor Yellow

        Write-Host $parsed.parser_error
    }

    Write-Host ""
    Write-Host "============================================================"
}


# ============================================================
# COMMAND ROUTER
# ============================================================

switch ($Command.ToLowerInvariant()) {

    "help" {
        Show-Help
        break
    }

    "start" {
        Start-Benchmark
        break
    }

    "worker" {
        Invoke-BenchmarkWorker
        break
    }

    "status" {
        Show-Status
        break
    }

    "show" {
        Show-Run
        break
    }

    "list" {
        Show-RunList
        break
    }

    "repair" {
        Repair-Run
        break
    }

    default {

        Write-Host ""
        Write-Host "Unknown command: $Command" `
            -ForegroundColor Red

        Show-Help

        exit 1
    }
}

