using FrontendService.Models;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using System.Text.Json;

public class DockerManagementController : Controller
{
    private readonly ILogger<DockerManagementController> _logger;
    private readonly IWebHostEnvironment _environment;

    public DockerManagementController(ILogger<DockerManagementController> logger, IWebHostEnvironment environment)
    {
        _logger = logger;
        _environment = environment;
    }

    private ProcessStartInfo GetDockerProcessInfo(string arguments)
    {
        var isDocker = _environment.EnvironmentName == "Docker";
        var startInfo = new ProcessStartInfo
        {
            FileName = "docker",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = isDocker ? "/" : AppDomain.CurrentDomain.BaseDirectory
        };

        if (isDocker)
        {
            startInfo.EnvironmentVariables["DOCKER_HOST"] = "unix:///var/run/docker.sock";
        }

        return startInfo;
    }

    private async Task<(bool success, string output, string error)> ExecuteDockerCommand(string arguments)
    {
        try
        {
            using var process = new Process { StartInfo = GetDockerProcessInfo(arguments) };

            process.Start();

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            await process.WaitForExitAsync();

            var output = await outputTask;
            var error = await errorTask;

            _logger.LogInformation("Docker command executed: {Arguments}, Exit Code: {ExitCode}", arguments, process.ExitCode);

            if (process.ExitCode != 0)
            {
                _logger.LogError("Docker command failed: {Error}", error);
                return (false, output, error);
            }

            return (true, output, error);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to execute docker command: {Arguments}", arguments);
            return (false, string.Empty, ex.Message);
        }
    }

    public async Task<IActionResult> Index()
    {
        var model = new DockerManagementViewModel();

        try
        {
            // Get containers
            var (containersSuccess, containersOutput, containersError) = await ExecuteDockerCommand("ps --format \"{{json .}}\"");
            if (!containersSuccess)
            {
                model.Error = $"Failed to get containers: {containersError}";
                return View(model);
            }

            model.Containers = containersOutput
                .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Select(json => JsonSerializer.Deserialize<ContainerInfo>(json))
                .Where(c => c != null)
                .ToList();

            // Get images
            var (imagesSuccess, imagesOutput, imagesError) = await ExecuteDockerCommand("images --format \"{{json .}}\"");
            if (!imagesSuccess)
            {
                model.Error = $"Failed to get images: {imagesError}";
                return View(model);
            }

            model.Images = imagesOutput
                .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Select(json => JsonSerializer.Deserialize<ImageInfo>(json))
                .Where(i => i != null)
                .ToList();

            // Get system info
            var (systemSuccess, systemOutput, systemError) = await ExecuteDockerCommand("system df --format \"{{json .}}\"");
            if (!systemSuccess)
            {
                model.Error = $"Failed to get system info: {systemError}";
                return View(model);
            }

            model.SystemInfo = JsonSerializer.Deserialize<SystemInfo>(systemOutput);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching Docker information");
            model.Error = $"Failed to execute docker command: {ex.Message}. Please ensure Docker is installed and running.";
        }

        return View(model);
    }

    [HttpPost]
    public async Task<IActionResult> ContainerAction(string containerId, string action)
    {
        try
        {
            var (success, _, error) = await ExecuteDockerCommand($"{action} {containerId}");
            if (!success)
            {
                return Json(new { success = false, error });
            }

            return Json(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error performing {Action} on container {ContainerId}", action, containerId);
            return Json(new { success = false, error = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> Logs(string containerId, int? lines = 100)
    {
        try
        {
            var (success, output, error) = await ExecuteDockerCommand($"logs --tail {lines} {containerId}");
            if (!success)
            {
                return Json(new { success = false, error });
            }

            return Json(new { success = true, logs = output });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting logs for container {ContainerId}", containerId);
            return Json(new { success = false, error = ex.Message });
        }
    }
}