/***********************************************/
/*       Copyright (C) Noble RT - 2021         */
/*   Belmu | GNU General Public License V3.0   */
/*                                             */
/* By downloading this content you have agreed */
/*     to the license and its terms of use.    */
/***********************************************/

/* DRAWBUFFERS:07 */

layout (location = 0) out vec4 color;
layout (location = 1) out vec4 volumetricLight;

#include "/include/atmospherics/celestial.glsl"
#include "/include/fragment/brdf.glsl"
#include "/include/fragment/raytracer.glsl"
#include "/include/fragment/reflections.glsl"
#include "/include/fragment/filter.glsl"
#include "/include/fragment/shadows.glsl"
#include "/include/atmospherics/fog.glsl"

void main() {
    color         = texture(colortex0, texCoords);
    vec3 viewPos0 = getViewPos0(texCoords);
    bool inWater  = isEyeInWater > 0.5;

    if(!isSky(texCoords)) {
        vec3 viewPos1 = getViewPos1(texCoords);
        vec3 viewDir0 = normalize(mat3(gbufferModelViewInverse) * viewPos0);

        material mat      = getMaterial(texCoords);
        material transMat = getMaterialTranslucents(texCoords);
        vec2 coords       = texCoords;

        #if GI == 1
            #if GI_FILTER == 1                
                color.rgb = SVGF(texCoords, colortex0, viewPos0, mat.normal, 1.5, 3);
            #endif
        #endif

        vec3 skyIlluminance = vec3(0.0), totalIllum = vec3(1.0);
        vec4 shadowmap      = texture(colortex3, texCoords);

        if(viewPos0.z != viewPos1.z) {
            mat = transMat;

            //////////////////////////////////////////////////////////
            /*-------------------- REFRACTIONS ---------------------*/
            //////////////////////////////////////////////////////////

            #if REFRACTIONS == 1
                vec3 hitPos;
                if(mat.blockId > 0 && mat.blockId <= 4) {
                    color.rgb = simpleRefractions(viewPos0, mat, hitPos);
                    coords    = hitPos.xy;
                }
            #endif

            //////////////////////////////////////////////////////////
            /*------------------ ALPHA BLENDING --------------------*/
            //////////////////////////////////////////////////////////

            #if GI == 0
                #ifdef WORLD_OVERWORLD
                    skyIlluminance = texture(colortex7, texCoords).rgb;
                    totalIllum     = shadowLightTransmittance();
                #else
                    shadowmap.rgb = vec3(0.0);
                #endif

                vec3 transLighting = applyLighting(viewPos0, mat, shadowmap, totalIllum, skyIlluminance, false);
                color.rgb          = mix(color.rgb * mix(vec3(1.0), mat.albedo, mat.alpha), transLighting, mat.alpha);
            #endif
        }

        //////////////////////////////////////////////////////////
        /*-------------------- WATER FOG -----------------------*/
        //////////////////////////////////////////////////////////

        #ifdef WORLD_OVERWORLD
            bool canFog = inWater ? true : mat.blockId == 1;
        
            if(canFog) {
                vec3 worldPos0 = transMAD3(gbufferModelViewInverse, getViewPos0(coords));
                vec3 worldPos1 = transMAD3(gbufferModelViewInverse, getViewPos1(coords));

                vec3 startPos = inWater ? vec3(0.0) : worldPos0;
                vec3 endPos   = inWater ? worldPos0 : worldPos1;

                #if WATER_FOG == 0
                    float depthDist = inWater ? length(worldPos0) : distance(worldPos0, worldPos1);
                    waterFog(color.rgb, depthDist, dot(viewDir0, sceneSunDir), skyIlluminance);
                #else
                    vec3 worldDir  = normalize(inWater ? worldPos0 : worldPos1);
                    volumetricWaterFog(color.rgb, startPos, endPos, worldDir);
                #endif
            }
        #endif

        //////////////////////////////////////////////////////////
        /*-------------------- REFLECTIONS ---------------------*/
        //////////////////////////////////////////////////////////

        #if GI == 0
            #if REFLECTIONS == 1
                vec3 reflections = texture(colortex4, texCoords * REFLECTIONS_RES).rgb;
                float NdotV      = maxEps(dot(mat.normal, -normalize(viewPos0)));

                if(mat.rough > 0.05) {
                    vec3 DFG  = envBRDFApprox(getMetalF0(mat.F0, mat.albedo), mat.rough, NdotV);
                    color.rgb = mix(color.rgb, reflections, DFG);
                } else {
                    color.rgb += reflections;
                }
            #endif
        #endif
    }

    //////////////////////////////////////////////////////////
    /*------------------ VL / RAIN FOG ---------------------*/
    //////////////////////////////////////////////////////////

    #if VL == 1
        #ifdef WORLD_OVERWORLD
            volumetricLight = vec4(volumetricLighting(viewPos0), 1.0);
        #endif
    #else
        #if RAIN_FOG == 1
            if(rainStrength > 0.0 && !inWater) {
                volumetricGroundFog(color.rgb, viewPos0, getMaterial(texCoords).lightmap.y);
            }
        #endif
    #endif
}
