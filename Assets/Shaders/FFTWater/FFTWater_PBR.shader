Shader "Custom/FFTWater_PBR"{

    Properties{
        _MetallicTex("Metallic Map", 2D) = "white"{}
        _NormalTex("Normal Map", 2D) = "bump"{}
        _AOTex("Ambient Occlusion Map", 2D) = "white"{}
    }

    SubShader{
        Tags{
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #define _TessellationEdgeLength 10
            #define PI 3.14159265358979323846

            /**
             * @brief Checks if a triangle is completely below a specific camera clip plane
             * @param p0 First vertex position in world space
             * @param p1 Second vertex position in world space
             * @param p2 Third vertex position in world space
             * @param planeIndex Index of the clip plane to check against (0-5)
             * @param bias Bias value to adjust the culling threshold
             * @return True if the triangle is completely below the specified clip plane
             */
            bool TriangleIsBelowClipPlane(float3 p0, float3 p1, float3 p2, int planeIndex, float bias){
                float4 plane = unity_CameraWorldClipPlanes[planeIndex];
                return dot(float4(p0, 1), plane) < 
                       bias && dot(float4(p1, 1), plane) < 
                       bias && dot(float4(p2, 1), plane) < 
                       bias;
            }

            /**
             * @brief Performs frustum culling for a triangle
             * @param p0 First vertex position in world space
             * @param p1 Second vertex position in world space
             * @param p2 Third vertex position in world space
             * @param bias Bias value to adjust the culling threshold
             * @return True if the triangle should be culled (outside frustum)
             */
            bool cullTriangle(float3 p0, float3 p1, float3 p2, float bias){
                return TriangleIsBelowClipPlane(p0, p1, p2, 0, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 1, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 2, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 3, bias);
            }

            half DotClamped(half3 a, half3 b){
                return saturate(dot(a, b));
            }

            /**
             * @brief Calculates tessellation factor based on edge length and view distance
             * @param cp0 First control point in world space
             * @param cp1 Second control point in world space
             * @return Tessellation factor for the edge between cp0 and cp1
             */
            float TessellationHeuristic(float3 cp0, float3 cp1){
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

                sampler2D _MetallicTex;
                sampler2D _NormalTex;
                sampler2D _AOTex;
                CBUFFER_START(UnityPerMaterial)
                    float4 _DisplacementTextures_ST;
                    float4 _SlopeTextures_ST;

                    float _MetallicStrength;
                    float _Smoothness;
                    float _NormalStrength;

                    float4 _BaseColor, _TipColor;

                    float _DisplacementDepthFalloff, _FoamDepthAttenuation;
                    
                    float _Tile0, _Tile1, _Tile2, _Tile3;
                    int _DebugTile0, _DebugTile1, _DebugTile2, _DebugTile3;
                    int _ContributeDisplacement0, _ContributeDisplacement1, _ContributeDisplacement2, _ContributeDisplacement3;
                    int _VisualizeLayer0, _VisualizeLayer1, _VisualizeLayer2, _VisualizeLayer3;
                    float _FoamSubtract0, _FoamSubtract1, _FoamSubtract2, _FoamSubtract3;
                CBUFFER_END

                struct VertexData{
                    float4 positionOS : POSITION;
                    float2 uv : TEXCOORD0;
                    float2 staticLightmapUV : TEXCOORD1;
                    float2 dynamicLightmapUV : TEXCOORD2;
                };

                struct v2f{
                    float4 positionCS : SV_POSITION;
                    float2 uv : TEXCOORD0;
                    float3 positionWS : TEXCOORD1;
                    float depth : TEXCOORD2;
                    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 3);
                    #ifdef DYNAMICLIGHTMAP_ON
                        float2 dynamicLightmapUV : TEXCOORD4;
                    #endif
                };

                struct TessellationControlPoint{
                    float4 positionOS : INTERNALTESSPOS;
                    float2 uv : TEXCOORD0;
                    float2 staticLightmapUV : TEXCOORD1;
                    float2 dynamicLightmapUV : TEXCOORD2;
                };

                struct TessellationFactors{
                    float edge[3] : SV_TESSFACTOR;
                    float inside : SV_INSIDETESSFACTOR;
                };

                SurfaceData createSurfaceData(v2f i){
                    SurfaceData surfaceData = (SurfaceData)0;
                    // Albedo output.
                    surfaceData.albedo = _BaseColor.rgb;
                    // Metallic output.
                    float4 metallicSample = tex2D(_MetallicTex, i.uv);
                    surfaceData.metallic = metallicSample * _MetallicStrength;
                    // Smoothness output.
                    surfaceData.smoothness = _Smoothness;
                    // Normal output.
                    float3 normalSample = UnpackNormal(tex2D(_NormalTex, i.uv));
                    normalSample.rg *= _NormalStrength;
                    surfaceData.normalTS = normalSample;
                    // Ambient Occlusion output.
                    float4 aoSample = tex2D(_AOTex, i.uv);
                    surfaceData.occlusion = aoSample.r;
                    // Alpha output.
                    surfaceData.alpha = _BaseColor.a;
                    return surfaceData;
                }

                InputData createInputData(v2f i, float3 normalTS, float4 tangentWS, float3 normalWS, float3 viewDir){
                    InputData inputData = (InputData)0;
                    // Position input.
                    inputData.positionWS = i.positionWS;
                    // Normal input.
                    float3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                    inputData.tangentToWorld = float3x3(tangentWS.xyz, bitangent, normalWS);
                    inputData.normalWS = TransformTangentToWorld(normalTS, inputData. tangentToWorld);
                    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
                    // View direction input.
                    inputData.viewDirectionWS = SafeNormalize(viewDir);
                    // Shadow coords.
                    inputData.shadowCoord = TransformWorldToShadowCoord(inputData .positionWS);
                    // Baked lightmaps.
                    #if defined(DYNAMICLIGHTMAP_ON)
                        inputData.bakedGI = SAMPLE_GI(i.staticLightmapUV, i.dynamicLightmapUV, i.vertexSH, inputData.normalWS);
                    #else
                        inputData.bakedGI = SAMPLE_GI(i.staticLightmapUV, i.vertexSH, inputData.normalWS);
                    #endif
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    inputData.shadowMask = SAMPLE_SHADOWMASK(i.staticLightmapUV);
                    return inputData;
                }

                /**
                * @brief Vertex shader function for tessellation
                * @param input Vertex input data
                * @return Tessellation control point
                */
                TessellationControlPoint vert(VertexData input){
                    TessellationControlPoint output;
                    output.positionOS = input.positionOS;
                    output.uv = input.uv;
                    output.staticLightmapUV = input.staticLightmapUV;
                    output.dynamicLightmapUV = input.dynamicLightmapUV;
                    return output;
                }

                /**
                * @brief Processes vertex data after tessellation
                * @param input Vertex input data
                * @return Processed vertex data with displacement applied
                */
                v2f tessVert(VertexData input){
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

                /**
                * @brief Calculates tessellation factors for a patch
                * @param patch Input patch of control points
                * @return Tessellation factors for the patch
                */
                TessellationFactors PatchFunction(InputPatch<TessellationControlPoint, 3> patch){
                    VertexPositionInputs p0_input = GetVertexPositionInputs(patch[0].positionOS);
                    VertexPositionInputs p1_input = GetVertexPositionInputs(patch[1].positionOS);
                    VertexPositionInputs p2_input = GetVertexPositionInputs(patch[2].positionOS);
                    float3 p0 = p0_input.positionWS;
                    float3 p1 = p1_input.positionWS;
                    float3 p2 = p2_input.positionWS;

                    TessellationFactors factors;
                    float bias = -0.5 * 100;
                    if (cullTriangle(p0, p1, p2, bias)){
                        factors.edge[0] = factors.edge[1] = factors.edge[2] = factors.inside = 0;
                    } else{
                        factors.edge[0] = TessellationHeuristic(p1, p2);
                        factors.edge[1] = TessellationHeuristic(p2, p0);
                        factors.edge[2] = TessellationHeuristic(p0, p1);
                        factors.inside = (TessellationHeuristic(p1, p2) +
                                    TessellationHeuristic(p2, p0) +
                                    TessellationHeuristic(p1, p2)) * (1 / 3.0);
                    }

                    return factors;
                }

                /**
                * @brief Hull shader for tessellation
                * @param patch Input patch of control points
                * @param id Control point ID
                * @return Control point for the specified ID
                */
                [domain("tri")]
                [outputcontrolpoints(3)]
                [outputtopology("triangle_cw")]
                [partitioning("integer")]
                [patchconstantfunc("PatchFunction")]
                TessellationControlPoint tessHull(InputPatch<TessellationControlPoint, 3> patch, uint id : SV_OutputControlPointID){
                    return patch[id];
                }

                /**
                * @brief Domain shader for tessellation
                * @param factors Tessellation factors
                * @param patch Output patch of control points
                * @param bcCoords Barycentric coordinates
                * @return Processed vertex data for the tessellated point
                */
                [domain("tri")]
                v2f tessDomain(TessellationFactors factors, OutputPatch<TessellationControlPoint, 3> patch, float3 bcCoords : SV_DOMAINLOCATION){
                    VertexData data;
                    data.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
                    data.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
                    data.dynamicLightmapUV = patch[0].dynamicLightmapUV * bcCoords.x + patch[1].dynamicLightmapUV * bcCoords.y + patch[2].dynamicLightmapUV * bcCoords.z;
                    data.staticLightmapUV = patch[0].staticLightmapUV * bcCoords.x + patch[1].staticLightmapUV * bcCoords.y + patch[2].staticLightmapUV * bcCoords.z;
                    return tessVert(data);
                }

                /**
                * @brief Fragment shader function
                * @param input Fragment input data
                * @return Final color for the fragment
                */
                float4 frag(v2f input) : SV_TARGET{

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
                    
                    // PB shading
                    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                    Light light = GetMainLight(shadowCoord);
                    float3 lightDir = light.direction;
                    float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
                    float3 halfwayDir = normalize(lightDir + viewDir);
                    float4 tangent = float4(normalize(cross(viewDir, normal)), 0.0);
                    float3 bitangent = cross(normal, tangent);
                    tangent.w = sign(dot(bitangent, cross(normal, tangent)));

                    SurfaceData surfaceData = createSurfaceData(input);
                    InputData inputData = createInputData(input, surfaceData.normalTS, tangent, normal, viewDir);
                    float4 outputColor = UniversalFragmentPBR(inputData, surfaceData);

                    outputColor = lerp(outputColor, _TipColor, saturate(foam));
 
                    if (_DebugTile0){
                        outputColor = cos(input.uv.x * _Tile0 * PI) * cos(input.uv.y * _Tile0 * PI);
                    }

                    if (_DebugTile1){
                        outputColor = cos(input.uv.x * _Tile1) * 1024 * cos(input.uv.y * _Tile1) * 1024;
                    }

                    if (_DebugTile2){
                        outputColor = cos(input.uv.x * _Tile2) * 1024 * cos(input.uv.y * _Tile2) * 1024;
                    }

                    if (_DebugTile3){
                        outputColor = cos(input.uv.x * _Tile3) * 1024 * cos(input.uv.y * _Tile3) * 1024;
                    }
                    return outputColor;
                }
            ENDHLSL
        }
    }
        Fallback Off
}