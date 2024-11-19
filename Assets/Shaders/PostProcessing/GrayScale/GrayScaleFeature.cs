using UnityEngine.Rendering.Universal;

public class GrayScaleFeature : ScriptableRendererFeature
{
    GrayScaleRenderPass pass;

    public override void Create()
    {
        name = "Grayscale";
        pass = new GrayScaleRenderPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        pass.Setup(renderer, "Grayscale Post Process");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass); // letting the renderer know which passes will be used before allocation
    }

}
