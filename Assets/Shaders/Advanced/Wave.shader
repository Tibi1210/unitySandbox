Shader "_Tibi/Tesselation/Wave"{
	Properties{
		_BaseColor ("Base Color", Color) = (1, 1, 1, 1)
		_BaseTex("Base Texture", 2D) = "white" {}

		_WaveStrength("Wave Strength", Range(0, 100)) = 0.1
		_WaveSpeed("Wave Speed", Range(0, 10)) = 1
		_WaveAmplitude("Wave Amplitude", Range(0, 10)) = 1
		_WavePhase("Wave Phase", Range(0, 10)) = 1

		[Enum(UnityEngine.Rendering.BlendMode)]
		_SrcBlend("Source Blend Factor", Int) = 1

		[Enum(UnityEngine.Rendering.BlendMode)]
		_DstBlend("Destination Blend Factor", Int) = 1

		_TessAmount("Tessellation Amount", Range(1, 64)) = 2
	}

	SubShader{
		Tags{
			"RenderType" = "Transparent"
			"Queue" = "Transparent"
			"RenderPipeline" = "UniversalPipeline"
		}

		Pass{

			Tags{
				"LightMode" = "UniversalForward"
			}
			Blend [_SrcBlend] [_DstBlend]


			HLSLPROGRAM
				
				#pragma vertex vert
				#pragma fragment frag
				#pragma hull tessHull
				#pragma domain tessDomain
				#pragma target 5.0

				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

				struct appdata{
					float4 positionOS : Position;
					float2 uv : TEXCOORD0;
				};

				struct tessControlPoint{
					float4 positionOS : INTERNALTESSPOS;
					float2 uv : TEXCOORD0;
				};

				struct tessFactors{
					float edge[3] : SV_TessFactor;
					float inside : SV_InsideTessFactor;
				};

				struct v2f{
					float4 positionCS : SV_Position;
					float2 uv : TEXCOORD0;
				};

				sampler2D _BaseTex;
				CBUFFER_START(UnityPerMaterial)
					float4 _BaseColor;
					float4 _BaseTex_ST;
					float _TessAmount;
					float _WaveStrength;
					float _WaveSpeed;
					float _WaveAmplitude;
					float _WavePhase;
				CBUFFER_END

				tessControlPoint vert(appdata v){
					tessControlPoint o;
					o.positionOS = v.positionOS;
					o.uv = v.uv;
					return o;
				}

				
				[domain("tri")]
				[outputcontrolpoints(3)]
				[outputtopology("triangle_cw")]
				[partitioning("fractional_odd")] //fractional_even
				[patchconstantfunc("patchConstantFunc")]
				tessControlPoint tessHull(InputPatch<tessControlPoint, 3> patch, uint id :SV_OutputControlPointID){
					return patch[id];
				}

				tessFactors patchConstantFunc(InputPatch<tessControlPoint, 3> patch){
					tessFactors f;
					f.edge[0] = f.edge[1] = f.edge[2] = _TessAmount;
					f.inside = _TessAmount;
					return f;
				}

				v2f tessVert(appdata v){
					v2f o;
					float4 positionWS = mul(unity_ObjectToWorld, v.positionOS);
					float height = _WaveAmplitude * sin((positionWS.x * _WaveStrength)+ (positionWS.z * _WaveStrength) + (_Time.y * _WaveSpeed) + _WavePhase);
					positionWS.y += height;
					o.positionCS = mul(UNITY_MATRIX_VP, positionWS);
					o.uv = TRANSFORM_TEX(v.uv, _BaseTex);
					return o;	
				}

				[domain("tri")]
				v2f tessDomain(tessFactors factors, OutputPatch<tessControlPoint, 3> patch, float3 bcCoords : SV_DomainLocation){
					appdata i;
					i.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
					i.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
					return tessVert(i);
				}

				float4 frag (v2f i) : SV_Target{
					float4 textureSample = tex2D(_BaseTex, i.uv);
					return textureSample * _BaseColor;
				}
			ENDHLSL
		}	
		
	}
	Fallback Off
}
