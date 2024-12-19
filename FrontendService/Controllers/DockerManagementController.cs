using FrontendService.Models;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using System.Text.Json;

public class DockerManagementController : Controller
{
    private readonly ILogger<DockerManagementController> _logger;
    private readonly IWebHostEnvironment _environment;

    public DockerManagementController(
        ILogger<DockerManagementController> logger,
        IWebHostEnvironment environment)
    {
        _logger = logger;
        _environment = environment;
    }

    private ProcessStartInfo GetDockerProcessInfo(string arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "docker",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = "/"
        };

        if (_environment.EnvironmentName == "Docker")
        {
            startInfo.Environment["DOCKER_HOST"] = "unix:///var/run/docker.sock";
            startInfo.Arguments = startInfo.Arguments.Replace("\"", "'");
        }

        _logger.LogInformation("Executing Docker command: {FileName} {Arguments} in {Env}",
            startInfo.FileName, startInfo.Arguments, _environment.EnvironmentName);

        return startInfo;
    }

    public async Task<IActionResult> Index()
    {
        var model = new DockerManagementViewModel();

        try
        {
            // Use --format without quotes in Docker environment
            var formatStr = _environment.EnvironmentName == "Docker"
                ? "ps --format '{\"json\": {{json .}}}'"
                : "ps --format \"{{json .}}\"";
            //var formatStr = "ps --format json";

            var (containersSuccess, containersOutput, containersError) =
                await ExecuteDockerCommand(formatStr);

            if (!containersSuccess)
            {
                _logger.LogError("Failed to get containers: {Error}", containersError);
                model.Error = $"Failed to get containers: {containersError}";
                return View(model);
            }

            if (!string.IsNullOrEmpty(containersOutput))
            {
                try
                {
                    model.Containers = containersOutput
                        .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                        .Select(json =>
                        {
                            _logger.LogDebug("Parsing container JSON: {Json}", json);
                            return JsonSerializer.Deserialize<ContainerInfo>(json);
                        })
                        .Where(c => c != null)
                        .ToList();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error parsing container output: {Output}", containersOutput);
                    model.Error = "Error parsing container data";
                    return View(model);
                }
            }

            // Use --format without quotes in Docker environment
            formatStr = _environment.EnvironmentName == "Docker"
                ? "images --format '{{json .}}'"
                : "images --format \"{{json .}}\"";

            var (imagesSuccess, imagesOutput, imagesError) =
                await ExecuteDockerCommand(formatStr);

            if (!imagesSuccess)
            {
                _logger.LogError("Failed to get images: {Error}", imagesError);
                model.Error = $"Failed to get images: {imagesError}";
                return View(model);
            }

            if (!string.IsNullOrEmpty(imagesOutput))
            {
                try
                {
                    model.Images = imagesOutput
                        .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                        .Select(json => JsonSerializer.Deserialize<ImageInfo>(json))
                        .Where(i => i != null)
                        .ToList();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error parsing image output: {Output}", imagesOutput);
                    model.Error = "Error parsing image data";
                    return View(model);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in Docker management index");
            model.Error = $"Error accessing Docker: {ex.Message}";
        }

        return View(model);
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

            _logger.LogInformation("Docker command result - Exit Code: {ExitCode}, Output: {Output}, Error: {Error}",
                process.ExitCode, output, error);

            return (process.ExitCode == 0, output, error);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing Docker command: {Arguments}", arguments);
            return (false, string.Empty, ex.Message);
        }
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
            _logger.LogError(ex, $"Error performing {action} on container {containerId}");
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
            _logger.LogError(ex, $"Error getting logs for container {containerId}");
            return Json(new { success = false, error = ex.Message });
        }
    }
}