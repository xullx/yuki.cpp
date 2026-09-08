[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [string]$Name = "manual",

    # New post-architecture runs must belong to an explicit Experiment.
    [string]$ExperimentId = "",

    # Optional methodology workload profile. If omitted, the harness
    # auto-detects the standard 2048+128 and decode-scaling profiles
    # where possible; otherwise the run is recorded as "custom".
    [string]$WorkloadId = "",

    [int]$PromptTokens = 0,

    # llama-bench accepts comma-separated values, e.g.:
    #   "128"
    #   "128,512,2048,8192"
    [string]$GenTokens = "0",

    # methodology-llamacpp-v1 default.
    [int]$Repetitions = 5,

    [int]$Batch = 4096,

    [int]$UBatch = 4096,

    # llama-bench accepts comma-separated values for several knobs.
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

$Script:BackendId = `
    "llamacpp-6703d7894-bf685ba62a42"

$Script:SuiteId = `
    "suite-llamacpp-6703d7894-yuki-exhaustion-v1"

$Script:MethodologyId = `
    "methodology-llamacpp-v1"

$Script:SuiteFile = Join-Path `
    "$Script:BenchRoot\registry\suites\$Script:SuiteId" `
    "suite.json"

$Script:BackendFile = Join-Path `
    "$Script:BenchRoot\registry\backends\$Script:BackendId" `
    "backend.json"

$Script:MethodologyFile = Join-Path `
    "$Script:BenchRoot\experiments\exp-llamacpp-methodology-freeze-v1" `
    "methodology.json"

$Script:RunSchema = `
    "yuki-llamacpp-benchmark-run-v3"

$Script:StatusSchema = `
    "yuki-llamacpp-benchmark-status-v2"

# Kept only for historical compatibility/evidence.
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
    Write-Host "      New runs require -ExperimentId."
    Write-Host ""
    Write-Host "  status"
    Write-Host "      Show status for a run."
    Write-Host ""
    Write-Host "  show"
    Write-Host "      Show parsed benchmark results, identities and memory data."
    Write-Host ""
    Write-Host "  list"
    Write-Host "      List recent llama.cpp benchmark runs."
    Write-Host ""
    Write-Host "  repair"
    Write-Host "      Reparse an existing bench.json without rerunning."
    Write-Host "      Legacy v2 runs remain repairable."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host ""
    Write-Host '  & .\yuki-bench-llamacpp.ps1 start `'
    Write-Host '      -ExperimentId "exp-..." `'
    Write-Host '      -Name "pp2048" `'
    Write-Host '      -WorkloadId "synthetic-interactive-v1" `'
    Write-Host '      -PromptTokens 2048 `'
    Write-Host '      -GenTokens "128" `'
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
    Write-Host "Backend:"
    Write-Host "  $Script:BackendId"
    Write-Host ""
    Write-Host "Suite:"
    Write-Host "  $Script:SuiteId"
    Write-Host ""
    Write-Host "Methodology:"
    Write-Host "  $Script:MethodologyId"
    Write-Host ""
    Write-Host "Post-architecture run schema:"
    Write-Host "  $Script:RunSchema"
    Write-Host ""
    Write-Host "This harness is specifically for llama.cpp."
    Write-Host "============================================================"
}

# ============================================================
# JSON / OBJECT HELPERS
# ============================================================

function Write-JsonFile {

    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path $Path -Parent

    if ($parent) {

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $parent |
            Out-Null
    }

    $temp = $Path + ".tmp"

    $Object |
        ConvertTo-Json -Depth 100 |
        Set-Content `
            -Path $temp `
            -Encoding UTF8

    # Validate JSON before replacing the authoritative file.
    $null = (
        Get-Content $temp -Raw |
        ConvertFrom-Json
    )

    Move-Item `
        -Path $temp `
        -Destination $Path `
        -Force
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


function Get-Sha256 {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Cannot hash missing file: $Path"
    }

    return (
        Get-FileHash `
            -Path $Path `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()
}


function Test-MultiValueString {

    param(
        $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    return (
        ([string]$Value) -match ','
    )
}


function Get-UniqueStringValues {

    param(
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @(
        ([string]$Value) `
            -split ',' |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } |
        Select-Object -Unique
    )
}


# ============================================================
# REPRODUCIBILITY CONTRACT
# ============================================================

function Get-BenchmarkContract {

    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedExperimentId
    )

    if (
        [string]::IsNullOrWhiteSpace(
            $RequestedExperimentId
        )
    ) {
        throw (
            "start requires -ExperimentId. " +
            "Create the Experiment record before launching a post-architecture run."
        )
    }

    foreach (
        $required in @(
            $Script:SuiteFile,
            $Script:BackendFile,
            $Script:MethodologyFile,
            $Script:Llama,
            $Script:Model
        )
    ) {

        if (-not (Test-Path $required)) {
            throw "Required benchmark contract path missing: $required"
        }
    }

    $suite = Read-JsonFile $Script:SuiteFile
    $backend = Read-JsonFile $Script:BackendFile
    $methodology = Read-JsonFile $Script:MethodologyFile

    if ($suite.id -ne $Script:SuiteId) {
        throw "Suite identity mismatch."
    }

    if (-not $suite.summary.manifest_complete) {
        throw "Suite coverage manifest is not complete."
    }

    if ($backend.id -ne $Script:BackendId) {
        throw "Backend registry identity mismatch."
    }

    if (
        -not
        $backend.parameter_registry.review.semantic_registry_structurally_complete
    ) {
        throw "Backend semantic registry is not structurally complete."
    }

    if ($methodology.id -ne $Script:MethodologyId) {
        throw "Methodology identity mismatch."
    }

    if ($methodology.status -ne "frozen") {
        throw "Methodology is not frozen."
    }

    $methodologyHash = Get-Sha256 $Script:MethodologyFile

    if (
        $suite.PSObject.Properties["methodology"] -and
        $suite.methodology.sha256 -and
        ([string]$suite.methodology.sha256).ToLowerInvariant() -ne
            $methodologyHash
    ) {
        throw (
            "Methodology hash differs from the suite binding. " +
            "Do not run benchmarks until the methodology identity is reconciled."
        )
    }

    $experimentFile = Join-Path `
        "$Script:BenchRoot\experiments\$RequestedExperimentId" `
        "experiment.json"

    if (-not (Test-Path $experimentFile)) {
        throw "Experiment record not found: $experimentFile"
    }

    $experiment = Read-JsonFile $experimentFile

    if ($experiment.id -ne $RequestedExperimentId) {
        throw "Experiment ID does not match its record."
    }

    if ($experiment.suite_ref -ne $suite.id) {
        throw "Experiment belongs to a different benchmark suite."
    }

    if (
        $experiment.PSObject.Properties["phase"] -and
        [int]$experiment.phase -eq 0
    ) {
        throw (
            "Phase-0 methodology experiment cannot own performance runs. " +
            "Create a Phase-1 or later Experiment."
        )
    }

    $experimentMethodologyId = $null
    $experimentMethodologyHash = $null

    if ($experiment.PSObject.Properties["methodology"]) {

        if (
            $experiment.methodology.PSObject.Properties["methodology_id"]
        ) {
            $experimentMethodologyId =
                [string]$experiment.methodology.methodology_id
        }
        elseif (
            $experiment.methodology.PSObject.Properties["id"]
        ) {
            $experimentMethodologyId =
                [string]$experiment.methodology.id
        }

        if (
            $experiment.methodology.PSObject.Properties["sha256"]
        ) {
            $experimentMethodologyHash =
                [string]$experiment.methodology.sha256
        }
    }

    if (
        -not $experimentMethodologyId -or
        $experimentMethodologyId -ne $methodology.id
    ) {
        throw (
            "Experiment does not explicitly reference " +
            "$($methodology.id)."
        )
    }

    if (
        -not $experimentMethodologyHash -or
        $experimentMethodologyHash.ToLowerInvariant() -ne
            $methodologyHash
    ) {
        throw (
            "Experiment methodology hash does not match the frozen contract."
        )
    }

    $targetFields = @(
        "machine_ref",
        "environment_ref",
        "host_session_ref",
        "backend_ref",
        "model_ref",
        "model_artifact_ref"
    )

    foreach ($field in $targetFields) {

        $suiteValue = $suite.target.$field
        $experimentValue = $experiment.target.$field

        if (
            $null -eq $suiteValue -or
            [string]::IsNullOrWhiteSpace(
                [string]$suiteValue
            )
        ) {
            throw "Suite target is missing $field."
        }

        if (
            $null -eq $experimentValue -or
            [string]::IsNullOrWhiteSpace(
                [string]$experimentValue
            )
        ) {
            throw "Experiment target is missing $field."
        }

        if (
            [string]$experimentValue -ne
            [string]$suiteValue
        ) {
            throw (
                "Experiment target '$field' does not match suite target."
            )
        }
    }

    if ($suite.target.backend_ref -ne $backend.id) {
        throw "Suite backend binding does not match backend registry."
    }

    # --------------------------------------------------------
    # CURRENT HOST SESSION VALIDATION
    #
    # A reboot must never silently reuse an old host-session ID.
    # --------------------------------------------------------

    $hostSessionFile = Join-Path `
        "$Script:BenchRoot\registry\host-sessions\$($suite.target.host_session_ref)" `
        "host-session.json"

    # Read both the parsed object and the raw JSON text.
    #
    # PowerShell 7 can automatically deserialize ISO-8601 JSON date
    # strings into System.DateTime. Casting that DateTime back to
    # [string] discards the original trailing Z/offset. On a non-UTC
    # host, reparsing that culture-formatted string as DateTimeOffset
    # can shift the instant by the local UTC offset and falsely classify
    # the current boot as a different host session.
    #
    # The raw JSON token is authoritative for boot-session identity.
    $hostSessionRaw =
        Get-Content `
            -Path $hostSessionFile `
            -Raw

    $hostSession =
        $hostSessionRaw |
        ConvertFrom-Json

    $os = Get-CimInstance Win32_OperatingSystem

    if ($null -eq $os.LastBootUpTime) {
        throw "Unable to determine current Windows boot time."
    }

    $currentBootUtc =
        $os.LastBootUpTime.ToUniversalTime()

    try {

        $bootTokenMatch =
            [regex]::Match(
                $hostSessionRaw,
                '"boot_time_utc"\s*:\s*"([^"]+)"'
            )

        if (-not $bootTokenMatch.Success) {
            throw "boot_time_utc JSON token not found."
        }

        $recordedBootToken =
            $bootTokenMatch.Groups[1].Value

        $recordedBootUtc =
            [datetimeoffset]::Parse(
                $recordedBootToken,
                [System.Globalization.CultureInfo]::InvariantCulture
            ).UtcDateTime
    }
    catch {

        throw (
            "Host-session record contains an invalid boot_time_utc. " +
            $_.Exception.Message
        )
    }

    $bootDifferenceSeconds =
        [math]::Abs(
            (
                $currentBootUtc -
                $recordedBootUtc
            ).TotalSeconds
        )

    if ($bootDifferenceSeconds -gt 2) {

        throw (
            "Host-session identity is stale after a reboot. " +
            "Rebind machine/environment/host-session identity before benchmarking."
        )
    }

    # --------------------------------------------------------
    # BACKEND EXECUTABLE IDENTITY
    # --------------------------------------------------------

    $currentExecutableHash =
        Get-Sha256 $Script:Llama

    $registryExecutableHash =
        [string]$backend.identity.executable.sha256

    if (
        $currentExecutableHash -ne
        $registryExecutableHash.ToLowerInvariant()
    ) {
        throw (
            "llama.exe SHA256 no longer matches the backend registry. " +
            "Create a new backend identity before benchmarking."
        )
    }

    # --------------------------------------------------------
    # MODEL ARTIFACT BINDING
    #
    # The full GGUF hash was frozen when the artifact registry
    # was created. Rehashing a 5 GiB model before every run is
    # intentionally avoided; path and size are checked here and
    # the exact artifact SHA256 is preserved in every run.
    # --------------------------------------------------------

    $artifactRef =
        [string]$suite.target.model_artifact_ref

    if (-not $artifactRef.StartsWith("sha256:")) {
        throw "Unsupported model artifact identity: $artifactRef"
    }

    $artifactHash =
        $artifactRef.Substring(7).ToLowerInvariant()

    $artifactFolder =
        "sha256-" + $artifactHash

    $artifactFile = Join-Path `
        "$Script:BenchRoot\registry\model-artifacts\$artifactFolder" `
        "artifact.json"

    $artifact = Read-JsonFile $artifactFile

    if (
        ([string]$artifact.sha256).ToLowerInvariant() -ne
        $artifactHash
    ) {
        throw "Model artifact registry hash mismatch."
    }

    $modelItem = Get-Item $Script:Model

    if (
        [uint64]$modelItem.Length -ne
        [uint64]$artifact.size_bytes
    ) {
        throw (
            "Model file size differs from the frozen model artifact. " +
            "Do not benchmark until the artifact identity is rebuilt."
        )
    }

    if (
        $artifact.source_path -and
        [string]$artifact.source_path -ne
        $Script:Model
    ) {
        throw "Model artifact source path differs from the configured harness model path."
    }

    return [pscustomobject][ordered]@{

        suite =
            $suite

        backend =
            $backend

        methodology =
            $methodology

        methodology_sha256 =
            $methodologyHash

        experiment =
            $experiment

        experiment_file =
            $experimentFile

        host_session =
            $hostSession

        host_session_file =
            $hostSessionFile

        model_artifact =
            $artifact

        model_artifact_file =
            $artifactFile

        executable_sha256 =
            $currentExecutableHash

        current_boot_time_utc =
            $currentBootUtc.ToString("o")
    }
}


