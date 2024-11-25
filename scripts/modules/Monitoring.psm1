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
        # Core Pro Service Dashboards
        @{ FileName = "frontend-pro-service.json"; GetContent = { Get-FrontendProServiceDashboard } },
        @{ FileName = "inventory-pro-service.json"; GetContent = { Get-InventoryProServiceDashboard } },
        @{ FileName = "order-pro-service.json"; GetContent = { Get-OrderProServiceDashboard } },
        @{ FileName = "overview-pro-service.json"; GetContent = { Get-OverviewProServiceDashboard } },

        # Microservices Pro Dashboards
        @{ FileName = "microservices-overview-pro-service.json"; GetContent = { Get-MicroservicesOverviewProDashboard } },
        @{ FileName = "microservices-dependency-pro-service.json"; GetContent = { Get-MicroservicesDependencyProDashboard } },
        @{ FileName = "microservices-performance-pro-service.json"; GetContent = { Get-MicroservicesPerformanceProDashboard } },
        @{ FileName = "microservices-traffic-pro-service.json"; GetContent = { Get-MicroservicesTrafficProDashboard } },

        # Docker Pro Dashboards
        @{ FileName = "docker-overview-pro-service.json"; GetContent = { Get-DockerOverviewProDashboard } },
        @{ FileName = "docker-resources-pro-service.json"; GetContent = { Get-DockerResourcesProDashboard } },
        @{ FileName = "docker-logs-pro-service.json"; GetContent = { Get-DockerLogsProDashboard } },
        @{ FileName = "docker-network-pro-service.json"; GetContent = { Get-DockerNetworkProDashboard } },

        # API Gateway Pro Dashboards
        @{ FileName = "api-gateway-traffic-pro-service.json"; GetContent = { Get-ApiGatewayTrafficProDashboard } },
        @{ FileName = "api-gateway-security-pro-service.json"; GetContent = { Get-ApiGatewaySecurityProDashboard } },
        @{ FileName = "api-gateway-performance-pro-service.json"; GetContent = { Get-ApiGatewayPerformanceProDashboard } },
        @{ FileName = "api-gateway-routing-pro-service.json"; GetContent = { Get-ApiGatewayRoutingProDashboard } },

        # Business and Operations Dashboards
        @{ FileName = "business-metrics-pro-service.json"; GetContent = { Get-BusinessMetricsProDashboard } },
        @{ FileName = "realtime-ops-pro-service.json"; GetContent = { Get-RealtimeOperationsProDashboard } },
        @{ FileName = "infrastructure-pro-service.json"; GetContent = { Get-InfrastructureProDashboard } },

        # Security and Health Dashboards
        @{ FileName = "security-pro-service.json"; GetContent = { Get-SecurityProDashboard } },
        @{ FileName = "service-health-pro-service.json"; GetContent = { Get-ServiceHealthProDashboard } },
        @{ FileName = "windows-nodeexporter-pro-service.json"; GetContent = { Get-WindowsNodeExporterDashboard } }
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
    if (docker ps -a --format "{{.Names}}" | Select-String -Pattern "insightops_grafana" -Quiet) {
        docker restart insightops_grafana
        Write-Host "Grafana container restarted successfully."
    } else {
        Write-Host "Grafana container does not exist."
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

function Get-FrontendProServiceDashboard {
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
        "name": "Frontend Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Frontend Service Pro Dashboard",
  "uid": "frontend-service-pro",
  "tags": ["frontend", "service", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "User Activity Overview",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 1000 },
              { "color": "red", "value": 5000 }
            ]
          }
        }
      },
      "targets": [
        {
          "expr": "sum(frontend_active_sessions)",
          "legendFormat": "Active Users"
        }
      ]
    },
    {
      "title": "Geographic Distribution",
      "type": "geomap",
      "gridPos": {"h": 8, "w": 12, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(frontend_sessions_by_region) by (region)",
          "legendFormat": "{{region}}"
        }
      ]
    },
    {
      "title": "Performance Metrics",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(frontend_page_load_time_bucket[5m])) by (le, page))",
          "legendFormat": "{{page}} - P95"
        },
        {
          "expr": "histogram_quantile(0.99, sum(rate(frontend_page_load_time_bucket[5m])) by (le, page))",
          "legendFormat": "{{page}} - P99"
        }
      ],
      "alert": {
        "name": "High Page Load Time",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "avg" },
            "evaluator": { "type": "gt", "params": [3] }
          }
        ]
      }
    },
    {
      "title": "Error Analysis",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(frontend_error_total[5m])) by (type, code)",
          "legendFormat": "{{type}} - {{code}}"
        }
      ]
    },
    {
      "title": "User Journey Funnel",
      "type": "barchart",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(frontend_user_journey_stage) by (stage)",
          "legendFormat": "{{stage}}"
        }
      ]
    },
    {
      "title": "Browser Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(frontend_browser_usage) by (browser)",
          "legendFormat": "{{browser}}"
        }
      ]
    },
    {
      "title": "Resource Loading",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(frontend_resource_load_time_sum[5m])) by (resource_type) / sum(rate(frontend_resource_load_time_count[5m])) by (resource_type)",
          "legendFormat": "{{resource_type}}"
        }
      ]
    },
    {
      "title": "API Interactions",
      "type": "table",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(frontend_api_calls_total[5m])) by (endpoint))",
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
        "name": "page",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(frontend_page_load_time_bucket, page)",
        "refresh": 2
      },
      {
        "name": "browser",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(frontend_browser_usage, browser)",
        "refresh": 2
      },
      {
        "name": "region",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(frontend_sessions_by_region, region)",
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

function Get-InventoryProServiceDashboard {
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
        "name": "Inventory Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Inventory Service Pro Dashboard",
  "uid": "inventory-service-pro",
  "tags": ["inventory", "service", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Stock Level Overview",
      "type": "gauge",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 50 },
              { "color": "green", "value": 80 }
            ]
          }
        }
      },
      "targets": [
        {
          "expr": "avg(inventory_stock_level_percentage)",
          "legendFormat": "Stock Level"
        }
      ]
    },
    {
      "title": "Low Stock Items",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "inventory_stock_level < inventory_reorder_point",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "item": "Item",
              "stock_level": "Current Stock",
              "reorder_point": "Reorder Point"
            }
          }
        }
      ],
      "alert": {
        "name": "Critical Stock Level",
        "frequency": "5m",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "count" },
            "evaluator": { "type": "gt", "params": [10] }
          }
        ]
      }
    },
    {
      "title": "Stock Movement Trends",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "targets": [
        {
          "expr": "sum(rate(inventory_stock_movement_total[5m])) by (direction)",
          "legendFormat": "{{direction}}"
        }
      ]
    },
    {
      "title": "Warehouse Capacity",
      "type": "bargauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "percentage",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 70 },
              { "color": "red", "value": 90 }
            ]
          }
        }
      },
      "targets": [
        {
          "expr": "(sum(inventory_used_space) by (warehouse) / sum(inventory_total_space) by (warehouse)) * 100",
          "legendFormat": "{{warehouse}}"
        }
      ]
    },
    {
      "title": "Stock Value Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(inventory_stock_value) by (category)",
          "legendFormat": "{{category}}"
        }
      ]
    },
    {
      "title": "Inventory Turnover",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(inventory_items_sold_total[7d]) / avg_over_time(inventory_stock_level[7d])",
          "legendFormat": "Turnover Rate"
        }
      ]
    },
    {
      "title": "Stock Accuracy",
      "type": "stat",
      "gridPos": {"h": 4, "w": 8, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "unit": "percentunit",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 0.95 },
              { "color": "green", "value": 0.98 }
            ]
          }
        }
      },
      "targets": [
        {
          "expr": "sum(inventory_actual_count) / sum(inventory_expected_count)",
          "legendFormat": "Accuracy"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "warehouse",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(inventory_used_space, warehouse)",
        "refresh": 2
      },
      {
        "name": "category",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(inventory_stock_value, category)",
        "refresh": 2
      }
    ]
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  }
}
'@
}

