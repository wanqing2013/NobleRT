/***********************************************/
/*              Noble RT - 2021              */
/*   Belmu | GNU General Public License V3.0   */
/*   Please do not claim my work as your own.  */
/***********************************************/

// Kneemund's Border Attenuation
float Kneemund_Attenuation(vec2 pos, float edgeFactor) {
    pos *= 1.0 - pos;
    return 1.0 - quintic(edgeFactor, 0.0, minOf(pos));
}

vec3 getHitColor(vec3 hitPos) {
    #if SSR_REPROJECTION == 1
        hitPos = reprojection(hitPos);
        return texture(colortex8, hitPos.xy).rgb;
    #else
        return texture(colortex4, hitPos.xy).rgb;
    #endif
}

vec3 getSkyFallback(vec3 reflected, Material mat) {
    vec2 coords = projectSphere(viewToScene(reflected));
    vec3 sky    = texture(colortex0, getAtmosphereCoordinates(coords, ATMOSPHERE_RESOLUTION, randF())).rgb;
    
	vec4 clouds = vec4(0.0, 0.0, 0.0, 1.0);
	#if CLOUDS == 1
		clouds = texture(colortex15, getAtmosphereCoordinates(coords, CLOUDS_RESOLUTION, 0.0));
	#endif

    return (sky * clouds.a + clouds.rgb) * getSkyLightIntensity(mat.lightmap.y);
}

//////////////////////////////////////////////////////////
/*------------------ SIMPLE REFLECTIONS ----------------*/
//////////////////////////////////////////////////////////

#if REFLECTIONS_TYPE == 0
    vec3 simpleReflections(vec3 viewPos, Material mat) {
        viewPos     += mat.normal * 1e-2;
        vec3 viewDir = normalize(viewPos);

        vec3 reflected = reflect(viewDir, mat.normal); vec3 hitPos;
        float hit      = float(raytrace(viewPos, reflected, SIMPLE_REFLECT_STEPS, randF(), hitPos));
        float factor   = Kneemund_Attenuation(hitPos.xy, ATTENUATION_FACTOR) * hit;
        vec3 hitColor  = getHitColor(hitPos);

        #if SKY_FALLBACK == 0
            vec3 color = mix(vec3(0.0), hitColor, factor);
        #else
            vec3 color = mix(getSkyFallback(reflected, mat), hitColor, factor);
        #endif

        float NdotL = clamp01(dot(mat.normal, reflected));
        float NdotV = maxEps(dot(mat.normal, viewDir));

        vec3  F  = fresnelComplex(NdotL, mat);
        float G1 = G1SmithGGX(NdotV, mat.rough);
        float G2 = G2SmithGGX(NdotL, NdotV, mat.rough);

        return color * ((F * G2) / G1);
    }
#else

//////////////////////////////////////////////////////////
/*------------------ ROUGH REFLECTIONS -----------------*/
//////////////////////////////////////////////////////////

    vec3 roughReflections(vec3 viewPos, Material mat) {
	    vec3 color = vec3(0.0); vec3 hitPos;
        int samples = 0;

        viewPos     += mat.normal * 1e-2;
        mat3 TBN     = constructViewTBN(mat.normal);
        vec3 viewDir = normalize(viewPos);
        float NdotV  = maxEps(dot(mat.normal, viewDir));
	
        for(int i = 0; i < ROUGH_SAMPLES; i++) {
            vec2 noise = TAA == 1 ? vec2(randF(), randF()) : uniformNoise(i, blueNoise);
        
            vec3 microfacet = TBN * sampleGGXVNDF(-viewDir * TBN, noise, mat.rough);
		    vec3 reflected  = reflect(viewDir, microfacet);	
            float NdotL     = abs(dot(mat.normal, reflected));

            float hit     = float(raytrace(viewPos, reflected, ROUGH_REFLECT_STEPS, randF(), hitPos));
            float factor  = Kneemund_Attenuation(hitPos.xy, ATTENUATION_FACTOR) * hit;
            vec3 hitColor = getHitColor(hitPos);

            #if SKY_FALLBACK == 0
                hitColor = mix(vec3(0.0), hitColor, factor);
            #else
                hitColor = mix(getSkyFallback(reflected, mat), hitColor, factor);
            #endif

            if(NdotV > 0.0 && NdotL > 0.0) {
                vec3  F  = fresnelComplex(dot(microfacet, -viewDir), mat);
                float G1 = G1SmithGGX(NdotV, mat.rough);
                float G2 = G2SmithGGX(NdotL, NdotV, mat.rough);

                color += hitColor * ((F * G2) / G1);
                samples++;
            }
	    }
	    return max0(color * rcp(samples));
    }
#endif

//////////////////////////////////////////////////////////
/*--------------------- REFRACTIONS --------------------*/
//////////////////////////////////////////////////////////

#if REFRACTIONS == 1
    vec3 simpleRefractions(vec3 viewPos, Material mat, inout vec3 hitPos) {
        viewPos += mat.normal * 1e-2;

        float  ior   = F0ToIOR(mat.F0);
        vec3 viewDir = normalize(viewPos);

        vec3 refracted = refract(viewDir, mat.normal, airIOR / ior);
        bool hit       = raytrace(viewPos, refracted, REFRACT_STEPS, randF(), hitPos);
        bool hand      = linearizeDepth(mat.depth0) < 0.56;
        if(!hit || hand) hitPos.xy = texCoords;

        float fresnel = fresnelDielectric(maxEps(dot(mat.normal, -viewDir)), ior);
        vec3 hitColor = vec3(
            texture(colortex4, hitPos.xy + vec2(5e-4 * rand(gl_FragCoord.xy))).r,
            texture(colortex4, hitPos.xy).g,
            texture(colortex4, hitPos.xy - vec2(5e-4 * rand(gl_FragCoord.yx))).b
        );

        return hitColor * (1.0 - fresnel);
    }
#endif
