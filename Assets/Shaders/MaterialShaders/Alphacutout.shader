Shader "_Tibi/ObjectShader/AlphaCutoff"{
	Properties{
	_BaseColor ("Base Color", Color) = (1, 1, 1, 1)
	_BaseTex("Base Texture", 2D) = "white" {}
	_ClipThreshold("Alpha Clip Threshold", Range(0, 1)) = 0.5
	}

	SubShader{

		Tags {

			"RenderType" = "Opaque"
			"Queue" = "AlphaTest"

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

			struct appdata{
			float4 positionOS : Position;
			float2 uv : TEXCOORD0;
			};

			struct v2f{
			float4 positionCS : SV_Position;
			float2 uv : TEXCOORD0;
			};

			sampler2D _BaseTex;
			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float4 _BaseTex_ST;
				float _ClipThreshold;
			CBUFFER_END

			v2f vert (appdata v){
				v2f o;
				o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
				o.uv = TRANSFORM_TEX(v.uv, _BaseTex);
				return o;
			}

			float4 frag (v2f i) : SV_Target{
				float4 textureSample = tex2D(_BaseTex, i.uv);
				float4 outputColor = textureSample * _BaseColor;
				clip(outputColor.a - _ClipThreshold);
				return outputColor;
			}
			ENDHLSL
		}

	}
}
