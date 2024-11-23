# Define the schema template
$dashboardSchema = @"
{
  "`$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Grafana Dashboard",
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Dashboard title"
    },
    "uid": {
      "type": "string",
      "description": "Dashboard UID"
    },
    "panels": {
      "type": "array",
      "items": {
        "`$ref": "#/definitions/panel"
      }
    }
  },
  "required": ["title", "uid", "panels"],
  "definitions": {
    "panel": {
      "type": "object",
      "properties": {
        "title": {
          "type": "string",
          "description": "Panel title"
        },
        "type": {
          "type": "string",
          "enum": ["timeseries", "table", "graph"]
        },
        "targets": {
          "type": "array",
          "items": {
            "`$ref": "#/definitions/target"
          }
        }
      },
      "required": ["title", "type"]
    },
    "target": {
      "type": "object",
      "properties": {
        "expr": {
          "type": "string",
          "description": "Target expression"
        }
      },
      "required": ["expr"]
    }
  }
}
"@

# Add this function to explicitly check file encoding
Function Test-FileEncoding {
    param (
        [string]$Path
    )
    
    $bytes = Get-Content -Path $Path -Raw -Encoding Byte
    Write-Verbose "First three bytes: $($bytes[0]) $($bytes[1]) $($bytes[2])"
    
    # Check for BOM
    if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Warning "File $Path has UTF-8 BOM"
        return $false
    }
    return $true
}

# Modify the file writing in Initialize-Monitoring
try {
    $cleanContent = $content | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress:$false
    
    # Try alternative approach using Out-File
    $cleanContent | Out-File -FilePath $path -Encoding utf8NoBOM -NoNewline
    
    # Verify the file
    if (-not (Test-FileEncoding -Path $path)) {
        Write-Error "File was written with BOM: $path"
        # Try to fix it
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length-1)])
        }
    }
} catch {
    Write-Error "Error writing dashboard: $($_.Exception.Message)"
}

Function Write-JsonWithoutBOM {
    param (
        [string]$Path,
        [string]$Content
    )
    
    # Convert string to bytes using UTF-8 encoding without BOM
    $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
    $jsonBytes = $utf8NoBomEncoding.GetBytes($Content)
    
    # Write bytes to file
    [System.IO.File]::WriteAllBytes($Path, $jsonBytes)
}

Function Validate-Dashboard {
    param (
        [string]$Content,
        [string]$Schema
    )

    try {
        # Ensure content is properly encoded
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        $jsonBytes = $utf8NoBomEncoding.GetBytes($Content)
        $cleanContent = $utf8NoBomEncoding.GetString($jsonBytes)

        # Parse JSON content
        $dashboardJson = $cleanContent | ConvertFrom-Json -ErrorAction Stop

        # Validate required fields
        if (-not $dashboardJson.title) {
            Write-Error "Dashboard title is missing."
            return $false
        }

        if (-not $dashboardJson.uid) {
            Write-Error "Dashboard UID is missing."
            return $false
        }

        if (-not $dashboardJson.panels -or $dashboardJson.panels.Count -eq 0) {
            Write-Error "Dashboard panels are missing."
            return $false
        }

        foreach ($panel in $dashboardJson.panels) {
            if (-not $panel.title) {
                Write-Error "Panel title is missing."
                return $false
            }

            if (-not $panel.type) {
                Write-Error "Panel type is missing."
                return $false
            }

            if ($panel.type -eq "timeseries") {
                foreach ($target in $panel.targets) {
                    if (-not $target.expr) {
                        Write-Error "Timeseries panel target expression is missing."
                        return $false
                    }
                }
            }
        }

        Write-Verbose "Dashboard validated successfully"
        return $true
    }
    catch {
        Write-Error "Error parsing or validating dashboard JSON: $($Error[0].Message)"
        return $false
    }
}