function Get-OrderProServiceDashboard {
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
        "name": "Order Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Order Service Pro Dashboard",
  "uid": "order-service-pro",
  "tags": ["orders", "service", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Order Processing Status",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 90 },
              { "color": "green", "value": 95 }
            ]
          },
          "unit": "percent"
        }
      },
      "targets": [
        {
          "expr": "sum(rate(order_processing_success_total[5m])) / sum(rate(order_processing_total[5m])) * 100",
          "legendFormat": "Success Rate"
        }
      ]
    },
    {
      "title": "Order Flow Analysis",
      "type": "nodeGraph",
      "gridPos": {"h": 8, "w": 12, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(order_stage_duration_seconds_count[5m])) by (from_stage, to_stage)",
          "legendFormat": "{{from_stage}} -> {{to_stage}}"
        }
      ]
    },
    {
      "title": "Order Processing Time",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(order_processing_duration_seconds_bucket[5m])) by (le, type))",
          "legendFormat": "{{type}} - P95"
        },
        {
          "expr": "histogram_quantile(0.99, sum(rate(order_processing_duration_seconds_bucket[5m])) by (le, type))",
          "legendFormat": "{{type}} - P99"
        }
      ],
      "alert": {
        "name": "High Processing Time",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "avg" },
            "evaluator": { "type": "gt", "params": [30] }
          }
        ]
      }
    },
    {
      "title": "Order Volume by Region",
      "type": "worldmap-panel",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(orders_total[5m])) by (region)",
          "legendFormat": "{{region}}"
        }
      ]
    },
    {
      "title": "Payment Methods Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(order_payment_method_total) by (method)",
          "legendFormat": "{{method}}"
        }
      ]
    },
    {
      "title": "Order Status Distribution",
      "type": "bargauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(orders_by_status) by (status)",
          "legendFormat": "{{status}}"
        }
      ]
    },
    {
      "title": "Failed Orders Analysis",
      "type": "table",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(order_failures_total[5m])) by (reason, stage))",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "reason": "Failure Reason",
              "stage": "Processing Stage",
              "Value": "Count"
            }
          }
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "region",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(orders_total, region)",
        "refresh": 2
      },
      {
        "name": "payment_method",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(order_payment_method_total, method)",
        "refresh": 2
      },
      {
        "name": "order_type",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(order_processing_duration_seconds_bucket, type)",
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

function Get-OverviewProServiceDashboard {
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
        "name": "System Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "System Overview Pro Dashboard",
  "uid": "overview-service-pro",
  "tags": ["overview", "service", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "System Health Score",
      "type": "gauge",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 80 },
              { "color": "green", "value": 90 }
            ]
          },
          "unit": "percent"
        }
      },
      "targets": [
        {
          "expr": "avg(up{service=~\"$service\"}) * 100",
          "legendFormat": "Health"
        }
      ]
    },
    {
      "title": "Service Status Matrix",
      "type": "status-history",
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "up{service=~\"$service\"}",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "System Resource Usage",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "targets": [
        {
          "expr": "sum(rate(process_cpu_seconds_total[5m])) by (service)",
          "legendFormat": "{{service}} CPU"
        },
        {
          "expr": "sum(process_resident_memory_bytes) by (service)",
          "legendFormat": "{{service}} Memory"
        }
      ]
    },
    {
      "title": "Error Rate Overview",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) * 100",
          "legendFormat": "{{service}}"
        }
      ],
      "alert": {
        "name": "High Error Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [5] }
          }
        ]
      }
    },
    {
      "title": "Service Dependencies",
      "type": "nodeGraph",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(service_calls_total[5m])) by (caller_service, called_service)",
          "legendFormat": "{{caller_service}} -> {{called_service}}"
        }
      ]
    },
    {
      "title": "Response Time Distribution",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Service SLA Status",
      "type": "bargauge",
      "gridPos": {"h": 6, "w": 24, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "percentage",
            "steps": [
              { "color": "red", "value": null },
              { "color": "yellow", "value": 95 },
              { "color": "green", "value": 99 }
            ]
          }
        }
      },
      "targets": [
        {
          "expr": "avg_over_time(up{service=~\"$service\"}[24h]) * 100",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Recent Alerts",
      "type": "table",
      "gridPos": {"h": 6, "w": 24, "x": 0, "y": 30},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "ALERTS{alertstate=\"firing\"}",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "alertname": "Alert",
              "severity": "Severity",
              "service": "Service"
            }
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
        "query": "label_values(up, service)",
        "refresh": 1,
        "includeAll": true,
        "multi": true
      },
      {
        "name": "timerange",
        "type": "interval",
        "query": "1m,5m,15m,30m,1h,6h,12h,24h",
        "current": {
          "selected": true,
          "text": "5m",
          "value": "5m"
        }
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

function Get-MicroservicesOverviewProDashboard {
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
        "name": "Deployments",
        "type": "dashboard"
      }
    ]
  },
  "title": "Microservices Overview Pro Dashboard",
  "uid": "microservices-overview-pro",
  "tags": ["microservices", "overview", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Services Health Matrix",
      "type": "statusmap",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "up{service=~\"$service\"}",
          "legendFormat": "{{service}} - {{instance}}"
        }
      ]
    },
    {
      "title": "Service Instance Count",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      },
      "targets": [
        {
          "expr": "count(up{service=~\"$service\"}) by (service)",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Cross-Service Communication",
      "type": "nodeGraph",
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(service_calls_total[5m])) by (source_service, destination_service)",
          "legendFormat": "{{source_service}} -> {{destination_service}}"
        }
      ]
    },
    {
      "title": "Service Response Times",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
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
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=~\"$service\"}[5m])) by (le, service))",
          "legendFormat": "{{service}} P95"
        }
      ],
      "alert": {
        "name": "High Latency Alert",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [1] }
          }
        ]
      }
    },
    {
      "title": "Error Rates",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{status=~\"5..\", service=~\"$service\"}[5m])) by (service) / sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (service) * 100",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Resource Usage by Service",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24},
      "datasource": "Prometheus",
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
    },
    {
      "title": "Circuit Breaker Status",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 32},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "circuit_breaker_state",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "service": "Service",
              "state": "State",
              "last_trip": "Last Trip"
            }
          }
        }
      ]
    },
    {
      "title": "Service Version Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 32},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value"]
        }
      },
      "targets": [
        {
          "expr": "count(service_version) by (version)",
          "legendFormat": "{{version}}"
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
        "refresh": 1,
        "includeAll": true,
        "multi": true
      },
      {
        "name": "instance",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(up{service=~\"$service\"}, instance)",
        "refresh": 1,
        "includeAll": true
      }
    ]
  },
  "time": {
    "from": "now-3h",
    "to": "now"
  }
}
'@
}

