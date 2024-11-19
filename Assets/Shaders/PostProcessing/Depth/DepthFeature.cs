using UnityEngine.Rendering.Universal;

// CHANGE
public class DepthFeature : ScriptableRendererFeature
{
    // CHANGE
    DepthPass pass;

    public override void Create()
    {
        // CHANGE
        name = "Depth";
        //CHANGE
        pass = new DepthPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        // CHANGE
        pass.Setup(renderer, "Depth");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}
