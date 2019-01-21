Shader "Splatoonity/WorldBinormalUnwrap"
{
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
				float3 worldPos : TEXCOORD0;
			};
			
			v2f vert (appdata_full v)
			{
				v2f o;
				float4 uvWorldPos = float4( v.texcoord1.xy * 2.0 - 1.0, 0.5, 1.0 );
				o.pos = mul( UNITY_MATRIX_VP, uvWorldPos );
				o.worldPos = mul(unity_ObjectToWorld, v.vertex ).xyz;
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				float3 worldBinormal = normalize( ddy( i.worldPos ) ) * 0.5 + 0.5;
				return float4(worldBinormal, 1.0);
			}
			ENDCG
		}
	}
}
