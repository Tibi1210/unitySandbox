using UnityEngine.Rendering.Universal;

// CHANGE
public class FogFeature : ScriptableRendererFeature
{
    // CHANGE
    FogPass pass;

    public override void Create()
    {
        // CHANGE
        name = "MyFog";
        //CHANGE
        pass = new FogPass();
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        // CHANGE
        pass.Setup(renderer, "MyFog");
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}
