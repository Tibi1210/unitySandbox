using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// CHNAGE
public class DepthPass : ScriptableRenderPass
{
    private Material material;
    // CHANGE
    private DepthSettings settings;

    private RenderTargetIdentifier source;
    private RenderTargetIdentifier mainTex;
    private RenderTargetIdentifier tempTex;

    private string profilerTag;

    public void Setup(ScriptableRenderer renderer, string profilerTag){

        this.profilerTag = profilerTag;
        source = renderer.cameraColorTargetHandle;
        VolumeStack stack = VolumeManager.instance.stack;
        // CHANGE
        settings = stack.GetComponent<DepthSettings>();
        renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        if (settings != null && settings.IsActive())
        {
            // CHANGE
            material = new Material(Shader.Find("_Tibi/PostProcess/Depth"));
        }
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        if (settings == null)
        {
            return;
        }
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
        material.SetColor("_FarColour", settings.farColor);
        material.SetColor("_NearColour", settings.nearColor);
        material.SetFloat("_FocusPoint", settings.focusPoint.value);
        cmd.Blit(mainTex, source, material);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd) {
        // CHANGE
        cmd.ReleaseTemporaryRT(Shader.PropertyToID("_MainTex"));
        cmd.ReleaseTemporaryRT(Shader.PropertyToID("_TempTex"));
    }
}
