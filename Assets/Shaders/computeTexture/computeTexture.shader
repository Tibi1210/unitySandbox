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
				#pragma hull tessHull
				#pragma domain tessDomain
				#pragma target 5.0

				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

				struct VertexData{
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

				TEXTURE2D_ARRAY(_BaseTex);
				SAMPLER(sampler_BaseTex);

				CBUFFER_START(UnityPerMaterial)
					float4 _BaseColor;
					float4 _BaseTex_ST;
					float _TessAmount;
					float _WaveStrength;
					float _WaveSpeed;
					float _WaveAmplitude;
					float _WavePhase;
				CBUFFER_END

				tessControlPoint vert(VertexData input){
					tessControlPoint output;
					output.positionOS = input.positionOS;
					output.uv = input.uv;
					return output;
				}

				tessFactors patchConstantFunc(InputPatch<tessControlPoint, 3> patch){
					tessFactors factor;
					factor.edge[0] = factor.edge[1] = factor.edge[2] = _TessAmount;
					factor.inside = _TessAmount;
					return factor;
				}

				
				[domain("tri")]
				[outputcontrolpoints(3)]
				[outputtopology("triangle_cw")]
				[partitioning("fractional_odd")] //fractional_even, integer
				[patchconstantfunc("patchConstantFunc")]
				tessControlPoint tessHull(InputPatch<tessControlPoint, 3> patch, uint id :SV_OutputControlPointID){
					return patch[id];
				}

				v2f tessVert(VertexData input){
					v2f output;

					float4 positionWS = mul(unity_ObjectToWorld, input.positionOS);
					float height = _WaveAmplitude * sin((positionWS.x * _WaveStrength)+ (positionWS.z * _WaveStrength) + (_Time.y * _WaveSpeed) + _WavePhase);
					positionWS.y += height;

					output.positionCS = mul(UNITY_MATRIX_VP, positionWS);
					output.uv = TRANSFORM_TEX(input.uv, _BaseTex);
					return output;	
				}

				[domain("tri")]
				v2f tessDomain(tessFactors factors, OutputPatch<tessControlPoint, 3> patch, float3 bcCoords : SV_DomainLocation){
					VertexData output;
					output.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
					output.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
					return tessVert(output);
				}

				float4 frag(v2f i) : SV_Target{
					float4 textureSample = SAMPLE_TEXTURE2D_ARRAY(_BaseTex, sampler_BaseTex, i.uv, 0);
					return textureSample * _BaseColor;
				}
			ENDHLSL
		}	
		
	}
	Fallback Off
}
