//Created by Paro.
Shader "Hidden/CloudShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags{
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct VertexData{
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f{
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD2;
                float3 viewDir : TEXCOORD3;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_ShapeNoise);
            SAMPLER(sampler_ShapeNoise);
            TEXTURE2D(_BlueNoise);
            SAMPLER(sampler_BlueNoise);
            TEXTURE3D(_DetailNoise);
            SAMPLER(sampler_DetailNoise);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST, _ShapeNoise_ST, _DetailNoise_ST, _BlueNoise_ST;
                float4 _color;
                float _alpha, _RenderDistance;
                float3 _BoundsMin, _BoundsMax;
                int _NumSteps, _numStepsLight;
                float _CloudScale, _cloudSmooth, _detailNoiseWeight, _detailNoiseScale;
                float3 _Wind, _detailNoiseWind;
                float4 _phaseParams;
                float _containerEdgeFadeDst, _DensityThreshold, _DensityMultiplier, _lightAbsorptionThroughCloud, _lightAbsorptionTowardSun, _darknessThreshold;
                float _rayOffsetStrength;
            CBUFFER_END

            v2f vert (VertexData input)
            {
                v2f output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = mul(UNITY_MATRIX_VP, float4(vertexInput.positionWS, 1.0));
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                output.positionWS = vertexInput.positionWS;
                float3 viewVector = mul(unity_CameraInvProjection, float4(input.uv * 2 - 1, 0, -1));
                output.viewDir = mul(unity_CameraToWorld, float4(viewVector,0));
                return output;
            }

            float remap(float v, float minOld, float maxOld, float minNew, float maxNew) {
                return minNew + (v-minOld) * (maxNew - minNew) / (maxOld-minOld);
            }

            float2 squareUV(float2 uv) {
                float width = _ScaledScreenParams.x;
                float height =_ScaledScreenParams.y;
                //float minDim = min(width, height);
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
            }

            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/
                float3 t0 = (boundsMin - rayOrigin) * invRaydir;
                float3 t1 = (boundsMax - rayOrigin) * invRaydir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection

                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection

                // CASE 3: ray misses box (dstA > dstB)

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            float sampleDensity(float3 pos)
            {
                float3 uvw = pos * _CloudScale * 0.001 + _Wind.xyz * 0.1 * _Time.y * _CloudScale;
                float3 size = _BoundsMax - _BoundsMin;
                float3 boundsCentre = (_BoundsMin+_BoundsMax) * 0.5f;

                float3 duvw = pos * _detailNoiseScale * 0.001 + _detailNoiseWind.xyz * 0.1 * _Time.y * _detailNoiseScale;

                float dstFromEdgeX = min(_containerEdgeFadeDst, min(pos.x - _BoundsMin.x, _BoundsMax.x - pos.x));
                float dstFromEdgeY = min(_cloudSmooth, min(pos.y - _BoundsMin.y, _BoundsMax.y - pos.y));
                float dstFromEdgeZ = min(_containerEdgeFadeDst, min(pos.z - _BoundsMin.z, _BoundsMax.z - pos.z));
                float edgeWeight = min(dstFromEdgeZ,dstFromEdgeX)/_containerEdgeFadeDst;

                float4 shape = SAMPLE_TEXTURE2D_LOD(_ShapeNoise, sampler_ShapeNoise, uvw.xz, 0);
                float4 detail = SAMPLE_TEXTURE3D_LOD(_DetailNoise, sampler_DetailNoise, duvw, 0);
                float density = max(0, lerp(shape.x, detail.x, _detailNoiseWeight) - _DensityThreshold) * _DensityMultiplier;
                return density * edgeWeight * (dstFromEdgeY/_cloudSmooth);
            }

            // Henyey-Greenstein
            float hg(float a, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(abs(1+g2-2*g*(a)), 1.5));
            }

            float phase(float a) {
                float blend = .5;
                float hgBlend = hg(a,_phaseParams.x) * (1-blend) + hg(a,-_phaseParams.y) * blend;
                return _phaseParams.z + hgBlend*_phaseParams.w;
            }

            // Calculate proportion of light that reaches the given point from the lightsource
            float lightmarch(float3 position) {
                float4 shadowCoord = TransformWorldToShadowCoord(position);
                Light light = GetMainLight(shadowCoord);
                float3 dirToLight = light.direction;
                float dstInsideBox = rayBoxDst(_BoundsMin, _BoundsMax, position, 1/dirToLight).y;
                
                float stepSize = dstInsideBox/_numStepsLight;
                float totalDensity = 0;

                for (int step = 0; step < _numStepsLight; step ++) {
                    position += dirToLight * stepSize;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }

                float transmittance = exp(-totalDensity * _lightAbsorptionTowardSun);
                return _darknessThreshold + transmittance * (1-_darknessThreshold);
            }

            float4 frag (v2f input) : SV_Target
            {
                // sample the texture
                float4 col = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, input.uv, 0);

                float viewLength = length(input.viewDir); 
                float3 rayOrigin = input.positionWS;
                float3 rayDir = input.viewDir / viewLength;

                //Depth
				float2 screenUVs = GetNormalizedScreenSpaceUV(input.positionCS);
				float rawDepth = SampleSceneDepth(screenUVs);
				float depth = LinearEyeDepth(rawDepth, _ZBufferParams);



                float2 rayToContainerInfo = rayBoxDst(_BoundsMin, _BoundsMax, rayOrigin, 1/rayDir);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;
                if(dstToBox + dstInsideBox > _RenderDistance) return col;

                // random starting offset (makes low-res results noisy rather than jagged/glitchy, which is nicer)
                float randomOffset = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_BlueNoise, squareUV(input.uv *3), 0);
                
                randomOffset *= _rayOffsetStrength;

                float dstTravelled = randomOffset;
                float stepSize = dstInsideBox / _NumSteps;
                float dstLimit = min(depth - dstToBox, dstInsideBox);

                float3 entryPoint = rayOrigin + rayDir * dstToBox;
                float transmittance = 1;
                float3 lightEnergy = 0;

                // Phase function makes clouds brighter around sun
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light light = GetMainLight(shadowCoord);
                float3 dirToLight = light.direction;
                float cosAngle = dot(rayDir, dirToLight); 
                float phaseVal = phase(cosAngle);

                while (dstTravelled < dstLimit) {
                    rayOrigin = entryPoint + rayDir * dstTravelled;
                    float density = sampleDensity(rayOrigin);
                    
                    if (density > 0) {
                        float lightTransmittance = lightmarch(rayOrigin);
                        lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                        transmittance *= exp(-density * stepSize * _lightAbsorptionThroughCloud);
                    
                        // Exit early if T is close to zero as further samples won't affect the result much
                        if (transmittance < 0.1) {
                            break;
                        }
                    }
                    dstTravelled += stepSize;
                }
                float3 cloudCol = lightEnergy * _color;
                float3 col0 = col * transmittance + cloudCol;
                return float4(lerp(col, col0, smoothstep(_RenderDistance, _RenderDistance * 0.25f, dstToBox + dstInsideBox) * _alpha), 0);
            }
            ENDHLSL
        }
    }
}
