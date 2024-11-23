// InsightOps.Observability/Metrics/SystemMetricsCollector.cs
using System.Diagnostics;
using Microsoft.Extensions.Logging;
using System.Runtime.InteropServices;

namespace InsightOps.Observability.Metrics;

public class SystemMetricsCollector
{
    private readonly ILogger<SystemMetricsCollector> _logger;
    private readonly RealTimeMetricsCollector _metricsCollector;
    private DateTime _lastCheck = DateTime.UtcNow;
    private double _lastCpuTime = 0;

    public SystemMetricsCollector(
        ILogger<SystemMetricsCollector> logger,
        RealTimeMetricsCollector metricsCollector)
    {
        _logger = logger;
        _metricsCollector = metricsCollector;
    }

    public SystemMetrics GetSystemMetrics()
    {
        try
        {
            var metrics = new SystemMetrics();

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                metrics = GetWindowsMetrics();
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                metrics = GetLinuxMetrics();
            }
            else
            {
                metrics = GetProcessMetrics();
            }

            metrics.StorageUsage = GetStorageUsage();
            return metrics;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting system metrics");
            return new SystemMetrics();
        }
    }

    private SystemMetrics GetWindowsMetrics()
    {
        using var process = Process.GetCurrentProcess();
        var cpuUsage = GetProcessCpuUsage(process);
        var memoryUsage = process.WorkingSet64 / (double)GetTotalPhysicalMemory() * 100;

        return new SystemMetrics
        {
            CpuUsage = Math.Round(cpuUsage, 2),
            MemoryUsage = Math.Round(memoryUsage, 2)
        };
    }

    private SystemMetrics GetLinuxMetrics()
    {
        try
        {
            var cpuUsage = 0.0;
            var memoryUsage = 0.0;

            if (File.Exists("/proc/stat") && File.Exists("/proc/meminfo"))
            {
                // Read CPU usage
                var cpuStats = File.ReadAllLines("/proc/stat")
                    .First()
                    .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Skip(1)
                    .Select(long.Parse)
                    .ToArray();

                var idleTime = cpuStats[3];
                var totalTime = cpuStats.Sum();

                var cpuDelta = totalTime - _lastCpuTime;
                var idleDelta = idleTime - _lastCheck.Ticks;

                cpuUsage = cpuDelta > 0
                    ? Math.Round((1.0 - (idleDelta / (double)cpuDelta)) * 100, 2)
                    : 0;

                _lastCpuTime = totalTime;
                _lastCheck = DateTime.UtcNow;

                // Read memory usage
                var memInfo = File.ReadAllLines("/proc/meminfo")
                    .Select(line => line.Split(':'))
                    .ToDictionary(
                        parts => parts[0].Trim(),
                        parts => long.Parse(parts[1].Trim().Split(' ')[0]));

                var totalMemory = memInfo["MemTotal"];
                var availableMemory = memInfo["MemAvailable"];
                memoryUsage = Math.Round(((totalMemory - availableMemory) / (double)totalMemory) * 100, 2);
            }

            return new SystemMetrics
            {
                CpuUsage = cpuUsage,
                MemoryUsage = memoryUsage
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reading Linux metrics");
            return GetProcessMetrics();
        }
    }

    private SystemMetrics GetProcessMetrics()
    {
        using var process = Process.GetCurrentProcess();
        return new SystemMetrics
        {
            CpuUsage = GetProcessCpuUsage(process),
            MemoryUsage = process.WorkingSet64 / (double)GetTotalPhysicalMemory() * 100
        };
    }

    private double GetProcessCpuUsage(Process process)
    {
        var currentTime = DateTime.UtcNow;
        var timeDiff = (currentTime - _lastCheck).TotalMilliseconds;

        if (timeDiff <= 0) return 0;

        var cpuUsage = (process.TotalProcessorTime.TotalMilliseconds /
            (Environment.ProcessorCount * timeDiff)) * 100;

        _lastCheck = currentTime;
        return Math.Round(Math.Min(100, cpuUsage), 2);
    }

    private double GetStorageUsage()
    {
        var drive = DriveInfo.GetDrives()
            .FirstOrDefault(d => d.IsReady && d.DriveType == DriveType.Fixed);

        if (drive != null)
        {
            return Math.Round((1 - ((double)drive.AvailableFreeSpace / drive.TotalSize)) * 100, 2);
        }

        return 0;
    }

    private static long GetTotalPhysicalMemory()
    {
        try
        {
            return GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        }
        catch
        {
            return 8L * 1024L * 1024L * 1024L; // Default to 8GB if unable to determine
        }
    }
}

public class SystemMetrics
{
    public double CpuUsage { get; set; }
    public double MemoryUsage { get; set; }
    public double StorageUsage { get; set; }
}
