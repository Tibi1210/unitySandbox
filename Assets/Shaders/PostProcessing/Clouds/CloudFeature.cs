using UnityEngine.Rendering.Universal;

// CHANGE
public class CloudFeature : ScriptableRendererFeature
{
    // CHANGE
    CloudPass pass;

    public override void Create()
    {
        // CHANGE
        name = "MyClouds";
        //CHANGE
        pass = new CloudPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        // CHANGE
        pass.Setup(renderer, "MyClouds");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}
