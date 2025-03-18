Shader "Custom/FFTWater_BRDF"{
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

                CBUFFER_START(UnityPerMaterial)
                    float4 _DisplacementTextures_ST;
                    float4 _SlopeTextures_ST;

                    float _NormalStrength, _FresnelNormalStrength, _SpecularNormalStrength;

                    float _Roughness, _Metallic, _Subsurface, _Specular, _SpecularTint, _Anisotropic, _Sheen, _SheenTint, _ClearCoat, _ClearCoatGloss;

                    float3 _Ambient, _DiffuseReflectance, _SpecularReflectance, _FresnelColor, _TipColor;
                    float _Shininess, _FresnelBias, _FresnelStrength, _FresnelShininess;
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
                };

                struct v2f{
                    float4 positionCS : SV_POSITION;
                    float2 uv : TEXCOORD0;
                    float3 positionWS : TEXCOORD1;
                    float depth : TEXCOORD2;
                };

                struct TessellationControlPoint{
                    float4 positionOS : INTERNALTESSPOS;
                    float2 uv : TEXCOORD0;
                };

                struct TessellationFactors{
                    float edge[3] : SV_TESSFACTOR;
                    float inside : SV_INSIDETESSFACTOR;
                };

                TessellationControlPoint vert(VertexData input){
                    TessellationControlPoint output;
                    output.positionOS = input.positionOS;
                    output.uv = input.uv;
                    return output;
                }

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

                [domain("tri")]
                [outputcontrolpoints(3)]
                [outputtopology("triangle_cw")]
                [partitioning("integer")]
                [patchconstantfunc("PatchFunction")]
                TessellationControlPoint tessHull(InputPatch<TessellationControlPoint, 3> patch, uint id : SV_OutputControlPointID){
                    return patch[id];
                }

                [domain("tri")]
                v2f tessDomain(TessellationFactors factors, OutputPatch<TessellationControlPoint, 3> patch, float3 bcCoords : SV_DOMAINLOCATION){
                    VertexData data;
                    data.positionOS = patch[0].positionOS * bcCoords.x + patch[1].positionOS * bcCoords.y + patch[2].positionOS * bcCoords.z;
                    data.uv = patch[0].uv * bcCoords.x + patch[1].uv * bcCoords.y + patch[2].uv * bcCoords.z;
                    return tessVert(data);
                }

                ///////////////////////////////////////////DisneyBRDF///////////////////////////////////////////
                float luminance(float3 color){
                    return dot(color, float3(0.299f, 0.587f, 0.114f));
                }

                float sqr(float x){ 
                    return x * x; 
                }

                float SchlickFresnel(float x){
                    x = saturate(1.0 - x);
                    float x2 = x * x;
        
                    return x2 * x2 * x; // equivalent to pow(1 - x, 5) it is two less mult instructions
                }

                 // Anisotropic Generalized Trowbridge Reitz with gamma == 2. This is equal to the popular GGX distribution.
                 float AnisotropicGTR2(float ndoth, float hdotx, float hdoty, float ax, float ay){
                    return rcp(PI * ax * ay * sqr(sqr(hdotx / ax) + sqr(hdoty / ay) + sqr(ndoth)));
                }

                // Anisotropic Geometric Attenuation Function for GGX.
                float AnisotropicSmithGGX(float ndots, float sdotx, float sdoty, float ax, float ay){
                    return rcp(ndots + sqrt(sqr(sdotx * ax) + sqr(sdoty * ay) + sqr(ndots)));
                }

                // Isotropic Generalized Trowbridge Reitz with gamma == 1
                float GTR1(float ndoth, float a){
                    float a2 = a * a;
                    float t = 1.0f + (a2 - 1.0f) * ndoth * ndoth;
                    return (a2 - 1.0f) / (PI * log(a2) * t);
                }

                // Isotropic Geometric Attenuation Function for GGX. This is technically different from what Disney uses, but it's basically the same.
                float SmithGGX(float alphaSquared, float ndotl, float ndotv){
                    float a = ndotv * sqrt(alphaSquared + ndotl * (ndotl - alphaSquared * ndotl));
                    float b = ndotl * sqrt(alphaSquared + ndotv * (ndotv - alphaSquared * ndotv));
        
                    return 0.5f / (a + b);
                }

                struct BRDFResults{
                    float3 diffuse;
                    float3 specular;
                    float3 clearcoat;
                };
        
                BRDFResults DisneyBRDF(float3 baseColor, float3 L, float3 V, float3 N, float3 X, float3 Y){
                    BRDFResults output;
                    output.diffuse = 0.0;
                    output.specular = 0.0;
                    output.clearcoat = 0.0;
        
                    float3 H = normalize(L + V); // Microfacet normal of perfect reflection
                    float ndotl = DotClamped(N, L);
                    float ndotv = DotClamped(N, V);
                    float ndoth = DotClamped(N, H);
                    float ldoth = DotClamped(L, H);
        
                    float3 surfaceColor = baseColor * _Ambient;
        
                    float Cdlum = luminance(surfaceColor);
        
                    float3 Ctint = Cdlum > 0.0 ? surfaceColor / Cdlum : 1.0;
                    float3 Cspec0 = lerp(_Specular * 0.08 * lerp(1.0, Ctint, _SpecularTint), surfaceColor, _Metallic);
                    float3 Csheen = lerp(1.0, Ctint, _SheenTint);
        
        
                    // Disney Diffuse
                    float FL = SchlickFresnel(ndotl);
                    float FV = SchlickFresnel(ndotv);
        
                    float Fss90 = ldoth * ldoth * _Roughness;
                    float Fd90 = 0.5 + 2.0 * Fss90;
        
                    float Fd = lerp(1.0f, Fd90, FL) * lerp(1.0f, Fd90, FV);
        
                    // Subsurface Diffuse (Hanrahan-Krueger brdf approximation)
        
                    float Fss = lerp(1.0f, Fss90, FL) * lerp(1.0f, Fss90, FV);
                    float ss = 1.25 * (Fss * (rcp(ndotl + ndotv) - 0.5f) + 0.5f);
        
                    // Specular
                    float alpha = _Roughness;
                    float alphaSquared = alpha * alpha;
        
                    // Anisotropic Microfacet Normal Distribution (Normalized Anisotropic GTR gamma == 2)
                    float aspectRatio = sqrt(1.0 - _Anisotropic * 0.9f);
                    float alphaX = max(0.001f, alphaSquared / aspectRatio);
                    float alphaY = max(0.001f, alphaSquared * aspectRatio);
                    float Ds = AnisotropicGTR2(ndoth, dot(H, X), dot(H, Y), alphaX, alphaY);
        
                    // Geometric Attenuation
                    float GalphaSquared = sqr(0.5 + _Roughness * 0.5f);
                    float GalphaX = max(0.001f, GalphaSquared / aspectRatio);
                    float GalphaY = max(0.001f, GalphaSquared * aspectRatio);
                    float G = AnisotropicSmithGGX(ndotl, dot(L, X), dot(L, Y), GalphaX, GalphaY);
                    G *= AnisotropicSmithGGX(ndotv, dot(V, X), dot (V, Y), GalphaX, GalphaY); // specular brdf denominator (4 * ndotl * ndotv) is baked into output here (I assume at least)  
        
                    // Fresnel Reflectance
                    float FH = SchlickFresnel(ldoth);
                    float3 F = lerp(Cspec0, 1.0f, FH);
        
                    // Sheen
                    float3 Fsheen = FH * _Sheen * Csheen;
        
                    // Clearcoat (Hard Coded Index Of Refraction -> 1.5f -> F0 -> 0.04)
                    float Dr = GTR1(ndoth, lerp(0.1f, 0.001f, _ClearCoatGloss)); // Normalized Isotropic GTR Gamma == 1
                    float Fr = lerp(0.04, 1.0f, FH);
                    float Gr = SmithGGX(ndotl, ndotv, 0.25f);
        
                    
                    output.diffuse = (1.0 / PI) * (lerp(Fd, ss, _Subsurface) * surfaceColor + Fsheen) * (1 - _Metallic);
                    output.specular = Ds * F * G;
                    output.clearcoat = 0.25 * _ClearCoat * Gr * Fr * Dr;
        
                    return output;
                }

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
                    
                    // shading modell
                    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                    Light light = GetMainLight(shadowCoord);
                    float3 lightDir = light.direction;
                    float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
                    float3 halfwayDir = normalize(lightDir + viewDir);
                    float4 tangent = float4(normalize(cross(viewDir, normal)), 0.0);
                    float3 bitangent = cross(normal, tangent);
                    tangent.w = sign(dot(bitangent, cross(normal, tangent)));
                    float3 Y = normalize(cross(normal, tangent) * tangent.w);

                    //float3 outputColor = customShading(normal, lightDir, viewDir, halfwayDir, light.color.rgb);
                    BRDFResults reflection = DisneyBRDF(_Ambient, lightDir, viewDir, normal, tangent, Y);

                    float3 outputColor = light.color.rgb * (reflection.diffuse + reflection.specular + reflection.clearcoat);
                    outputColor *= DotClamped(normal, lightDir);
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
                    return float4(outputColor, 1.0);
                }
            ENDHLSL
        }
    }
        Fallback Off
}