Function Initialize-Monitoring {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    # Create the dashboard directory
    $dashboardPath = Join-Path $ConfigPath "grafana/dashboards"
    if (-not (Test-Path $dashboardPath)) {
        New-Item -ItemType Directory -Path $dashboardPath -Force | Out-Null
        Write-Verbose "Created dashboard directory: $dashboardPath"
    }

    # Define dashboard configurations
    $dashboards = @(
        @{ FileName = "api-gateway.json"; Content = (Get-ApiGatewayDashboard) },
        @{ FileName = "security.json"; Content = (Get-SecurityDashboard) },
        @{ FileName = "service-health.json"; Content = (Get-ServiceHealthDashboard) },
        @{ FileName = "frontend-realtime.json"; Content = (Get-FrontendRealtimeDashboard) },
        @{ FileName = "orders-realtime.json"; Content = (Get-OrdersRealtimeDashboard) },
        @{ FileName = "inventory-realtime.json"; Content = (Get-InventoryRealtimeDashboard) },
        @{ FileName = "frontend-service.json"; Content = (Get-FrontendServiceDashboard) },
        @{ FileName = "inventory-service.json"; Content = (Get-InventoryServiceDashboard) },
        @{ FileName = "order-service.json"; Content = (Get-OrderServiceDashboard) },
        @{ FileName = "overview.json"; Content = (Get-OverviewDashboard) }
    )

    foreach ($dashboard in $dashboards) {
        $path = Join-Path $dashboardPath $dashboard.FileName
        $content = $dashboard.Content

        try {
            Write-Verbose "Processing dashboard: $($dashboard.FileName)"

            # Validate JSON content using Validate-Dashboard
            Write-Verbose "Validating dashboard content..."
            $isValid = Validate-Dashboard -Content $content -Schema $dashboardSchema

            if (-not $isValid) {
                Write-Warning "Dashboard validation failed: $($dashboard.FileName)"
                continue
            }

            # Convert JSON string to object and back to ensure proper formatting
            $jsonObject = $content | ConvertFrom-Json
            $cleanContent = $jsonObject | ConvertTo-Json -Depth 100 -Compress:$false

            # Write JSON to file without BOM
            try {
                # First attempt - write file
                $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($path, $cleanContent, $utf8NoBomEncoding)
                Write-Verbose "Initial file write completed: $path"

                # Verify the encoding
                $encodingCheck = Test-FileEncoding -Path $path
                if (-not $encodingCheck) {
                    Write-Verbose "BOM detected, attempting to fix..."
                    # Read content and rewrite without BOM
                    $bytes = [System.IO.File]::ReadAllBytes($path)
                    if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                        [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length-1)])
                        Write-Verbose "BOM removed from file: $path"
                    }
                    
                    # Verify again
                    $secondCheck = Test-FileEncoding -Path $path
                    if (-not $secondCheck) {
                        Write-Warning "Failed to remove BOM from file: $path"
                    } else {
                        Write-Verbose "File successfully written without BOM: $path"
                    }
                }

                Write-Host "Successfully processed dashboard: $($dashboard.FileName)" -ForegroundColor Green
            }
            catch {
                Write-Error "Error writing to file ($path): $_"
                continue
            }
        }
        catch {
            Write-Error "Error processing dashboard file ($path): $_"
            continue
        }
    }

    Write-Host "`nDashboard initialization complete. Location: $dashboardPath" -ForegroundColor Cyan
    Write-Host "Total dashboards processed: $($dashboards.Count)" -ForegroundColor Cyan
    
    # Final verification of all files
    Write-Host "`nVerifying all dashboard files..." -ForegroundColor Yellow
    Get-ChildItem -Path $dashboardPath -Filter "*.json" | ForEach-Object {
        $verificationResult = Test-FileEncoding -Path $_.FullName
        $status = if ($verificationResult) { "OK" } else { "Has BOM" }
        Write-Host "$($_.Name): $status" -ForegroundColor $(if ($verificationResult) { "Green" } else { "Red" })
    }
}

