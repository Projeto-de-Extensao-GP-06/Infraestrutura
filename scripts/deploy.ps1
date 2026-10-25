# ------------------------------------------------------------------------------
# deploy.ps1 -- Build completo + Push para ECR + Atualizacao no Docker Swarm
# Versao nativa para PowerShell (Windows)
#
# USO:
#   .\deploy.ps1            --> build + deploy frontend E backend (padrao)
#   .\deploy.ps1 all        --> igual ao de cima
#   .\deploy.ps1 frontend   --> so o frontend
#   .\deploy.ps1 backend    --> so o backend
# ------------------------------------------------------------------------------

param (
    [string]$Service = "all",
    [string]$FrontendPath = "",
    [string]$BackendPath = ""
)

$ErrorActionPreference = "Stop"

function Write-Info    { Write-Host ">> $args" -ForegroundColor Blue }
function Write-Success { Write-Host "   [OK] $args" -ForegroundColor Green }
function Write-Warn    { Write-Host "   [AVISO] $args" -ForegroundColor Yellow }
function Write-Err     { Write-Host "   [ERRO] $args" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultFrontend = Resolve-Path (Join-Path $ScriptDir "..\..\Frontend") -ErrorAction SilentlyContinue
$DefaultBackend  = Resolve-Path (Join-Path $ScriptDir "..\..\Backend") -ErrorAction SilentlyContinue

if (-not $FrontendPath -and $DefaultFrontend) { $FrontendPath = $DefaultFrontend.Path }
if (-not $BackendPath  -and $DefaultBackend)  { $BackendPath  = $DefaultBackend.Path }

$DeployFrontend = ($Service -eq "all" -or $Service -eq "frontend")
$DeployBackend  = ($Service -eq "all" -or $Service -eq "backend")

if (-not $DeployFrontend -and -not $DeployBackend) {
    Write-Err "Servico invalido: '$Service'. Use: all | frontend | backend"
}

# ------------------------------------------------------------------------------
# 1. Verificar Ferramentas no Windows
# ------------------------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "Docker nao encontrado no PATH. Inicie o Docker Desktop."
}
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Err "AWS CLI nao encontrado. Verifique o PATH do Windows."
}
if ($DeployFrontend -and -not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Err "npm / Node.js nao encontrado no PATH."
}

# Maven: suporta mvn global, Maven Wrapper (mvnw.cmd) ou reaproveita target/*.jar existente
$MvnCmd = "mvn"
if ($DeployBackend) {
    if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
        $mvnwPath = Join-Path $BackendPath "mvnw.cmd"
        if (Test-Path $mvnwPath) {
            $MvnCmd = $mvnwPath
        } else {
            $existingJar = Get-ChildItem (Join-Path $BackendPath "target") -Filter "*.jar" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($existingJar) {
                $MvnCmd = "SKIP_EXISTING_JAR"
            } else {
                Write-Err "Maven (mvn ou mvnw.cmd) nao encontrado para compilar o backend."
            }
        }
    }
}

# ------------------------------------------------------------------------------
# 2. Verificar Credenciais AWS
# ------------------------------------------------------------------------------
Write-Info "Verificando credenciais AWS..."
try {
    $identityJson = aws sts get-caller-identity --output json | ConvertFrom-Json
    $AccountId = $identityJson.Account
    Write-Success "Credenciais AWS validas (Conta: $AccountId)"
} catch {
    Write-Host ""
    Write-Host "  As credenciais AWS nao estao configuradas ou expiraram." -ForegroundColor Yellow
    Write-Host "  Defina as variaveis no PowerShell antes de executar:" -ForegroundColor Yellow
    Write-Host "    `$env:AWS_ACCESS_KEY_ID = '...'" -ForegroundColor Cyan
    Write-Host "    `$env:AWS_SECRET_ACCESS_KEY = '...'" -ForegroundColor Cyan
    Write-Host "    `$env:AWS_SESSION_TOKEN = '...'" -ForegroundColor Cyan
    Write-Host ""
    Write-Err "Credenciais AWS invalidas ou expiradas."
}

# ------------------------------------------------------------------------------
# 3. Detectar Regiao e Repositorios ECR
# ------------------------------------------------------------------------------
$AllVarsFile = Join-Path $ScriptDir "..\ansible\inventories\group_vars\all.yml"
$InventoryFile = Join-Path $ScriptDir "..\ansible\inventories\production.ini"

$AwsRegion = $env:AWS_DEFAULT_REGION
if (-not $AwsRegion) { $AwsRegion = $env:AWS_REGION }
if (-not $AwsRegion) {
    $AwsRegion = aws configure get region 2>$null
    if (-not $AwsRegion) { $AwsRegion = "us-east-1" }
}

if (Test-Path $AllVarsFile) {
    $regionLine = Get-Content $AllVarsFile | Select-String "^aws_region:\s*(.+)$"
    if ($regionLine) {
        $AwsRegion = $regionLine.Matches.Groups[1].Value.Trim().Trim('"').Trim("'")
    }
}

$EcrRegistry = "$AccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$EcrFrontendRepo = "$EcrRegistry/sgpj-frontend"
$EcrBackendRepo  = "$EcrRegistry/sgpj-backend"

