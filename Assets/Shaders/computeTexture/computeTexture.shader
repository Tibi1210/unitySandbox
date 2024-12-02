Shader "_Tibi/test/computeTexture"{

	SubShader{
		Tags{
			"RenderType" = "Opaque"
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}

		Pass{

			Tags{
				"LightMode" = "UniversalForward"
			}

			HLSLPROGRAM
				
				#pragma vertex vert
				#pragma fragment frag

				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

				struct VertexData{
					float4 positionOS : Position;
					float2 uv : TEXCOORD0;
				};

				struct v2f{
					float4 positionCS : SV_Position;
					float2 uv : TEXCOORD0;
				};

				TEXTURE2D_ARRAY(_BaseTex);
				SAMPLER(sampler_BaseTex);

				CBUFFER_START(UnityPerMaterial)
					float4 _BaseTex_ST;
				CBUFFER_END


				v2f vert(VertexData input){
					v2f output;

					output.positionCS = TransformObjectToHClip(input.positionOS);
					output.uv = TRANSFORM_TEX(input.uv, _BaseTex);
					return output;	
				}

				float4 frag(v2f i) : SV_Target{
					float4 textureSample = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, i.uv, 0, 0);
					return textureSample;
				}
			ENDHLSL
		}	
		
	}
	Fallback Off
}
