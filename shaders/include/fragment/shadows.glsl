/***********************************************/
/*          Copyright (C) 2023 Belmu           */
/*       GNU General Public License V3.0       */
/***********************************************/

/*
float contactShadow(vec3 viewPosition, vec3 rayDirection, int stepCount, float jitter) {
    vec3 rayPosition  = viewToScreen(viewPosition);
         rayDirection = normalize(viewToScreen(viewPosition + rayDirection) - rayPosition);

    const float contactShadowDepthLenience = 0.2;

    vec3 increment    = rayDirection * (contactShadowDepthLenience * rcp(stepCount));
         rayPosition += increment * (1.0 + jitter);

    for(int i = 0; i <= stepCount; i++, rayPosition += increment) {
        if(saturate(rayPosition.xy) != rayPosition.xy) return 1.0;

        float depth = texelFetch(depthtex1, ivec2(rayPosition.xy * viewSize), 0).r;
        if(depth >= rayPosition.z) return 1.0;

                 depth = linearizeDepth(depth);
        float rayDepth = linearizeDepth(rayPosition.z);

        if(abs(depth - rayDepth) / depth < contactShadowDepthLenience) return 0.0;
    }
    return 1.0;
}
*/

vec3 worldToShadow(vec3 worldPosition) {
	return projectOrthogonal(shadowProjection, transform(shadowModelView, worldPosition));
}

float visibility(sampler2D tex, vec3 samplePos) {
    return step(samplePos.z, texelFetch(tex, ivec2(samplePos.xy * shadowMapResolution), 0).r);
}

vec3 getShadowColor(vec3 samplePos) {
    if(saturate(samplePos) != samplePos) return vec3(1.0);

    float shadowDepth0 = visibility(shadowtex0, samplePos);
    float shadowDepth1 = visibility(shadowtex1, samplePos);
    vec4 shadowCol     = texelFetch(shadowcolor0, ivec2(samplePos.xy * shadowMapResolution), 0);
    
    #if TONEMAP == ACES
        shadowCol.rgb = srgbToAP1Albedo(shadowCol.rgb);
    #else
        shadowCol.rgb = srgbToLinear(shadowCol.rgb);
    #endif

    return mix(vec3(shadowDepth0), shadowCol.rgb * (1.0 - shadowCol.a), saturate(shadowDepth1 - shadowDepth0));
}

#if SHADOWS == 1 
    #if SHADOW_TYPE == 1
        float findBlockerDepth(vec3 shadowPosition, out float ssDepth) {
            float avgBlockerDepth = 0.0, totalSSDepth = 0.0; int blockers = 0;

            for(int i = 0; i < BLOCKER_SEARCH_SAMPLES; i++) {
                vec2 offset      = BLOCKER_SEARCH_RADIUS * diskSampling(i, BLOCKER_SEARCH_SAMPLES, randF() * TAU) * rcp(shadowMapResolution);
                vec2 localCoords = shadowPosition.xy + offset;
                if(saturate(localCoords) != localCoords) return -1.0;

                ivec2 shadowCoords = ivec2(localCoords * shadowMapResolution);
                float depth1       = texelFetch(shadowtex1, shadowCoords, 0).r;

                if(shadowPosition.z > depth1) {
                    avgBlockerDepth += depth1;
                    totalSSDepth    += max0(shadowPosition.z - depth1);
                    blockers++;
                }
            }
            // Subsurface depth calculation from SixthSurge#3922
            // -shadowProjectionInverse[2].z helps us convert the depth to a meters scale
            ssDepth = (totalSSDepth * -shadowProjectionInverse[2].z) / (SHADOW_DEPTH_STRETCH * float(blockers));

            return blockers > 0 ? avgBlockerDepth / float(blockers) : -1.0;
        }
    #endif

    vec3 PCF(vec3 shadowPosition, float penumbraSize) {
	    vec3 shadowResult = vec3(0.0); vec2 offset = vec2(0.0);

        for(int i = 0; i < SHADOW_SAMPLES; i++) {
            #if SHADOW_TYPE != 2
                offset = (diskSampling(i, SHADOW_SAMPLES, randF() * TAU) * penumbraSize) * rcp(shadowMapResolution);
            #endif

            vec3 samplePos = distortShadowSpace(shadowPosition + vec3(offset, 0.0)) * 0.5 + 0.5;
            shadowResult  += getShadowColor(samplePos);
        }
        return shadowResult * rcp(SHADOW_SAMPLES);
    }
#endif

vec3 calculateShadowMapping(vec3 scenePosition, vec3 geoNormal, out float ssDepth) {
    #if SHADOWS == 1 
        vec3  shadowPosition = worldToShadow(scenePosition);
        float NdotL          = dot(geoNormal, shadowLightVector);

        // Shadow bias implementation from Emin#7309 and concept from gri573#7741
        float biasAdjust = log2(max(4.0, shadowDistance - shadowMapResolution * 0.125)) * 0.35;
        shadowPosition  += mat3(shadowProjection) * (mat3(shadowModelView) * geoNormal) * getDistortionFactor(shadowPosition.xy) * biasAdjust;
        shadowPosition  *= 1.0002;

        float penumbraSize = NORMAL_SHADOW_PENUMBRA;
        ssDepth = 0.0;

        #if SHADOW_TYPE == 1
            vec3 shadowPosDistort = distortShadowSpace(shadowPosition) * 0.5 + 0.5;
            float avgBlockerDepth = findBlockerDepth(shadowPosDistort, ssDepth);
            if(avgBlockerDepth < 0.0) {
                ssDepth = 1.0;
                return vec3(-1.0);
            }

            if(texture(shadowcolor0, shadowPosDistort.xy).a > 0.0)
                penumbraSize = max(MIN_SHADOW_PENUMBRA, (max0(shadowPosDistort.z - avgBlockerDepth) * LIGHT_SIZE) / avgBlockerDepth);
            else
                penumbraSize = WATER_CAUSTICS_BLUR_RADIUS;
        #endif

        return PCF(shadowPosition, penumbraSize);
    #else
        return vec3(1.0);
    #endif
}
