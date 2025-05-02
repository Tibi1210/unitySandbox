using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// CHNAGE
public class FogPass : ScriptableRenderPass
{
    private Material material;
    // CHANGE
    private FogSettings settings;

    private RenderTargetIdentifier source;
    private RenderTargetIdentifier mainTex;

    private string profilerTag;

    public void Setup(ScriptableRenderer renderer, string profilerTag){

        this.profilerTag = profilerTag;
        source = renderer.cameraColorTargetHandle;
        VolumeStack stack = VolumeManager.instance.stack;
        // CHANGE
        settings = stack.GetComponent<FogSettings>();
        renderPassEvent = RenderPassEvent.BeforeRenderingSkybox;
        if (settings != null && settings.IsActive())
        {
            // CHANGE
            material = new Material(Shader.Find("_Tibi/PostProcess/Fog"));
        }
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        if (settings == null) return;
        int id = Shader.PropertyToID("_MainTex");
        mainTex = new RenderTargetIdentifier(id);
        cmd.GetTemporaryRT(id, cameraTextureDescriptor);
        base.Configure(cmd, cameraTextureDescriptor);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (!settings.IsActive())
        {
            return;
        }
        CommandBuffer cmd = CommandBufferPool.Get(profilerTag);
        // CHANGE
        cmd.Blit(source, mainTex);
        material.SetFloat("_alpha", settings.alpha.value);
        material.SetColor("_color", settings.color.value);
        material.SetColor("_color2", settings.color2.value);
        material.SetFloat("_RenderDistance", settings.RenderDistance.value);
        cmd.Blit(mainTex, source, material);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd) {
        // CHANGE
        cmd.ReleaseTemporaryRT(Shader.PropertyToID("_MainTex"));
    }
}