function Get-MicroservicesDependencyProDashboard {
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
        "name": "Service Changes",
        "type": "dashboard"
      }
    ]
  },
  "title": "Microservices Dependency Pro Dashboard",
  "uid": "microservices-dependency-pro",
  "tags": ["microservices", "dependency", "pro"],
  "refresh": "30s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Service Dependency Map",
      "type": "nodeGraph",
      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(service_calls_total[5m])) by (caller, callee)",
          "legendFormat": "{{caller}} -> {{callee}}"
        }
      ]
    },
    {
      "title": "Dependency Health Matrix",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(service_call_errors_total[5m])) by (caller, callee) / sum(rate(service_calls_total[5m])) by (caller, callee)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Cross-Service Latency",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(service_call_duration_bucket[5m])) by (le, caller, callee))",
          "legendFormat": "{{caller}} -> {{callee}}"
        }
      ]
    },
    {
      "title": "Circuit Breaker Triggers",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(circuit_breaker_trips_total[5m])) by (service)",
          "legendFormat": "{{service}}"
        }
      ],
      "alert": {
        "name": "Circuit Breaker Alert",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "sum" },
            "evaluator": { "type": "gt", "params": [5] }
          }
        ]
      }
    },
    {
      "title": "Service Availability Impact",
      "type": "state-timeline",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "avg_over_time(up{service=~\"$service\"}[5m])",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Dependency Chain Analysis",
      "type": "table",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 28},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "service_dependency_depth",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "service": "Service",
              "depth": "Dependency Depth",
              "dependencies": "Direct Dependencies"
            }
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
        "query": "label_values(up, service)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "errorThreshold",
        "type": "constant",
        "label": "Error Rate Threshold",
        "value": "5"
      }
    ]
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  }
}
'@
}

