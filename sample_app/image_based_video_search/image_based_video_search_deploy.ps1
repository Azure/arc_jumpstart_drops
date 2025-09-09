#Requires -Version 5.1

<#
.SYNOPSIS
    Pulls and installs Intel Image-Based Video Search (IBVS) Helm chart from OCI registry.

.DESCRIPTION
    This script pulls the Intel Image-Based Video Search (IBVS) Helm chart from Docker Hub OCI registry
    and installs it in a Kubernetes cluster with proper error handling and validation.

.PARAMETER ChartVersion
    Version of the image-based-video-search chart to install (default: 1.0.1)

.PARAMETER Namespace
    Kubernetes namespace to install the chart (default: ibvs)

.PARAMETER ReleaseName
    Helm release name (default: ibvs)

.PARAMETER CreateNamespace
    Create namespace if it doesn't exist (default: true)

.PARAMETER DryRun
    Perform a dry run without actually installing

.EXAMPLE
    .\image_based_video_search_deploy.ps1
    
.EXAMPLE
    .\image_based_video_search_deploy.ps1 -ChartVersion "1.0.2" -Namespace "ibvs-prod"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ChartVersion = "1.0.1",
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "ibvs",
    
    [Parameter(Mandatory = $false)]
    [string]$ReleaseName = "ibvs",
    
    [Parameter(Mandatory = $false)]
    [switch]$CreateNamespace = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Configuration
$ChartRegistry = "oci://registry-1.docker.io/intel/image-based-video-search"
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Info" { "White" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..." -Level "Info"
    
    # Check if Helm is installed
    try {
        $helmVersion = helm version --short 2>$null
        Write-Log "Helm found: $helmVersion" -Level "Success"
    }
    catch {
        Write-Log "Helm is not installed or not in PATH" -Level "Error"
        throw "Please install Helm first: https://helm.sh/docs/intro/install/"
    }
    
    # Check if kubectl is available and cluster is accessible
    try {
        $clusterInfo = kubectl cluster-info --request-timeout=10s 2>$null
        Write-Log "Kubernetes cluster is accessible" -Level "Success"
    }
    catch {
        Write-Log "Cannot connect to Kubernetes cluster" -Level "Error"
        throw "Please ensure kubectl is configured and cluster is accessible"
    }
}

# Pull Helm chart
function Invoke-HelmPull {
    param(
        [string]$Registry,
        [string]$Version
    )
    
    Write-Log "Pulling Helm chart from $Registry version $Version..." -Level "Info"
    
    try {
        $pullCommand = "helm pull $Registry --version $Version"
        Write-Log "Executing: $pullCommand" -Level "Info"
        
        Invoke-Expression $pullCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Chart pulled successfully" -Level "Success"
        } else {
            throw "Helm pull failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Log "Failed to pull chart: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# Install Helm chart
function Invoke-HelmInstall {
    param(
        [string]$ReleaseName,
        [string]$Namespace,
        [bool]$CreateNamespace,
        [bool]$DryRun
    )
    
    Write-Log "Installing Helm chart..." -Level "Info"
    
    try {
        $installArgs = @(
            "helm install $ReleaseName"
            "image-based-video-search-$ChartVersion.tgz"
            "-n $Namespace"
        )
        
        if ($CreateNamespace) {
            $installArgs += "--create-namespace"
        }
        
        if ($DryRun) {
            $installArgs += "--dry-run"
            Write-Log "Performing dry run..." -Level "Warning"
        }
        
        $installCommand = $installArgs -join " "
        Write-Log "Executing: $installCommand" -Level "Info"
        
        Invoke-Expression $installCommand
        
        if ($LASTEXITCODE -eq 0) {
            if ($DryRun) {
                Write-Log "Dry run completed successfully" -Level "Success"
            } else {
                Write-Log "Chart installed successfully" -Level "Success"
            }
        } else {
            throw "Helm install failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Log "Failed to install chart: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# Main execution
function Main {
    try {
        Write-Log "Starting Image-Based Video Search (IBVS) Helm chart deployment" -Level "Info"
        Write-Log "Chart Version: $ChartVersion" -Level "Info"
        Write-Log "Namespace: $Namespace" -Level "Info"
        Write-Log "Release Name: $ReleaseName" -Level "Info"
        
        Test-Prerequisites
        Invoke-HelmPull -Registry $ChartRegistry -Version $ChartVersion
        Invoke-HelmInstall -ReleaseName $ReleaseName -Namespace $Namespace -CreateNamespace $CreateNamespace -DryRun $DryRun
        
        if (-not $DryRun) {
            Write-Log "Deployment completed successfully!" -Level "Success"
            Write-Log "You can check the status with: helm status $ReleaseName -n $Namespace" -Level "Info"
        }
    }
    catch {
        Write-Log "Deployment failed: $($_.Exception.Message)" -Level "Error"
        exit 1
    }
}

# Execute main function
Main