Shader "_Tibi/Terrain_LOD" {
	SubShader {
		Tags {
			"RenderType" = "Opaque"
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}

		Pass {

			Tags{
				"LightMode" = "UniversalForward"
			}

			HLSLPROGRAM

			#pragma target 5.0
			#pragma vertex vert
			#pragma hull tessHull
			#pragma domain tessDomain
			#pragma fragment frag

			#define EDGE_LEN 10
			#define PI 3.14159265358979323846

			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

			bool TriangleIsBelowClipPlane(float3 p0, float3 p1, float3 p2, int planeIndex, float bias) {
				float4 plane = unity_CameraWorldClipPlanes[planeIndex];
				return dot(float4(p0, 1), plane) < bias && dot(float4(p1, 1), plane) < bias && dot(float4(p2, 1), plane) < bias;
			}

			bool cullTriangle(float3 p0, float3 p1, float3 p2, float bias) {
				return TriangleIsBelowClipPlane(p0, p1, p2, 0, bias) ||
					   TriangleIsBelowClipPlane(p0, p1, p2, 1, bias) ||
					   TriangleIsBelowClipPlane(p0, p1, p2, 2, bias) ||
					   TriangleIsBelowClipPlane(p0, p1, p2, 3, bias);
			}

			struct VertexData {
				float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
			};

			struct v2f {
				float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
				float3 positionWS : TEXCOORD1;
			};

			struct TessellationControlPoint {
                float4 positionOS : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
            };

			struct TessellationFactors {
				float edge[3] : SV_TESSFACTOR;
				float inside : SV_INSIDETESSFACTOR;
			};

			float TessellationHeuristic(float3 cp0, float3 cp1) {
				float edgeLength = distance(cp0, cp1);
				float3 edgeCenter = (cp0 + cp1) * 0.5;
				float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

				return edgeLength * _ScreenParams.y / (EDGE_LEN * (pow(viewDistance * 0.5, 1.2)));
			}

			TEXTURE2D_ARRAY(_BaseTex);
			SAMPLER(sampler_BaseTex);

			CBUFFER_START(UnityPerMaterial)
				float4 _BaseTex_ST;
			CBUFFER_END

			TessellationControlPoint vert(VertexData input) {
				TessellationControlPoint output;
				output.positionOS = input.positionOS;
				output.uv = input.uv;
				return output;
			}

			v2f tessVert(VertexData input) {

				v2f output;

				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
				
				//float4 positionWS = mul(unity_ObjectToWorld, input.positionOS);
				float4 positionWS = float4(vertexInput.positionWS,1);
				
				float4 displacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 0, 0);
				positionWS.y = displacement.x;

				output.positionWS = positionWS;
				output.positionCS = mul(UNITY_MATRIX_VP, positionWS);
				output.uv = TRANSFORM_TEX(input.uv, _BaseTex);
				return output;
			}

			TessellationFactors PatchFunction(InputPatch<TessellationControlPoint, 3> patch) {
				VertexPositionInputs p0_input = GetVertexPositionInputs(patch[0].positionOS);
				VertexPositionInputs p1_input = GetVertexPositionInputs(patch[1].positionOS);
				VertexPositionInputs p2_input = GetVertexPositionInputs(patch[2].positionOS);
                float3 p0 = p0_input.positionWS;
                float3 p1 = p1_input.positionWS;
                float3 p2 = p2_input.positionWS;

                TessellationFactors factors;
                float bias = -0.5 * 100;
                if (cullTriangle(p0, p1, p2, bias)) {
                    factors.edge[0] = factors.edge[1] = factors.edge[2] = factors.inside = 0;
                } else {
                    factors.edge[0] = TessellationHeuristic(p1, p2);
                    factors.edge[1] = TessellationHeuristic(p2, p0);
                    factors.edge[2] = TessellationHeuristic(p0, p1);
                    factors.inside = (TessellationHeuristic(p1, p2) +
                                TessellationHeuristic(p2, p0) +
                                TessellationHeuristic(p1, p2)) * (1 / 3.0);
                }
                return factors;
            }

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [partitioning("integer")]
            [patchconstantfunc("PatchFunction")]
            TessellationControlPoint tessHull(InputPatch<TessellationControlPoint, 3> patch, uint id : SV_OutputControlPointID) {
                return patch[id];
            }

            [domain("tri")]
            v2f tessDomain(TessellationFactors factors, OutputPatch<TessellationControlPoint, 3> patch, float3 bcCoords : SV_DOMAINLOCATION) {
                VertexData data;
                data.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
                data.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
                return tessVert(data);
            }

			float4 frag(v2f input) : SV_TARGET {
				float4 textureSample = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 0, 0);
				return float4(textureSample.rrr, 1.0);
			}

			ENDHLSL
		}
	}
		Fallback Off
}