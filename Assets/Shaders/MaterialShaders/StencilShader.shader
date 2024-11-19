Shader "_Tibi/ObjectShader/StencilShader"
{
    Properties
    {
        [IntRange] _StencilRef("Stencil Ref", Range(0, 255)) = 1
    }

    SubShader
    {
        Tags{
            "RenderType" = "Opaque"
            "Queue" = "Geometry-1"
            "RenderPipeline" = "UniversalPipeline" 
        }

        Pass
        {
           	Stencil{
                   Ref[_StencilRef]
                   Comp Always
                   Pass Replace
            }
            ZWrite Off


        }
    }
    Fallback Off
}
