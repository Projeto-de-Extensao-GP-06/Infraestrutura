<#
.SYNOPSIS
    Sincroniza as credenciais ativas da AWS (Vocareum / AWS Academy) no GitHub Secrets
    e dispara o workflow de CD em todos os repositórios para compilar e subir imagens no ECR.
#>

param(
    [switch]$NoTrigger
)

$ErrorActionPreference = "Stop"

# Localizar o executavel do gh
$ghExe = "gh"
if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    if (Test-Path "C:\Program Files\GitHub CLI\gh.exe") {
        $ghExe = "C:\Program Files\GitHub CLI\gh.exe"
    } else {
        Write-Error "GitHub CLI (gh) nao encontrado. Instale ou configure o PATH."
    }
}

# 1. Validar autenticacao no GitHub
Write-Host "--> Verificando login no GitHub..." -ForegroundColor Cyan
& $ghExe auth status > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Voce nao esta autenticado no GitHub CLI. Execute uma vez:"
    Write-Host "   & '$ghExe' auth login" -ForegroundColor Yellow
    exit 1
}

# 2. Obter credenciais ativas da AWS
Write-Host "--> Lendo credenciais ativas da AWS..." -ForegroundColor Cyan
$accessKey = aws configure get aws_access_key_id
$secretKey = aws configure get aws_secret_access_key
$sessionToken = aws configure get aws_session_token

if ([string]::IsNullOrWhiteSpace($accessKey) -or [string]::IsNullOrWhiteSpace($secretKey) -or [string]::IsNullOrWhiteSpace($sessionToken)) {
    Write-Error "Credenciais da AWS nao encontradas ou incompletas no 'aws configure'. Atualize suas credenciais primeiro."
}

$repos = @(
    "Projeto-de-Extensao-GP-06/Backend",
    "Projeto-de-Extensao-GP-06/Frontend",
    "Projeto-de-Extensao-GP-06/Agent-Backend"
)

# 3. Sincronizar Secrets em cada repositorio
foreach ($repo in $repos) {
    Write-Host "`n--> Sincronizando Secrets no repositorio: $repo" -ForegroundColor Green
    
    $accessKey | & $ghExe secret set AWS_ACCESS_KEY_ID --repo $repo
    $secretKey | & $ghExe secret set AWS_SECRET_ACCESS_KEY --repo $repo
    $sessionToken | & $ghExe secret set AWS_SESSION_TOKEN --repo $repo

    Write-Host "   [OK] Secrets atualizados com sucesso em $repo" -ForegroundColor Gray

    # 4. Disparar workflow de CD (build e push para o ECR)
    if (-not $NoTrigger) {
        Write-Host "   [>>] Disparando workflow de CD (cd.yml) na branch main..." -ForegroundColor Yellow
        try {
            & $ghExe workflow run cd.yml --repo $repo --ref main
            Write-Host "   [OK] Workflow disparado em $repo" -ForegroundColor Cyan
        } catch {
            Write-Warning "   Falha ao disparar workflow em $repo: $_"
        }
    }
}

Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host "  Concluido com sucesso! Todas as credenciais foram sincronizadas" -ForegroundColor Green
Write-Host "  e as builds para o Amazon ECR foram iniciadas." -ForegroundColor Green
Write-Host "=================================================================`n" -ForegroundColor Green