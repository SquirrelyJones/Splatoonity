Shader "Splatoonity/SplatShader" {
	Properties {
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_BumpTex ("Normal", 2D) = "bump" {}
		_SplatTileNormalTex ("Splat Tile Normal", 2D) = "bump" {}
		_SplatTileBump ("Splat Tile Bump", Range(1,10)) = 1.0
		_SplatEdgeBump ("Splat Edge Bump", Range(1,10)) = 1.0
		_SplatEdgeBumpWidth ("Splat Edge Bump Width", Range(1,10)) = 1.0
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0
	}	
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 200
		
		CGPROGRAM
		// Physically based Standard lighting model, and enable shadows on all light types
		#pragma surface surf Standard fullforwardshadows

		// Use shader model 3.0 target, to get nicer looking lighting
		#pragma target 3.0

		sampler2D _MainTex;
		sampler2D _BumpTex;
		sampler2D _SplatTileNormalTex;
		float _SplatEdgeBump;
		float _SplatEdgeBumpWidth;
		float _SplatTileBump;

		sampler2D _SplatTex;
		float4 _SplatTex_TexelSize;
		sampler2D _WorldTangentTex;
		sampler2D _WorldBinormalTex;

		struct Input {
			float2 uv_MainTex;
			float2 uv2_SplatTex;
			float3 worldNormal;
			float3 worldTangent;
			float3 worldBinormal;
			float3 worldPos;
			INTERNAL_DATA
		};

		half _Glossiness;
		half _Metallic;
		fixed4 _Color;
		
		static const float _Clip = 0.5;

		float3x3 cotangent_frame( float3 N, float3 p, float2 uv )
		{
		    // get edge vectors of the pixel triangle
		    float3 dp1 = ddx( p );
		    float3 dp2 = ddy( p );
		    float2 duv1 = ddx( uv );
		    float2 duv2 = ddy( uv );
		 
		    // solve the linear system
		    float3 dp2perp = cross( dp2, N );
		    float3 dp1perp = cross( N, dp1 );
		    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
		    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;
		 
		    // construct a scale-invariant frame 
		    float invmax = rsqrt( max( dot(T,T), dot(B,B) ) );
		    float3 TinvMax = normalize(T * invmax);
		    float3 BinvMax =  normalize(B * invmax);
		    return float3x3(float3( TinvMax.x, BinvMax.x, N.x ), float3( TinvMax.y, BinvMax.y, N.y ), float3( TinvMax.z, BinvMax.z, N.z ));
		    //return float3x3( TinvMax, BinvMax, N );
		}

		half3 perturb_normal( float3 localNormal, float3 N, float3 V, float2 uv )
		{
		    // assume N, the interpolated vertex normal and 
		    // V, the view vector (vertex to eye)
			float3x3 TBN = cotangent_frame( N, -V, uv );
			return normalize( mul( TBN, localNormal ) );
		}

		void surf (Input IN, inout SurfaceOutputStandard o) {
			
			// Sample splat map texture with offsets
			float4 splatSDF = tex2D (_SplatTex, IN.uv2_SplatTex);
			float4 splatSDFx = tex2D (_SplatTex, IN.uv2_SplatTex + float2(_SplatTex_TexelSize.x,0) );
			float4 splatSDFy = tex2D (_SplatTex, IN.uv2_SplatTex + float2(0,_SplatTex_TexelSize.y) );

			// Use ddx ddy to figure out a max clip amount to keep edge aliasing at bay when viewing from extreme angles or distances
			half splatDDX = length( ddx(IN.uv2_SplatTex * _SplatTex_TexelSize.zw) );
			half splatDDY = length( ddy(IN.uv2_SplatTex * _SplatTex_TexelSize.zw) );
			half clipDist = sqrt( splatDDX * splatDDX + splatDDY * splatDDY );
			half clipDistHard = max( clipDist * 0.01, 0.01 );
			half clipDistSoft = 0.01 * _SplatEdgeBumpWidth;

			// Smoothstep to make a soft mask for the splats
			float4 splatMask = smoothstep( ( _Clip - 0.01 ) - clipDistHard, ( _Clip - 0.01 ) + clipDistHard, splatSDF );
			float splatMaskTotal = max( max( splatMask.x, splatMask.y ), max( splatMask.z, splatMask.w ) );

			// Smoothstep to make the edge bump mask for the splats
			float4 splatMaskInside = smoothstep( _Clip - clipDistSoft, _Clip + clipDistSoft, splatSDF );
			splatMaskInside = max( max( splatMaskInside.x, splatMaskInside.y ), max( splatMaskInside.z, splatMaskInside.w ) );

			// Create normal offset for each splat channel
			float4 offsetSplatX = splatSDF - splatSDFx;
			float4 offsetSplatY = splatSDF - splatSDFy;

			// Combine all normal offsets into single offset
			float2 offsetSplat = lerp( float2(offsetSplatX.x,offsetSplatY.x), float2(offsetSplatX.y,offsetSplatY.y), splatMask.y );
			offsetSplat = lerp( offsetSplat, float2(offsetSplatX.z,offsetSplatY.z), splatMask.z );
			offsetSplat = lerp( offsetSplat, float2(offsetSplatX.w,offsetSplatY.w), splatMask.w );
			offsetSplat = normalize( float3( offsetSplat, 0.0001) ).xy; // Normalize to ensure parity between texture sizes
			offsetSplat = offsetSplat * ( 1.0 - splatMaskInside ) * _SplatEdgeBump;

			// Add some extra bump over the splat areas
			float2 splatTileNormalTex = tex2D( _SplatTileNormalTex, IN.uv2_SplatTex * 10.0 ).xy;
			offsetSplat += ( splatTileNormalTex.xy - 0.5 ) * _SplatTileBump  * 0.2;

			// Create the world normal of the splats
			#if 0
				// Use tangentless technique to get world normals
				float3 worldNormal = WorldNormalVector (IN, float3(0,0,1) );
				float3 offsetSplatLocal2 = normalize( float3( offsetSplat, sqrt( 1.0 - saturate( dot( offsetSplat, offsetSplat ) ) ) ) );
				float3 offsetSplatWorld = perturb_normal( offsetSplatLocal2, worldNormal, normalize( IN.worldPos - _WorldSpaceCameraPos ), IN.uv2_SplatTex );
			#else
				// Sample the world tangent and binormal textures for texcoord1 (the second uv channel)
				// you could skip the binormal texture and cross the vertex normal with the tangent texture to get the bitangent
				float3 worldTangentTex = tex2D ( _WorldTangentTex, IN.uv2_SplatTex ).xyz * 2.0 - 1.0;
				float3 worldBinormalTex = tex2D ( _WorldBinormalTex, IN.uv2_SplatTex ).xyz * 2.0 - 1.0;

				// Create the world normal of the splats
				float3 offsetSplatWorld = offsetSplat.x * worldTangentTex + offsetSplat.y * worldBinormalTex;
			#endif

			// Get the tangent and binormal for the texcoord0 (this is just the actual tangent and binormal that comes in from the vertex shader)
			float3 worldTangent = WorldNormalVector (IN, float3(1,0,0) );
			float3 worldBinormal = WorldNormalVector (IN, float3(0,1,0) );

			// Convert the splat world normal to tangent normal for texcood0
			float2 offsetSplatLocal = 0;
			offsetSplatLocal.x = dot( worldTangent, offsetSplatWorld );
			offsetSplatLocal.y = dot( worldBinormal, offsetSplatWorld );

			// sample the normal map from the main material
			float4 normalMap = tex2D( _BumpTex, IN.uv_MainTex );
			normalMap.xyz = UnpackNormal( normalMap );
			float3 tanNormal = normalMap.xyz;

			// Add the splat normal to the tangent normal
			tanNormal.xy += offsetSplatLocal * splatMaskTotal;
			tanNormal = normalize( tanNormal );

			// Albedo comes from a texture tinted by color
			float4 MainTex = tex2D (_MainTex, IN.uv_MainTex );
			fixed4 c = MainTex * _Color;

			// Lerp the color with the splat colors based on the splat mask channels
			c.xyz = lerp( c.xyz, float3(1.0,0.5,0.0), splatMask.x );
			c.xyz = lerp( c.xyz, float3(1.0,0.0,0.0), splatMask.y );
			c.xyz = lerp( c.xyz, float3(0.0,1.0,0.0), splatMask.z );
			c.xyz = lerp( c.xyz, float3(0.0,0.0,1.0), splatMask.w );
			
			o.Albedo = c.rgb;
			o.Normal = tanNormal;
			o.Metallic = _Metallic;
			o.Smoothness = lerp( _Glossiness, 0.7, splatMaskTotal );
			o.Alpha = c.a;

		}
		ENDCG
	} 
	FallBack "Diffuse"
}