function Get-MicroservicesPerformanceProDashboard {
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
        "name": "Performance Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Microservices Performance Pro Dashboard",
  "uid": "microservices-performance-pro",
  "tags": ["microservices", "performance", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Service Response Time Overview",
      "type": "gauge",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 200 },
              { "color": "red", "value": 500 }
            ]
          },
          "unit": "ms"
        }
      },
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_ms_bucket{service=~\"$service\"}[5m])) by (le))",
          "legendFormat": "P95 Latency"
        }
      ]
    },
    {
      "title": "Latency Distribution by Service",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_request_duration_ms_bucket{service=~\"$service\"}[5m])) by (le, service)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Memory Usage Patterns",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "targets": [
        {
          "expr": "sum(jvm_memory_used_bytes{service=~\"$service\"}) by (service, area)",
          "legendFormat": "{{service}} - {{area}}"
        }
      ]
    },
    {
      "title": "CPU Usage Analysis",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(process_cpu_seconds_total{service=~\"$service\"}[5m])) by (service)",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Garbage Collection Impact",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(jvm_gc_collection_seconds_sum{service=~\"$service\"}[5m])",
          "legendFormat": "{{service}} - {{gc}}"
        }
      ],
      "alert": {
        "name": "High GC Time",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [0.1] }
          }
        ]
      }
    },
    {
      "title": "Thread States",
      "type": "bargauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "jvm_threads_states_threads{service=~\"$service\"}",
          "legendFormat": "{{state}}"
        }
      ]
    },
    {
      "title": "Database Connection Pool",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "hikaricp_connections_active{service=~\"$service\"}",
          "legendFormat": "{{service}} - Active"
        },
        {
          "expr": "hikaricp_connections_idle{service=~\"$service\"}",
          "legendFormat": "{{service}} - Idle"
        }
      ]
    },
    {
      "title": "Cache Hit Rates",
      "type": "gauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 24},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
          "unit": "percent"
        }
      },
      "targets": [
        {
          "expr": "rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m])) * 100",
          "legendFormat": "{{cache}}"
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
        "refresh": 1,
        "includeAll": true,
        "multi": true
      },
      {
        "name": "interval",
        "type": "interval",
        "query": "1m,5m,10m,30m,1h,6h,12h,1d",
        "current": {
          "selected": true,
          "text": "5m",
          "value": "5m"
        }
      }
    ]
  }
}
'@
}

