Shader "Splatoonity/WorldPosUnwrap"
{
	Properties
	{
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct v2f
			{
				float4 pos : SV_POSITION;
				float3 worldPos : TEXCOORD3;
			};
			
			v2f vert (appdata_full v)
			{
				v2f o;
				float4 uvWorldPos = float4( v.texcoord1.xy * 2.0 - 1.0, 0.5, 1.0 );
				o.pos = mul( UNITY_MATRIX_VP, uvWorldPos );
				//o.pos = float4( v.texcoord1.xy * 2.0 - 1.0, 0, 1 );
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				return o;
			}
			
			float4 frag (v2f i) : SV_Target
			{
				float3 worldPos = i.worldPos;
				return float4(worldPos, 1.0);
			}
			ENDCG
		}
	}
}
