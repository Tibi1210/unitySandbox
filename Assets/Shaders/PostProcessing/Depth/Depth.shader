// CHANGE
Shader "_Tibi/PostProcess/Depth"{
	
	Properties{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader{

		Tags{
			"RenderType"="Opaque"
			"RenderPipeline"="UniversalPipeline"
		}

		Pass {
			HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
           
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
           
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;

            };

            struct v2f
            {
                float4 positionCS : SV_Position;
				float4 positionSS : TEXCOORD0;
                float2 uv : TEXCOORD1;
            };
           
			sampler2D _MainTex;
			CBUFFER_START(UnityPerMaterial)
					float4 _NearColour;
					float4 _FarColour;
                    float _FocusPoint;
			CBUFFER_END

            v2f vert(appdata i)
            {
                v2f o;

				VertexPositionInputs vertexInput = GetVertexPositionInputs(i.positionOS.xyz);
				o.positionCS = vertexInput.positionCS;
				o.positionSS = ComputeScreenPos(o.positionCS);
                o.uv = i.uv;
				return o;
            }
           
            float4 frag(v2f i) : SV_Target
            {
                float2 screenspaceUVs = i.positionSS.xy / i.positionSS.w;

                float rawDepth = SampleSceneDepth(screenspaceUVs);
				float scene01Depth = Linear01Depth(rawDepth, _ZBufferParams); // (0-1)
                float sceneEyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams)*10;

                float4 outColor = float4(0,0,0,1);

                if(sceneEyeDepth<_FocusPoint){
                    // near plane
				    outColor = lerp(_NearColour, float4(0,0,0,1), sceneEyeDepth/_FocusPoint);
				    //outColor = tex2D(_MainTex, i.uv);
                }else{
                    // far plane
				    outColor = lerp(_FarColour, float4(0,0,0,1), _FocusPoint/sceneEyeDepth);
                }

                return outColor;

            }
            ENDHLSL
		}

	}
}

// ADD TO URP RENDER FEATURE TO PROFILE
