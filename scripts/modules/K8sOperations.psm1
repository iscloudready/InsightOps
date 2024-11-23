# Module: K8sOperations.psm1

function Initialize-K8sNamespace {
    param (
        [string]$Namespace = "observability"
    )
    Write-Host "Creating Kubernetes namespace: $Namespace"
    kubectl create namespace $Namespace -o yaml --dry-run=client | kubectl apply -f -
}

function Deploy-Loki {
    param (
        [string]$HelmChartPath = "./charts/loki",
        [string]$Namespace = "observability"
    )
    Write-Host "Deploying Loki to namespace: $Namespace"
    helm upgrade --install loki $HelmChartPath --namespace $Namespace
}

function Deploy-Tempo {
    param (
        [string]$HelmChartPath = "./charts/tempo",
        [string]$Namespace = "observability"
    )
    Write-Host "Deploying Tempo to namespace: $Namespace"
    helm upgrade --install tempo $HelmChartPath --namespace $Namespace
}

function Deploy-Prometheus {
    param (
        [string]$HelmChartPath = "./charts/prometheus",
        [string]$Namespace = "observability"
    )
    Write-Host "Deploying Prometheus to namespace: $Namespace"
    helm upgrade --install prometheus $HelmChartPath --namespace $Namespace
}

function Deploy-Grafana {
    param (
        [string]$HelmChartPath = "./charts/grafana",
        [string]$Namespace = "observability"
    )
    Write-Host "Deploying Grafana to namespace: $Namespace"
    helm upgrade --install grafana $HelmChartPath --namespace $Namespace
}

function Configure-GrafanaDashboards {
    param (
        [string]$DashboardPath = "./dashboards"
    )
    Write-Host "Configuring Grafana Dashboards from path: $DashboardPath"
    foreach ($file in Get-ChildItem -Path $DashboardPath -Filter *.json) {
        Write-Host "Uploading dashboard: $($file.Name)"
        # Replace below with Grafana provisioning logic using REST API
        Invoke-RestMethod -Uri "http://grafana:3000/api/dashboards/db" `
            -Method POST `
            -Body (Get-Content $file.FullName -Raw) `
            -Headers @{Authorization = "Bearer $GrafanaAdminToken"} `
            -ContentType "application/json"
    }
}

Export-ModuleMember -Function *  # Export all functions
