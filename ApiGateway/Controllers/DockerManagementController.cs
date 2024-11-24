using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using System.Net.Http;
using FrontendService.Models;
//using FrontendService.Models;

namespace FrontendService.Controllers
{
    public class DockerManagementController : Controller
    {
        private readonly IHttpClientFactory _clientFactory;
        private readonly ILogger<DockerManagementController> _logger;

        public DockerManagementController(IHttpClientFactory clientFactory, ILogger<DockerManagementController> logger)
        {
            _clientFactory = clientFactory;
            _logger = logger;
        }

        public async Task<IActionResult> Index()
        {
            var model = new DockerManagementViewModel();

            try
            {
                // Get containers
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "docker",
                        Arguments = "ps --format \"{{json .}}\"",
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                var output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                var containers = output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .Select(json => JsonSerializer.Deserialize<ContainerInfo>(json))
                    .Where(c => c != null)
                    .ToList();

                model.Containers = containers;

                // Get images
                process.StartInfo.Arguments = "images --format \"{{json .}}\"";
                process.Start();
                output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                var images = output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                    .Select(json => JsonSerializer.Deserialize<ImageInfo>(json))
                    .Where(i => i != null)
                    .ToList();

                model.Images = images;

                // Get system info
                process.StartInfo.Arguments = "system df --format \"{{json .}}\"";
                process.Start();
                output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                model.SystemInfo = JsonSerializer.Deserialize<SystemInfo>(output);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching Docker information");
                model.Error = "Failed to fetch Docker information: " + ex.Message;
            }

            return View(model);
        }

        [HttpPost]
        public async Task<IActionResult> ContainerAction(string containerId, string action)
        {
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "docker",
                        Arguments = $"{action} {containerId}",
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                await process.WaitForExitAsync();

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
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "docker",
                        Arguments = $"logs --tail {lines} {containerId}",
                        RedirectStandardOutput = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                var logs = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                return Json(new { success = true, logs });
            }
            catch (Exception ex)
            {
                return Json(new { success = false, error = ex.Message });
            }
        }
    }
}