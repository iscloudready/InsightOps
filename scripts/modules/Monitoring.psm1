$script:CONFIG_PATH = $env:CONFIG_PATH
$script:PROMETHEUS_PATH = Join-Path $script:CONFIG_PATH "prometheus"

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
        # Professional Service Dashboards
        @{ FileName = "api-gateway-pro-service.json"; GetContent = { Get-ApiGatewayProDashboard } },
        @{ FileName = "business-metrics-pro-service.json"; GetContent = { Get-BusinessMetricsProDashboard } },
        @{ FileName = "security-pro-service.json"; GetContent = { Get-SecurityProDashboard } },
        @{ FileName = "service-health-pro-service.json"; GetContent = { Get-ServiceHealthProDashboard } },
        @{ FileName = "realtime-ops-pro-service.json"; GetContent = { Get-RealtimeOperationsProDashboard } },
        @{ FileName = "infrastructure-pro-service.json"; GetContent = { Get-InfrastructureProDashboard } },

        # Working Service Dashboards
        @{ FileName = "frontend-service.json"; GetContent = { Get-FrontendServiceDashboard } },
        @{ FileName = "inventory-service.json"; GetContent = { Get-InventoryServiceDashboard } },
        @{ FileName = "order-service.json"; GetContent = { Get-OrderServiceDashboard } },
        @{ FileName = "overview-service.json"; GetContent = { Get-OverviewServiceDashboard } },
        @{ FileName = "windowsnodeexporter-service.json"; GetContent = { Get-WindowsNodeExporterDashboard } }
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

    # Restart Grafana container
    Write-Host "Restarting Grafana container..."
    docker restart insightops_grafana
    Write-Host "Grafana container restarted successfully."
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

function Get-OverviewServiceDashboard {
    return @'
{
  "title": "Overview Service Dashboard",
  "uid": "overview-service",
  "tags": ["overview", "service"],
  "refresh": "10s",
  "panels": [
    {
      "title": "System Overview",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(up{job=~\".*\"} == 1)",
          "legendFormat": "Active Services"
        }
      ],
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
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

function Get-WindowsNodeExporterDashboard {
    return @'
{
  "title": "Windows Node Exporter Service Dashboard",
  "uid": "windows-service",
  "tags": ["windows", "service"],
  "refresh": "5s",
  "panels": [
    {
      "title": "CPU Usage",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "orange",
                "value": 70
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "100 - (avg by (instance) (irate(windows_cpu_time_total{mode=\"idle\"}[1m])) * 100)",
          "legendFormat": "CPU Usage"
        }
      ]
    },
    {
      "title": "Memory Usage",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "orange",
                "value": 80
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0},
      "targets": [
        {
          "expr": "(windows_cs_physical_memory_bytes - windows_os_physical_memory_free_bytes) / windows_cs_physical_memory_bytes * 100",
          "legendFormat": "Memory Usage"
        }
      ]
    },
    {
      "title": "Disk Usage",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "orange",
                "value": 80
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
      "targets": [
        {
          "expr": "100 - ((windows_logical_disk_free_bytes * 100) / windows_logical_disk_size_bytes)",
          "legendFormat": "{{volume}}"
        }
      ]
    },
    {
      "title": "Network Bandwidth",
      "type": "timeseries",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "rate(windows_net_bytes_total[5m])",
          "legendFormat": "Network Traffic"
        }
      ]
    }
  ]
}
'@
}



