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

# Define JSON writing function
function Write-JsonWithoutBOM {
    param(
        [string]$path,
        [string]$content
    )
    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Parent $path
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        # Write file without BOM
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($path, $content.Trim(), $utf8NoBomEncoding)
        return $true
    }
    catch {
        Write-Error "Error writing file $path : $_"
        return $false
    }
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
    $dashboardPath = Join-Path $ConfigPath "grafana\dashboards"
    if (-not (Test-Path $dashboardPath)) {
        New-Item -ItemType Directory -Path $dashboardPath -Force | Out-Null
    }

    # Define dashboard configurations
    $dashboards = @(
        @{ FileName = "api-gateway.json"; GetContent = { Get-ApiGatewayDashboard } },
        @{ FileName = "security.json"; GetContent = { Get-SecurityDashboard } },
        @{ FileName = "service-health.json"; GetContent = { Get-ServiceHealthDashboard } },
        @{ FileName = "frontend-realtime.json"; GetContent = { Get-FrontendRealtimeDashboard } },
        @{ FileName = "orders-realtime.json"; GetContent = { Get-OrdersRealtimeDashboard } },
        @{ FileName = "inventory-realtime.json"; GetContent = { Get-InventoryRealtimeDashboard } },
        @{ FileName = "frontend-service.json"; GetContent = { Get-FrontendServiceDashboard } },
        @{ FileName = "inventory-service.json"; GetContent = { Get-InventoryServiceDashboard } },
        @{ FileName = "order-service.json"; GetContent = { Get-OrderServiceDashboard } },
        @{ FileName = "overview.json"; GetContent = { Get-OverviewDashboard } }
    )

    foreach ($dashboard in $dashboards) {
        $path = Join-Path $dashboardPath $dashboard.FileName
        try {
            # Get content using scriptblock
            $content = & $dashboard.GetContent
            
            if ([string]::IsNullOrEmpty($content)) {
                Write-Warning "Empty content returned for $($dashboard.FileName)"
                continue
            }

            # Write the dashboard file
            $success = Write-JsonWithoutBOM -path $path -content $content
            
            if ($success) {
                # Verify the file
                if (Test-Path $path) {
                    $bytes = [System.IO.File]::ReadAllBytes($path)
                    if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                        Write-Warning "BOM detected in $($dashboard.FileName)"
                    } else {
                        Write-Host "Successfully created $($dashboard.FileName)" -ForegroundColor Green
                    }
                }
            }
        }
        catch {
            Write-Error "Error processing $($dashboard.FileName): $_"
        }
    }

    Write-Host "`nDashboard initialization complete. Location: $dashboardPath"
    
    # Final verification
    Get-ChildItem -Path $dashboardPath -Filter "*.json" | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasBom = $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $status = if ($hasBom) { "Has BOM" } else { "No BOM" }
        Write-Host "$($_.Name): $status" -ForegroundColor $(if ($hasBom) { "Red" } else { "Green" })
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
    return @"
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
    }
  ]
}
"@
}

# Dashboard JSON definitions remain the same but with proper encoding handling
function Get-InventoryRealtimeDashboard {
    return @'
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
