/***********************************************/
/*          Copyright (C) 2023 Belmu           */
/*       GNU General Public License V3.0       */
/***********************************************/

/* RENDERTARGETS: 11 */

layout (location = 0) out uvec2 fog;

in vec2 textureCoords;
in vec2 vertexCoords;

#include "/include/taau_scale.glsl"
#include "/include/common.glsl"

#include "/include/atmospherics/constants.glsl"

#if defined WORLD_OVERWORLD || defined WORLD_END
	#include "/include/atmospherics/atmosphere.glsl"
#endif

#include "/include/fragment/shadows.glsl"
#include "/include/atmospherics/fog.glsl"

void main() {
    vec2 fragCoords = gl_FragCoord.xy * pixelSize / RENDER_SCALE;
	if(saturate(fragCoords) != fragCoords) discard;

    Material material = getMaterial(vertexCoords);

    float depth0        = texture(depthtex0, vertexCoords).r;
    vec3  viewPosition0 = screenToView(vec3(textureCoords, depth0));

    float depth1        = texture(depthtex1, vertexCoords).r;
    vec3  viewPosition1 = screenToView(vec3(textureCoords, depth1));
    vec3 scenePosition0 = viewToScene(viewPosition0);

    vec3 skyIlluminance = vec3(0.0), directIlluminance = vec3(0.0);
    
    #if defined WORLD_OVERWORLD || defined WORLD_END
        directIlluminance = texelFetch(ILLUMINANCE_BUFFER, ivec2(0), 0).rgb;
        skyIlluminance    = texture(ILLUMINANCE_BUFFER, vertexCoords).rgb;

        #if defined WORLD_OVERWORLD
            float VdotL = dot(normalize(scenePosition0 - gbufferModelViewInverse[3].xyz), shadowLightVector);
        #else
            float VdotL = dot(normalize(scenePosition0 - gbufferModelViewInverse[3].xyz), starVector);
        #endif
    #else
        directIlluminance = getBlockLightColor(material) * saturate(material.lightmap.x + 0.3);
        float VdotL = 0.0;
    #endif

    bool  sky      = isSky(vertexCoords);
    float skylight = 0.0;

    vec3 scatteringLayer0    = vec3(0.0);
    vec3 transmittanceLayer0 = vec3(1.0);

    vec3 scatteringLayer1    = vec3(0.0);
    vec3 transmittanceLayer1 = vec3(1.0);

    if(!sky) {
        skylight = getSkylightFalloff(material.lightmap.y);

        if(viewPosition0.z != viewPosition1.z) {
            //////////////////////////////////////////////////////////
            /*---------------- FRONT TO BACK FOG -------------------*/
            //////////////////////////////////////////////////////////

            vec3 scenePosition1 = viewToScene(viewPosition1);

            if(isEyeInWater != 1 && material.blockId == WATER_ID) {
                #if defined WORLD_OVERWORLD || defined WORLD_END
                    #if defined WORLD_OVERWORLD && defined SUNLIGHT_LEAKING_FIX
                        directIlluminance *= float(material.lightmap.y != 0.0);
                    #endif

                    #if WATER_FOG == 0
                        computeWaterFogApproximation(scatteringLayer0, transmittanceLayer0, scenePosition0, scenePosition1, VdotL, directIlluminance, skyIlluminance, skylight);
                    #else
                        bool skyTranslucents = texture(depthtex1, vertexCoords).r == 1.0;
                        computeVolumetricWaterFog(scatteringLayer0, transmittanceLayer0, scenePosition0, scenePosition1, VdotL, directIlluminance, skyIlluminance, skylight, skyTranslucents);
                    #endif
                #endif
            } else {
                #if AIR_FOG == 1
                    computeVolumetricAirFog(scatteringLayer0, transmittanceLayer0, scenePosition0, scenePosition1, viewPosition0, VdotL, directIlluminance, skyIlluminance, skylight);
                #elif AIR_FOG == 2
                    computeAirFogApproximation(scatteringLayer0, transmittanceLayer0, viewPosition0, VdotL, directIlluminance, skyIlluminance, skylight);
                #endif
            }
        }
    } else {
        skylight = 1.0;
    }

    //////////////////////////////////////////////////////////
    /*------------------ EYE TO FRONT FOG ------------------*/
    //////////////////////////////////////////////////////////

    if(isEyeInWater == 1) {
        #if defined WORLD_OVERWORLD || defined WORLD_END
            #if WATER_FOG == 0
                computeWaterFogApproximation(scatteringLayer1, transmittanceLayer1, gbufferModelViewInverse[3].xyz, scenePosition0, VdotL, directIlluminance, skyIlluminance, skylight);
            #else
                computeVolumetricWaterFog(scatteringLayer1, transmittanceLayer1, gbufferModelViewInverse[3].xyz, scenePosition0, VdotL, directIlluminance, skyIlluminance, skylight, sky);
            #endif
        #endif
    } else {
        #if AIR_FOG == 1
            computeVolumetricAirFog(scatteringLayer1, transmittanceLayer1, gbufferModelViewInverse[3].xyz, scenePosition0, viewPosition0, VdotL, directIlluminance, skyIlluminance, skylight);
        #elif AIR_FOG == 2
            computeAirFogApproximation(scatteringLayer1, transmittanceLayer1, viewPosition0, VdotL, directIlluminance, skyIlluminance, skylight);
        #endif
    }

    fog.x = packUnormArb(logLuvEncode(scatteringLayer0    * transmittanceLayer1 + scatteringLayer1), uvec4(8));
    fog.y = packUnormArb(logLuvEncode(transmittanceLayer0 * transmittanceLayer1                   ), uvec4(8));
}
