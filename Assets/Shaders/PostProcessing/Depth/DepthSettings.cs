using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// CHANGE
[System.Serializable, VolumeComponentMenu("_Tibi/Depth")]

// CHANGE
public sealed class DepthSettings : VolumeComponent, IPostProcessComponent
{
    public ClampedFloatParameter focusPoint = new ClampedFloatParameter(1, 1, 1000);

    public Color nearColor = new Color(1f, 0f, 0f);
    public Color farColor = new Color(0f, 1f, 0f);

    public bool IsActive() => focusPoint.value > 1 && active;

    public bool IsTileCompatible() => false;
}