function Get-MicroservicesTrafficProDashboard {
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
        "name": "Traffic Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Microservices Traffic Pro Dashboard",
  "uid": "microservices-traffic-pro",
  "tags": ["microservices", "traffic", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Request Rate Overview",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "unit": "reqps"
        }
      },
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[5m]))",
          "legendFormat": "Total RPS"
        }
      ]
    },
    {
      "title": "Traffic Distribution by Service",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 8, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (service)",
          "legendFormat": "{{service}}"
        }
      ]
    },
    {
      "title": "Traffic Flow Visualization",
      "type": "nodeGraph",
      "gridPos": {"h": 8, "w": 10, "x": 14, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (source_service, destination_service)",
          "legendFormat": "{{source_service}} -> {{destination_service}}"
        }
      ]
    },
    {
      "title": "Request Rate by Method",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "bars",
            "fillOpacity": 60
          }
        }
      },
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (method)",
          "legendFormat": "{{method}}"
        }
      ]
    },
    {
      "title": "Status Code Distribution",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (status)",
          "legendFormat": "{{status}}"
        }
      ],
      "alert": {
        "name": "High Error Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "sum" },
            "evaluator": { "type": "gt", "params": [100] }
          }
        ]
      }
    },
    {
      "title": "Top Endpoints",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(http_requests_total{service=~\"$service\"}[5m])) by (endpoint))",
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
    },
    {
      "title": "Network Traffic Volume",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "unit": "bytes"
        }
      },
      "targets": [
        {
          "expr": "sum(rate(network_receive_bytes_total{service=~\"$service\"}[5m])) by (service)",
          "legendFormat": "{{service}} - Received"
        },
        {
          "expr": "sum(rate(network_transmit_bytes_total{service=~\"$service\"}[5m])) by (service)",
          "legendFormat": "{{service}} - Transmitted"
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
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "status_code",
        "type": "custom",
        "query": "200,400,401,403,404,500,502,503,504",
        "current": {
          "selected": true,
          "text": "500",
          "value": "500"
        }
      }
    ]
  }
}
'@
}

function Get-DockerOverviewProDashboard {
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
        "name": "Docker Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Docker Overview Pro Dashboard",
  "uid": "docker-overview-pro",
  "tags": ["docker", "containers", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Container Status Overview",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      },
      "targets": [
        {
          "expr": "sum(docker_container_status)",
          "legendFormat": "Running Containers"
        }
      ]
    },
    {
      "title": "Container Health Matrix",
      "type": "statusmap",
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "docker_container_health_status",
          "legendFormat": "{{name}}"
        }
      ]
    },
    {
      "title": "Resource Utilization",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
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
      "title": "Container Restarts",
      "type": "bargauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "options": {
        "orientation": "horizontal",
        "showUnfilled": true
      },
      "targets": [
        {
          "expr": "docker_container_restart_count",
          "legendFormat": "{{name}}"
        }
      ],
      "alert": {
        "name": "High Restart Count",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [5] }
          }
        ]
      }
    },
    {
      "title": "Network Traffic by Container",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(container_network_receive_bytes_total[5m])",
          "legendFormat": "{{container}} Rx"
        },
        {
          "expr": "rate(container_network_transmit_bytes_total[5m])",
          "legendFormat": "{{container}} Tx"
        }
      ]
    },
    {
      "title": "Disk Usage",
      "type": "gauge",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "max": 100,
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
      "targets": [
        {
          "expr": "(container_fs_usage_bytes / container_fs_limit_bytes) * 100",
          "legendFormat": "{{container}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(container_cpu_usage_seconds_total, container)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "node",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(node)",
        "refresh": 1
      }
    ]
  },
  "time": {
    "from": "now-3h",
    "to": "now"
  }
}
'@
}

