using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GrayScaleRenderPass : ScriptableRenderPass
{
    private Material material;
    private GrayScaleSettings settings;

    private RenderTargetIdentifier source;
    private RenderTargetIdentifier mainTex;
    private string profilerTag;

    public void Setup(ScriptableRenderer renderer, string profilerTag){

        this.profilerTag = profilerTag;
        source = renderer.cameraColorTargetHandle;
        VolumeStack stack = VolumeManager.instance.stack;
        settings = stack.GetComponent<GrayScaleSettings>();
        renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        if (settings != null && settings.IsActive())
        {
            material = new Material(Shader.Find("_Tibi/PostProcess/GrayScale"));
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
        cmd.Blit(source, mainTex);
        material.SetFloat("_Strength", settings.strength.value);
        cmd.Blit(mainTex, source, material);
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd) {
        cmd.ReleaseTemporaryRT(Shader.PropertyToID("_MainTex"));
    }
}
