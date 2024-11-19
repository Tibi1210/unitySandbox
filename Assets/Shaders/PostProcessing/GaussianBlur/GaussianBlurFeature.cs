using UnityEngine.Rendering.Universal;

public class GaussianBlurFeature : ScriptableRendererFeature
{
    GaussianBlurRenderPass pass;

    public override void Create()
    {
        name = "Gaussian Blur";
        pass = new GaussianBlurRenderPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        pass.Setup(renderer, "GaussianBlur Post Process");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}