function Get-DockerResourcesProDashboard {
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
        "name": "Resource Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Docker Resources Pro Dashboard",
  "uid": "docker-resources-pro",
  "tags": ["docker", "resources", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "CPU Usage by Container",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
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
      "targets": [
        {
          "expr": "rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])",
          "legendFormat": "{{container}}"
        }
      ]
    },
    {
      "title": "Memory Usage Trends",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "container_memory_usage_bytes{container!=\"\"}",
          "legendFormat": "{{container}}"
        }
      ]
    },
    {
      "title": "Network I/O",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "unit": "bytes"
        }
      },
      "targets": [
        {
          "expr": "rate(container_network_receive_bytes_total[5m])",
          "legendFormat": "{{container}} Rx"
        },
        {
          "expr": "rate(container_network_transmit_bytes_total[5m])",
          "legendFormat": "{{container}} Tx"
        }
      ]
    },
    {
      "title": "Disk I/O",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(container_fs_reads_bytes_total[5m])",
          "legendFormat": "{{container}} Reads"
        },
        {
          "expr": "rate(container_fs_writes_bytes_total[5m])",
          "legendFormat": "{{container}} Writes"
        }
      ]
    },
    {
      "title": "Resource Limits vs Usage",
      "type": "bargauge",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "options": {
        "orientation": "horizontal",
        "showUnfilled": true
      },
      "targets": [
        {
          "expr": "container_spec_memory_limit_bytes",
          "legendFormat": "{{container}} Memory Limit"
        },
        {
          "expr": "container_memory_usage_bytes",
          "legendFormat": "{{container}} Memory Usage"
        }
      ]
    },
    {
      "title": "Container Throttling",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(container_cpu_cfs_throttled_periods_total[5m])",
          "legendFormat": "{{container}}"
        }
      ],
      "alert": {
        "name": "High CPU Throttling",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [10] }
          }
        ]
      }
    }
  ],
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(container_cpu_usage_seconds_total, container)",
        "refresh": 1,
        "includeAll": true
      }
    ]
  }
}
'@
}

function Get-DockerLogsProDashboard {
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
        "name": "Log Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Docker Logs Pro Dashboard",
  "uid": "docker-logs-pro",
  "tags": ["docker", "logs", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Log Volume Overview",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Loki",
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      },
      "targets": [
        {
          "expr": "sum(count_over_time({container=~\"$container\"} [5m]))",
          "legendFormat": "Log Rate"
        }
      ]
    },
    {
      "title": "Log Level Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 8, "x": 6, "y": 0},
      "datasource": "Loki",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(count_over_time({container=~\"$container\"} |= \"error\" [5m])) by (level)",
          "legendFormat": "{{level}}"
        }
      ]
    },
    {
      "title": "Error Trends",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 10, "x": 14, "y": 0},
      "datasource": "Loki",
      "targets": [
        {
          "expr": "sum(count_over_time({container=~\"$container\"} |= \"error\" [5m])) by (container)",
          "legendFormat": "{{container}}"
        }
      ],
      "alert": {
        "name": "High Error Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [100] }
          }
        ]
      }
    },
    {
      "title": "Log Patterns",
      "type": "table",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "datasource": "Loki",
      "targets": [
        {
          "expr": "topk(10, sum(count_over_time({container=~\"$container\"} [5m])) by (pattern))",
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
    },
    {
      "title": "Live Log Stream",
      "type": "logs",
      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 16},
      "datasource": "Loki",
      "options": {
        "showTime": true,
        "showLabels": true,
        "showCommonLabels": false,
        "wrapLogMessage": true,
        "prettifyLogMessage": true,
        "enableLogDetails": true
      },
      "targets": [
        {
          "expr": "{container=~\"$container\"} |~ \"$search\"",
          "legendFormat": "{{container}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(container)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "search",
        "type": "textbox",
        "label": "Search",
        "current": {
          "value": "error|warn|exception"
        }
      }
    ]
  }
}
'@
}

