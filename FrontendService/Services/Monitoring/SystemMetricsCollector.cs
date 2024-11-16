using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;
using static FrontendService.Services.Monitoring.MetricsCollector;

namespace FrontendService.Services.Monitoring
{
    public class SystemMetricsCollector
    {
        private readonly ConcurrentDictionary<string, Queue<MetricDataPoint>> _metricHistory = new();
        private const int MAX_HISTORY_POINTS = 100;
        private readonly ILogger<SystemMetricsCollector> _logger;
        private PerformanceCounter? _cpuCounter;
        private PerformanceCounter? _ramCounter;
        private DateTime _lastCheck = DateTime.UtcNow;
        private double _lastCpuTotal = 0;
        private double _lastCpuIdle = 0;

        public SystemMetricsCollector(ILogger<SystemMetricsCollector> logger)
        {
            _logger = logger;
            InitializeCounters();
        }

        private void InitializeCounters()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                try
                {
                    _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total", true);
                    _ramCounter = new PerformanceCounter("Memory", "% Committed Bytes In Use", true);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to initialize Windows performance counters");
                }
            }
        }

        public SystemMetrics GetSystemMetrics()
        {
            var metrics = new SystemMetrics();

            try
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    metrics = GetWindowsMetrics();
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                {
                    metrics = GetLinuxMetrics();
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    metrics = GetMacMetrics();
                }

                // Get disk usage for any platform
                metrics.StorageUsage = GetStorageUsage();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error collecting system metrics");
                return GetFallbackMetrics();
            }

            return metrics;
        }

        private SystemMetrics GetWindowsMetrics()
        {
            var metrics = new SystemMetrics();

            if (_cpuCounter != null && _ramCounter != null)
            {
                try
                {
                    metrics.CpuUsage = Math.Round(_cpuCounter.NextValue(), 2);
                    metrics.MemoryUsage = Math.Round(_ramCounter.NextValue(), 2);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error reading Windows performance counters");
                }
            }
            else
            {
                // Fallback to Process.GetCurrentProcess() metrics
                using var process = Process.GetCurrentProcess();
                metrics.CpuUsage = GetProcessCpuUsage(process);
                metrics.MemoryUsage = GetProcessMemoryUsage(process);
            }

            return metrics;
        }

        private SystemMetrics GetLinuxMetrics()
        {
            var metrics = new SystemMetrics();

            try
            {
                // CPU Usage from /proc/stat
                if (File.Exists("/proc/stat"))
                {
                    var lines = File.ReadAllLines("/proc/stat");
                    if (lines.Length > 0)
                    {
                        var cpuLine = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        var values = cpuLine.Skip(1).Select(long.Parse).ToArray();

                        var idle = values[3];
                        var total = values.Sum();

                        var cpuDelta = total - _lastCpuTotal;
                        var idleDelta = idle - _lastCpuIdle;

                        metrics.CpuUsage = cpuDelta == 0 ? 0 :
                            Math.Round((1.0 - ((double)idleDelta / cpuDelta)) * 100, 2);

                        _lastCpuTotal = total;
                        _lastCpuIdle = idle;
                    }
                }

                // Memory Usage from /proc/meminfo
                if (File.Exists("/proc/meminfo"))
                {
                    var lines = File.ReadAllLines("/proc/meminfo");
                    var memInfo = new Dictionary<string, long>();

                    foreach (var line in lines)
                    {
                        var parts = line.Split(':', StringSplitOptions.TrimEntries);
                        if (parts.Length == 2)
                        {
                            var valueStr = new string(parts[1].TakeWhile(char.IsDigit).ToArray());
                            if (long.TryParse(valueStr, out var value))
                            {
                                memInfo[parts[0]] = value;
                            }
                        }
                    }

                    if (memInfo.ContainsKey("MemTotal") && memInfo.ContainsKey("MemAvailable"))
                    {
                        var total = memInfo["MemTotal"];
                        var available = memInfo["MemAvailable"];
                        metrics.MemoryUsage = Math.Round(((total - available) / (double)total) * 100, 2);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading Linux system metrics");
            }

            return metrics;
        }

        private SystemMetrics GetMacMetrics()
        {
            var metrics = new SystemMetrics();

            try
            {
                // On macOS, we'll use process-level metrics as fallback
                using var process = Process.GetCurrentProcess();
                metrics.CpuUsage = GetProcessCpuUsage(process);
                metrics.MemoryUsage = GetProcessMemoryUsage(process);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading macOS system metrics");
            }

            return metrics;
        }

        private double GetStorageUsage()
        {
            try
            {
                var drive = DriveInfo.GetDrives()
                    .FirstOrDefault(d => d.IsReady && d.DriveType == DriveType.Fixed);

                if (drive != null)
                {
                    var totalSize = drive.TotalSize;
                    var freeSpace = drive.AvailableFreeSpace;
                    return Math.Round((1 - ((double)freeSpace / totalSize)) * 100, 2);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting storage usage");
            }

            return 0;
        }

        private double GetProcessCpuUsage(Process process)
        {
            try
            {
                var currentTime = DateTime.UtcNow;
                var timeDiff = (currentTime - _lastCheck).TotalMilliseconds;
                var cpuTime = process.TotalProcessorTime;

                if (timeDiff > 0)
                {
                    var cpuUsage = (cpuTime.TotalMilliseconds / (Environment.ProcessorCount * timeDiff)) * 100;
                    _lastCheck = currentTime;
                    return Math.Round(Math.Min(100, cpuUsage), 2);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error calculating process CPU usage");
            }

            return 0;
        }

        private double GetProcessMemoryUsage(Process process)
        {
            try
            {
                var totalPhysicalMemory = GetTotalPhysicalMemory();
                if (totalPhysicalMemory > 0)
                {
                    return Math.Round((process.WorkingSet64 / (double)totalPhysicalMemory) * 100, 2);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error calculating process memory usage");
            }

            return 0;
        }

        private long GetTotalPhysicalMemory()
        {
            try
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    return GetWindowsTotalMemory();
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                {
                    return GetLinuxTotalMemory();
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    return GetMacTotalMemory();
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting total physical memory");
            }

            return 0;
        }

        private long GetWindowsTotalMemory()
        {
            try
            {
                var gcMemoryInfo = GC.GetGCMemoryInfo();
                return gcMemoryInfo.TotalAvailableMemoryBytes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting Windows total memory");
                return 0;
            }
        }

        private long GetLinuxTotalMemory()
        {
            try
            {
                if (File.Exists("/proc/meminfo"))
                {
                    var meminfo = File.ReadAllLines("/proc/meminfo");
                    var totalLine = meminfo.FirstOrDefault(l => l.StartsWith("MemTotal:"));
                    if (totalLine != null)
                    {
                        var value = new string(totalLine.Where(char.IsDigit).ToArray());
                        if (long.TryParse(value, out var total))
                        {
                            return total * 1024; // Convert from KB to bytes
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading total physical memory on Linux");
            }
            return 0;
        }

        private long GetMacTotalMemory()
        {
            try
            {
                var gcMemoryInfo = GC.GetGCMemoryInfo();
                return gcMemoryInfo.TotalAvailableMemoryBytes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting macOS total memory");
                return 0;
            }
        }

        private SystemMetrics GetFallbackMetrics()
        {
            return new SystemMetrics
            {
                CpuUsage = 0,
                MemoryUsage = 0,
                StorageUsage = 0
            };
        }

        public void RecordMetric(string name, double value)
        {
            var queue = _metricHistory.GetOrAdd(name, _ => new Queue<MetricDataPoint>());

            lock (queue)
            {
                queue.Enqueue(new MetricDataPoint { Timestamp = DateTime.UtcNow, Value = value });
                while (queue.Count > MAX_HISTORY_POINTS)
                {
                    queue.Dequeue();
                }
            }
        }

        public double GetAverageResponseTime()
        {
            if (_metricHistory.TryGetValue("api_response_time", out var queue))
            {
                lock (queue)
                {
                    return queue.Count > 0 ? queue.Average(p => p.Value) : 0;
                }
            }
            return 0;
        }

        public double GetRequestRate()
        {
            if (_metricHistory.TryGetValue("api_response_time", out var queue))
            {
                lock (queue)
                {
                    if (queue.Count < 2) return 0;
                    var timeSpan = queue.Last().Timestamp - queue.First().Timestamp;
                    return timeSpan.TotalMinutes > 0 ? queue.Count / timeSpan.TotalMinutes : 0;
                }
            }
            return 0;
        }

        private class MetricDataPoint
        {
            public DateTime Timestamp { get; set; }
            public double Value { get; set; }
        }

        public class SystemMetrics
        {
            public double CpuUsage { get; set; }
            public double MemoryUsage { get; set; }
            public double StorageUsage { get; set; }
        }
    }
}