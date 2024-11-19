using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// CHANGE
[System.Serializable, VolumeComponentMenu("_Tibi/SamplePostProcess")]

// CHANGE
public sealed class SamplePostProcessSettings : VolumeComponent, IPostProcessComponent
{

    // CHANGE
    [Tooltip("Some parameter to modify")]
    public ClampedIntParameter kernelSize = new ClampedIntParameter(1, 1, 101);
    public bool IsActive() => kernelSize.value > 1 && active;

    public bool IsTileCompatible() => false;
}
