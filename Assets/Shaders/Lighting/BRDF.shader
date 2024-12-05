Shader "_Tibi/Lighting/BRDF"{
    
    Properties{
		_BaseColor("Base Color", Color) = (1,1,1,1)
		_Metalic("Metalic", Range(0.0, 1.0)) = 0.0
		_Reflectance("Reflectance", Range(0.0, 1.0)) = 0.5
		_Roughness("Roughness", Range(0.0, 1.0)) = 0.5
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

			#define PI 3.14159265358979323846

			#pragma vertex vert
			#pragma fragment frag

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			struct VertexData{
				float4 positionOS : POSITION;
				float2 uv : TEXCOORD0;
				float3 normalOS : NORMAL;
			};
			struct v2f{
				float4 positionCS : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 positionWS : TEXCOORD1;
				float3 normalWS : TEXCOORD2;
				float3 viewWS : TEXCOORD3;
			};

			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float _Metalic;
				float _Reflectance;
				float _Roughness;
			CBUFFER_END

			half DotClamped(half3 a, half3 b){
				return saturate(dot(a, b));
			}

			v2f vert (VertexData input){
				v2f output;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
				output.positionWS = vertexInput.positionWS;
				output.positionCS = vertexInput.positionCS;
				output.uv = input.uv;
				output.normalWS = TransformObjectToWorldNormal(input.normalOS);
				output.viewWS = GetWorldSpaceNormalizeViewDir(output.positionWS);
				return output;
			}

			float3 Fresnelschlick(float theta, float f0){
				return f0 + (1.0 - f0) * pow(1.0 - theta, 5.0);
			}
			float D_GGX(float ndoth){
				float alpha = _Roughness * _Roughness;
				float alpha2 = alpha * alpha;
				float ndoth2 = ndoth * ndoth;
				float b = (ndoth2 * (alpha2 - 1.0) + 1.0);
				return alpha2 * 1/PI * (b * b);
			}
			float G1_GGX_Schlick(float ndot){
				float alpha = _Roughness * _Roughness;
				float k = alpha / 2.0;
				return max(ndot, 0.001) / (ndot * (1.0 - k) + k);
			}
			float G_Smith(float ndotv, float ndotl){
				return G1_GGX_Schlick(ndotl) * G1_GGX_Schlick(ndotv);
			}
			

			// Inputs: 
			// - float3 normalDir: surface normal dierction in WS
			// - float3 viewDir: view direction in WS
			// - float3 lightDir: incoming light direction 
			// - float3 lightColor: incoming light color
			// Output:
			// - float3 color: the calculated color value
			float3 PBR(float3 normalDir, float3 viewDir, float3 lightDir, float3 lightColor){

				float3 halfwayDir = normalize(lightDir + viewDir);
				float ndotv = DotClamped(normalDir, viewDir);
				float ndotl = DotClamped(normalDir, lightDir);
				float ndoth = DotClamped(normalDir, halfwayDir);
				float vdoth = DotClamped(viewDir, halfwayDir);

				float3 f0 = float3(0.16 * (_Reflectance*_Reflectance), 0.16 * (_Reflectance*_Reflectance), 0.16 * (_Reflectance*_Reflectance));
				f0 = lerp(f0, _BaseColor, _Metalic);

				// specular
				float3 F = Fresnelschlick(vdoth, f0);
				float D = D_GGX(ndoth); // rough
				float G = G_Smith(ndotv, ndotl); // rough
				float3 specular = (F * D * G) / (4.0 * max(ndotv, 0.001) * max(ndotl, 0.001));

				// diffuse
				float3 rhoD = _BaseColor;
				rhoD *= float3(1.0, 1.0, 1.0) - F;
				rhoD *= (1.0 - _Metalic);
				float3 diff = _BaseColor * 1/PI;

				// return float3(1.0, 0.0, 0.0);
				return diff + specular;
			}


			float4 frag (v2f input) : SV_TARGET{
				float3 normalDir = normalize(input.normalWS);
				float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
				Light light = GetMainLight(shadowCoord);
				float3 lightDir = light.direction;	

				float3 outputColor = PBR(normalDir, input.viewWS, lightDir, light.color.rgb);

				return float4(outputColor,1.0);
			}

			ENDHLSL
        }


    }
}