function Get-DockerNetworkProDashboard {
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
        "name": "Network Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "Docker Network Pro Dashboard",
  "uid": "docker-network-pro",
  "tags": ["docker", "network", "pro"],
  "refresh": "10s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Network Topology",
      "type": "nodeGraph",
      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "container_network_receive_bytes_total",
          "legendFormat": "{{container}}"
        }
      ]
    },
    {
      "title": "Network Traffic Rate",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "unit": "Bps",
          "custom": {
            "drawStyle": "line",
            "lineInterpolation": "smooth",
            "fillOpacity": 10
          }
        }
      },
      "targets": [
        {
          "expr": "rate(container_network_receive_bytes_total{container=~\"$container\"}[5m])",
          "legendFormat": "{{container}} Rx"
        },
        {
          "expr": "rate(container_network_transmit_bytes_total{container=~\"$container\"}[5m])",
          "legendFormat": "{{container}} Tx"
        }
      ]
    },
    {
      "title": "Network Errors",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(container_network_receive_errors_total[5m])) by (container)",
          "legendFormat": "{{container}} Rx Errors"
        },
        {
          "expr": "sum(rate(container_network_transmit_errors_total[5m])) by (container)",
          "legendFormat": "{{container}} Tx Errors"
        }
      ],
      "alert": {
        "name": "Network Error Spike",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [10] }
          }
        ]
      }
    },
    {
      "title": "TCP Connections",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "container_network_tcp_usage_total{container=~\"$container\"}",
          "legendFormat": "{{container}}"
        }
      ]
    },
    {
      "title": "Network Packet Size Distribution",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(container_network_receive_packets_total[5m])",
          "format": "heatmap"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(container_network_receive_bytes_total, container)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "network",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(container_network_receive_bytes_total, network)",
        "refresh": 1
      }
    ]
  }
}
'@
}

function Get-ApiGatewayTrafficProDashboard {
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
        "name": "API Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "API Gateway Traffic Pro Dashboard",
  "uid": "api-gateway-traffic-pro",
  "tags": ["api", "gateway", "traffic", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Request Rate Overview",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      },
      "targets": [
        {
          "expr": "sum(rate(gateway_http_requests_total[5m]))",
          "legendFormat": "Requests/sec"
        }
      ]
    },
    {
      "title": "Traffic Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 8, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(rate(gateway_http_requests_total[5m])) by (route)",
          "legendFormat": "{{route}}"
        }
      ]
    },
    {
      "title": "Response Status Codes",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 10, "x": 14, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "bars",
            "fillOpacity": 60
          }
        }
      },
      "targets": [
        {
          "expr": "sum(rate(gateway_http_requests_total[5m])) by (status)",
          "legendFormat": "{{status}}"
        }
      ]
    },
    {
      "title": "Latency Distribution",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_request_duration_seconds_bucket[5m])) by (le)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Top Endpoints",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(gateway_http_requests_total[5m])) by (route))",
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
        "name": "route",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(gateway_http_requests_total, route)",
        "refresh": 1,
        "includeAll": true
      },
      {
        "name": "status",
        "type": "custom",
        "query": "2xx,3xx,4xx,5xx",
        "current": {
          "selected": true,
          "text": "4xx",
          "value": "4xx"
        }
      }
    ]
  }
}
'@
}

