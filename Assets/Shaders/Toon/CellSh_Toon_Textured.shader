Shader "_Tibi/Lighting/csh_text"{
	 Properties{
		_BaseColor ("Base Color", Color) = (1, 1, 1, 1)
		_BaseTex("Base Texture", 2D) = "white" {}
		
		_Shear("Shear Amount", Vector) = (0, 0, 0, 0)

		_Center("Center", Vector) = (0.5,0.5,0,0)
		_RadialScale("Radial Scale", Float) = 1
		_LengthScale("Length Scale", Float) = 1


		_Smoothness ("Smoothness", Range(0.0, 1.0)) = 1.0
		_rimThreshold ("Rim Threshold", Range(0.1, 10.0)) = 0.1

		_eDiffuse ("Edge Diffuse", Range(0.0, 1.0)) = 0
		_eSpecular ("Edge Specular", Range(0.0001, 1.0)) = 0.0001
		_eSpecularOffset ("Edge Specular Offset", Range(0.0, 1.0)) = 0
		_eDistanceAttenuation ("Edge Distance Attenuation", Range(0.0, 1.0)) = 1
		_eShadowAttenuation ("Edge Shadow Attenuation", Range(0.0, 1.0)) = 1
		_eRim ("Edge Rim", Range(0.1, 1.0)) = 0.642
		_eRimOffset ("Edge Rim Offset", Range(0.0, 1.0)) = 0
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
			// HLSL code goes in here.

			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
			#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
			#pragma multi_compile _ _SHADOWS_SOFT
			#pragma multi_compile_instancing


			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			struct appdata{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			};

			struct v2f{
				float4 positionCS : SV_POSITION;
				float3 normalWS : TEXCOORD1;
				float3 viewWS : TEXCOORD2;
				float3 positionWS : TEXCOORD3;
				float2 uv : TEXCOORD4;
			};

			struct Edging{
				float diffuse;
				float specular;
				float specularOffset;
				float distanceAttenuation;
				float shadowAttenuation;
				float rim;
				float rimOffset;
			};

			struct SurfaceVariables{
				float3 normal;
				float3 view;
				float smoothness;
				float shininess;
				float rimThreshold;
				Edging edgeParams;
			};
			
			sampler2D _BaseTex;
			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float4 _BaseTex_ST;

				float2 _Center;
				float _RadialScale;
				float _LengthScale;

				float4 _Shear;

				float _Smoothness;
				float _rimThreshold;

				float _eDiffuse;
				float _eSpecular;
				float _eSpecularOffset;
				float _eDistanceAttenuation;
				float _eShadowAttenuation;
				float _eRim;
				float _eRimOffset;

			CBUFFER_END

			float2 cartesianToPolar(float2 cartUV){
				float2 offset = cartUV - _Center;
				float radius = length(offset) * 2;
				float angle = atan2(offset.x, offset.y) / (2.0f * PI);
				return float2(radius, angle);
			}

			v2f vert (appdata i){
				v2f o;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(i.positionOS.xyz);
				VertexNormalInputs normalInput = GetVertexNormalInputs(i.normalOS);
				o.positionCS = vertexInput.positionCS;
				o.normalWS = normalInput.normalWS;
				o.positionWS = vertexInput.positionWS;
				o.viewWS = GetWorldSpaceNormalizeViewDir(o.positionWS);
				o.uv = TRANSFORM_TEX(i.uv, _BaseTex);

				float2x2 shearMatrix = float2x2(1, -_Shear.x, -_Shear.y, 1);

				o.uv = mul(shearMatrix, o.uv);

				return o;
			}

			float3 calculateShading(Light l, SurfaceVariables s){

				float shadowAttenSmoothStep = smoothstep(0.0, s.edgeParams.shadowAttenuation, l.shadowAttenuation);
				float distAttenSmoothStep = smoothstep(0.0, s.edgeParams.distanceAttenuation, l.distanceAttenuation);
				float attenuation = shadowAttenSmoothStep * distAttenSmoothStep;
				
				float diffuse = saturate(dot(s.normal, l.direction));
				diffuse *= attenuation;
				diffuse = smoothstep(0.0,  s.edgeParams.diffuse, diffuse);

				float3 h = SafeNormalize(l.direction + s.view);
				float specular = saturate(dot(s.normal, h));
				specular = pow(specular, s.shininess);
				specular *= diffuse *  s.smoothness;
				specular = s.smoothness * smoothstep((1 - s.smoothness) * s.edgeParams.specular + s.edgeParams.specularOffset, s.edgeParams.specular + s.edgeParams.specularOffset, specular);

				float rim = 1 - dot(s.view, s.normal);
				rim *= pow(diffuse, s.rimThreshold);
				rim = s.smoothness * smoothstep(s.edgeParams.rim - 0.5 * s.edgeParams.rimOffset, s.edgeParams.rim + 0.5 * s.edgeParams.rimOffset, rim);

				return l.color * (diffuse + max(specular, rim));

			}

			float4 frag (v2f i) : SV_TARGET{

				float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);

				Light light = GetMainLight(shadowCoord);

				SurfaceVariables sv;
				sv.normal = normalize(i.normalWS);
				sv.view = SafeNormalize(i.viewWS);
				sv.smoothness = _Smoothness;
				sv.shininess = exp2(10 * sv.smoothness + 1);
				sv.rimThreshold = _rimThreshold;

				Edging e;
				e.diffuse = _eDiffuse;
				e.specular = _eSpecular;
				e.specularOffset = _eSpecularOffset;
				e.distanceAttenuation = _eDistanceAttenuation;
				e.shadowAttenuation = _eShadowAttenuation;
				e.rim = _eRim;
				e.rimOffset = _eRimOffset;

				sv.edgeParams = e;

				float3 coloredLighting = calculateShading(light, sv);
				int pixelLightCount = GetAdditionalLightsCount();
				for(int j = 0; j < pixelLightCount; j++){
					light = GetAdditionalLight(j, i.positionWS, 1);
					coloredLighting += calculateShading(light, sv);
				}



				float2 radialUV = cartesianToPolar(i.uv);
				radialUV.x *= _RadialScale;
				radialUV.y *= _LengthScale;
				//float4 textureSample = tex2D(_BaseTex, radialUV);
				float4 textureSample = tex2D(_BaseTex, i.uv);
				//float4 textureSample = tex2D(_BaseTex, i.viewWS);
				float3 color = textureSample * _BaseColor;

				return float4(color * coloredLighting,1);
			}

			ENDHLSL
		 }

		Pass{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }
			ZWrite On
			ZTest LEqual
			HLSLPROGRAM
				#pragma vertex ShadowPassVertex
				#pragma fragment ShadowPassFragment
				#pragma multi_compile_instancing
				#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
				#include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
			ENDHLSL
		}

		Pass{
			Name "DepthOnly"
			Tags{"LightMode" = "DepthOnly"}
			ZWrite On
			ColorMask 0
			HLSLPROGRAM
				#pragma vertex DepthOnlyVertex
				#pragma fragment DepthOnlyFragment
				#include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"
				#include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
				#pragma multi_compile_instancing
				#pragma multi_compile _ DOTS_INSTANCING_ON
			ENDHLSL
		}
		UsePass "Universal Render Pipeline/Lit/DepthNormals"




	 }
}