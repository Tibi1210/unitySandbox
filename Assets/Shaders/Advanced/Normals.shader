Shader "_Tibi/Geometry/Normals"{
	Properties{
		_BaseColor("Base Color", Color) = (1,1,1,1)
		_WireThickness("Wire Thickness", Range(0, 0.1)) = 0.01
		_WireLength("Wire Length", Range(0, 1)) = 0.2
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

			Cull Off

			HLSLPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma geometry geom
			#pragma target 5.0

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			struct appdata{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float4 tangentOS : TANGENT;
			};
			struct v2g{
				float4 positionWS : SV_POSITION;
				float3 normalWS : NORMAL;
				float4 tangentWS : TANGENT;
			};
			struct g2f {
					float4 positionCS : SV_POSITION;
			};


			CBUFFER_START(UnityPerMaterial)
				float4 _BaseColor;
				float _WireThickness;
				float _WireLength;
			CBUFFER_END

			v2g vert (appdata v){
				v2g o;
				o.positionWS = mul(unity_ObjectToWorld, v.positionOS);
				o.normalWS = TransformObjectToWorldNormal(v.normalOS);
				o.tangentWS = mul(unity_ObjectToWorld, v.tangentOS);
				return o;
			}

			g2f geomToClip(float3 positionOS, float3 offsetOS)
			{
				g2f o;
				o.positionCS = TransformWorldToHClip(positionOS+offsetOS);
				return o;
			}

			[maxvertexcount(8)]
			void geom(point v2g i[1], inout TriangleStream<g2f> triStream) {
				float3 normal = normalize(i[0].normalWS);
				float4 tangent = normalize(i[0].tangentWS);
				float3 bitangent = normalize(cross(normal, tangent.xyz) * tangent.w);
				float3 xOffset = tangent * _WireThickness * 0.5f;
				float3 yOffset = normal * _WireLength;
				float3 zOffset = bitangent * _WireThickness * 0.5f;
				float3 offsets[8] =
									{
									-xOffset,
									xOffset,
									-xOffset + yOffset,
									xOffset + yOffset,
									-zOffset,
									zOffset,
									-zOffset + yOffset,
									zOffset + yOffset
									};

				float4 pos = i[0].positionWS;

				triStream.Append(geomToClip(pos, offsets[0]));
				triStream.Append(geomToClip(pos, offsets[1]));
				triStream.Append(geomToClip(pos, offsets[2]));
				triStream.Append(geomToClip(pos, offsets[3]));
				triStream.RestartStrip();
				triStream.Append(geomToClip(pos, offsets[4]));
				triStream.Append(geomToClip(pos, offsets[5]));
				triStream.Append(geomToClip(pos, offsets[6]));
				triStream.Append(geomToClip(pos, offsets[7]));
				triStream.RestartStrip();
			}

			float4 frag (v2g i) : SV_TARGET{
				return _BaseColor;
			}

			ENDHLSL
		}

	}
}