function Provision-Dashboard {
    param (
        [string]$DashboardPath,
        [string]$GrafanaApiUrl,
        [string]$GrafanaToken
    )

    try {
        # Load dashboard JSON using UTF-8 without BOM
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        $jsonBytes = [System.IO.File]::ReadAllBytes($DashboardPath)
        $DashboardJson = $utf8NoBomEncoding.GetString($jsonBytes)

        # Validate JSON
        if (-not (Validate-Dashboard -Content $DashboardJson -Schema $dashboardSchema)) {
            throw "Invalid dashboard JSON: $DashboardPath"
        }

        # Ensure proper content encoding for API request
        $headers = @{
            'Authorization' = "Bearer $GrafanaToken"
            'Content-Type' = 'application/json; charset=utf-8'
        }

        # Send API request
        $Response = Invoke-RestMethod -Uri "$GrafanaApiUrl/api/dashboards/db" `
            -Method Post `
            -Body $DashboardJson `
            -Headers $headers

        Write-Host "Dashboard provisioned successfully: $DashboardPath"
    }
    catch {
        Write-Error "Error provisioning dashboard: $($_.Exception.Message)"
    }
}

function Get-OverviewDashboard {
    return @'
{
    "title": "System Overview Dashboard",
    "uid": "system-overview",
    "tags": ["overview", "system"],
    "refresh": "5s",
    "panels": [
        {
            "title": "System Health Status",
            "type": "gauge",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "avg(up{job=~\".*\"})*100",
                    "legendFormat": "System Health"
                }
            ],
            "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
            "options": {
                "thresholds": [
                    {"color": "red", "value": null},
                    {"color": "yellow", "value": 80},
                    {"color": "green", "value": 95}
                ]
            }
        },
        {
            "title": "Active Services",
            "type": "stat",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "count(up{job=~\".*\"} == 1)",
                    "legendFormat": "Active Services"
                }
            ],
            "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
        },
        {
            "title": "Total Request Rate",
            "type": "timeseries",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "sum(rate(http_requests_total[5m]))",
                    "legendFormat": "Requests/sec"
                }
            ],
            "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
        },
        {
            "title": "Error Rate by Service",
            "type": "timeseries",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)",
                    "legendFormat": "{{service}}"
                }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
        },
        {
            "title": "Service Response Times",
            "type": "heatmap",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "sum(rate(http_request_duration_seconds_bucket[5m])) by (le)",
                    "format": "heatmap"
                }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
        },
        {
            "title": "System Resources",
            "type": "timeseries",
            "datasource": "Prometheus",
            "targets": [
                {
                    "expr": "sum(rate(process_cpu_seconds_total[5m])) by (job)",
                    "legendFormat": "{{job}} - CPU"
                },
                {
                    "expr": "sum(process_resident_memory_bytes) by (job)",
                    "legendFormat": "{{job}} - Memory"
                }
            ],
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
        }
    ]
}
'@
}

# Dashboard JSON definitions remain the same but with proper encoding handling
function Get-InventoryRealtimeDashboard {
    $json = @'
{
  "title": "Inventory Real-Time",
  "uid": "inventory-realtime",
  "tags": ["inventory", "realtime"],
  "refresh": "5s",
  "panels": [
    {
      "title": "Stock Level Changes",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "delta(inventory_stock_level[1m])",
          "legendFormat": "{{item}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
    },
    {
      "title": "Low Stock Alerts",
      "type": "table",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "inventory_stock_level < inventory_reorder_point",
          "instant": true
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "transformations": [
        {
          "type": "filterByValue",
          "options": {
            "value": 1
          }
        }
      ]
    }
  ]
}
'@
    return $json
}

function Get-OrdersRealtimeDashboard {
    return @'
{
  "title": "Order Processing Real-Time",
  "uid": "orders-realtime",
  "tags": ["orders", "realtime"],
  "refresh": "5s",
  "panels": [
    {
      "title": "Order Processing Pipeline",
      "type": "nodeGraph",
      "datasource": "Tempo",
      "targets": [
        {
          "expr": "traces{service=\"order-service\"}"
        }
      ],
      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 0}
    },
    {
      "title": "Order Rate",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(orders_processed_total[1m])"
        }
      ],
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 12},
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      }
    }
  ]
}
'@
}

function Get-FrontendRealtimeDashboard {
    return @'
{
  "title": "Frontend Real-Time Metrics",
  "uid": "frontend-realtime",
  "tags": ["frontend", "realtime"],
  "refresh": "5s",
  "panels": [
    {
      "title": "Active Users",
      "type": "gauge",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(frontend_active_sessions)"
        }
      ],
      "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
      "options": {
        "thresholds": [
          {"color": "green", "value": null},
          {"color": "yellow", "value": 100},
          {"color": "red", "value": 200}
        ]
      }
    },
    {
      "title": "Page Load Times",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "frontend_page_load_time_seconds{quantile=\"0.95\"}"
        }
      ],
      "gridPos": {"h": 8, "w": 16, "x": 8, "y": 0}
    }
  ]
}
'@
}

function Get-ServiceHealthDashboard {
    return @'
{
  "title": "Service Health Overview",
  "uid": "service-health",
  "tags": ["health", "services"],
  "refresh": "10s",
  "panels": [
    {
      "title": "Service Status Matrix",
      "type": "statusmap",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "up{job=~\"frontend|api-gateway|inventory-service|order-service\"}"
        }
      ],
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0}
    },
    {
      "title": "Resource Usage by Service",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(process_cpu_seconds_total[5m])) by (service)",
          "legendFormat": "{{service}} - CPU"
        },
        {
          "expr": "sum(process_resident_memory_bytes) by (service)",
          "legendFormat": "{{service}} - Memory"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
    }
  ]
}
'@
}

function Get-SecurityDashboard {
    return @'
{
  "title": "Security Metrics",
  "uid": "security-metrics",
  "tags": ["security", "monitoring"],
  "panels": [
    {
      "title": "Authentication Attempts",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(authentication_attempts_total[5m])) by (status)",
          "legendFormat": "{{status}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "alert": {
        "name": "High Failed Auth Rate",
        "conditions": [
          {
            "evaluator": {
              "params": [5],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": ["A"]
            },
            "reducer": {
              "params": [],
              "type": "avg"
            },
            "type": "query"
          }
        ]
      }
    },
    {
      "title": "Request Rate by IP",
      "type": "bargauge",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(http_requests_total[5m])) by (client_ip))",
          "legendFormat": "{{client_ip}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    }
  ]
}
'@
}

function Get-ApiGatewayDashboard {
    return @'
{
  "title": "API Gateway Metrics",
  "uid": "api-gateway-metrics",
  "tags": ["api-gateway", "routing"],
  "panels": [
    {
      "title": "Gateway Request Flow",
      "type": "stat-timeline",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_requests_total[1m])) by (service)",
          "legendFormat": "{{service}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "options": {
        "showValue": "always",
        "colWidth": 0.9
      }
    },
    {
      "title": "Route Latencies",
      "type": "heatmap",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(gateway_route_duration_seconds_bucket[5m])",
          "legendFormat": "{{route}}"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    },
    {
      "title": "Circuit Breaker Status",
      "type": "table",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "gateway_circuit_breaker_state",
          "instant": true
        }
      ],
      "gridPos": {"h": 6, "w": 24, "x": 0, "y": 8},
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "endpoint": "Endpoint",
              "state": "State",
              "failures": "Failures"
            }
          }
        }
      ]
    }
  ]
}
'@
}

function Get-FrontendServiceDashboard {
    return @'
{
  "title": "Frontend Service Dashboard",
  "uid": "frontend-service",
  "tags": ["frontend", "service"],
  "refresh": "5s",
  "panels": [
    {
      "title": "Active Users",
      "type": "gauge",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(frontend_active_sessions)"
        }
      ],
      "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
    },
    {
      "title": "Page Load Times (95th Percentile)",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "frontend_page_load_time_seconds{quantile='0.95'}"
        }
      ],
      "gridPos": {"h": 8, "w": 16, "x": 8, "y": 0}
    },
    {
      "title": "Session Errors",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(frontend_session_errors_total[5m]))"
        }
      ],
      "gridPos": {"h": 4, "w": 8, "x": 0, "y": 8}
    },
    {
      "title": "Latency by API Endpoint",
      "type": "bar",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, rate(api_request_duration_seconds_bucket[5m])) by (endpoint)"
        }
      ],
      "gridPos": {"h": 8, "w": 16, "x": 0, "y": 12}
    }
  ]
}
'@
}

function Get-InventoryServiceDashboard {
    return @'
{
  "title": "Inventory Service Dashboard",
  "uid": "inventory-service",
  "tags": ["inventory", "service"],
  "refresh": "10s",
  "panels": [
    {
      "title": "Stock Levels",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "inventory_stock_level"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
    },
    {
      "title": "Low Stock Alerts",
      "type": "table",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "inventory_stock_level < inventory_reorder_point"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
    }
  ]
}
'@
}

function Get-OrderServiceDashboard {
    return @'
{
  "title": "Order Service Dashboard",
  "uid": "order-service",
  "tags": ["orders", "service"],
  "refresh": "5s",
  "panels": [
    {
      "title": "Order Processing Rate",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(order_service_orders_processed_total[1m])"
        }
      ],
      "gridPos": {"h": 4, "w": 8, "x": 0, "y": 0}
    },
    {
      "title": "Failed Orders",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(order_service_failed_orders_total[5m]))"
        }
      ],
      "gridPos": {"h": 8, "w": 16, "x": 8, "y": 0}
    }
  ]
}
'@
}

Export-ModuleMember -Function @(
    'Initialize-Monitoring',
    'Validate-Dashboard',
    'Provision-Dashboard',
    'Get-FrontendServiceDashboard',
    'Get-ApiGatewayDashboard',
    'Get-InventoryServiceDashboard',
    'Get-OrderServiceDashboard',
    'Get-FrontendRealtimeDashboard',
    'Get-OrdersRealtimeDashboard',
    'Get-InventoryRealtimeDashboard',
    'Get-ServiceHealthDashboard',
    'Get-SecurityDashboard'
)
