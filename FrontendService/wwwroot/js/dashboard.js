// dashboard.js
class DashboardManager {
    constructor() {
        this.updateInterval = null;
        this.retryCount = 0;
        this.maxRetries = 3;
        this.retryDelay = 5000;
        this.refreshInterval = 30000; // 30 seconds
    }

    async initialize() {
        try {
            await this.updateDashboard();
            this.startPolling();
            this.setupEventListeners();
        } catch (error) {
            console.error('Failed to initialize dashboard:', error);
            this.handleError(error);
        }
    }

    async updateDashboard() {
        try {
            const [dashboardData, serviceStatus] = await Promise.all([
                this.fetchWithTimeout('/Home/GetDashboardData'),
                this.fetchWithTimeout('/Home/GetServiceStatus')
            ]);

            this.updateMetrics(dashboardData);
            this.updateServiceStatus(serviceStatus);
            this.updateResourceUsage(dashboardData);
            this.updateLastRefreshTime();

            // Reset retry count on successful update
            this.retryCount = 0;

            // Remove any error messages
            this.clearErrors();
        } catch (error) {
            this.handleError(error);
            throw error;
        }
    }

    async fetchWithTimeout(url, timeout = 5000) {
        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), timeout);

            const response = await fetch(url, { signal: controller.signal });
            clearTimeout(timeoutId);

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            return await response.json();
        } catch (error) {
            if (error.name === 'AbortError') {
                throw new Error('Request timed out');
            }
            throw error;
        }
    }

    updateMetrics(data) {
        // Update dashboard metrics
        const elements = {
            activeOrdersCount: data.activeOrders,
            inventoryCount: data.inventoryCount,
            systemHealth: data.systemHealth,
            responseTime: data.responseTime
        };

        for (const [id, value] of Object.entries(elements)) {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = value;
                // Add animation class for value changes
                element.classList.add('value-updated');
                setTimeout(() => element.classList.remove('value-updated'), 1000);
            }
        }
    }

    updateServiceStatus(services) {
        const tbody = document.querySelector('#servicesTable tbody');
        if (!tbody) return;

        services.forEach(service => {
            const row = document.getElementById(`${service.name.toLowerCase().replace(' ', '')}ServiceRow`);
            if (row) {
                const statusBadge = row.querySelector('.badge');
                const uptimeCell = row.querySelector('td:nth-child(3)');
                const lastUpdateCell = row.querySelector('td:nth-child(4)');

                if (statusBadge) {
                    statusBadge.className = `badge ${service.status === 'Healthy' ? 'bg-success' : 'bg-danger'}`;
                    statusBadge.textContent = service.status;
                }
                if (uptimeCell) uptimeCell.textContent = service.uptime;
                if (lastUpdateCell) lastUpdateCell.textContent = new Date(service.lastUpdated).toLocaleString();
            }
        });
    }

    updateResourceUsage(data) {
        const resources = ['cpu', 'memory', 'storage'];
        resources.forEach(resource => {
            const usageValue = data[`${resource}Usage`];
            const bar = document.getElementById(`${resource}Usage`);
            const text = document.getElementById(`${resource}UsageText`);

            if (bar && text) {
                bar.style.width = `${usageValue}%`;
                text.textContent = `${usageValue}%`;

                // Update color based on usage
                let color = 'bg-success';
                if (usageValue > 80) color = 'bg-danger';
                else if (usageValue > 60) color = 'bg-warning';

                bar.className = `progress-bar ${color}`;
            }
        });
    }

    handleError(error) {
        console.error('Dashboard update failed:', error);

        this.retryCount++;
        if (this.retryCount <= this.maxRetries) {
            // Show warning message
            this.showError(`Update failed. Retrying in ${this.retryDelay / 1000} seconds...`, 'warning');
            setTimeout(() => this.updateDashboard(), this.retryDelay);
        } else {
            // Show error message
            this.showError('Failed to update dashboard. Please refresh the page.', 'danger');
            this.stopPolling();
        }
    }

    showError(message, type = 'danger') {
        const alertDiv = document.createElement('div');
        alertDiv.className = `alert alert-${type} alert-dismissible fade show`;
        alertDiv.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;

        const container = document.querySelector('.container-fluid');
        if (container) {
            container.insertBefore(alertDiv, container.firstChild);
        }
    }

    clearErrors() {
        const alerts = document.querySelectorAll('.alert');
        alerts.forEach(alert => alert.remove());
    }

    startPolling() {
        if (!this.updateInterval) {
            this.updateInterval = setInterval(() => this.updateDashboard(), this.refreshInterval);
        }
    }

    stopPolling() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }

    setupEventListeners() {
        // Manual refresh button
        const refreshButton = document.querySelector('[data-refresh]');
        if (refreshButton) {
            refreshButton.addEventListener('click', () => this.updateDashboard());
        }

        // Cleanup on page hide/unload
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.stopPolling();
            } else {
                this.startPolling();
            }
        });

        window.addEventListener('beforeunload', () => this.stopPolling());
    }

    updateLastRefreshTime() {
        const lastUpdated = document.getElementById('lastUpdated');
        if (lastUpdated) {
            lastUpdated.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
        }
    }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const dashboard = new DashboardManager();
    dashboard.initialize();
});