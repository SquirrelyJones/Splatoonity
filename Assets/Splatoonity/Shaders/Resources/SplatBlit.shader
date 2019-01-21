Shader "Splatoonity/SplatBlit"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	
	CGINCLUDE
	
	#include "UnityCG.cginc"
	
	struct v2f
	{
		float4 pos : SV_POSITION;
		float2 uv : TEXCOORD0;
	};

	sampler2D _MainTex;
	float4 _MainTex_TexelSize;

	sampler2D _WorldPosTex;
	sampler2D _worldTangentTex;
	sampler2D _worldBinormalTex;
	sampler2D _WorldNormalTex;

	sampler2D _LastSplatTex;

	int _TotalSplats;
	float4x4 _SplatMatrix[10];
	float4 _SplatScaleBias[10];
	float4 _SplatChannelMask[10];

	float2 _SplatTexSize;
	
	v2f vert (appdata_img v)
	{
		v2f o;
		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv = v.texcoord.xy;
		return o;
	}
	
	float4 frag (v2f i) : COLOR
	{
		
		float4 currentSplat = tex2D(_LastSplatTex, i.uv);
		float4 wpos = tex2D(_WorldPosTex, i.uv);
		
		for( int i = 0; i < _TotalSplats; i++ ){
			float3 opos = mul(_SplatMatrix[i], float4(wpos.xyz,1)).xyz;

			// skip if outside of projection volume
			if( opos.x > -0.5 && opos.x < 0.5 && opos.y > -0.5 && opos.y < 0.5 && opos.z > -0.5 && opos.z < 0.5 ){
				// generate splat uvs
				float2 uv = saturate( opos.xz + 0.5 );
				uv *= _SplatScaleBias[i].xy;
				uv += _SplatScaleBias[i].zw;
				
				// sample the texture
				float newSplatTex = tex2D( _MainTex, uv ).x;
				newSplatTex = saturate( newSplatTex - abs( opos.y ) * abs( opos.y ) );
				currentSplat = min( currentSplat, 1.0 - newSplatTex * ( 1.0 - _SplatChannelMask[i] ) );
				currentSplat = max( currentSplat, newSplatTex * _SplatChannelMask[i]);
			}

		}

		// mask based on world coverage
		// needed for accurate score calculation
		return currentSplat * wpos.w;
	}
	
	float4 fragClear (v2f i) : COLOR
	{
		return float4(0,0,0,0);
	}
	
	float4 fragBleed (v2f i) : COLOR
	{
		
		float2 uv = i.uv;
		float4 worldPos = tex2D(_MainTex, uv);
		
		if( worldPos.w < 0.5 ){
			worldPos += tex2D( _MainTex, uv + float2(-1,-1) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(-1,0) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(-1,1) * _MainTex_TexelSize.xy );
			
			worldPos += tex2D( _MainTex, uv + float2(0,-1) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(0,0) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(0,1) * _MainTex_TexelSize.xy );
			
			worldPos += tex2D( _MainTex, uv + float2(1,-1) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(1,0) * _MainTex_TexelSize.xy );
			worldPos += tex2D( _MainTex, uv + float2(1,1) * _MainTex_TexelSize.xy );
		
			worldPos.xyz *= 1.0 / max( worldPos.w, 0.00001 );
			worldPos.w = min( worldPos.w, 1.0 );
		}
		
		return worldPos;
	}

	float4 smoothSample( float2 uv ){
		return smoothstep( 0.5 - 0.01, 0.5 + 0.01, tex2D (_MainTex, uv ) );
	}
	
	
	float4 fragDownsample (v2f i) : COLOR
	{

		float2 size = _MainTex_TexelSize.xy;

		float4 splatSDF = smoothSample( i.uv + size * float2( -3, -3 ) );
		splatSDF += smoothSample( i.uv + size * float2( -3, -1 ) );
		splatSDF += smoothSample( i.uv + size * float2( -3, 1 ) );
		splatSDF += smoothSample( i.uv + size * float2( -3, 3 ) );

		splatSDF += smoothSample( i.uv + size * float2( -1, -3 ) );
		splatSDF += smoothSample( i.uv + size * float2( -1, -1 ) );
		splatSDF += smoothSample( i.uv + size * float2( -1, 1 ) );
		splatSDF += smoothSample( i.uv + size * float2( -1, 3 ) );

		splatSDF += smoothSample( i.uv + size * float2( 1, -3 ) );
		splatSDF += smoothSample( i.uv + size * float2( 1, -1 ) );
		splatSDF += smoothSample( i.uv + size * float2( 1, 1 ) );
		splatSDF += smoothSample( i.uv + size * float2( 1, 3 ) );

		splatSDF += smoothSample( i.uv + size * float2( 3, -3 ) );
		splatSDF += smoothSample( i.uv + size * float2( 3, -1 ) );
		splatSDF += smoothSample( i.uv + size * float2( 3, 1 ) );
		splatSDF += smoothSample( i.uv + size * float2( 3, 3 ) );

		// keep it a nice high value so the mips are readable
		//splatSDF *= 0.0625;

		return splatSDF;
	}

	float4 fragCompile (v2f i) : COLOR
	{

		float2 size = _MainTex_TexelSize.xy;

		float4 splatSDF = tex2D (_MainTex, i.uv);

		float total = 0.00001;
		total += splatSDF.x + splatSDF.y + splatSDF.z + splatSDF.w;
		splatSDF *= 1.0 / total;

		return splatSDF;
	}

	ENDCG
	
	SubShader
	{
		ZTest Off
		Cull Off
		ZWrite Off
		Fog { Mode off }

		//Pass 0 decal rendering pass
		Pass
		{
			Name "Splat"
			CGPROGRAM
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 3.0
			ENDCG
		}
		
		//Pass 1 clear splat map pass
		Pass
		{
			Name "Clear"
			CGPROGRAM
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert
			#pragma fragment fragClear
			#pragma target 3.0
			ENDCG
		}
		
		//Pass 2 bleed pass
		Pass
		{
			Name "Bleed"
			CGPROGRAM
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert
			#pragma fragment fragBleed
			#pragma target 3.0
			ENDCG
		}
		
		//Pass 3 downsample pass
		Pass
		{
			Name "Downsample"
			CGPROGRAM
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert
			#pragma fragment fragDownsample
			#pragma target 3.0
			ENDCG
		}

		//Pass 4 compile pass
		Pass
		{
			Name "Compile"
			CGPROGRAM
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert
			#pragma fragment fragCompile
			#pragma target 3.0
			ENDCG
		}
	}
}
