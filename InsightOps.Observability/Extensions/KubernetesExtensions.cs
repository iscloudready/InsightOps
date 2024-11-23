using Microsoft.Extensions.DependencyInjection;

public static class KubernetesExtensions
{
    public static IServiceCollection AddKubernetesSupport(
        this IServiceCollection services)
    {
        services.AddSingleton<IKubernetesClient, KubernetesClient>();
        services.AddHostedService<KubernetesMetricsCollector>();
        return services;
    }
}