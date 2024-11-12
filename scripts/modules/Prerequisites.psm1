function Test-PortAvailability {
    param (
        [int]$Port,
        [string]$Service
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $result = $tcpClient.ConnectAsync("127.0.0.1", $Port).Wait(1000)
        $tcpClient.Close()
        
        if ($result) {
            return $false  # Port is in use
        }
        return $true  # Port is available
    }
    catch {
        return $true  # Connection failed means port is available
    }
}

function Test-AllPrerequisites {
    [CmdletBinding()]
    param()
    
    $allPassed = $true
    Write-Host "`nChecking System Prerequisites" -ForegroundColor Cyan

    # System Requirements Section
    Write-Host "`nSystem Requirements:" -ForegroundColor Yellow
    
    # Docker Check
    try {
        $dockerVersion = docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Docker installed: $dockerVersion" -ForegroundColor Green
            
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Docker service running" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] Docker service not running" -ForegroundColor Red
                $allPassed = $false
            }
        } else {
            Write-Host "[FAIL] Docker not found" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] Docker check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Development Tools Section
    Write-Host "`nDevelopment Tools:" -ForegroundColor Yellow
    
    # .NET SDK Check
    try {
        $dotnetVersion = dotnet --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] .NET SDK: $dotnetVersion" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] .NET SDK not found" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[FAIL] .NET SDK check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Git Check
    try {
        $gitVersion = git --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Git: $gitVersion" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Git not found" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[FAIL] Git check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Network Requirements Section
    Write-Host "`nNetwork Requirements:" -ForegroundColor Yellow
    
    # Port Checks
    $portsToCheck = @(
        @{Port = 5010; Service = "Frontend"},
        @{Port = 5011; Service = "API Gateway"},
        @{Port = 5012; Service = "Order Service"},
        @{Port = 5013; Service = "Inventory Service"},
        @{Port = 3001; Service = "Grafana"},
        @{Port = 9091; Service = "Prometheus"},
        @{Port = 3101; Service = "Loki"},
        @{Port = 4317; Service = "Tempo"}
    )

    foreach ($portCheck in $portsToCheck) {
        if (Test-PortAvailability -Port $portCheck.Port -Service $portCheck.Service) {
            Write-Host "[OK] Port $($portCheck.Port) available ($($portCheck.Service))" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Port $($portCheck.Port) in use (required for $($portCheck.Service))" -ForegroundColor Red
            $allPassed = $false
        }
    }

    # Internet Connectivity Section
    Write-Host "`nInternet Connectivity:" -ForegroundColor Yellow
    
    # Docker Hub connectivity check
    try {
        $dockerPull = docker pull hello-world 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Docker Hub accessible" -ForegroundColor Green
            docker rmi hello-world -f | Out-Null  # Clean up test image
        } else {
            Write-Host "[WARNING] Docker Hub access might be restricted" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[WARNING] Could not verify Docker Hub access" -ForegroundColor Yellow
    }

    # Check other essential services
    $urls = @(
        @{Url = "github.com"; Name = "GitHub"},
        @{Url = "nuget.org"; Name = "NuGet"}
    )

    foreach ($url in $urls) {
        try {
            $connection = Test-Connection -ComputerName $url.Url -Count 1 -Quiet
            if ($connection) {
                Write-Host "[OK] Connected to $($url.Name)" -ForegroundColor Green
            } else {
                Write-Host "[INFO] Unable to connect to $($url.Name) (connection may still work through proxy)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[INFO] Could not test connection to $($url.Name)" -ForegroundColor Yellow
        }
    }

    # Summary
    Write-Host "`nPrerequisites Check Summary:" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "[PASS] All essential prerequisites met!" -ForegroundColor Green
        Write-Host "System is ready for InsightOps deployment" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Some prerequisites need attention" -ForegroundColor Yellow
        Write-Host "Review the warnings above before proceeding" -ForegroundColor Yellow
    }

    return $true  # Return true to allow proceeding even with warnings
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    try {
        # Check Docker is running
        $dockerInfo = docker info 2>&1
        # Filter out any warnings that contain 'blkio'
        $errors = $dockerInfo | Where-Object { 
            $_ -like "*ERROR*" -and $_ -notlike "*blkio*" -and $_ -notlike "*WARNING*"
        }
        
        if ($errors) {
            Write-Host "Docker has errors:" -ForegroundColor Red
            $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            return $false
        }

        # Check configuration exists
        if (-not (Test-Configuration)) {
            Write-Host "Configuration check failed" -ForegroundColor Red
            return $false
        }

        # All checks passed
        return $true
    }
    catch {
        Write-Host "Prerequisite check failed: $_" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-AllPrerequisites',
    'Test-Prerequisites'
)