function Get-ApiGatewayProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Deployment Markers",
        "type": "dashboard"
      }
    ]
  },
  "title": "API Gateway Service Pro",
  "uid": "api-gateway-service-pro",
  "tags": ["api", "gateway", "service"],
  "refresh": "10s",
  "timezone": "browser",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Gateway Health",
      "type": "stat",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 80 },
              { "color": "green", "value": 90 }
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 4, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "avg(up{job=\"api-gateway\"}) * 100",
          "legendFormat": "Health"
        }
      ]
    },
    {
      "title": "Request Rate",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 4, "y": 0},
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{job=\"api-gateway\"}[5m])) by (status)",
          "legendFormat": "{{status}}"
        }
      ]
    },
    {
      "title": "Error Rate",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 5 },
              { "color": "red", "value": 10 }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{job=\"api-gateway\", status=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"api-gateway\"}[5m])) * 100",
          "legendFormat": "Error Rate"
        }
      ]
    },
    {
      "title": "Latency Distribution",
      "type": "heatmap",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(http_request_duration_seconds_bucket{job=\"api-gateway\"}[5m])) by (le)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Top Endpoints",
      "type": "table",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "targets": [
        {
          "expr": "topk(10, sum(rate(http_requests_total{job=\"api-gateway\"}[5m])) by (endpoint))",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "sortBy",
          "options": {
            "fields": {},
            "sort": [
              {
                "field": "Value",
                "order": "desc"
              }
            ]
          }
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "service",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(http_requests_total, service)",
        "refresh": 2
      }
    ]
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  }
}
'@
}

function Get-SecurityProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(255, 96, 96, 1)",
        "name": "Security Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Security Service Pro",
  "uid": "security-service-pro",
  "tags": ["security", "service"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Authentication Status",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          },
          "color": {
            "mode": "palette-classic"
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "sum(rate(auth_attempts_total[5m])) by (status)",
          "legendFormat": "{{status}}"
        }
      ],
      "alert": {
        "name": "High Failed Auth Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": [ "A", "5m", "now" ] },
            "reducer": { "type": "avg", "params": [] },
            "evaluator": { "type": "gt", "params": [ 10 ] }
          }
        ]
      }
    },
    {
      "title": "Active Sessions",
      "type": "stat",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null }
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
      "targets": [
        {
          "expr": "sum(active_sessions)",
          "legendFormat": "Sessions"
        }
      ]
    },
    {
      "title": "IP Blacklist Hits",
      "type": "timeseries",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(ip_blacklist_hits_total[5m])) by (ip)",
          "legendFormat": "{{ip}}"
        }
      ],
      "alert": {
        "name": "Multiple Blacklist Hits",
        "frequency": "1m",
        "conditions": [
          {
            "type": "query",
            "query": { "params": [ "A", "5m", "now" ] },
            "reducer": { "type": "sum", "params": [] },
            "evaluator": { "type": "gt", "params": [ 100 ] }
          }
        ]
      }
    }
  ],
  "templating": {
    "list": [
      {
        "name": "status",
        "type": "custom",
        "query": "success,failure",
        "current": { "value": "failure" },
        "options": [
          { "value": "success", "text": "Success" },
          { "value": "failure", "text": "Failure" }
        ]
      }
    ]
  }
}
'@
}

function Get-ServiceHealthProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Service Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Service Health Pro",
  "uid": "service-health-pro",
  "tags": ["health", "service"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Overall Service Health",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 80 },
              { "color": "green", "value": 95 }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "avg(up{service=~\"$service\"}) * 100",
          "legendFormat": "Health Score"
        }
      ]
    },
    {
      "title": "Service Response Times",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          }
        }
      },
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=~\"$service\"}[5m])) by (le, service))",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Error Rates by Service",
      "type": "timeseries",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{status=~\"5..\", service=~\"$service\"}[5m])) by (service) / sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (service) * 100",
          "legendFormat": "{{service}}"
        }
      ],
      "alert": {
        "name": "High Error Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": [ "A", "5m", "now" ] },
            "reducer": { "type": "avg", "params": [] },
            "evaluator": { "type": "gt", "params": [ 5 ] }
          }
        ]
      }
    },
    {
      "title": "Resource Usage",
      "type": "timeseries",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(process_cpu_seconds_total{service=~\"$service\"}[5m])) by (service)",
          "legendFormat": "{{service}} CPU"
        },
        {
          "expr": "sum(process_resident_memory_bytes{service=~\"$service\"}) by (service)",
          "legendFormat": "{{service}} Memory"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "service",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(up, service)",
        "refresh": 2,
        "includeAll": true
      }
    ]
  }
}
'@
}

