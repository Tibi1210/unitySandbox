Shader "Custom/FFTWater"{
	SubShader{
		Tags{
			"RenderType" = "Opaque"
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}

		HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#define _TessellationEdgeLength 10
			#define PI 3.14159265358979323846

			bool TriangleIsBelowClipPlane(float3 p0, float3 p1, float3 p2, int planeIndex, float bias){
				float4 plane = unity_CameraWorldClipPlanes[planeIndex];
				return dot(float4(p0, 1), plane) < bias && dot(float4(p1, 1), plane) < bias && dot(float4(p2, 1), plane) < bias;
			}

			bool cullTriangle(float3 p0, float3 p1, float3 p2, float bias){
				return TriangleIsBelowClipPlane(p0, p1, p2, 0, bias) ||
					TriangleIsBelowClipPlane(p0, p1, p2, 1, bias) ||
					TriangleIsBelowClipPlane(p0, p1, p2, 2, bias) ||
					TriangleIsBelowClipPlane(p0, p1, p2, 3, bias);
			}

			half DotClamped(half3 a, half3 b){
				return saturate(dot(a, b));
			}

			float TessellationHeuristic(float3 cp0, float3 cp1) {
					float edgeLength = distance(cp0, cp1);
					float3 edgeCenter = (cp0 + cp1) * 0.5;
					float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

					return edgeLength * _ScreenParams.y / (_TessellationEdgeLength * (pow(viewDistance * 0.5, 1.2)));
			}
		ENDHLSL

		Pass{

			Tags{
				"LightMode" = "UniversalForward"
			}

			HLSLPROGRAM

				#pragma target 5.0
				#pragma vertex vert
				#pragma hull tessHull
				#pragma domain tessDomain
				#pragma fragment frag

				TEXTURE2D_ARRAY(_DisplacementTextures);
				SAMPLER(sampler_DisplacementTextures);
				TEXTURE2D_ARRAY(_SlopeTextures);
				SAMPLER(sampler_SlopeTextures);

				CBUFFER_START(UnityPerMaterial)
					float4 _DisplacementTextures_ST;
					float4 _SlopeTextures_ST;

					float _NormalStrength, _FresnelNormalStrength, _SpecularNormalStrength;

					float3 _Ambient, _DiffuseReflectance, _SpecularReflectance, _FresnelColor, _TipColor;
					float _Shininess, _FresnelBias, _FresnelStrength, _FresnelShininess;
					float _DisplacementDepthFalloff, _FoamDepthAttenuation;
					
					float _Tile0, _Tile1, _Tile2, _Tile3;
					int _DebugTile0, _DebugTile1, _DebugTile2, _DebugTile3;
					int _ContributeDisplacement0, _ContributeDisplacement1, _ContributeDisplacement2, _ContributeDisplacement3;
					int _VisualizeLayer0, _VisualizeLayer1, _VisualizeLayer2, _VisualizeLayer3;
					float _FoamSubtract0, _FoamSubtract1, _FoamSubtract2, _FoamSubtract3;
				CBUFFER_END

				struct VertexData {
					float4 positionOS : POSITION;
					float2 uv : TEXCOORD0;
				};

				struct v2f {
					float4 positionCS : SV_POSITION;
					float2 uv : TEXCOORD0;
					float3 positionWS : TEXCOORD1;
					float depth : TEXCOORD2;
				};

				struct TessellationControlPoint {
					float4 positionOS : INTERNALTESSPOS;
					float2 uv : TEXCOORD0;
				};

				struct TessellationFactors {
					float edge[3] : SV_TESSFACTOR;
					float inside : SV_INSIDETESSFACTOR;
				};

				TessellationControlPoint vert(VertexData input) {
					TessellationControlPoint output;
					output.positionOS = input.positionOS;
					output.uv = input.uv;
					return output;
				}

				v2f tessVert(VertexData input) {
					v2f output;
					input.uv = 0;
					VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
					output.positionWS = vertexInput.positionWS;

					float3 displacement1, displacement2, displacement3, displacement4 = float3(0.0f,0.0f,0.0f);


					displacement1 = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTextures, sampler_DisplacementTextures, float2(output.positionWS.xz * _Tile0), 0, 0) * _VisualizeLayer0 * _ContributeDisplacement0;
					displacement2 = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTextures, sampler_DisplacementTextures, float2(output.positionWS.xz * _Tile1), 1, 0) * _VisualizeLayer1 * _ContributeDisplacement1;
					displacement3 = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTextures, sampler_DisplacementTextures, float2(output.positionWS.xz * _Tile2), 2, 0) * _VisualizeLayer2 * _ContributeDisplacement2;
					displacement4 = SAMPLE_TEXTURE2D_ARRAY_LOD(_DisplacementTextures, sampler_DisplacementTextures, float2(output.positionWS.xz * _Tile3), 3, 0) * _VisualizeLayer3 * _ContributeDisplacement3;
					float3 displacement = displacement1 + displacement2 + displacement3 + displacement4;

					float4 clipPos = vertexInput.positionCS;
					float depth = 1 - Linear01Depth(clipPos.z / clipPos.w, _ZBufferParams);

					displacement = lerp(0.0, displacement, pow(saturate(depth), _DisplacementDepthFalloff));

					input.positionOS.xyz += mul(unity_WorldToObject, displacement.xyz);
					vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
					
					output.positionCS = vertexInput.positionCS;
					output.uv = output.positionWS.xz;
					output.positionWS = vertexInput.positionWS;
					output.depth = depth;
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

				float3 customShading(float3 normal, float3 lightDir, float3 viewDir, float3 halfwayDir, float3 lightColor){
				
					float ndotl = DotClamped(normal, lightDir);
					float3 diffuseReflectance = _DiffuseReflectance / PI;
					float3 diffuse = lightColor * ndotl * diffuseReflectance;

					// Schlick Fresnel
					float3 fresnelNormal = normal;
					fresnelNormal.xz *= _FresnelNormalStrength;
					fresnelNormal = normalize(fresnelNormal);
					float base = 1 - dot(viewDir, fresnelNormal);
					float exponential = pow(base, _FresnelShininess);
					float R = exponential + _FresnelBias * (1.0 - exponential);
					R *= _FresnelStrength;
					float3 fresnel = _FresnelColor * R;

					float3 specularReflectance = _SpecularReflectance;
					float3 specNormal = normal;
					specNormal.xz *= _SpecularNormalStrength;
					specNormal = normalize(specNormal);
					float spec = pow(DotClamped(specNormal, halfwayDir), _Shininess) * ndotl;
					float3 specular = lightColor * specularReflectance * spec;
					// Schlick Fresnel but again for specular
					base = 1 - DotClamped(viewDir, halfwayDir);
					exponential = pow(base, 5.0);
					R = exponential + _FresnelBias * (1.0 - exponential);
					specular *= R;
					
					return _Ambient + diffuse + specular + fresnel;
				}

				float4 frag(v2f input) : SV_TARGET {

					float4 displacementFoam1 = SAMPLE_TEXTURE2D_ARRAY(_DisplacementTextures,sampler_DisplacementTextures, float2(input.uv * _Tile0), 0) * _VisualizeLayer0;
					displacementFoam1.a + _FoamSubtract0;
					float4 displacementFoam2 = SAMPLE_TEXTURE2D_ARRAY(_DisplacementTextures,sampler_DisplacementTextures, float2(input.uv * _Tile1), 1) * _VisualizeLayer1;
					displacementFoam2.a + _FoamSubtract1;
					float4 displacementFoam3 = SAMPLE_TEXTURE2D_ARRAY(_DisplacementTextures,sampler_DisplacementTextures, float2(input.uv * _Tile2), 2) * _VisualizeLayer2;
					displacementFoam3.a + _FoamSubtract2;
					float4 displacementFoam4 = SAMPLE_TEXTURE2D_ARRAY(_DisplacementTextures,sampler_DisplacementTextures, float2(input.uv * _Tile3), 3) * _VisualizeLayer3;
					displacementFoam4.a + _FoamSubtract3;
					float4 displacementFoam = displacementFoam1 + displacementFoam2 + displacementFoam3 + displacementFoam4;

					float2 slopes1 = SAMPLE_TEXTURE2D_ARRAY(_SlopeTextures,sampler_SlopeTextures, float2(input.uv * _Tile0), 0) * _VisualizeLayer0;
					float2 slopes2 = SAMPLE_TEXTURE2D_ARRAY(_SlopeTextures,sampler_SlopeTextures, float2(input.uv * _Tile1), 1) * _VisualizeLayer1;
					float2 slopes3 = SAMPLE_TEXTURE2D_ARRAY(_SlopeTextures,sampler_SlopeTextures, float2(input.uv * _Tile2), 2) * _VisualizeLayer2;
					float2 slopes4 = SAMPLE_TEXTURE2D_ARRAY(_SlopeTextures,sampler_SlopeTextures, float2(input.uv * _Tile3), 3) * _VisualizeLayer3;
					float2 slopes = slopes1 + slopes2 + slopes3 + slopes4;
					
					slopes *= _NormalStrength;
					float foam = lerp(0.0, saturate(displacementFoam.a), pow(input.depth, _FoamDepthAttenuation));
					
					slopes *= _NormalStrength;
					float3 normal = normalize(float3(-slopes.x, 1.0, -slopes.y));
					normal = normalize(TransformObjectToWorldNormal(normal));
					
					// shading modell
					float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
					Light light = GetMainLight(shadowCoord);
					float3 lightDir = light.direction;
					float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
					float3 halfwayDir = normalize(lightDir + viewDir);
					float3 outputColor = customShading(normal, lightDir, viewDir, halfwayDir, light.color.rgb);
					outputColor = lerp(outputColor, _TipColor, saturate(foam));

					if (_DebugTile0) {
						outputColor = cos(input.uv.x * _Tile0 * PI) * cos(input.uv.y * _Tile0 * PI);
					}

					if (_DebugTile1) {
						outputColor = cos(input.uv.x * _Tile1) * 1024 * cos(input.uv.y * _Tile1) * 1024;
					}

					if (_DebugTile2) {
						outputColor = cos(input.uv.x * _Tile2) * 1024 * cos(input.uv.y * _Tile2) * 1024;
					}

					if (_DebugTile3) {
						outputColor = cos(input.uv.x * _Tile3) * 1024 * cos(input.uv.y * _Tile3) * 1024;
					}
					return float4(outputColor, 1.0);
				}
			ENDHLSL
		}
	}
		Fallback Off
}