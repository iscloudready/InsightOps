namespace FrontendService.Models
{
    public class DockerManagementViewModel
    {
        public List<ContainerInfo> Containers { get; set; } = new();
        public List<ImageInfo> Images { get; set; } = new();
        public SystemInfo SystemInfo { get; set; }
        public string Error { get; set; }
    }

    public class ContainerInfo
    {
        public string ID { get; set; }
        public string Names { get; set; }
        public string Image { get; set; }
        public string Command { get; set; }
        public string Created { get; set; }
        public string Status { get; set; }
        public string Ports { get; set; }
    }

    public class ImageInfo
    {
        public string Repository { get; set; }
        public string Tag { get; set; }
        public string ID { get; set; }
        public string Created { get; set; }
        public string Size { get; set; }
    }

    public class SystemInfo
    {
        public string Type { get; set; }
        public string Total { get; set; }
        public string Active { get; set; }
        public string Size { get; set; }
        public string Reclaimable { get; set; }
    }
}