function Get-BusinessMetricsProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Business Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Business Metrics Service Pro",
  "uid": "business-metrics-service-pro",
  "tags": ["business", "service"],
  "refresh": "5m",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Revenue Overview",
      "type": "stat",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 50000 },
              { "color": "green", "value": 100000 }
            ]
          },
          "unit": "currencyUSD"
        }
      },
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "sum(order_total_amount_sum)",
          "legendFormat": "Total Revenue"
        }
      ]
    },
    {
      "title": "Orders by Status",
      "type": "piechart",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 8, "x": 6, "y": 0},
      "options": {
        "legend": {
          "displayMode": "table",
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(orders_total) by (status)",
          "legendFormat": "{{status}}"
        }
      ]
    },
    {
      "title": "Customer Satisfaction",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 70 },
              { "color": "green", "value": 90 }
            ]
          },
          "unit": "percent"
        }
      },
      "gridPos": {"h": 8, "w": 8, "x": 14, "y": 0},
      "targets": [
        {
          "expr": "avg(customer_satisfaction_score) * 100",
          "legendFormat": "CSAT"
        }
      ]
    },
    {
      "title": "Revenue Trends",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10,
            "spanNulls": false
          },
          "unit": "currencyUSD"
        }
      },
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(order_total_amount_sum[1h])) by (product_category)",
          "legendFormat": "{{product_category}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "timeframe",
        "type": "interval",
        "query": "1h,6h,12h,1d,7d,30d,90d",
        "current": { "selected": true, "text": "7d", "value": "7d" }
      },
      {
        "name": "product_category",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(order_total_amount_sum, product_category)",
        "refresh": 2,
        "includeAll": true
      }
    ]
  }
}
'@
}

function Get-RealtimeOperationsProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(255, 96, 96, 1)",
        "name": "Alerts",
        "type": "dashboard"
      }
    ]
  },
  "title": "Realtime Operations Service Pro",
  "uid": "realtime-ops-service-pro",
  "tags": ["operations", "realtime", "service"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "System Load",
      "type": "gauge",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 70 },
              { "color": "red", "value": 85 }
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "avg(rate(node_cpu_seconds_total{mode!=\"idle\"}[5m])) * 100",
          "legendFormat": "CPU Load"
        }
      ]
    },
    {
      "title": "Real-time Throughput",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "bars",
            "lineWidth": 1,
            "fillOpacity": 50
          }
        }
      },
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[1m])) by (service)",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Active Connections",
      "type": "stat",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null }
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 4, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(active_connections)",
          "legendFormat": "Connections"
        }
      ]
    },
    {
      "title": "Memory Usage Trend",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          },
          "unit": "bytes"
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 4, "y": 8},
      "targets": [
        {
          "expr": "sum(process_resident_memory_bytes) by (service)",
          "legendFormat": "{{service}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "service",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(http_requests_total, service)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "instance",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(up{service=~\"$service\"}, instance)",
        "refresh": 1
      }
    ]
  },
  "time": {
    "from": "now-15m",
    "to": "now"
  }
}
'@
}

function Get-InfrastructureProDashboard {
    return @'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(255, 96, 96, 1)",
        "name": "Infrastructure Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Infrastructure Service Pro",
  "uid": "infrastructure-service-pro",
  "tags": ["infrastructure", "service"],
  "refresh": "30s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Cluster Overview",
      "type": "nodeGraph",
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "kube_pod_info",
          "legendFormat": "{{pod}}"
        }
      ]
    },
    {
      "title": "Resource Utilization",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "targets": [
        {
          "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (container)",
          "legendFormat": "{{container}} CPU"
        },
        {
          "expr": "sum(container_memory_usage_bytes{container!=\"\"}) by (container)",
          "legendFormat": "{{container}} Memory"
        }
      ]
    },
    {
      "title": "Network Traffic",
      "type": "timeseries",
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          },
          "unit": "bytes"
        }
      },
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "targets": [
        {
          "expr": "sum(rate(container_network_receive_bytes_total[5m])) by (pod)",
          "legendFormat": "{{pod}} Received"
        },
        {
          "expr": "sum(rate(container_network_transmit_bytes_total[5m])) by (pod)",
          "legendFormat": "{{pod}} Transmitted"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_namespace_status_phase, namespace)",
        "refresh": 1
      },
      {
        "name": "deployment",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_deployment_status_replicas, deployment)",
        "refresh": 1
      }
    ]
  }
}
'@
}

