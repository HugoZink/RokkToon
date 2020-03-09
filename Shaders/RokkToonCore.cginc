#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"

sampler2D _MainTex;
float4 _MainTex_ST;
float4 _Color;
float _Cutoff;

#if defined(_NORMALMAP)
    sampler2D _BumpMap;
    float4 _BumpMap_ST;
    float _BumpScale;
#endif

sampler2D _Ramp;
float _ToonContrast;
float _ToonRampOffset;
float3 _StaticToonLight;

float _Intensity;
float _Saturation;

float _DirectLightBoost;
float _IndirectLightBoost;

#if defined(_RAMPMASK_ON)
    sampler2D _RampMaskTex;

    sampler2D _RampR;
    float _ToonContrastR;
    float _ToonRampOffsetR;
    float _IntensityR;
    float _SaturationR;
    
    sampler2D _RampG;
    float _ToonContrastG;
    float _ToonRampOffsetG;
    float _IntensityG;
    float _SaturationG;
    
    sampler2D _RampB;
    float _ToonContrastB;
    float _ToonRampOffsetB;
    float _IntensityB;
    float _SaturationB;
#endif

#if defined(_METALLICGLOSSMAP)
    sampler2D _MetallicGlossMap;
#endif

float _Metallic;
float _Glossiness;

#if defined(_SPECGLOSSMAP)
    // _SpecColor is already defined somewhere
    //loat4 _SpecColor;
    sampler2D _SpecGlossMap;
#endif

#if defined(_EMISSION)
    sampler2D _EmissionMap;
    float4 _EmissionColor;
#endif

#if defined(_MATCAP_ADD) || defined(_MATCAP_MULTIPLY)
    sampler2D _MatCap;
    float _MatCapStrength;
#endif

#if defined(_RIMLIGHT_ADD) || defined(_RIMLIGHT_MIX)
    sampler2D _RimTex;
    float4 _RimLightColor;
    float _RimLightMode;
    float _RimWidth;
    float _RimInvert;
#endif

struct appdata
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
};

struct v2f
{
    float2 uv : TEXCOORD0;
    float4 pos : SV_POSITION;
    float3 normalDir : TEXCOORD1;
    float3 tangentDir : TEXCOORD2;
    float3 bitangentDir : TEXCOORD3;
    float4 worldPos : TEXCOORD4;
    SHADOW_COORDS(5)
};

#include "RokkToonLighting.cginc"
#include "RokkToonRamping.cginc"

#if defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
    #include "RokkToonMetallicSpecular.cginc"
#endif

#if defined(_MATCAP_ADD) || defined(_MATCAP_MULTIPLY)
    #include "RokkToonMatcap.cginc"
#endif

#if defined(_RIMLIGHT_ADD) || defined(_RIMLIGHT_MIX)
    #include "RokkToonRimlight.cginc"
#endif

float3 NormalDirection(v2f i)
{
    float3 normalDir = normalize(i.normalDir);
    
    // Perturb normals with a normal map
    #if defined(_NORMALMAP)
        float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);
        float3 bumpTex = UnpackScaleNormal(tex2D(_BumpMap,TRANSFORM_TEX(i.uv, _BumpMap)), _BumpScale);
        float3 normalLocal = bumpTex.rgb;
        normalDir = normalize(mul(normalLocal, tangentTransform));
    #endif
    
    return normalDir;
}

v2f vert (appdata v)
{
    v2f o;
    o.pos = UnityObjectToClipPos(v.vertex);
    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
    o.normalDir = UnityObjectToWorldNormal(v.normal);
    o.tangentDir = normalize( mul( unity_ObjectToWorld, float4( v.tangent.xyz, 0.0 ) ).xyz );
    o.bitangentDir = normalize(cross(o.normalDir, o.tangentDir) * v.tangent.w);
    o.worldPos = mul(unity_ObjectToWorld, v.vertex);
    TRANSFER_SHADOW(o);
    return o;
}

float4 frag (v2f i) : SV_Target
{
    float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);

    // Sample main texture
    float4 mainTex = tex2D(_MainTex, i.uv);
    mainTex *= _Color;
    
    // Cutout
    #if defined(_ALPHATEST_ON)
        clip(mainTex.a - _Cutoff);
    #endif
    
    // Get all vars related to toon ramping
    float IntensityVar;
    float SaturationVar;
    float ToonContrastVar;
    float ToonRampOffsetVar;
    float4 ToonRampMaskColor;
    GetToonVars(i.uv, IntensityVar, SaturationVar, ToonContrastVar, ToonRampOffsetVar, ToonRampMaskColor);
    
    // Obtain albedo from main texture and multiply by intensity
    float3 albedo = mainTex.rgb * IntensityVar;
    
    // Apply saturation modifier
    float lum = Luminance(albedo);
    albedo = lerp(float3(lum, lum, lum), albedo, SaturationVar);

    // Get normal direction from vertex normals (and normal maps if applicable)
    float3 normalDir = NormalDirection(i);
    
    // Matcap
    #if defined(_MATCAP_ADD) || defined(_MATCAP_MULTIPLY)
        Matcap(viewDir, normalDir, albedo);
    #endif
    
    // Rimlight
    #if defined(_RIMLIGHT_ADD) || defined(_RIMLIGHT_MIX)
        Rimlight(i.uv, viewDir, normalDir, albedo);
    #endif
    
    // Lighting
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos.xyz);
    
    float3 lightDirection;
    float3 lightColor;
    
    // Fill the finalcolor with indirect light data
    float3 finalColor = IndirectToonLighting(albedo, normalDir, i.worldPos.xyz);
    
    #ifdef UNITY_PASS_FORWARDBASE
        // Run the lighting function with non-realtime data first
        GetBaseLightData(lightDirection, lightColor);
        finalColor += ToonLighting(albedo, normalDir, lightDirection, lightColor * _IndirectLightBoost, ToonRampMaskColor, ToonContrastVar, ToonRampOffsetVar);
    #endif
    
    // Fill lightDirection and lightColor with current light data
    GetLightData(i.worldPos.xyz, lightDirection, lightColor);
    
    // Apply current light
    // If the current light is black or attenuation is 0, it will have no effect. Skip it to save on calculations and texture samples.
    if(any(_LightColor0.rgb != 0) && attenuation != 0)
    {
        finalColor += ToonLighting(albedo, normalDir, lightDirection, lightColor * _DirectLightBoost, ToonRampMaskColor, ToonContrastVar, ToonRampOffsetVar) * attenuation;
    }
    
    // Apply metallic
    #if defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
        MetallicSpecularGloss(i.worldPos.xyz, i.uv, normalDir, finalColor);
    #endif
    
    // Apply emission
    #if defined(UNITY_PASS_FORWARDBASE) && defined(_EMISSION)
        float4 emissive = tex2D(_EmissionMap, i.uv);
        emissive *= _EmissionColor;
        
        finalColor += emissive;
    #endif
    
    #if defined(_ALPHABLEND_ON)
        float finalAlpha = mainTex.a;
    #else
        float finalAlpha = 1;
    #endif

    return float4(finalColor, finalAlpha);
}