Shader "_Tibi/Lighting/PhongShading"{
    
    Properties{
		_BaseColor ("Base Color", Color) = (1, 1, 1, 1)
		_GlossPower("Gloss Power", Float) = 400
    }

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
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#define PI 3.14159265358979323846

			struct appdata{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			};
			struct v2f{
				float4 positionCS : SV_POSITION;
				float3 normalWS : TEXCOORD1;
				float3 positionWS : TEXCOORD2;
				float2 uv : TEXCOORD0;
			};

			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float _GlossPower;
			CBUFFER_END

			v2f vert (appdata v){
				v2f o;
				o.uv = v.uv;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS);
				o.positionWS = vertexInput.positionWS;
				o.positionCS = mul(UNITY_MATRIX_VP, float4(vertexInput.positionWS, 1.0));
				VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS);
				o.normalWS = normalInput.normalWS;
				return o;
			}

			half DotClamped(half3 a, half3 b){
                return saturate(dot(a, b));
            }

			float4 frag (v2f i) : SV_TARGET{

				float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light light = GetMainLight(shadowCoord);
                float3 lightDir = light.direction;
                float3 viewDir = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float3 halfwayDir = normalize(lightDir + viewDir);

				float3 diffuse = 1/PI * _BaseColor;
				float specular = pow(DotClamped(i.normalWS, halfwayDir), _GlossPower);


				return float4(diffuse + specular, 1.0);
			}

			ENDHLSL
        }


    }
}