# Function to create Prometheus configuration file
function Create-PrometheusConfig {
    param (
        [string]$configPath,
        [string]$systemIp,
        [int]$exporterPort,
        [int]$prometheusPort
    )
    try {
        if (-not $configPath) {
            throw "CONFIG_PATH is not set."
        }
        if (-not $systemIp) {
            throw "System IP address is not set."
        }
        if (-not $exporterPort) {
            throw "Exporter port is not set."
        }
        if (-not $prometheusPort) {
            throw "Prometheus port is not set."
        }

        $configFilePath = Join-Path $configPath "prometheus.yml"
        if (Test-Path $configFilePath -PathType Container) {
            # If the path exists as a container (folder), remove it
            Remove-Item $configFilePath -Recurse -Force
        }

        $prometheusConfig = @"
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${prometheusPort}']

  - job_name: 'dotnet'
    static_configs:
      - targets: ['gateway:80', 'orders:80', 'inventory:80', 'frontend:80']

  - job_name: 'windows_exporter'
    static_configs:
      - targets: ['${systemIp}:${exporterPort}', 'localhost:${exporterPort}']
"@
        $prometheusConfig | Set-Content -Path $configFilePath -Force
        Write-Host "Prometheus configuration created at $configFilePath."
    } catch {
        Write-Host "An error occurred: $($Error[0].Message)"
        Write-Host "Error details: $($Error[0].Exception.ToString())"
    }
}

# Function to update Prometheus configuration file
function Update-PrometheusConfigFile {
    param (
        [string]$systemIp,
        [int]$exporterPort
    )
    try {
        if (-not $systemIp) {
            throw "System IP address is not set."
        }
        if (-not $exporterPort) {
            throw "Exporter port is not set."
        }

        $configPath = Join-Path $script:CONFIG_PATH "/prometheus"
        $configFilePath = Join-Path $configPath "prometheus.yml"

        if (!(Test-Path $configFilePath)) {
            # Create the configuration file if it doesn't exist
            Create-PrometheusConfig -configPath $configPath -systemIp $systemIp -exporterPort $exporterPort -prometheusPort 9090
        } else {
            # Check if the windows_exporter job already exists
            $configContent = Get-Content -Path $configFilePath -Raw
            if ($configContent -match "job_name: 'windows_exporter'") {
                Write-Host "Windows exporter job already exists in Prometheus configuration."
            } else {
                # Update the existing configuration file
                $windowsExporterConfig = @"
  
  - job_name: 'windows_exporter'
    static_configs:
      - targets: ['${systemIp}:${exporterPort}', 'localhost:${exporterPort}']
"@
                Add-Content -Path $configFilePath -Value $windowsExporterConfig -Force
                Write-Host "Updated Prometheus configuration at $configFilePath."
            }
        }
    } catch {
        Write-Host "An error occurred: $($Error[0].Message)"
        Write-Host "Error details: $($Error[0].Exception.ToString())"
    }
}

Export-ModuleMember -Function @(
    # Core Functions
    'Initialize-Monitoring',
    'Validate-Dashboard',
    'Provision-Dashboard',

    # Pro Dashboards
    'Get-ApiGatewayProDashboard',
    'Get-SecurityProDashboard',
    'Get-ServiceHealthProDashboard',
    'Get-BusinessMetricsProDashboard',
    'Get-RealtimeOperationsProDashboard',
    'Get-InfrastructureProDashboard',

    # Service Dashboards
    'Get-FrontendServiceDashboard',
    'Get-InventoryServiceDashboard',
    'Get-OrderServiceDashboard',
    'Get-OverviewServiceDashboard',
    'Get-WindowsNodeExporterDashboard',

    'Update-PrometheusConfig',
    'Update-PrometheusConfigFile',
    'Create-PrometheusConfig'
)