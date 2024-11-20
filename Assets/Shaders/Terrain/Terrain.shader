Shader "_Tibi/test/asd"{

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

					VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
					
					//float4 positionWS = mul(unity_ObjectToWorld, input.positionOS);
					float4 positionWS = float4(vertexInput.positionWS,1);
					
					float4 displacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 0, 0);
					positionWS.y = displacement.x;

					output.positionCS = mul(UNITY_MATRIX_VP, positionWS);
					output.uv = TRANSFORM_TEX(input.uv, _BaseTex);
					return output;

				}

				float4 frag(v2f i) : SV_Target{
					float4 textureSample = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, i.uv, 0, 0);
					return float4(textureSample.rrr, 1.0);
				}
			ENDHLSL
		}	
		
	}
	Fallback Off
}
