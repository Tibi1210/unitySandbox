Shader "_Tibi/Terrain_LOD"{
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

            #pragma target 5.0
            #pragma vertex vert
            #pragma hull tessHull
            #pragma domain tessDomain
            #pragma fragment frag

            #define EDGE_LEN 8
            #define PI 3.14159265358979323846

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

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

            struct VertexData{
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f{
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float3 normal: TEXCOORD2;
                float3 tangent: TEXCOORD3;
            };

            struct TessellationControlPoint{
                float4 positionOS : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
            };

            struct TessellationFactors{
                float edge[3] : SV_TESSFACTOR;
                float inside : SV_INSIDETESSFACTOR;
            };

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

                return edgeLength * _ScreenParams.y / (EDGE_LEN * (pow(viewDistance * 0.5, 1.2)));
            }

            TEXTURE2D_ARRAY(_BaseTex);
            SAMPLER(sampler_BaseTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseTex_ST;
                float4 _TopColor, _BotColor;
                float _Roughness, _Metallic, _Subsurface, _Specular, _SpecularTint, _Anisotropic, _Sheen, _SheenTint, _ClearCoat, _ClearCoatGloss;
                int _isNormal;
            CBUFFER_END

            /**
             * @brief Vertex shader function for tessellation
             * @param input Vertex input data
             * @return Tessellation control point
             */
            TessellationControlPoint vert(VertexData input){
                TessellationControlPoint output;
                output.positionOS = input.positionOS;
                output.uv = input.uv;
                return output;
            }

            /**
             * @brief Processes vertex data after tessellation
             * @param input Vertex input data
             * @return Processed vertex data with displacement applied
             */
            v2f tessVert(VertexData input){
                v2f output;
                
                float2 uv = input.uv * 5.0;
                output.uv = TRANSFORM_TEX(uv, _BaseTex);

                //float4 displacement = noised(float3(uv, 1.0));
                float4 displacement = SAMPLE_TEXTURE2D_ARRAY_LOD(_BaseTex, sampler_BaseTex, input.uv, 0, 0);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
                //float4 positionWS = mul(unity_ObjectToWorld, input.positionOS);
                float4 positionWS = float4(vertexInput.positionWS,1);
                positionWS.y = displacement.x * 100; 

                // Calculate normal from derivatives
                float3 normal = float3(-displacement.y, 1.0, -displacement.w);
                normal = normalize(normal);

                output.positionWS = positionWS;
                output.positionCS = mul(UNITY_MATRIX_VP, positionWS);

                VertexNormalInputs normalInput = GetVertexNormalInputs(normal);
                output.normal = normalInput.normalWS;
                output.tangent = normalInput.tangentWS;

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
                //if (cullTriangle(p0, p1, p2, bias)){
                //    factors.edge[0] = factors.edge[1] = factors.edge[2] = factors.inside = 0;
                //} else{
                    factors.edge[0] = TessellationHeuristic(p1, p2);
                    factors.edge[1] = TessellationHeuristic(p2, p0);
                    factors.edge[2] = TessellationHeuristic(p0, p1);
                    factors.inside = (TessellationHeuristic(p1, p2) +
                                TessellationHeuristic(p2, p0) +
                                TessellationHeuristic(p1, p2)) * (1 / 3.0);
                //}
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
                return tessVert(data);
            }

            half DotClamped(half3 a, half3 b){
                return saturate(dot(a, b));
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
    
                float3 surfaceColor = baseColor * baseColor;
    
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
            

            /**
             * @brief Fragment shader function
             * @param input Fragment input data
             * @return Final color for the fragment
             */
            float4 frag(v2f input) : SV_TARGET{

                float _MinY = 0; 
                float _MaxY = 50;

                // shading modell
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light light = GetMainLight(shadowCoord);
                float3 lightDir = light.direction;
                float3 viewDir = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 halfwayDir = normalize(lightDir + viewDir);

                float4 tangent = float4(input.tangent, 1.0);
                float3 bitangent = cross(input.normal, tangent);
                tangent.w = sign(dot(bitangent, cross(input.normal, tangent)));
                float3 Y = normalize(cross(input.normal, tangent) * tangent.w);

                BRDFResults reflection = DisneyBRDF(_TopColor, lightDir, viewDir, input.normal, tangent, Y);
                float3 topColor = light.color.rgb * (reflection.diffuse + reflection.specular + reflection.clearcoat);
                
                reflection = DisneyBRDF(_BotColor, lightDir, viewDir, input.normal, tangent, Y);
                float3 botColor = light.color.rgb * (reflection.diffuse + reflection.specular + reflection.clearcoat);

                float normalizedY = saturate((input.positionWS.y - _MinY) / (_MaxY - _MinY));


                if(_isNormal){ 
                    return float4(input.normal,1.0);
                }
                return float4(lerp(botColor, topColor, normalizedY),1.0);
  
            }

            ENDHLSL
        }
    }

        Fallback Off
}