# Detectar IP do Manager (se o inventario ja existir)
$ManagerIp = ""
$KeyFile = ""
if (Test-Path $InventoryFile) {
    $invLines = Get-Content $InventoryFile
    foreach ($line in $invLines) {
        if ($line -match "ansible_host=([0-9.]+)") {
            $ManagerIp = $matches[1]
            break
        }
    }
    foreach ($line in $invLines) {
        if ($line -match "ansible_ssh_private_key_file=(\S+)") {
            $KeyFile = $matches[1]
            break
        }
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  SGPJ Deploy (PowerShell) -- Build + ECR + Swarm" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
if ($DeployFrontend) { Write-Host "  Frontend   : $FrontendPath" }
if ($DeployBackend)  { Write-Host "  Backend    : $BackendPath" }
Write-Host "  ECR        : $EcrRegistry"
Write-Host "  Regiao AWS : $AwsRegion"
if ($ManagerIp) {
    Write-Host "  Manager IP : $ManagerIp"
} else {
    Write-Host "  Manager IP : [Swarm ainda nao ativo - apenas push ECR]" -ForegroundColor Yellow
}
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# 4. Login no ECR
# ------------------------------------------------------------------------------
Write-Info "Autenticando no Amazon ECR..."
$loginPassword = aws ecr get-login-password --region $AwsRegion
$loginPassword | docker login --username AWS --password-stdin $EcrRegistry
if ($LASTEXITCODE -ne 0) { Write-Err "Falha na autenticacao com o ECR." }
Write-Success "Autenticado no ECR com sucesso!"

# ------------------------------------------------------------------------------
# 5. FRONTEND
# ------------------------------------------------------------------------------
if ($DeployFrontend) {
    if (-not (Test-Path $FrontendPath)) { Write-Err "Pasta do frontend nao encontrada: $FrontendPath" }

    Write-Info "Compilando Frontend React (npm run build)..."
    Push-Location $FrontendPath
    try {
        npm run build
        if ($LASTEXITCODE -ne 0) { Write-Err "Falha no build do Frontend (npm run build)." }
        Write-Success "Frontend compilado com sucesso!"

        Write-Info "Criando imagem Docker do Frontend..."
        docker build --platform linux/amd64 -t "${EcrFrontendRepo}:latest" .
        if ($LASTEXITCODE -ne 0) { Write-Err "Falha no docker build do Frontend." }
        Write-Success "Imagem Docker do Frontend criada!"

        Write-Info "Enviando imagem do Frontend para o ECR..."
        docker push "${EcrFrontendRepo}:latest"
        if ($LASTEXITCODE -ne 0) { Write-Err "Falha no docker push do Frontend." }
        Write-Success "Imagem do Frontend enviada ao ECR!"
    } finally {
        Pop-Location
    }
}

# ------------------------------------------------------------------------------
# 6. BACKEND
# ------------------------------------------------------------------------------
if ($DeployBackend) {
    if (-not (Test-Path $BackendPath)) { Write-Err "Pasta do backend nao encontrada: $BackendPath" }

    Push-Location $BackendPath
    try {
        if ($MvnCmd -eq "SKIP_EXISTING_JAR") {
            $existingJar = (Get-ChildItem "target" -Filter "*.jar" | Select-Object -First 1).Name
            Write-Info "Reaproveitando JAR existente em target/: $existingJar"
        } elseif ($MvnCmd -match "mvnw") {
            Write-Info "Compilando Backend Spring Boot via Maven Wrapper (.\mvnw.cmd package)..."
            & $MvnCmd clean package -DskipTests
            if ($LASTEXITCODE -ne 0) { Write-Err "Falha no build do Backend via mvnw.cmd." }
            Write-Success "Backend compilado com sucesso (.jar gerado)!"
        } else {
            Write-Info "Compilando Backend Spring Boot (mvn package)..."
            mvn clean package -DskipTests
            if ($LASTEXITCODE -ne 0) { Write-Err "Falha no build do Backend (mvn package)." }
            Write-Success "Backend compilado com sucesso (.jar gerado)!"
        }

        Write-Info "Criando imagem Docker do Backend..."
        docker build --platform linux/amd64 -t "${EcrBackendRepo}:latest" .
        if ($LASTEXITCODE -ne 0) { Write-Err "Falha no docker build do Backend." }
        Write-Success "Imagem Docker do Backend criada!"

        Write-Info "Enviando imagem do Backend para o ECR..."
        docker push "${EcrBackendRepo}:latest"
        if ($LASTEXITCODE -ne 0) { Write-Err "Falha no docker push do Backend." }
        Write-Success "Imagem do Backend enviada ao ECR!"
    } finally {
        Pop-Location
    }
}

# ------------------------------------------------------------------------------
# 7. ATUALIZACAO NO SWARM (Se ativo)
# ------------------------------------------------------------------------------
if ($ManagerIp) {
    Write-Info "Cluster Swarm detectado no Manager ($ManagerIp). Atualizando servicos..."
    $sshCmd = "ssh -o StrictHostKeyChecking=no"
    if ($KeyFile) { $sshCmd += " -i `"$KeyFile`"" }

    if ($DeployFrontend) {
        Invoke-Expression "$sshCmd ubuntu@$ManagerIp 'docker service update --image ${EcrFrontendRepo}:latest --with-registry-auth sgpj_nginx'"
        Write-Success "Servico sgpj_nginx atualizado com zero-downtime!"
    }
    if ($DeployBackend) {
        Invoke-Expression "$sshCmd ubuntu@$ManagerIp 'docker service update --image ${EcrBackendRepo}:latest --with-registry-auth sgpj_backend'"
        Write-Success "Servico sgpj_backend atualizado com zero-downtime!"
    }
} else {
    Write-Warn "Cluster Swarm ainda nao esta no ar."
    Write-Warn "As imagens ja estao prontas no ECR! Agora rode: terraform apply -auto-approve"
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  [OK] Deploy concluido com sucesso!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
