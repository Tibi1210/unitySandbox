Shader "_Tibi/Lighting/DisneyBRDF"{
    
    Properties{
        _AlbedoTex ("Albedo", 2D) = "" {}
        _NormalTex ("Normal", 2D) = "" {}
        _TangentTex ("Tangent", 2D) = "" {}
        _NormalStrength ("Normal Strength", Range(0.0, 3.0)) = 1.0
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _Metallic ("Metallic", Range(0.0, 1.0)) = 0
        _Subsurface ("Subsurface", Range(0.0, 1.0)) = 0
        _Specular ("Specular", Range(0.0, 2.0)) = 0.5
        _Roughness ("Roughness", Range(0.0, 1.0)) = 0.5
        _SpecularTint ("Specular Tint", Range(0.0, 1.0)) = 0.0
        _Anisotropic ("Anisotropic", Range(0.0, 1.0)) = 0.0
        _Sheen ("Sheen", Range(0.0, 1.0)) = 0.0
        _SheenTint ("Sheen Tint", Range(0.0, 1.0)) = 0.5
        _ClearCoat ("Clear Coat", Range(0.0, 1.0)) = 0.0
        _ClearCoatGloss ("Clear Coat Gloss", Range(0.0, 1.0)) = 1.0
    }

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

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			#define PI 3.14159265358979323846

			struct VertexData{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			};
			struct v2f{
				float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float3 normal: TEXCOORD2;
                float4 tangent: TEXCOORD3;
			};

			 
			TEXTURE2D(_AlbedoTex);
            SAMPLER(sampler_AlbedoTex);
			TEXTURE2D(_NormalTex);
            SAMPLER(sampler_NormalTex);
			TEXTURE2D(_TangentTex);
            SAMPLER(sampler_TangentTex);

			CBUFFER_START(UnityPerMaterial)
				float4 _AlbedoTex_ST, _NormalTex_ST, _TangentTex_ST;
				float3 _BaseColor;
				float _NormalStrength, _Roughness, _Metallic, _Subsurface, _Specular, _SpecularTint, _Anisotropic, _Sheen, _SheenTint, _ClearCoat, _ClearCoatGloss;
			CBUFFER_END

			v2f vert (VertexData input){
				v2f output;
				output.uv = input.uv;
				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
				output.positionWS = vertexInput.positionWS;
				output.positionCS = mul(UNITY_MATRIX_VP, float4(vertexInput.positionWS, 1.0));
				VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
				output.normal = normalInput.normalWS;
				output.tangent = float4(normalInput.tangentWS, 1.0);
				return output;
			}

			half DotClamped(half3 a, half3 b){
                return saturate(dot(a, b));
            }

			float sqr(float x) { 
				return x * x; 
			}
	
			float luminance(float3 color) {
				return dot(color, float3(0.299f, 0.587f, 0.114f));
			}
	
			float SchlickFresnel(float x) {
				x = saturate(1.0f - x);
				float x2 = x * x;
	
				return x2 * x2 * x; // While this is equivalent to pow(1 - x, 5) it is two less mult instructions
			}
	
			// Isotropic Generalized Trowbridge Reitz with gamma == 1
			float GTR1(float ndoth, float a) {
				float a2 = a * a;
				float t = 1.0f + (a2 - 1.0f) * ndoth * ndoth;
				return (a2 - 1.0f) / (PI * log(a2) * t);
			}
	
			// Anisotropic Generalized Trowbridge Reitz with gamma == 2. This is equal to the popular GGX distribution.
			float AnisotropicGTR2(float ndoth, float hdotx, float hdoty, float ax, float ay) {
				return rcp(PI * ax * ay * sqr(sqr(hdotx / ax) + sqr(hdoty / ay) + sqr(ndoth)));
			}
	
			// Isotropic Geometric Attenuation Function for GGX. This is technically different from what Disney uses, but it's basically the same.
			float SmithGGX(float alphaSquared, float ndotl, float ndotv) {
				float a = ndotv * sqrt(alphaSquared + ndotl * (ndotl - alphaSquared * ndotl));
				float b = ndotl * sqrt(alphaSquared + ndotv * (ndotv - alphaSquared * ndotv));
	
				return 0.5f / (a + b);
			}
	
			// Anisotropic Geometric Attenuation Function for GGX.
			float AnisotropicSmithGGX(float ndots, float sdotx, float sdoty, float ax, float ay) {
				return rcp(ndots + sqrt(sqr(sdotx * ax) + sqr(sdoty * ay) + sqr(ndots)));
			}
	
			struct BRDFResults {
				float3 diffuse;
				float3 specular;
				float3 clearcoat;
			};
	
			BRDFResults DisneyBRDF(float3 baseColor, float3 L, float3 V, float3 N, float3 X, float3 Y) {
				BRDFResults output;
				output.diffuse = 0.0f;
				output.specular = 0.0f;
				output.clearcoat = 0.0f;
	
				float3 H = normalize(L + V); // Microfacet normal of perfect reflection
	
				float ndotl = DotClamped(N, L);
				float ndotv = DotClamped(N, V);
				float ndoth = DotClamped(N, H);
				float ldoth = DotClamped(L, H);
	
				float3 surfaceColor = baseColor * _BaseColor;
	
				float Cdlum = luminance(surfaceColor);
	
				float3 Ctint = Cdlum > 0.0f ? surfaceColor / Cdlum : 1.0f;
				float3 Cspec0 = lerp(_Specular * 0.08f * lerp(1.0f, Ctint, _SpecularTint), surfaceColor, _Metallic);
				float3 Csheen = lerp(1.0f, Ctint, _SheenTint);
	
	
				// Disney Diffuse
				float FL = SchlickFresnel(ndotl);
				float FV = SchlickFresnel(ndotv);
	
				float Fss90 = ldoth * ldoth * _Roughness;
				float Fd90 = 0.5f + 2.0f * Fss90;
	
				float Fd = lerp(1.0f, Fd90, FL) * lerp(1.0f, Fd90, FV);
	
				// Subsurface Diffuse (Hanrahan-Krueger brdf approximation)
	
				float Fss = lerp(1.0f, Fss90, FL) * lerp(1.0f, Fss90, FV);
				float ss = 1.25f * (Fss * (rcp(ndotl + ndotv) - 0.5f) + 0.5f);
	
				// Specular
				float alpha = _Roughness;
				float alphaSquared = alpha * alpha;
	
				// Anisotropic Microfacet Normal Distribution (Normalized Anisotropic GTR gamma == 2)
				float aspectRatio = sqrt(1.0f - _Anisotropic * 0.9f);
				float alphaX = max(0.001f, alphaSquared / aspectRatio);
				float alphaY = max(0.001f, alphaSquared * aspectRatio);
				float Ds = AnisotropicGTR2(ndoth, dot(H, X), dot(H, Y), alphaX, alphaY);
	
				// Geometric Attenuation
				float GalphaSquared = sqr(0.5f + _Roughness * 0.5f);
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
	
				
				output.diffuse = (1.0f / PI) * (lerp(Fd, ss, _Subsurface) * surfaceColor + Fsheen) * (1 - _Metallic);
				output.specular = Ds * F * G;
				output.clearcoat = 0.25f * _ClearCoat * Gr * Fr * Dr;
	
				return output;
			}
            

			float4 frag (v2f i) : SV_TARGET{


				float2 uv = i.uv;
                
                float3 unnormalizedNormalWS = i.normal;
                float renormFactor = 1.0f / length(unnormalizedNormalWS);

                float3x3 worldToTangent;
                float3 bitangent = cross(unnormalizedNormalWS, i.tangent.xyz) * i.tangent.w;
                worldToTangent[0] = i.tangent.xyz * renormFactor;
                worldToTangent[1] = bitangent * renormFactor;
                worldToTangent[2] = unnormalizedNormalWS * renormFactor;

                // Unpack DXT5nm tangent space normal
				float4 packedNormal = SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, uv);
                packedNormal.w *= packedNormal.x;

                float3 N;
                N.xy = packedNormal.wy * 2.0f - 1.0f;
                N.xy *= _NormalStrength;
                N.z = sqrt(1.0f - saturate(dot(N.xy, N.xy)));
                N = mul(N, worldToTangent);

                // Unpack DXT5nm tangent space tangent
                float3 T;
				
                T.xy = SAMPLE_TEXTURE2D(_TangentTex, sampler_TangentTex, uv).wy * 2 - 1;
                T.z = sqrt(1 - saturate(dot(T.xy, T.xy)));

                T = mul(lerp(float3(1.0f, 0.0f, 0.0f), T, saturate(_NormalStrength)), worldToTangent);
                
                float3 albedo = SAMPLE_TEXTURE2D(_AlbedoTex, sampler_AlbedoTex, uv).rgb;
				
				float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light light = GetMainLight(shadowCoord);
                float3 lightDir = light.direction;
                float3 viewDir = GetWorldSpaceNormalizeViewDir(i.positionWS);

                float3 L = normalize(light.direction); // Direction *towards* light source
                float3 V = normalize(viewDir); // Direction *towards* camera
                float3 X = normalize(T);
                float3 Y = normalize(cross(N, T) * i.tangent.w);

                BRDFResults reflection = DisneyBRDF(albedo, L, V, N, X, Y);

                float3 output = light.color * (reflection.diffuse + reflection.specular + reflection.clearcoat);
                output *= DotClamped(N, L);

                return float4(max(0.0f, output), 1.0f);

			}

			ENDHLSL
        }


    }
}
