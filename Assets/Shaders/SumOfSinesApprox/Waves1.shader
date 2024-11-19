Shader "_Tibi/test/Waves1"{

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

				#define _TessellationEdgeLength 10

				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
				#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

				struct VertexData{
					float4 positionOS : POSITION;
					float3 normalOS : NORMAL;
					float2 uv : TEXCOORD0;
				};

				struct TessellationControlPoint {
					float4 positionOS : INTERNALTESSPOS;
					float2 uv : TEXCOORD0;
				};
	
				struct TessellationFactors {
					float edge[3] : SV_TESSFACTOR;
					float inside : SV_INSIDETESSFACTOR;
				};

				struct v2f{
					float4 positionCS : SV_POSITION;
					float2 uv : TEXCOORD0;
					float3 normalWS : TEXCOORD1;
					float3 viewWS : TEXCOORD2;
				};
				
				float TessellationHeuristic(float3 cp0, float3 cp1) {
					float edgeLength = distance(cp0, cp1);
					float3 edgeCenter = (cp0 + cp1) * 0.5;
					float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

					return edgeLength * _ScreenParams.y / (_TessellationEdgeLength * (pow(viewDistance * 0.5, 1.2)));
				}

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

				TEXTURE2D_ARRAY(_BaseTex);
				SAMPLER(sampler_BaseTex);

				CBUFFER_START(UnityPerMaterial)
					float4 _BaseColor;
					float4 _BaseTex_ST;
					float _GlossPower;
					float _FresnelNormalStrength;
					float _FresnelShininess;
					float _FresnelBias;
					float _FresnelStrength;
					float _SpecularNormalStrength;
				CBUFFER_END

				TessellationControlPoint vert(VertexData input) {
					TessellationControlPoint output;
					output.positionOS = input.positionOS;
					output.uv = TRANSFORM_TEX(input.uv, _BaseTex);
					return output;
				}

				v2f tessVert(VertexData input){
					v2f output;
					
					VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
					
					//float4 positionWS = mul(unity_ObjectToWorld, input.positionOS);
					float4 positionWS = float4(vertexInput.positionWS,1);
					
					float3 displacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 0, 0);
					float3 normal = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 1, 0);
					
					positionWS.y = displacement.y;
					positionWS.x += displacement.x;
					positionWS.z += displacement.z;
					
					VertexNormalInputs normalInput = GetVertexNormalInputs(normal);
					output.normalWS = normalInput.normalWS;

					output.viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
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
				[partitioning("integer")] //fractional_even, integer, fractional_odd
				[patchconstantfunc("PatchFunction")]
				TessellationControlPoint tessHull(InputPatch<TessellationControlPoint, 3> patch, uint id :SV_OutputControlPointID){
					return patch[id];
				}

				[domain("tri")]
				v2f tessDomain(TessellationFactors factors, OutputPatch<TessellationControlPoint, 3> patch, float3 bcCoords : SV_DomainLocation){
					VertexData output;
					output.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
					output.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
					return tessVert(output);
				}

				float4 frag(v2f input) : SV_Target{
					float3 tex = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 1, 0);
					float3 normal = normalize(input.normalWS);
					float3 view = SafeNormalize(input.viewWS);
					float3 ambient = SampleSH(input.normalWS);
					Light mainLight = GetMainLight();
					float3 halfVector = SafeNormalize(mainLight.direction + view);

					float3 diffuse = mainLight.color * saturate(dot(mainLight.direction, normal));
					
					// Schlick Fresnel
					float3 fresnelNormal = normal;
					fresnelNormal.xz *= _FresnelNormalStrength;
					fresnelNormal = normalize(fresnelNormal);
					float base = 1 - saturate(dot(view, fresnelNormal));
					float exponential = pow(base, _FresnelShininess);
					float R = exponential + _FresnelBias * (1.0 - exponential);
					R *= _FresnelStrength;
					float3 fresnelColor = mainLight.color * R;

					float3 specularReflectance = float3(1,1,1);
					float3 specNormal = normal;
					specNormal.xz *= _SpecularNormalStrength;
					specNormal = normalize(specNormal);
					float spec = pow(saturate(dot(specNormal, halfVector)), _GlossPower) * saturate(dot(mainLight.direction, normal));
					float3 specularColor = mainLight.color * specularReflectance * spec;
					// Schlick Fresnel but again for specular
					base = 1 - saturate(dot(view, halfVector));
					exponential = pow(base, 5.0);
					R = exponential + _FresnelBias * (1.0 - exponential);
					specularColor *= R;

					float4 diffuseLighting = float4(ambient + diffuse, 1.0f);
					float4 specularLighting = float4(specularColor + fresnelColor, 1.0f);

					return _BaseColor * diffuseLighting + specularLighting;
				}
			ENDHLSL
		}	
		
	}
	Fallback Off
}
