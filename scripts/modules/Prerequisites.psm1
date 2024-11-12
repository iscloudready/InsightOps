function Test-PortAvailability {
    param (
        [int]$Port,
        [string]$Service
    )
    
    try {
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $Port)
        $socket = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Stream,
            [System.Net.Sockets.ProtocolType]::Tcp
        )
        
        try {
            $socket.Bind($endpoint)
            $socket.Close()
            return $true
        }
        catch {
            $socket.Close()
            return $false
        }
    }
    catch {
        return $false
    }
}

function Test-AllPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-Host "`nChecking System Prerequisites" -ForegroundColor Cyan
    $allPassed = $true
    $issues = @()

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
                $issues += "Docker service needs to be started"
                $allPassed = $false
            }
        } else {
            Write-Host "[FAIL] Docker not found" -ForegroundColor Red
            $issues += "Docker needs to be installed"
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] Docker check failed" -ForegroundColor Red
        $issues += "Docker check failed: $_"
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
            $issues += ".NET SDK needs to be installed"
            $allPassed = $false
        }
    } catch {
        Write-Host "[FAIL] .NET SDK check failed" -ForegroundColor Red
        $issues += ".NET SDK check failed"
        $allPassed = $false
    }

    # Git Check
    try {
        $gitVersion = git --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Git: $gitVersion" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Git not found" -ForegroundColor Red
            $issues += "Git needs to be installed"
            $allPassed = $false
        }
    } catch {
        Write-Host "[FAIL] Git check failed" -ForegroundColor Red
        $issues += "Git check failed"
        $allPassed = $false
    }

    # Network Requirements Section
    Write-Host "`nNetwork Requirements:" -ForegroundColor Yellow
    
    # Port Checks
    $requiredPorts = @(
        @{Port = 5010; Service = "Frontend"},
        @{Port = 5011; Service = "API Gateway"},
        @{Port = 5012; Service = "Order Service"},
        @{Port = 5013; Service = "Inventory Service"},
        @{Port = 3001; Service = "Grafana"},
        @{Port = 9091; Service = "Prometheus"},
        @{Port = 3101; Service = "Loki"},
        @{Port = 4317; Service = "Tempo"}
    )

    $portsInUse = @()
    foreach ($portInfo in $requiredPorts) {
        $isAvailable = Test-PortAvailability -Port $portInfo.Port -Service $portInfo.Service
        if ($isAvailable) {
            Write-Host "[OK] Port $($portInfo.Port) available ($($portInfo.Service))" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Port $($portInfo.Port) in use (required for $($portInfo.Service))" -ForegroundColor Red
            $portsInUse += "$($portInfo.Port) ($($portInfo.Service))"
            $allPassed = $false
        }
    }

    if ($portsInUse.Count -gt 0) {
        $issues += "Ports in use: $($portsInUse -join ', ')"
    }

    # Internet Connectivity Check
    Write-Host "`nInternet Connectivity:" -ForegroundColor Yellow
    $urlsToCheck = @(
        @{Url = "docker.io"; Name = "Docker Hub"},
        @{Url = "github.com"; Name = "GitHub"},
        @{Url = "nuget.org"; Name = "NuGet"}
    )

    foreach ($urlInfo in $urlsToCheck) {
        try {
            $result = Test-NetConnection -ComputerName $urlInfo.Url -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet
            if ($result.TcpTestSucceeded) {
                Write-Host "[OK] Can reach $($urlInfo.Name)" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] Cannot reach $($urlInfo.Name)" -ForegroundColor Red
                $issues += "Cannot connect to $($urlInfo.Name)"
                $allPassed = $false
            }
        } catch {
            Write-Host "[ERROR] Failed to check connection to $($urlInfo.Name)" -ForegroundColor Red
            $issues += "Failed to check connection to $($urlInfo.Name)"
            $allPassed = $false
        }
    }

    # Final Summary
    Write-Host "`nPrerequisites Summary:" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "[PASS] All prerequisites met!" -ForegroundColor Green
        Write-Host "      System is ready for InsightOps deployment" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Some prerequisites not met" -ForegroundColor Red
        Write-Host "`nIssues to resolve:" -ForegroundColor Yellow
        foreach ($issue in $issues) {
            Write-Host "      • $issue" -ForegroundColor Yellow
        }
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "      1. Address the issues listed above" -ForegroundColor Yellow
        Write-Host "      2. Run this check again" -ForegroundColor Yellow
    }

    return $allPassed
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    try {
        $result = docker info 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-AllPrerequisites',
    'Test-Prerequisites'
)