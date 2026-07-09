# RAG System Quick Setup Script (Windows)
# Installs Ollama, downloads models, and tests endpoints

param(
    [switch]$SkipOllama = $false,
    [switch]$TestOnly = $false,
    [switch]$GPUSupport = $false
)

Write-Host @"
================================================================================
                   RAG SYSTEM QUICK SETUP
                 Ollama + Gemma-7B + Qwen3-Embedding
================================================================================
"@ -ForegroundColor Cyan

# Function to test if service is running
function Test-ServiceRunning($port) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 2 -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# Function to download file
function Download-File($url, $path) {
    Write-Host "Downloading: $url" -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $path
        Write-Host "✓ Downloaded to: $path" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "✗ Download failed: $_" -ForegroundColor Red
        return $false
    }
}

# Check if Ollama is installed
if (-not $SkipOllama) {
    Write-Host "`n[1/5] Checking Ollama Installation..." -ForegroundColor Cyan

    $ollamaPath = $null
    if (Test-Path "$env:LOCALAPPDATA\Programs\Ollama") {
        $ollamaPath = "$env:LOCALAPPDATA\Programs\Ollama"
    } elseif (Test-Path "C:\Program Files\Ollama") {
        $ollamaPath = "C:\Program Files\Ollama"
    }

    if ($null -eq $ollamaPath) {
        Write-Host "Ollama not found. Installing..." -ForegroundColor Yellow
        Write-Host "Download from: https://ollama.ai/download" -ForegroundColor Yellow
        Write-Host "Or run: winget install Ollama.Ollama" -ForegroundColor Yellow
        $confirm = Read-Host "Have you installed Ollama? (y/n)"
        if ($confirm -ne 'y') {
            Write-Host "Please install Ollama first: https://ollama.ai/download" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "✓ Ollama found at: $ollamaPath" -ForegroundColor Green
    }
}

# Check Ollama service
Write-Host "`n[2/5] Checking Ollama Service..." -ForegroundColor Cyan
if (Test-ServiceRunning 11434) {
    Write-Host "✓ Ollama is running on port 11434" -ForegroundColor Green
} else {
    Write-Host "✗ Ollama is not running" -ForegroundColor Yellow
    Write-Host "Starting Ollama..." -ForegroundColor Yellow

    # Try to start via Windows Service
    $service = Get-Service -Name "Ollama" -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        Start-Service -Name "Ollama" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    } else {
        Write-Host "Please start Ollama manually from Windows Start Menu or System Tray" -ForegroundColor Yellow
        $confirm = Read-Host "Is Ollama running now? (y/n)"
        if ($confirm -ne 'y') {
            exit 1
        }
    }
}

# Pull models
if (-not $TestOnly) {
    Write-Host "`n[3/5] Pulling Models..." -ForegroundColor Cyan

    Write-Host "Pulling gemma:7b (4.7 GB)..." -ForegroundColor Yellow
    & ollama pull gemma:7b
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ gemma:7b ready" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to pull gemma:7b" -ForegroundColor Red
    }

    Write-Host "`nPulling qwen:text-embedding-qwen3-embedding-8b (3.1 GB)..." -ForegroundColor Yellow
    & ollama pull "qwen:text-embedding-qwen3-embedding-8b"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ qwen embedding ready" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to pull qwen embedding" -ForegroundColor Red
    }

    Write-Host "`n[4/5] Listing Installed Models..." -ForegroundColor Cyan
    & ollama list
}

# Test endpoints
Write-Host "`n[5/5] Testing Ollama Endpoints..." -ForegroundColor Cyan

Write-Host "`nTesting Embedding API..." -ForegroundColor Yellow
try {
    $embedResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/embeddings" `
        -Method POST `
        -ContentType "application/json" `
        -Body (@{
            model = "qwen:text-embedding-qwen3-embedding-8b"
            prompt = "What is RAG?"
        } | ConvertTo-Json) `
        -TimeoutSec 30 `
        -ErrorAction Stop

    $embedData = $embedResponse.Content | ConvertFrom-Json
    if ($null -ne $embedData.embedding) {
        Write-Host "✓ Embedding API working" -ForegroundColor Green
        Write-Host "  Embedding dimensions: $($embedData.embedding.Length)" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ Embedding API failed: $_" -ForegroundColor Red
}

Write-Host "`nTesting LLM API (this may take 10-30 seconds on first run)..." -ForegroundColor Yellow
try {
    $llmResponse = Invoke-WebRequest -Uri "http://localhost:11434/api/generate" `
        -Method POST `
        -ContentType "application/json" `
        -Body (@{
            model = "gemma:7b"
            prompt = "What is RAG? Answer in one sentence."
            stream = $false
            temperature = 0.3
            num_predict = 128
        } | ConvertTo-Json) `
        -TimeoutSec 60 `
        -ErrorAction Stop

    $llmData = $llmResponse.Content | ConvertFrom-Json
    if ($null -ne $llmData.response) {
        Write-Host "✓ LLM API working" -ForegroundColor Green
        Write-Host "  Response: $($llmData.response.Substring(0, [Math]::Min(100, $llmData.response.Length)))..." -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ LLM API failed: $_" -ForegroundColor Red
}

# Summary
Write-Host @"

================================================================================
                         SETUP COMPLETE
================================================================================

✓ Ollama is running at http://localhost:11434
✓ Models are downloaded and ready

NEXT STEPS:

1. Start n8n:
   docker run -p 5678:5678 n8n/n8n

2. Open http://localhost:5678

3. Import workflow:
   File → Import → Select rag-workflow.json

4. Test the RAG system:
   curl -X POST http://localhost:5678/webhook/rag ^
     -H "Content-Type: application/json" ^
     -d "{\"question\": \"What is RAG?\"}"

5. Monitor Ollama performance:
   - Check taskbar for Ollama system tray
   - GPU usage: Task Manager → GPU tab
   - Models status: ollama list

EXPECTED LATENCY:
  - Embedding: 2-5 seconds
  - LLM generation: 5-15 seconds (CPU) or 2-5s (GPU)
  - Total: 7-20 seconds

TROUBLESHOOTING:
  - If slow, check GPU is being used (nvidia-smi)
  - If out of memory, use smaller models (gemma:2b, mistral:7b)
  - See LOCAL_MODELS_SETUP.md for detailed guide

================================================================================

"@ -ForegroundColor Green

Write-Host "Press any key to continue..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
