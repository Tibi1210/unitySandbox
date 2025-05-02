Shader "_Tibi/DynamicLOD"{
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

            #define _TessellationEdgeLength 10
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
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
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

                return edgeLength * _ScreenParams.y / (_TessellationEdgeLength * (pow(viewDistance * 0.5, 1.2)));
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
                return output;
            }

            /**
             * @brief Processes vertex data after tessellation
             * @param input Vertex input data
             * @return Processed vertex data
             */
            v2f tessVert(VertexData input){
                v2f output;
                input.uv = 0;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                output.uv = input.uv;
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
                return tessVert(data);
            }
            
            /**
            * @brief Fragment shader function
            * @param input Fragment input data
            * @return Final color for the fragment
            */
            float4 frag(v2f input) : SV_TARGET{
                return float4(0.5, 0.5, 0.5, 1.0);
            }

            ENDHLSL
        }


        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
        Fallback Off
}