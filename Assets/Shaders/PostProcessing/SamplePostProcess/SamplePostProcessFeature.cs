using UnityEngine.Rendering.Universal;

// CHANGE
public class SamplePostProcessFeature : ScriptableRendererFeature
{
    // CHANGE
    SamplePostProcessPass pass;

    public override void Create()
    {
        // CHANGE
        name = "SamplePostProcess";
        //CHANGE
        pass = new SamplePostProcessPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        // CHANGE
        pass.Setup(renderer, "SamplePostProcess");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}
