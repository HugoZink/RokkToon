// Indirect lighting, consists of SH and vertex lights
// In ForwardAdd, there is no indirect lighting.
float3 IndirectToonLighting(float3 albedo, float3 normalDir, float3 worldPos)
{
    #ifdef UNITY_PASS_FORWARDBASE
        // Apply SH
        // The sample direction is zero to sample flatly, for a toonier look
        float3 lighting = albedo * ShadeSH9(float4(0,0,0,1));
        
        // Apply vertex lights
        #if defined(VERTEXLIGHT_ON)
            lighting += albedo * Shade4PointLights(
                    unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
                    unity_LightColor[0].rgb, unity_LightColor[1].rgb,
                    unity_LightColor[2].rgb, unity_LightColor[3].rgb,
                    unity_4LightAtten0, worldPos, normalDir
            );
        #endif
    
    #else
        // In additive passes, start with zero as base
        float3 lighting = float3(0,0,0);
    #endif
    
    return lighting;
}

// Obtain a light direction from baked lighting.
float3 GIsonarDirection()
{
    float3 dir = Unity_SafeNormalize(unity_SHAr.xyz + unity_SHAg.xyz + unity_SHAb.xyz);
    if(all(dir == 0))
    {
        dir = _StaticToonLight;
    }
    return dir;
}

// Simple lambert lighting
float3 ToonLighting(float3 albedo, float3 normalDir, float3 lightDir, float3 lightColor, float4 ToonRampMaskColor, float toonContrast, float toonRampOffset)
{
    float dotProduct = saturate(dot(normalDir, lightDir));
    
    // Turn ndotl into UV's for toon ramp
    // Sample toon ramp diagonally to cover horizontal and vertical ramps (thanks Rero)
    float2 rampUV = saturate(float2(dotProduct, dotProduct) + toonRampOffset);
    
    #if defined(_RAMPMASK_ON)
        float4 ramp;
        if(ToonRampMaskColor.r > 0.5)
        {
            ramp = tex2D(_RampR, rampUV);
        }
        else if(ToonRampMaskColor.g > 0.5)
        {
            ramp = tex2D(_RampG, rampUV);
        }
        else if(ToonRampMaskColor.b > 0.5)
        {
            ramp = tex2D(_RampB, rampUV);
        }
        else
        {
            ramp = tex2D(_Ramp, rampUV);
        }
    #else
        float4 ramp = tex2D(_Ramp, rampUV);
    #endif
    
    // Multiply by toon ramp color value rather than ndotl
    return albedo * lightColor * ramp.rgb * toonContrast;
}

// Fill the light direction and light color parameters with data from SH.
// This ensures that there is always some toon shading going on.
void GetBaseLightData(inout float3 lightDirection, inout float3 lightColor)
{
    lightDirection = GIsonarDirection();
    lightColor = ShadeSH9(float4(0,0,0,1));
}

// Fill the light direction and light color parameters.
void GetLightData(float3 worldPos, inout float3 lightDirection, inout float3 lightColor)
{
    #ifdef UNITY_PASS_FORWARDBASE
        // Take directional light direction and color
        lightDirection = normalize(_WorldSpaceLightPos0.xyz);
        lightColor = _LightColor0.rgb;
    #else
        // Pass is forwardadd
        // Check if the light is directional or point/spot.
        // Directional lights get their pos interpreted as direction
        // Other lights get their direction calculated from their pos
        #if defined(DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
            lightDirection = normalize(_WorldSpaceLightPos0.xyz);
            lightColor = _LightColor0.rgb;
        #else
            lightDirection = normalize(_WorldSpaceLightPos0.xyz - worldPos);
            lightColor = _LightColor0.rgb;
        #endif
    #endif
}