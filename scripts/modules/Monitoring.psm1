# Monitoring.psm1
function Initialize-Monitoring {
    param (
        [string]$ConfigPath
    )

    # Create dashboard directory
    $dashboardPath = Join-Path $ConfigPath "grafana/dashboards"
    if (-not (Test-Path $dashboardPath)) {
        New-Item -ItemType Directory -Path $dashboardPath -Force
    }

    # Write dashboard files
    $dashboards = @{
        "api-gateway.json" = Get-ApiGatewayDashboard
        "security.json" = Get-SecurityDashboard
        "service-health.json" = Get-ServiceHealthDashboard
        "frontend-realtime.json" = Get-FrontendRealtimeDashboard
        "orders-realtime.json" = Get-OrdersRealtimeDashboard
        "inventory-realtime.json" = Get-InventoryRealtimeDashboard
    }

    foreach ($dashboard in $dashboards.GetEnumerator()) {
        $path = Join-Path $dashboardPath $dashboard.Key
        $content = $dashboard.Value
        Set-Content -Path $path -Value $content -Encoding UTF8
    }
}

# Include all dashboard JSON definitions here
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
          { "color": "green", "value": null },
          { "color": "yellow", "value": 100 },
          { "color": "red", "value": 200 }
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

Export-ModuleMember -Function @(
    'Initialize-Monitoring',
    'Get-ApiGatewayDashboard', 
    'Get-SecurityDashboard',
    'Get-ServiceHealthDashboard',
    'Get-FrontendRealtimeDashboard',
    'Get-OrdersRealtimeDashboard',
    'Get-InventoryRealtimeDashboard'
)