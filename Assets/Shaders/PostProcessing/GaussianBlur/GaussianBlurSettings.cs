using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable, VolumeComponentMenu("_Tibi/GaussianBlur")]
public sealed class GaussianBlurSettings : VolumeComponent, IPostProcessComponent
{

    [Tooltip("How large the convolution kernel is. " + "A larger kernel means stronger blurring.")]
    public ClampedIntParameter kernelSize = new ClampedIntParameter(1, 1, 101);
    public bool IsActive() => kernelSize.value > 1 && active;

    public bool IsTileCompatible() => false;
}