function Set-ExperimentRunReference {

    param(
        [Parameter(Mandatory = $true)]
        $Experiment,

        [Parameter(Mandatory = $true)]
        [string]$ExperimentFile,

        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    $existingRuns = @()

    if ($Experiment.PSObject.Properties["runs"]) {
        $existingRuns = @($Experiment.runs)
    }

    if ($RunId -notin $existingRuns) {
        $existingRuns += $RunId
    }

    Set-ObjectProperty `
        $Experiment `
        "runs" `
        @($existingRuns)

    Set-ObjectProperty `
        $Experiment `
        "updated_at" `
        (Get-Date).ToString("o")

    if (
        $Experiment.PSObject.Properties["status"] -and
        $Experiment.status -eq "planned"
    ) {
        $Experiment.status = "running"
    }

    Write-JsonFile `
        -Object $Experiment `
        -Path $ExperimentFile
}


function Resolve-WorkloadProfile {

    param(
        [Parameter(Mandatory = $true)]
        $Methodology,

        [string]$RequestedWorkloadId,

        [int]$RequestedPromptTokens,

        [string]$RequestedGenTokens
    )

    $profiles =
        @($Methodology.workload_profiles)

    if (
        -not
        [string]::IsNullOrWhiteSpace(
            $RequestedWorkloadId
        )
    ) {

        $matched = @(
            $profiles |
            Where-Object {
                $_.id -eq $RequestedWorkloadId
            }
        )

        if ($matched.Count -ne 1) {
            throw "Unknown methodology workload profile: $RequestedWorkloadId"
        }

        return $RequestedWorkloadId
    }

    if (
        $RequestedPromptTokens -eq 2048 -and
        $RequestedGenTokens.Trim() -eq "128"
    ) {
        return "synthetic-interactive-v1"
    }

    $normalizedGen = (
        Get-UniqueStringValues $RequestedGenTokens
    ) -join ","

    if (
        $RequestedPromptTokens -eq 0 -and
        $normalizedGen -eq "128,512,2048,8192"
    ) {
        return "decode-scaling-v1"
    }

    return "custom"
}


function Get-SweepMetadata {

    param(
        $Parameters
    )

    $dimensions = @()

    foreach (
        $definition in @(
            [pscustomobject]@{
                id = "gen_tokens"
                value = $Parameters.gen_tokens
            },
            [pscustomobject]@{
                id = "threads"
                value = $Parameters.threads
            },
            [pscustomobject]@{
                id = "gpu_layers"
                value = $Parameters.gpu_layers
            },
            [pscustomobject]@{
                id = "cpu_moe"
                value = $Parameters.cpu_moe
            }
        )
    ) {

        $values =
            Get-UniqueStringValues `
                $definition.value

        if ($values.Count -gt 1) {

            $dimensions +=
                [pscustomobject][ordered]@{
                    parameter_id =
                        $definition.id

                    requested_values =
                        @($values)
                }
        }
    }

    return [pscustomobject][ordered]@{

        invocation_mode =
            if ($dimensions.Count -gt 0) {
                "native_multi_value"
            }
            else {
                "single_configuration"
            }

        dimensions =
            @($dimensions)

        single_backend_process =
            $true

        shared_model_load =
            $true

        measurement_order =
            @()

        measurement_order_state =
            "pending"

        order_basis =
            "llama-bench output row order"
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

        [string]$RunId = "",

        [string]$EngineState = "",

        $EngineExitCode = $null,

        [string]$ParserState = "not_run",

        [string]$ParserError = "",

        [string]$HarnessState = "ok",

        [string]$HarnessError = "",

        [string]$TerminationCategory = "",

        $ProcessCompleted = $null
    )

    $status = [ordered]@{

        schema =
            $Script:StatusSchema

        run_id =
            $RunId

        state =
            $State

        message =
            $Message

        engine_state =
            $EngineState

        engine_exit_code =
            $EngineExitCode

        parser_state =
            $ParserState

        parser_error =
            $ParserError

        harness_state =
            $HarnessState

        harness_error =
            $HarnessError

        termination_category =
            $TerminationCategory

        process_completed =
            $ProcessCompleted

        worker_pid =
            $PID

        updated_at =
            (Get-Date).ToString("o")
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
        [string]$Path,

        $RequestedParameters = $null
    )

    if (-not (Test-Path $Path)) {
        throw "bench.json not found: $Path"
    }

    if ((Get-Item $Path).Length -eq 0) {
        throw "bench.json is empty."
    }

    # --------------------------------------------------------
    # NORMALIZE TOP-LEVEL JSON
    # --------------------------------------------------------

    $parsed = ConvertFrom-Json (
        Get-Content $Path -Raw
    )

    $rows = @()

    if ($parsed -is [System.Array]) {

        foreach ($item in $parsed) {
            $rows += ,$item
        }
    }
    else {

        $rows += ,$parsed
    }

    if ($rows.Count -eq 0) {
        throw "bench.json contains no benchmark rows."
    }

    # --------------------------------------------------------
    # SCALAR VALIDATOR
    # --------------------------------------------------------

    function Get-ScalarValue {

        param(
            $Value,

            [Parameter(Mandatory = $true)]
            [string]$Field,

            [Parameter(Mandatory = $true)]
            [int]$RowIndex
        )

        if ($null -eq $Value) {
            return $null
        }

        if ($Value -is [System.Array]) {

            if ($Value.Count -eq 0) {
                return $null
            }

            if ($Value.Count -eq 1) {
                return $Value[0]
            }

            throw (
                "Field '$Field' in benchmark row $RowIndex " +
                "contains multiple values: [" +
                (($Value | ForEach-Object { "$_" }) -join ", ") +
                "]"
            )
        }

        return $Value
    }

    $measurements = @()
    $measurementOrdinal = 0

    for (
        $rowIndex = 0;
        $rowIndex -lt $rows.Count;
        $rowIndex++
    ) {

        $row = $rows[$rowIndex]

        if ($null -eq $row) {
            continue
        }

        $avgRaw = Get-ScalarValue `
            -Value $row.avg_ts `
            -Field "avg_ts" `
            -RowIndex $rowIndex

        if ($null -eq $avgRaw) {
            continue
        }

        $stdRaw = Get-ScalarValue `
            -Value $row.stddev_ts `
            -Field "stddev_ts" `
            -RowIndex $rowIndex

        $promptRaw = Get-ScalarValue `
            -Value $row.n_prompt `
            -Field "n_prompt" `
            -RowIndex $rowIndex

        $genRaw = Get-ScalarValue `
            -Value $row.n_gen `
            -Field "n_gen" `
            -RowIndex $rowIndex

        $batchRaw = Get-ScalarValue `
            -Value $row.n_batch `
            -Field "n_batch" `
            -RowIndex $rowIndex

        $ubatchRaw = Get-ScalarValue `
            -Value $row.n_ubatch `
            -Field "n_ubatch" `
            -RowIndex $rowIndex

        $threadsRaw = Get-ScalarValue `
            -Value $row.n_threads `
            -Field "n_threads" `
            -RowIndex $rowIndex

        $gpuLayersRaw = Get-ScalarValue `
            -Value $row.n_gpu_layers `
            -Field "n_gpu_layers" `
            -RowIndex $rowIndex

        $cpuMoeRaw = Get-ScalarValue `
            -Value $row.n_cpu_moe `
            -Field "n_cpu_moe" `
            -RowIndex $rowIndex

        $nPrompt = 0
        $nGen = 0

        if ($null -ne $promptRaw) {
            $nPrompt = [int64]$promptRaw
        }

        if ($null -ne $genRaw) {
            $nGen = [int64]$genRaw
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

        $stdValue = $null

        if ($null -ne $stdRaw) {

            $stdValue = [math]::Round(
                [double]$stdRaw,
                4
            )
        }

        $measurementOrdinal++

        $measurementId =
            "measurement-" +
            $measurementOrdinal.ToString("D4")

        $samplesTs = @($row.samples_ts)
        $samplesNs = @($row.samples_ns)

        $sampleCount = [math]::Max(
            $samplesTs.Count,
            $samplesNs.Count
        )

        $repetitionSamples = @()

        for (
            $sampleIndex = 0;
            $sampleIndex -lt $sampleCount;
            $sampleIndex++
        ) {

            $sampleTs = $null
            $sampleNs = $null

            if ($sampleIndex -lt $samplesTs.Count) {
                $sampleTs = $samplesTs[$sampleIndex]
            }

            if ($sampleIndex -lt $samplesNs.Count) {
                $sampleNs = $samplesNs[$sampleIndex]
            }

            $repetitionSamples +=
                [pscustomobject][ordered]@{

                    repetition =
                        $sampleIndex + 1

                    tokens_per_second =
                        $sampleTs

                    nanoseconds =
                        $sampleNs
                }
        }

        $requestedSnapshot = [ordered]@{}

        if ($null -ne $RequestedParameters) {

            $requestedSnapshot = [ordered]@{

                prompt_tokens =
                    $RequestedParameters.prompt_tokens

                gen_tokens =
                    $RequestedParameters.gen_tokens

                repetitions =
                    $RequestedParameters.repetitions

                batch =
                    $RequestedParameters.batch

                ubatch =
                    $RequestedParameters.ubatch

                threads =
                    $RequestedParameters.threads

                gpu_layers =
                    $RequestedParameters.gpu_layers

                cpu_moe =
                    $RequestedParameters.cpu_moe

                cpu_mask =
                    $RequestedParameters.cpu_mask

                cpu_strict =
                    $RequestedParameters.cpu_strict

                poll =
                    $RequestedParameters.poll

                kv_k =
                    $RequestedParameters.kv_k

                kv_v =
                    $RequestedParameters.kv_v

                flash_attention =
                    $RequestedParameters.flash_attention

                device =
                    $RequestedParameters.device

                load_mode =
                    $RequestedParameters.load_mode

                no_kv_offload =
                    $RequestedParameters.no_kv_offload

                no_op_offload =
                    $RequestedParameters.no_op_offload

                no_host =
                    $RequestedParameters.no_host

                numa =
                    $RequestedParameters.numa
            }
        }

        $resolvedSnapshot = [ordered]@{

            n_prompt =
                $nPrompt

            n_gen =
                $nGen

            n_batch =
                $batchRaw

            n_ubatch =
                $ubatchRaw

            n_threads =
                $threadsRaw

            n_gpu_layers =
                $gpuLayersRaw

            n_cpu_moe =
                $cpuMoeRaw

            cpu_mask =
                $row.cpu_mask

            cpu_strict =
                $row.cpu_strict

            poll =
                $row.poll

            type_k =
                $row.type_k

            type_v =
                $row.type_v

            flash_attn =
                $row.flash_attn

            no_kv_offload =
                $row.no_kv_offload

            no_op_offload =
                $row.no_op_offload

            no_host =
                $row.no_host

            split_mode =
                $row.split_mode

            main_gpu =
                $row.main_gpu

            devices =
                $row.devices
        }

        $observedSnapshot = [ordered]@{

            backends =
                $row.backends

            build_commit =
                $row.build_commit

            build_number =
                $row.build_number

            cpu_info =
                $row.cpu_info

            gpu_info =
                $row.gpu_info

            model_filename =
                $row.model_filename

            model_type =
                $row.model_type

            model_size =
                $row.model_size

            model_n_params =
                $row.model_n_params

            test_time =
                $row.test_time
        }

        $measurement = [pscustomobject][ordered]@{

            measurement_id =
                $measurementId

            order_index =
                $measurementOrdinal - 1

            source_row_index =
                $rowIndex

            kind =
                $kind

            requested =
                [pscustomobject]$requestedSnapshot

            resolved =
                [pscustomobject]$resolvedSnapshot

            observed =
                [pscustomobject]$observedSnapshot

            performance = [pscustomobject][ordered]@{

                avg_tokens_per_second =
                    [math]::Round(
                        [double]$avgRaw,
                        4
                    )

                stddev_tokens_per_second =
                    $stdValue

                avg_nanoseconds =
                    $row.avg_ns

                stddev_nanoseconds =
                    $row.stddev_ns
            }

            repetitions =
                @($repetitionSamples)

            repetition_count =
                $repetitionSamples.Count

            # ------------------------------------------------
            # Compatibility fields retained for show/repair and
            # historical analysis code.
            # ------------------------------------------------

            row_index =
                $rowIndex

            n_prompt =
                $nPrompt

            n_gen =
                $nGen

            avg_ts =
                [math]::Round(
                    [double]$avgRaw,
                    4
                )

            stddev_ts =
                $stdValue

            avg_ns =
                $row.avg_ns

            stddev_ns =
                $row.stddev_ns

            n_batch =
                $batchRaw

            n_ubatch =
                $ubatchRaw

            n_threads =
                $threadsRaw

            n_gpu_layers =
                $gpuLayersRaw

            n_cpu_moe =
                $cpuMoeRaw

            cpu_mask =
                $row.cpu_mask

            cpu_strict =
                $row.cpu_strict

            poll =
                $row.poll

            type_k =
                $row.type_k

            type_v =
                $row.type_v

            flash_attn =
                $row.flash_attn

            no_kv_offload =
                $row.no_kv_offload

            no_op_offload =
                $row.no_op_offload

            no_host =
                $row.no_host

            split_mode =
                $row.split_mode

            main_gpu =
                $row.main_gpu

            devices =
                $row.devices

            backends =
                $row.backends

            build_commit =
                $row.build_commit

            build_number =
                $row.build_number

            cpu_info =
                $row.cpu_info

            gpu_info =
                $row.gpu_info

            model_filename =
                $row.model_filename

            model_type =
                $row.model_type

            model_size =
                $row.model_size

            model_n_params =
                $row.model_n_params

            test_time =
                $row.test_time

            samples_ts =
                @($samplesTs)

            samples_ns =
                @($samplesNs)
        }

        $measurements += $measurement
    }

    if ($measurements.Count -eq 0) {

        throw (
            "llama-bench completed, but no rows containing " +
            "avg_ts could be parsed."
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

        initial_gpu_free_mib =
            $null

        full_gpu_offload =
            $null

        offloaded_layers =
            $null

        total_layers =
            $null

        cpu_mapped_model_mib =
            $null

        gpu_model_mib =
            $null

        gpu_kv_mib =
            $null

        host_kv_mib =
            $null

        gpu_recurrent_mib =
            $null

        gpu_compute_mib =
            $null

        host_compute_mib =
            $null

        snapshot_count =
            0

        context_snapshots =
            @()

        linkage = [ordered]@{

            state =
                "not_attempted"

            method =
                "measurement_id_assigned_from_context_creation_order"

            linked_snapshot_count =
                0

            measurement_count =
                0

            note = (
                "Post-architecture snapshots receive explicit measurement IDs. " +
                "The current llama-bench log does not emit those IDs itself, " +
                "so correspondence is established from context creation order " +
                "and then persisted explicitly."
            )
        }

        pinned_memory_failure =
            $false

        allocation_failure =
            $false

        gpu_fallback =
            $false

        partial_offload =
            $null

        summary_mode =
            "max_across_contexts"

        raw_lines =
            @()
    }

    if (-not (Test-Path $Path)) {
        return [pscustomobject]$summary
    }

    $allLines = @(Get-Content $Path)

    $hasExplicitContextMarkers = (
        @(
            $allLines |
            Where-Object {
                $_ -match
                    'llama_context.*construct|constructing llama_context'
            }
        ).Count -gt 0
    )

    $interesting = @()
    $snapshots = @()
    $current = $null

    function New-MemorySnapshot {

        param(
            [int]$Index
        )

        return [ordered]@{

            index =
                $Index

            measurement_id =
                $null

            measurement_order_index =
                $null

            linkage_state =
                "unlinked"

            gpu_kv_mib =
                $null

            host_kv_mib =
                $null

            gpu_recurrent_mib =
                $null

            gpu_compute_mib =
                $null

            host_compute_mib =
                $null
        }
    }
    foreach ($line in $allLines) {

        $isInteresting = (
            $line -match
                'llama_context.*construct|constructing llama_context|buffer size|KV self size|compute buffer|offloaded|MiB free|GiB free|OutOfDeviceMemory|pinned memory|allocation failed'
        )

        if ($isInteresting) {
            $interesting += $line
        }

        # ----------------------------------------------------
        # EXPLICIT CONTEXT START
        # ----------------------------------------------------

        if (
            $hasExplicitContextMarkers -and
            $line -match
                'llama_context.*construct|constructing llama_context'
        ) {

            if ($null -ne $current) {
                $snapshots += [pscustomobject]$current
            }

            $current =
                New-MemorySnapshot `
                    -Index $snapshots.Count

            continue
        }

        # ----------------------------------------------------
        # GLOBAL MODEL / DEVICE DATA
        # ----------------------------------------------------

        if (
            $line -match
                '(\d+(?:\.\d+)?)\s+MiB free'
        ) {
            $summary.initial_gpu_free_mib =
                [double]$Matches[1]
        }

        if (
            $line -match
                'offloaded\s+(\d+)/(\d+)\s+layers to GPU'
        ) {

            $summary.offloaded_layers =
                [int]$Matches[1]

            $summary.total_layers =
                [int]$Matches[2]

            $summary.full_gpu_offload = (
                $summary.offloaded_layers -eq
                $summary.total_layers
            )

            $summary.partial_offload = (
                $summary.offloaded_layers -gt 0 -and
                $summary.offloaded_layers -lt
                $summary.total_layers
            )
        }

        if (
            $line -match
                'CPU_Mapped model buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.cpu_mapped_model_mib =
                [double]$Matches[1]
        }

        if (
            $line -match
                'Vulkan\d+ model buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {
            $summary.gpu_model_mib =
                [double]$Matches[1]
        }

        # ----------------------------------------------------
        # GPU KV BUFFER
        # ----------------------------------------------------

        if (
            $line -match
                'Vulkan\d+ KV buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {

            if ($null -eq $current) {

                $current =
                    New-MemorySnapshot `
                        -Index $snapshots.Count
            }
            elseif (
                -not $hasExplicitContextMarkers -and
                $null -ne $current.gpu_kv_mib
            ) {

                $snapshots +=
                    [pscustomobject]$current

                $current =
                    New-MemorySnapshot `
                        -Index $snapshots.Count
            }

            $current.gpu_kv_mib =
                [double]$Matches[1]

            continue
        }

        # ----------------------------------------------------
        # HOST / CPU KV BUFFER
        # ----------------------------------------------------

        if (
            $line -match
                '(?:CPU|CPU_Mapped|Vulkan_Host) KV buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {

            if ($null -eq $current) {

                $current =
                    New-MemorySnapshot `
                        -Index $snapshots.Count
            }
            elseif (
                -not $hasExplicitContextMarkers -and
                $null -ne $current.host_kv_mib
            ) {

                $snapshots +=
                    [pscustomobject]$current

                $current =
                    New-MemorySnapshot `
                        -Index $snapshots.Count
            }

            $current.host_kv_mib =
                [double]$Matches[1]

            continue
        }

        if (
            $null -ne $current -and
            $line -match
                'Vulkan\d+ RS buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {

            $current.gpu_recurrent_mib =
                [double]$Matches[1]

            continue
        }

        # Only sched_reserve lines are treated as allocation
        # events. Destructor lines are intentionally ignored.

        if (
            $null -ne $current -and
            $line -match
                '^sched_reserve:\s+Vulkan\d+ compute buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {

            $current.gpu_compute_mib =
                [double]$Matches[1]

            continue
        }

        if (
            $null -ne $current -and
            $line -match
                '^sched_reserve:\s+(?:Vulkan_Host|CPU(?:_Mapped)?) compute buffer size\s*=\s*([\d.]+)\s+MiB'
        ) {

            $current.host_compute_mib =
                [double]$Matches[1]

            if (-not $hasExplicitContextMarkers) {

                $snapshots +=
                    [pscustomobject]$current

                $current =
                    $null
            }

            continue
        }

        # ----------------------------------------------------
        # FAILURE / FALLBACK FLAGS
        # ----------------------------------------------------

        if (
            $line -match
                'Failed to allocate pinned memory'
        ) {
            $summary.pinned_memory_failure =
                $true
        }

        if (
            $line -match
                'OutOfDeviceMemory|allocation failed'
        ) {
            $summary.allocation_failure =
                $true
        }
    }

    if ($null -ne $current) {
        $snapshots += [pscustomobject]$current
    }

    for (
        $i = 0;
        $i -lt $snapshots.Count;
        $i++
    ) {
        $snapshots[$i].index = $i
    }

    $summary.raw_lines =
        @($interesting)

    $summary.context_snapshots =
        @($snapshots)

    $summary.snapshot_count =
        $snapshots.Count

    # --------------------------------------------------------
    # MAXIMUM SUMMARY VALUES
    # --------------------------------------------------------

    foreach (
        $definition in @(
            [pscustomobject]@{
                source = "gpu_kv_mib"
                target = "gpu_kv_mib"
            },
            [pscustomobject]@{
                source = "host_kv_mib"
                target = "host_kv_mib"
            },
            [pscustomobject]@{
                source = "gpu_recurrent_mib"
                target = "gpu_recurrent_mib"
            },
            [pscustomobject]@{
                source = "gpu_compute_mib"
                target = "gpu_compute_mib"
            },
            [pscustomobject]@{
                source = "host_compute_mib"
                target = "host_compute_mib"
            }
        )
    ) {

        $values = @(
            $snapshots |
            ForEach-Object {

                $value =
                    $_.PSObject.Properties[
                        $definition.source
                    ].Value

                if ($null -ne $value) {
                    [double]$value
                }
            }
        )

        if ($values.Count -gt 0) {

            $maximum = (
                $values |
                Measure-Object -Maximum
            ).Maximum

            $summary[
                $definition.target
            ] = $maximum
        }
    }

    $summary.gpu_fallback = (
        $summary.pinned_memory_failure -or
        $summary.allocation_failure
    )

    return [pscustomobject]$summary
}


function Link-MemorySnapshotsToMeasurements {

    param(
        [Parameter(Mandatory = $true)]
        $Memory,

        [Parameter(Mandatory = $true)]
        [array]$Measurements
    )

    $snapshots =
        @($Memory.context_snapshots)

    $measurementCount =
        $Measurements.Count

    $snapshotCount =
        $snapshots.Count

    $linkCount =
        [math]::Min(
            $measurementCount,
            $snapshotCount
        )

    for (
        $i = 0;
        $i -lt $linkCount;
        $i++
    ) {

        Set-ObjectProperty `
            $snapshots[$i] `
            "measurement_id" `
            $Measurements[$i].measurement_id

        Set-ObjectProperty `
            $snapshots[$i] `
            "measurement_order_index" `
            $Measurements[$i].order_index

        Set-ObjectProperty `
            $snapshots[$i] `
            "linkage_state" `
            "linked_by_context_order"
    }

    for (
        $i = $linkCount;
        $i -lt $snapshotCount;
        $i++
    ) {

        Set-ObjectProperty `
            $snapshots[$i] `
            "linkage_state" `
            "unmatched_snapshot"
    }

    $Memory.context_snapshots =
        @($snapshots)

    $Memory.linkage = [pscustomobject][ordered]@{

        state =
            if (
                $measurementCount -eq
                    $snapshotCount -and
                $measurementCount -gt 0
            ) {
                "complete"
            }
            elseif (
                $measurementCount -eq 0 -and
                $snapshotCount -eq 0
            ) {
                "not_applicable"
            }
            else {
                "partial"
            }

        method =
            "measurement_id_assigned_from_context_creation_order"

        linked_snapshot_count =
            $linkCount

        measurement_count =
            $measurementCount

        snapshot_count =
            $snapshotCount

        unmatched_measurements =
            [math]::Max(
                0,
                $measurementCount -
                $snapshotCount
            )

        unmatched_snapshots =
            [math]::Max(
                0,
                $snapshotCount -
                $measurementCount
            )

        note = (
            "Every linked snapshot now carries an explicit measurement_id. " +
            "The linkage basis is preserved rather than implied."
        )
    }

    return $Memory
}


function Get-ExecutionAssessment {

    param(
        $Run,
        $Memory,
        [string]$ParserState
    )

    $engineState =
        [string]$Run.result.engine_state

    $processCompleted =
        $false

    if (
        $Run.result.PSObject.Properties[
            "process_completed"
        ]
    ) {
        $processCompleted =
            [bool]$Run.result.process_completed
    }

    $cleanExecution =
        $null

    if ($processCompleted) {

        $cleanExecution = (
            $engineState -eq "complete" -and
            $ParserState -eq "complete" -and
            -not $Memory.pinned_memory_failure -and
            -not $Memory.allocation_failure -and
            -not $Memory.gpu_fallback
        )
    }

    $placementState =
        "unknown"

    if ($null -ne $Memory.full_gpu_offload) {

        if ($Memory.full_gpu_offload) {
            $placementState = "full_gpu_offload"
        }
        elseif (
            $null -ne $Memory.offloaded_layers -and
            [int]$Memory.offloaded_layers -eq 0
        ) {
            $placementState = "cpu_only"
        }
        elseif ($Memory.partial_offload) {
            $placementState = "partial_gpu_offload"
        }
        else {
            $placementState = "non_full_gpu_offload"
        }
    }

    return [pscustomobject][ordered]@{

        clean_execution =
            $cleanExecution

        clean_winner_eligible =
            ($cleanExecution -eq $true)

        fallback_detected =
            [bool]$Memory.gpu_fallback

        pinned_memory_failure =
            [bool]$Memory.pinned_memory_failure

        allocation_failure =
            [bool]$Memory.allocation_failure

        placement_state =
            $placementState

        full_gpu_offload =
            $Memory.full_gpu_offload

        partial_offload =
            $Memory.partial_offload

        interpretation = (
            "Intentional partial placement is not automatically a fallback. " +
            "Winner eligibility requires normal engine completion, successful parsing, " +
            "and no detected allocation/pinned-memory fallback."
        )
    }
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

    $runFile =
        Join-Path $RunDirectory "run.json"

    $benchFile =
        Join-Path $RunDirectory "bench.json"

    $benchErr =
        Join-Path $RunDirectory "bench-stderr.log"

    if (-not (Test-Path $benchErr)) {

        # Legacy runs used other stderr names.
        $candidate =
            Get-ChildItem `
                $RunDirectory `
                -File `
                -Filter "*stderr*.log" `
                -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($candidate) {
            $benchErr = $candidate.FullName
        }
    }

    $run =
        Read-JsonFile $runFile

    if (
        $null -eq
        $run.PSObject.Properties["result"]
    ) {

        $run |
            Add-Member `
                -NotePropertyName "result" `
                -NotePropertyValue ([pscustomobject]@{})
    }

    $requestedParameters = $null

    if (
        $run.PSObject.Properties["configuration"] -and
        $run.configuration.PSObject.Properties["requested"] -and
        $run.configuration.requested.PSObject.Properties["parameters"]
    ) {
        $requestedParameters =
            $run.configuration.requested.parameters
    }
    elseif (
        $run.PSObject.Properties["parameters"]
    ) {
        $requestedParameters =
            $run.parameters
    }

    $parserState =
        "not_run"

    $parserError =
        ""

    $measurements =
        @()

    try {

        $measurements = @(
            Parse-BenchJson `
                -Path $benchFile `
                -RequestedParameters $requestedParameters
        )

        $parserState =
            "complete"
    }
    catch {

        $parserState =
            "parser_error"

        $parserError = (
            $_.Exception.Message +
            "`n" +
            $_.ScriptStackTrace
        )
    }

    $memory =
        Parse-MemoryLog $benchErr

    if ($parserState -eq "complete") {

        $memory =
            Link-MemorySnapshotsToMeasurements `
                -Memory $memory `
                -Measurements $measurements
    }

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
        @($measurements)

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

    if (
        $run.PSObject.Properties["configuration"]
    ) {

        $resolvedMeasurementSets = @(
            $measurements |
            ForEach-Object {

                [pscustomobject][ordered]@{

                    measurement_id =
                        $_.measurement_id

                    order_index =
                        $_.order_index

                    parameters =
                        $_.resolved
                }
            }
        )

        $observedMeasurementSets = @(
            $measurements |
            ForEach-Object {

                [pscustomobject][ordered]@{

                    measurement_id =
                        $_.measurement_id

                    order_index =
                        $_.order_index

                    runtime =
                        $_.observed
                }
            }
        )

        $run.configuration.resolved =
            [pscustomobject][ordered]@{

                state =
                    if ($parserState -eq "complete") {
                        "complete"
                    }
                    else {
                        "unavailable_due_to_parser_error"
                    }

                measurements =
                    @($resolvedMeasurementSets)
            }

        $run.configuration.observed =
            [pscustomobject][ordered]@{

                state =
                    if ($parserState -eq "complete") {
                        "complete"
                    }
                    else {
                        "partial"
                    }

                measurements =
                    @($observedMeasurementSets)

                memory =
                    $memory
            }
    }

    if (
        $run.PSObject.Properties["execution"]
    ) {

        $measurementOrder = @(
            $measurements |
            Sort-Object order_index |
            ForEach-Object {
                $_.measurement_id
            }
        )

        if (
            $run.execution.PSObject.Properties[
                "process_reuse"
            ]
        ) {

            $measurementOrderState =
                if ($parserState -eq "complete") {
                    "recorded"
                }
                else {
                    "unavailable_due_to_parser_error"
                }

            Set-ObjectProperty `
                $run.execution.process_reuse `
                "measurement_order" `
                @($measurementOrder)

            Set-ObjectProperty `
                $run.execution.process_reuse `
                "measurement_order_state" `
                $measurementOrderState
        }

        Set-ObjectProperty `
            $run.execution `
            "measurement_count" `
            $measurements.Count
    }

    $rawRepetitionsPreserved =
        $false

    if (
        $parserState -eq "complete" -and
        $measurements.Count -gt 0
    ) {

        $missingSamples = @(
            $measurements |
            Where-Object {
                $_.repetition_count -le 0
            }
        )

        $rawRepetitionsPreserved =
            ($missingSamples.Count -eq 0)
    }

    Set-ObjectProperty `
        $run.result `
        "raw_repetitions_preserved" `
        $rawRepetitionsPreserved

    $executionAssessment =
        Get-ExecutionAssessment `
            -Run $run `
            -Memory $memory `
            -ParserState $parserState

    Set-ObjectProperty `
        $run.result `
        "execution_assessment" `
        $executionAssessment

    Set-ObjectProperty `
        $run.result `
        "clean_execution" `
        $executionAssessment.clean_execution

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

    Set-ObjectProperty `
        $run `
        "updated_at" `
        (Get-Date).ToString("o")

    Write-JsonFile `
        -Object $run `
        -Path $runFile

    return [pscustomobject][ordered]@{

        run =
            $run

        parser_state =
            $parserState

        parser_error =
            $parserError

        measurements =
            @($measurements)

        memory =
            $memory

        execution_assessment =
            $executionAssessment
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

    # --------------------------------------------------------
    # ENFORCE POST-ARCHITECTURE CONTRACT BEFORE CREATING RUN
    # --------------------------------------------------------

    $contract =
        Get-BenchmarkContract `
            -RequestedExperimentId $ExperimentId

    $runsRoot =
        Join-Path $Script:BenchRoot "runs"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $runsRoot |
        Out-Null

    $safeName = (
        $Name -replace
        '[^A-Za-z0-9._-]',
        '-'
    ).Trim("-")

    if (-not $safeName) {
        $safeName = "manual"
    }

    $timestamp =
        Get-Date -Format "yyyyMMdd-HHmmss"

    $shortId =
        ([guid]::NewGuid().ToString("N")).Substring(0, 8)

    $runId =
        "run-" +
        $timestamp +
        "-" +
        $safeName +
        "-" +
        $shortId

    $runDirectory =
        Join-Path `
            $runsRoot `
            $runId

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $runDirectory |
        Out-Null

    $statusFile =
        Join-Path $runDirectory "status.json"

    $runFile =
        Join-Path $runDirectory "run.json"

    $benchFile =
        Join-Path $runDirectory "bench.json"

    $benchErr =
        Join-Path $runDirectory "bench-stderr.log"

    $workerOut =
        Join-Path $runDirectory "worker-out.log"

    $workerErr =
        Join-Path $runDirectory "worker-err.log"

    $systemHash = $null

    if (Test-Path $Script:SystemProfile) {

        $systemHash =
            Get-Sha256 $Script:SystemProfile
    }

    $harnessHash =
        Get-Sha256 $PSCommandPath

    $parameters = [ordered]@{

        prompt_tokens =
            $PromptTokens

        gen_tokens =
            $GenTokens

        repetitions =
            $Repetitions

        batch =
            $Batch

        ubatch =
            $UBatch

        threads =
            $Threads

        gpu_layers =
            $GpuLayers

        cpu_moe =
            $CpuMoe

        cpu_mask =
            $CpuMask

        cpu_strict =
            $CpuStrict

        poll =
            $Poll

        kv_k =
            $KvK

        kv_v =
            $KvV

        flash_attention =
            $FlashAttention

        device =
            $Device

        load_mode =
            $LoadMode

        no_kv_offload =
            $NoKvOffload

        no_op_offload =
            $NoOpOffload

        no_host =
            $NoHost

        numa =
            $Numa

        verbose =
            [bool]$VerboseBench
    }

    $parameterObject =
        [pscustomobject]$parameters

    $argumentPreview =
        Build-LlamaArguments `
            $parameterObject

    $resolvedWorkloadId =
        Resolve-WorkloadProfile `
            -Methodology $contract.methodology `
            -RequestedWorkloadId $WorkloadId `
            -RequestedPromptTokens $PromptTokens `
            -RequestedGenTokens $GenTokens

    $sweepMetadata =
        Get-SweepMetadata `
            $parameterObject

    $createdAt =
        (Get-Date).ToString("o")

    $frozenHarnessHash = $null

    if (
        $contract.methodology.tooling_provenance -and
        $contract.methodology.tooling_provenance.benchmark_harness
    ) {
        $frozenHarnessHash =
            $contract.methodology.tooling_provenance.benchmark_harness.sha256
    }

    $run = [ordered]@{

        schema =
            $Script:RunSchema

        id =
            $runId

        created_at =
            $createdAt

        updated_at =
            $createdAt

        status =
            "queued"

        name =
            $safeName

        references = [ordered]@{

            suite_ref =
                $contract.suite.id

            methodology_ref =
                $contract.methodology.id

            methodology_sha256 =
                $contract.methodology_sha256

            experiment_ref =
                $contract.experiment.id

            machine_ref =
                $contract.suite.target.machine_ref

            environment_ref =
                $contract.suite.target.environment_ref

            host_session_ref =
                $contract.suite.target.host_session_ref

            backend_ref =
                $contract.backend.id

            model_ref =
                $contract.suite.target.model_ref

            model_artifact_ref =
                $contract.suite.target.model_artifact_ref
        }

        provenance = [ordered]@{

            harness = [ordered]@{

                path =
                    $PSCommandPath

                sha256 =
                    $harnessHash

                phase0_frozen_harness_sha256 =
                    $frozenHarnessHash

                enforcement_generation =
                    "phase0-integrated-v1"
            }

            methodology = [ordered]@{

                id =
                    $contract.methodology.id

                path =
                    $Script:MethodologyFile

                sha256 =
                    $contract.methodology_sha256

                state =
                    "frozen"
            }

            backend = [ordered]@{

                id =
                    $contract.backend.id

                executable =
                    $Script:Llama

                executable_sha256 =
                    $contract.executable_sha256

                commit =
                    $contract.backend.identity.commit

                build_number =
                    $contract.backend.identity.build_number
            }

            model_artifact = [ordered]@{

                id =
                    $contract.suite.target.model_artifact_ref

                registry_path =
                    $contract.model_artifact_file

                source_path =
                    $Script:Model

                size_bytes =
                    [uint64]$contract.model_artifact.size_bytes

                sha256 =
                    ([string]$contract.model_artifact.sha256).ToLowerInvariant()

                verification_this_run = [ordered]@{

                    path_checked =
                        $true

                    size_checked =
                        $true

                    full_hash_recomputed =
                        $false

                    reason = (
                        "Exact artifact hash was frozen in the artifact registry; " +
                        "5 GiB GGUF is not rehashed before every run."
                    )
                }
            }

            host = [ordered]@{

                current_boot_time_utc =
                    $contract.current_boot_time_utc

                host_session_record =
                    $contract.host_session_file
            }

            system_profile_legacy = [ordered]@{

                path =
                    $Script:SystemProfile

                sha256 =
                    $systemHash
            }
        }

        configuration = [ordered]@{

            requested = [ordered]@{

                workload_profile_ref =
                    $resolvedWorkloadId

                parameters =
                    $parameters

                exact_arguments =
                    @($argumentPreview)

                source =
                    "harness_cli"
            }

            resolved = [ordered]@{

                state =
                    "pending"

                measurements =
                    @()
            }

            observed = [ordered]@{

                state =
                    "pending"

                measurements =
                    @()

                memory =
                    $null
            }
        }

        execution = [ordered]@{

            workload_profile_ref =
                $resolvedWorkloadId

            methodology_default_repetitions =
                $contract.methodology.synthetic_engine.default_repetitions

            repetitions_requested =
                $Repetitions

            warmup_policy =
                $contract.methodology.synthetic_engine.warmup

            cache_state =
                "not_applicable"

            process_reuse =
                $sweepMetadata

            measurement_count =
                0

            started_at =
                $null

            completed_at =
                $null

            worker_pid =
                $null
        }

        files = [ordered]@{

            run_json =
                $runFile

            status_json =
                $statusFile

            bench_json =
                $benchFile

            bench_stderr =
                $benchErr

            worker_stdout =
                $workerOut

            worker_stderr =
                $workerErr

            brain_restore_error =
                (
                    Join-Path `
                        $runDirectory `
                        "brain-restore-error.log"
                )
        }

        result = [ordered]@{

            engine_state =
                "queued"

            engine_exit_code =
                $null

            parser_state =
                "not_run"

            parser_error =
                ""

            harness_state =
                "ready"

            harness_error =
                ""

            process_completed =
                $false

            bridge_timeout =
                $null

            wall_seconds =
                $null

            gpu_fallback =
                $null

            clean_execution =
                $null

            raw_repetitions_preserved =
                $false

            measurements =
                @()

            memory =
                $null

            execution_assessment =
                $null

            termination = [ordered]@{

                category =
                    $null

                observed_at =
                    $null

                evidence_state =
                    "pending"

                root_cause =
                    "not_assessed"

                notes =
                    @()
            }

            brain_restore = [ordered]@{

                state =
                    "pending"

                error =
                    ""

                completed_at =
                    $null
            }
        }

        # ----------------------------------------------------
        # LEGACY COMPATIBILITY
        #
        # Historical tools can still read these fields while
        # configuration.requested is authoritative for v3.
        # ----------------------------------------------------

        backend_profile = [ordered]@{

            id =
                $Script:BackendProfileId

            family =
                "llama.cpp"

            backend =
                "Vulkan"
        }

        system_profile = [ordered]@{

            path =
                $Script:SystemProfile

            sha256 =
                $systemHash
        }

        harness = [ordered]@{

            path =
                $PSCommandPath

            sha256 =
                $harnessHash
        }

        executable =
            $Script:Llama

        model =
            $Script:Model

        parameters =
            $parameters

        exact_arguments =
            @($argumentPreview)
    }

    Write-JsonFile `
        -Object $run `
        -Path $runFile

    Write-RunStatus `
        -Path $statusFile `
        -State "queued" `
        -Message "Benchmark queued." `
        -RunId $runId `
        -EngineState "queued" `
        -EngineExitCode $null `
        -ParserState "not_run" `
        -HarnessState "ready" `
        -TerminationCategory "" `
        -ProcessCompleted $false

    # Link the immutable run identity into its primary
    # scientific Experiment before the detached worker starts.
    Set-ExperimentRunReference `
        -Experiment $contract.experiment `
        -ExperimentFile $contract.experiment_file `
        -RunId $runId

    $workerHost =
        $null

    $workerCandidates = @(
        (Join-Path $PSHOME "pwsh.exe"),
        (Join-Path $PSHOME "powershell.exe")
    )

    foreach ($candidate in $workerCandidates) {

        if (Test-Path $candidate) {

            $workerHost =
                $candidate

            break
        }
    }

    if (-not $workerHost) {

        $workerHost = (
            Get-Process -Id $PID
        ).Path
    }

    if (-not $workerHost) {
        throw "Could not resolve PowerShell executable for benchmark worker."
    }

    try {

        $process =
            Start-Process `
                -FilePath $workerHost `
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

        $run =
            Read-JsonFile $runFile

        $run.execution.worker_pid =
            $process.Id

        $run.updated_at =
            (Get-Date).ToString("o")

        Write-JsonFile `
            -Object $run `
            -Path $runFile
    }
    catch {

        $startError = (
            $_.Exception.Message +
            "`n" +
            $_.ScriptStackTrace
        )

        $run =
            Read-JsonFile $runFile

        $run.status =
            "harness_error"

        $run.updated_at =
            (Get-Date).ToString("o")

        $run.result.harness_state =
            "error"

        $run.result.harness_error =
            $startError

        $run.result.termination.category =
            "harness_error"

        $run.result.termination.observed_at =
            (Get-Date).ToString("o")

        $run.result.termination.evidence_state =
            "confirmed"

        Write-JsonFile `
            -Object $run `
            -Path $runFile

        Write-RunStatus `
            -Path $statusFile `
            -State "harness_error" `
            -Message $_.Exception.Message `
            -RunId $runId `
            -EngineState "not_started" `
            -EngineExitCode $null `
            -ParserState "not_run" `
            -HarnessState "error" `
            -HarnessError $startError `
            -TerminationCategory "harness_error" `
            -ProcessCompleted $false

        throw
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK STARTED"
    Write-Host "============================================================"
    Write-Host "Run ID:     $runId"
    Write-Host "Runner PID: $($process.Id)"
    Write-Host "Experiment: $($contract.experiment.id)"
    Write-Host "Methodology:$($contract.methodology.id)"
    Write-Host "Workload:   $resolvedWorkloadId"
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

    $runDirectory =
        Resolve-RunPath $RunPath

    $runFile =
        Join-Path $runDirectory "run.json"

    $statusFile =
        Join-Path $runDirectory "status.json"

    $benchFile =
        Join-Path $runDirectory "bench.json"

    $benchErr =
        Join-Path $runDirectory "bench-stderr.log"

    $run =
        Read-JsonFile $runFile

    if (
        $run.schema -ne
        $Script:RunSchema
    ) {
        throw (
            "worker only launches post-architecture v3 runs. " +
            "Legacy runs remain available through show/repair."
        )
    }

    $runId =
        [string]$run.id

    # Revalidate the frozen contract inside the detached worker.
    $contract =
        Get-BenchmarkContract `
            -RequestedExperimentId $run.references.experiment_ref

    if (
        $run.references.methodology_sha256 -ne
        $contract.methodology_sha256
    ) {
        throw "Run methodology hash differs from the frozen contract."
    }

    if (
        $run.references.host_session_ref -ne
        $contract.suite.target.host_session_ref
    ) {
        throw "Run host-session reference differs from the current suite binding."
    }

    $brain =
        $null

    $brainWasRunning =
        $false

    $engineExitCode =
        $null

    $engineState =
        "not_started"

    $parserState =
        "not_run"

    $parserError =
        ""

    $wallSeconds =
        $null

    try {

        Write-RunStatus `
            -Path $statusFile `
            -State "preparing" `
            -Message "Stopping YUKI Brain." `
            -RunId $runId `
            -EngineState "not_started" `
            -EngineExitCode $null `
            -ParserState "not_run" `
            -HarnessState "running" `
            -TerminationCategory "" `
            -ProcessCompleted $false

        $brain =
            Get-CimInstance Win32_Process |
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

        $brainWasRunning =
            ($null -ne $brain)

        if ($brainWasRunning) {

            Stop-Process `
                -Id $brain.ProcessId `
                -Force

            Start-Sleep 2
        }

        $run =
            Read-JsonFile $runFile

        $run.status =
            "benchmark_running"

        $run.updated_at =
            (Get-Date).ToString("o")

        $run.execution.started_at =
            (Get-Date).ToString("o")

        $run.execution.worker_pid =
            $PID

        Set-ObjectProperty `
            $run.execution `
            "brain_was_running_before" `
            $brainWasRunning

        $run.result.engine_state =
            "running"

        $run.result.harness_state =
            "running"

        Write-JsonFile `
            -Object $run `
            -Path $runFile

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_running" `
            -Message "llama-bench is running." `
            -RunId $runId `
            -EngineState "running" `
            -EngineExitCode $null `
            -ParserState "not_run" `
            -HarnessState "running" `
            -TerminationCategory "" `
            -ProcessCompleted $false

        $arguments =
            Build-LlamaArguments `
                $run.parameters

        $sw =
            [System.Diagnostics.Stopwatch]::StartNew()

        # Non-zero llama.cpp exit codes are captured through
        # LASTEXITCODE and remain separate from parser/harness
        # failures.
        $oldPreference =
            $ErrorActionPreference

        try {

            $ErrorActionPreference =
                "Continue"

            & $Script:Llama @arguments `
                2> $benchErr |
                Set-Content `
                    -Path $benchFile `
                    -Encoding UTF8

            $engineExitCode =
                $LASTEXITCODE
        }
        finally {

            $ErrorActionPreference =
                $oldPreference
        }

        $sw.Stop()

        $wallSeconds =
            [math]::Round(
                $sw.Elapsed.TotalSeconds,
                3
            )

        if ($engineExitCode -eq 0) {
            $engineState = "complete"
        }
        else {
            $engineState = "failed"
        }

        $run =
            Read-JsonFile $runFile

        $run.updated_at =
            (Get-Date).ToString("o")

        $run.execution.completed_at =
            (Get-Date).ToString("o")

        $run.result.engine_state =
            $engineState

        $run.result.engine_exit_code =
            $engineExitCode

        $run.result.process_completed =
            $true

        $run.result.wall_seconds =
            $wallSeconds

        $run.result.termination.category =
            if ($engineExitCode -eq 0) {
                "normal"
            }
            else {
                "engine_error"
            }

        $run.result.termination.observed_at =
            (Get-Date).ToString("o")

        $run.result.termination.evidence_state =
            "confirmed"

        $run.result.termination.root_cause =
            if ($engineExitCode -eq 0) {
                "not_applicable"
            }
            else {
                "backend_nonzero_exit"
            }

        Write-JsonFile `
            -Object $run `
            -Path $runFile

        # ----------------------------------------------------
        # PARSE ONLY AFTER ENGINE COMPLETION
        # ----------------------------------------------------

        if ($engineExitCode -eq 0) {

            $parsed =
                Update-RunFromFiles `
                    -RunDirectory $runDirectory

            $parserState =
                $parsed.parser_state

            $parserError =
                $parsed.parser_error
        }

        $run =
            Read-JsonFile $runFile

        $run.result.harness_state =
            "complete"

        $run.result.harness_error =
            ""

        if ($engineExitCode -ne 0) {

            $run.status =
                "benchmark_failed"

            $run.result.parser_state =
                "not_run"

            Write-JsonFile `
                -Object $run `
                -Path $runFile

            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_failed" `
                -Message (
                    "llama-bench exited with code " +
                    $engineExitCode
                ) `
                -RunId $runId `
                -EngineState "failed" `
                -EngineExitCode $engineExitCode `
                -ParserState "not_run" `
                -HarnessState "complete" `
                -TerminationCategory "engine_error" `
                -ProcessCompleted $true
        }
        elseif ($parserState -eq "complete") {

            $run.status =
                "benchmark_complete"

            Write-JsonFile `
                -Object $run `
                -Path $runFile

            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_complete" `
                -Message "Engine complete; parser complete." `
                -RunId $runId `
                -EngineState "complete" `
                -EngineExitCode 0 `
                -ParserState "complete" `
                -HarnessState "complete" `
                -TerminationCategory "normal" `
                -ProcessCompleted $true
        }
        else {

            # A successful benchmark remains a successful engine
            # run even if normalization/parsing fails.
            $run.status =
                "benchmark_complete"

            $run.result.parser_state =
                "parser_error"

            $run.result.parser_error =
                $parserError

            Write-JsonFile `
                -Object $run `
                -Path $runFile

            Write-RunStatus `
                -Path $statusFile `
                -State "benchmark_complete" `
                -Message (
                    "Engine complete; parser error. " +
                    "Raw benchmark data is preserved."
                ) `
                -RunId $runId `
                -EngineState "complete" `
                -EngineExitCode 0 `
                -ParserState "parser_error" `
                -ParserError $parserError `
                -HarnessState "complete" `
                -TerminationCategory "normal" `
                -ProcessCompleted $true
        }
    }
    catch {

        $fatalError = (
            $_.Exception.Message +
            "`n" +
            $_.ScriptStackTrace
        )

        try {

            $run =
                Read-JsonFile $runFile

            $run.status =
                "harness_error"

            $run.updated_at =
                (Get-Date).ToString("o")

            $run.result.harness_state =
                "error"

            $run.result.harness_error =
                $fatalError

            if (
                -not
                $run.result.termination.category
            ) {

                $run.result.termination.category =
                    "harness_error"

                $run.result.termination.observed_at =
                    (Get-Date).ToString("o")

                $run.result.termination.evidence_state =
                    "confirmed"

                $run.result.termination.root_cause =
                    "harness_exception"
            }

            Write-JsonFile `
                -Object $run `
                -Path $runFile
        }
        catch {
            # The original harness exception is preserved in
            # status.json even if run.json itself cannot be updated.
        }

        Write-RunStatus `
            -Path $statusFile `
            -State "harness_error" `
            -Message $_.Exception.Message `
            -RunId $runId `
            -EngineState $engineState `
            -EngineExitCode $engineExitCode `
            -ParserState $parserState `
            -ParserError $parserError `
            -HarnessState "error" `
            -HarnessError $fatalError `
            -TerminationCategory "harness_error" `
            -ProcessCompleted (
                $null -ne $engineExitCode
            )
    }
    finally {

        $restoreState =
            "complete"

        $restoreError =
            ""

        try {

            . $Script:Actions

            Start-Brain

            Start-Sleep 3
        }
        catch {

            $restoreState =
                "failed"

            $restoreError = (
                $_.Exception.Message +
                "`n" +
                $_.ScriptStackTrace
            )

            $restoreLog =
                Join-Path `
                    $runDirectory `
                    "brain-restore-error.log"

            $restoreError |
                Set-Content `
                    $restoreLog `
                    -Encoding UTF8
        }

        try {

            $run =
                Read-JsonFile $runFile

            if (
                -not
                $run.result.PSObject.Properties["brain_restore"]
            ) {

                Set-ObjectProperty `
                    $run.result `
                    "brain_restore" `
                    ([pscustomobject]@{})
            }

            Set-ObjectProperty `
                $run.result.brain_restore `
                "state" `
                $restoreState

            Set-ObjectProperty `
                $run.result.brain_restore `
                "error" `
                $restoreError

            Set-ObjectProperty `
                $run.result.brain_restore `
                "completed_at" `
                (Get-Date).ToString("o")

            $run.updated_at =
                (Get-Date).ToString("o")

            Write-JsonFile `
                -Object $run `
                -Path $runFile
        }
        catch {
            # Preserve benchmark evidence even if restoration
            # metadata itself cannot be written.
        }
    }
}

# ============================================================
# STATUS COMMAND
# ============================================================

function Show-Status {

    $runDirectory =
        Resolve-RunPath $RunPath

    $statusFile =
        Join-Path `
            $runDirectory `
            "status.json"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK STATUS"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host ""

    if (Test-Path $statusFile) {

        try {

            $status =
                Read-JsonFile $statusFile

            $status |
                Format-List
        }
        catch {

            Write-Host "status.json could not be parsed." `
                -ForegroundColor Yellow

            Get-Content $statusFile
        }
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

    $runDirectory =
        Resolve-RunPath $RunPath

    $runFile =
        Join-Path `
            $runDirectory `
            "run.json"

    $statusFile =
        Join-Path `
            $runDirectory `
            "status.json"

    $run =
        Read-JsonFile $runFile

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP BENCHMARK RESULT"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host "Schema: $($run.schema)"

    if ($run.PSObject.Properties["id"]) {
        Write-Host "Run ID: $($run.id)"
    }

    if (
        $run.PSObject.Properties["references"]
    ) {

        Write-Host ""
        Write-Host "=== REPRODUCIBILITY ===" `
            -ForegroundColor Cyan

        $run.references |
            Select-Object `
                experiment_ref,
                suite_ref,
                methodology_ref,
                methodology_sha256,
                machine_ref,
                environment_ref,
                host_session_ref,
                backend_ref,
                model_ref,
                model_artifact_ref |
            Format-List
    }

    if (Test-Path $statusFile) {

        try {

            $status =
                Read-JsonFile $statusFile

            Write-Host ""
            Write-Host "=== STATUS ===" `
                -ForegroundColor Cyan

            Write-Host "State:        $($status.state)"
            Write-Host "Engine:       $($status.engine_state)"
            Write-Host "Engine exit:  $($status.engine_exit_code)"
            Write-Host "Parser:       $($status.parser_state)"
            Write-Host "Harness:      $($status.harness_state)"
            Write-Host "Termination:  $($status.termination_category)"
            Write-Host "Completed:    $($status.process_completed)"

            if ($status.parser_error) {

                Write-Host ""
                Write-Host "Parser error:" `
                    -ForegroundColor Yellow

                Write-Host $status.parser_error
            }

            if ($status.harness_error) {

                Write-Host ""
                Write-Host "Harness error:" `
                    -ForegroundColor Red

                Write-Host $status.harness_error
            }
        }
        catch {

            Write-Host ""
            Write-Host "status.json parse error." `
                -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "=== MEASUREMENTS ===" `
        -ForegroundColor Cyan

    $measurements =
        @()

    if (
        $run.result -and
        $run.result.PSObject.Properties["measurements"]
    ) {
        $measurements =
            @($run.result.measurements)
    }

    if ($measurements.Count -gt 0) {

        $measurements |
            Select-Object `
                measurement_id,
                order_index,
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
        Write-Host "=== MEMORY ===" `
            -ForegroundColor Cyan

        $run.result.memory |
            Select-Object `
                initial_gpu_free_mib,
                full_gpu_offload,
                offloaded_layers,
                total_layers,
                gpu_model_mib,
                gpu_kv_mib,
                host_kv_mib,
                gpu_recurrent_mib,
                gpu_compute_mib,
                host_compute_mib,
                pinned_memory_failure,
                allocation_failure,
                gpu_fallback,
                partial_offload |
            Format-List

        if (
            $run.result.memory.PSObject.Properties["linkage"]
        ) {

            Write-Host "Memory linkage:"

            $run.result.memory.linkage |
                Format-List
        }
    }

    if (
        $run.result -and
        $run.result.PSObject.Properties[
            "execution_assessment"
        ] -and
        $run.result.execution_assessment
    ) {

        Write-Host ""
        Write-Host "=== EXECUTION ASSESSMENT ===" `
            -ForegroundColor Cyan

        $run.result.execution_assessment |
            Format-List
    }

    if (
        $run.result -and
        $run.result.PSObject.Properties[
            "termination"
        ] -and
        $run.result.termination
    ) {

        Write-Host ""
        Write-Host "=== TERMINATION ===" `
            -ForegroundColor Cyan

        $run.result.termination |
            Format-List
    }

    if (
        $run.execution -and
        $run.execution.PSObject.Properties[
            "process_reuse"
        ]
    ) {

        Write-Host ""
        Write-Host "=== PROCESS / ORDER ===" `
            -ForegroundColor Cyan

        $run.execution.process_reuse |
            Format-List
    }

    Write-Host "============================================================"
}

# ============================================================
# LIST COMMAND
# ============================================================

function Show-RunList {

    $runsPath =
        Join-Path `
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

        $statusFile =
            Join-Path `
                $dir.FullName `
                "status.json"

        $runFile =
            Join-Path `
                $dir.FullName `
                "run.json"

        $state = ""
        $parser = ""
        $message = ""
        $runId = ""
        $experiment = ""
        $schema = ""

        if (Test-Path $statusFile) {

            try {

                $status =
                    Read-JsonFile $statusFile

                $state =
                    $status.state

                $parser =
                    $status.parser_state

                $message =
                    $status.message

                if ($status.PSObject.Properties["run_id"]) {
                    $runId = $status.run_id
                }
            }
            catch {

                $state =
                    "status_parse_error"
            }
        }

        if (Test-Path $runFile) {

            try {

                $run =
                    Read-JsonFile $runFile

                $schema =
                    $run.schema

                if (
                    -not $runId -and
                    $run.PSObject.Properties["id"]
                ) {
                    $runId = $run.id
                }

                if (
                    $run.PSObject.Properties["references"]
                ) {
                    $experiment =
                        $run.references.experiment_ref
                }
            }
            catch {
            }
        }

        $items +=
            [pscustomobject][ordered]@{

                run =
                    $dir.Name

                run_id =
                    $runId

                experiment =
                    $experiment

                schema =
                    $schema

                state =
                    $state

                parser =
                    $parser

                message =
                    $message
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

    $runDirectory =
        Resolve-RunPath $RunPath

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "YUKI LLAMA.CPP RUN REPAIR"
    Write-Host "============================================================"
    Write-Host "Run: $runDirectory"
    Write-Host ""

    $parsed =
        Update-RunFromFiles `
            -RunDirectory $runDirectory `
            -Repair

    $run =
        Read-JsonFile (
            Join-Path `
                $runDirectory `
                "run.json"
        )

    $statusFile =
        Join-Path `
            $runDirectory `
            "status.json"

    $runId = ""

    if ($run.PSObject.Properties["id"]) {
        $runId = [string]$run.id
    }

    $engineState =
        [string]$run.result.engine_state

    $engineExitCode =
        $run.result.engine_exit_code

    $terminationCategory = ""

    if (
        $run.result.PSObject.Properties["termination"] -and
        $run.result.termination
    ) {
        $terminationCategory =
            [string]$run.result.termination.category
    }

    # --------------------------------------------------------
    # DO NOT TURN INTERRUPTED LEGACY RUNS INTO "COMPLETE"
    # JUST BECAUSE repair WAS INVOKED.
    # --------------------------------------------------------

    $knownInterruption = (
        $terminationCategory -in @(
            "host_bugcheck",
            "host_reboot",
            "power_loss",
            "host_hang",
            "manual_cancel",
            "process_crash",
            "unknown_interruption"
        )
    )

    $engineCompletionUnknown = (
        $engineState -in @(
            "",
            "queued",
            "running",
            "not_started"
        )
    )

    if (
        $knownInterruption -or
        $engineCompletionUnknown
    ) {

        $statusState =
            "interrupted"

        if (-not $terminationCategory) {
            $terminationCategory =
                "unknown_interruption"
        }

        Write-RunStatus `
            -Path $statusFile `
            -State $statusState `
            -Message (
                "Run reparsed where possible; engine completion " +
                "remains interrupted or unknown."
            ) `
            -RunId $runId `
            -EngineState $engineState `
            -EngineExitCode $engineExitCode `
            -ParserState $parsed.parser_state `
            -ParserError $parsed.parser_error `
            -HarnessState "repair_complete" `
            -TerminationCategory $terminationCategory `
            -ProcessCompleted $false
    }
    elseif (
        $engineState -eq "failed" -or
        (
            $null -ne $engineExitCode -and
            [int]$engineExitCode -ne 0
        )
    ) {

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_failed" `
            -Message "Existing failed benchmark reparsed where possible." `
            -RunId $runId `
            -EngineState "failed" `
            -EngineExitCode $engineExitCode `
            -ParserState $parsed.parser_state `
            -ParserError $parsed.parser_error `
            -HarnessState "repair_complete" `
            -TerminationCategory "engine_error" `
            -ProcessCompleted $true
    }
    elseif ($parsed.parser_state -eq "complete") {

        $finalTerminationCategory =
            if ($terminationCategory) {
                $terminationCategory
            }
            else {
                "normal"
            }

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_complete" `
            -Message "Existing benchmark reparsed successfully." `
            -RunId $runId `
            -EngineState "complete" `
            -EngineExitCode 0 `
            -ParserState "complete" `
            -HarnessState "repair_complete" `
            -TerminationCategory $finalTerminationCategory `
            -ProcessCompleted $true

        Write-Host "Parser: COMPLETE" `
            -ForegroundColor Green

        Write-Host ""

        $parsed.measurements |
            Select-Object `
                measurement_id,
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

        $finalTerminationCategory =
            if ($terminationCategory) {
                $terminationCategory
            }
            else {
                "normal"
            }

        Write-RunStatus `
            -Path $statusFile `
            -State "benchmark_complete" `
            -Message (
                "Engine completion is preserved; parser still has an error."
            ) `
            -RunId $runId `
            -EngineState "complete" `
            -EngineExitCode 0 `
            -ParserState "parser_error" `
            -ParserError $parsed.parser_error `
            -HarnessState "repair_complete" `
            -TerminationCategory $finalTerminationCategory `
            -ProcessCompleted $true

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