function Get-ApiGatewaySecurityProDashboard {
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
  "title": "API Gateway Security Pro Dashboard",
  "uid": "api-gateway-security-pro",
  "tags": ["api", "gateway", "security", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Authentication Status",
      "type": "stat",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "options": {
        "colorMode": "value",
        "graphMode": "area"
      },
      "targets": [
        {
          "expr": "sum(rate(gateway_auth_success_total[5m])) / sum(rate(gateway_auth_total[5m])) * 100",
          "legendFormat": "Auth Success Rate"
        }
      ]
    },
    {
      "title": "Authentication Failures",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 8, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_auth_failure_total[5m])) by (reason)",
          "legendFormat": "{{reason}}"
        }
      ],
      "alert": {
        "name": "High Auth Failure Rate",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [50] }
          }
        ]
      }
    },
    {
      "title": "JWT Token Stats",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 10, "x": 14, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(gateway_jwt_validation_total[5m])",
          "legendFormat": "Validations"
        },
        {
          "expr": "rate(gateway_jwt_validation_failed_total[5m])",
          "legendFormat": "Failures"
        }
      ]
    },
    {
      "title": "Rate Limiting",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_rate_limit_exceeded_total[5m])) by (endpoint)",
          "legendFormat": "{{endpoint}}"
        }
      ]
    },
    {
      "title": "Suspicious IPs",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(gateway_blocked_requests_total[5m])) by (client_ip))",
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
        "name": "endpoint",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(gateway_requests_total, endpoint)",
        "refresh": 1,
        "includeAll": true
      }
    ]
  }
}
'@
}

function Get-ApiGatewayPerformanceProDashboard {
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
        "name": "Performance Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "API Gateway Performance Pro Dashboard",
  "uid": "api-gateway-performance-pro",
  "tags": ["api", "gateway", "performance", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Gateway Latency",
      "type": "gauge",
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 100 },
              { "color": "red", "value": 200 }
            ]
          },
          "unit": "ms"
        }
      },
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(gateway_request_duration_ms_bucket[5m])) by (le))",
          "legendFormat": "P95 Latency"
        }
      ]
    },
    {
      "title": "Response Time Distribution",
      "type": "heatmap",
      "gridPos": {"h": 8, "w": 18, "x": 6, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_request_duration_ms_bucket[5m])) by (le, endpoint)",
          "format": "heatmap"
        }
      ]
    },
    {
      "title": "Resource Utilization",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(process_cpu_seconds_total{job=\"api-gateway\"}[5m])",
          "legendFormat": "CPU Usage"
        },
        {
          "expr": "process_resident_memory_bytes{job=\"api-gateway\"}",
          "legendFormat": "Memory Usage"
        }
      ]
    },
    {
      "title": "Throughput Analysis",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_requests_total[5m])) by (endpoint)",
          "legendFormat": "{{endpoint}}"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "endpoint",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(gateway_requests_total, endpoint)",
        "refresh": 1,
        "includeAll": true
      }
    ]
  }
}
'@
}

function Get-ApiGatewayRoutingProDashboard {
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
        "name": "Routing Events",
        "type": "dashboard"
      }
    ]
  },
  "title": "API Gateway Routing Pro Dashboard",
  "uid": "api-gateway-routing-pro",
  "tags": ["api", "gateway", "routing", "pro"],
  "refresh": "5s",
  "schemaVersion": 38,
  "version": 1,
  "panels": [
    {
      "title": "Route Status Overview",
      "type": "statusmap",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "gateway_route_status",
          "legendFormat": "{{route}}"
        }
      ]
    },
    {
      "title": "Route Success Rate",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "sum(rate(gateway_route_success_total[5m])) by (route) / sum(rate(gateway_route_requests_total[5m])) by (route) * 100",
          "legendFormat": "{{route}}"
        }
      ]
    },
    {
      "title": "Route Latency",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(gateway_route_duration_seconds_bucket[5m])) by (le, route))",
          "legendFormat": "{{route}} P95"
        }
      ],
      "alert": {
        "name": "High Route Latency",
        "conditions": [
          {
            "type": "query",
            "query": { "params": ["A", "5m", "now"] },
            "reducer": { "type": "max" },
            "evaluator": { "type": "gt", "params": [1] }
          }
        ]
      }
    },
    {
      "title": "Route Traffic Distribution",
      "type": "piechart",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "datasource": "Prometheus",
      "options": {
        "legend": {
          "placement": "right",
          "values": ["value", "percent"]
        }
      },
      "targets": [
        {
          "expr": "sum(rate(gateway_route_requests_total[5m])) by (route)",
          "legendFormat": "{{route}}"
        }
      ]
    },
    {
      "title": "Failed Routes",
      "type": "table",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "topk(10, sum(rate(gateway_route_errors_total[5m])) by (route, error_type))",
          "instant": true
        }
      ],
      "transformations": [
        {
          "type": "organize",
          "config": {
            "indexByName": {},
            "renameByName": {
              "route": "Route",
              "error_type": "Error Type",
              "Value": "Error Rate"
            }
          }
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "route",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(gateway_route_requests_total, route)",
        "refresh": 1,
        "includeAll": true
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