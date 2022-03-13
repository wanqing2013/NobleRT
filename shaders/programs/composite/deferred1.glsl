/***********************************************/
/*        Copyright (C) NobleRT - 2022         */
/*   Belmu | GNU General Public License V3.0   */
/*                                             */
/* By downloading this content you have agreed */
/*     to the license and its terms of use.    */
/***********************************************/

/* RENDERTARGETS: 0,5 */

layout (location = 0) out vec3 color;
layout (location = 1) out vec4 historyBuffer;

#include "/include/utility/blur.glsl"

#include "/include/fragment/brdf.glsl"

#include "/include/atmospherics/celestial.glsl"
#include "/include/atmospherics/atmosphere.glsl"

#include "/include/fragment/raytracer.glsl"
#include "/include/fragment/pathtracer.glsl"
#include "/include/fragment/shadows.glsl"

#if GI == 1 && GI_TEMPORAL_ACCUMULATION == 1
    #include "/include/post/taa.glsl"

    void temporalAccumulation(inout vec3 color, Material mat, sampler2D prevTex, inout float frames) {
        vec3 prevPos   = reprojection(vec3(texCoords, texture(depthtex0, texCoords).r));
        vec3 prevColor = texture(prevTex, prevPos.xy).rgb;

        float totalWeight = float(clamp01(prevPos.xy) == prevPos.xy);

        #if ACCUMULATION_VELOCITY_WEIGHT == 0
            vec4 weightTex     = texture(colortex10, texCoords);
            float normalWeight = pow(dot(mat.normal, weightTex.rgb), 8.0);

            float depthWeight = pow5(exp2(-abs(prevPos.z - weightTex.a)));

            totalWeight *= normalWeight * depthWeight;
        #else
            totalWeight *= 1.0 - (1.0 / max(frames, 1.0));
        #endif

        color = clamp16(mix(color, prevColor, totalWeight));
    }
#endif

void main() {
    color         = vec3(0.0);
    vec3 viewPos0 = getViewPos0(texCoords);

    //////////////////////////////////////////////////////////
    /*------------------------ SKY -------------------------*/
    //////////////////////////////////////////////////////////

    if(isSky(texCoords)) {
        color = computeSky(viewPos0, true);
        return;
    }

    //////////////////////////////////////////////////////////
    /*--------------------- MATERIAL -----------------------*/
    //////////////////////////////////////////////////////////

    Material mat   = getMaterial(texCoords);
    vec4 shadowmap = texture(colortex3, texCoords);
    float frames   = 0.0;

    vec3 skyIlluminance = vec3(0.0);
    #ifdef WORLD_OVERWORLD
        skyIlluminance = texture(colortex7, texCoords).rgb;
    #endif

    #if ACCUMULATION_VELOCITY_WEIGHT == 1
        frames = hasMoved() ? 1.0 : texture(colortex5, texCoords).a + 1.0;
    #endif

    vec2 causticsCoords = distortShadowSpace(worldToShadow(viewToWorld(viewPos0))).xy;
    //shadowmap.rgb += texture(shadowcolor1, causticsCoords * 0.5 + 0.5).r;

    #if GI == 0
        //////////////////////////////////////////////////////////
        /*--------------------- LIGHTING -----------------------*/
        //////////////////////////////////////////////////////////

        if(!mat.isMetal) {
            #if AO == 1
                #if SSAO_FILTER == 1
                    shadowmap.a = gaussianBlur(texCoords, colortex3, 1.2, 2.0, 4).a;
                #endif
            #endif

            color = computeDiffuse(viewPos0, shadowDir, mat, shadowmap, sampleDirectIlluminance(), skyIlluminance);
        }
    #else
        //////////////////////////////////////////////////////////
        /*------------------- PATH TRACING ---------------------*/
        //////////////////////////////////////////////////////////

        vec2 scaledUv = texCoords * (1.0 / GI_RESOLUTION);

        if(clamp(texCoords, vec2(0.0), vec2(GI_RESOLUTION + 1e-3)) == texCoords) {
            pathTrace(color, vec3(scaledUv, texture(depthtex1, scaledUv).r));

            #if GI_TEMPORAL_ACCUMULATION == 1
                temporalAccumulation(color, mat, colortex5, frames);
            #endif
        }
    #endif
    historyBuffer = vec4(color, frames);
}
