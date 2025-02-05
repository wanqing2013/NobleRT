/***********************************************/
/*          Copyright (C) 2023 Belmu           */
/*       GNU General Public License V3.0       */
/***********************************************/

#include "/include/taau_scale.glsl"
#include "/include/common.glsl"

#if GI == 1
    /* RENDERTARGETS: 4,9,10 */

    layout (location = 0) out vec4 color;
    layout (location = 1) out uvec2 firstBounceData;
    layout (location = 2) out vec2 temporalData;
#else
    /* RENDERTARGETS: 4,10 */

    layout (location = 0) out vec4 color;
    layout (location = 1) out vec2 temporalData;
#endif

in vec2 textureCoords;
in vec2 vertexCoords;

#include "/include/atmospherics/constants.glsl"
#include "/include/fragment/brdf.glsl"
#include "/include/atmospherics/celestial.glsl"

#if GI == 1
    #include "/include/fragment/raytracer.glsl"
    #include "/include/fragment/pathtracer.glsl"
#endif

void main() {
    vec2 fragCoords = gl_FragCoord.xy * pixelSize / RENDER_SCALE;
	if(saturate(fragCoords) != fragCoords) { discard; return; }

    float depth         = texture(depthtex0, vertexCoords).r;
    vec3  viewPosition0 = screenToView(vec3(textureCoords, depth));

    if(depth == 1.0) {
        vec3 sky = renderAtmosphere(vertexCoords, viewPosition0);
        #if GI == 1
            firstBounceData.x = packUnormArb(logLuvEncode(sky), uvec4(8));
        #else
            color.rgb = sky;
        #endif
        return;
    }

    Material material = getMaterial(vertexCoords);

    #if HARDCODED_SSS == 1
        if(material.blockId > NETHER_PORTAL_ID && material.blockId <= PLANTS_ID && material.subsurface <= EPS) material.subsurface = HARDCODED_SSS_VAL;
    #endif

    #if AO_FILTER == 1 && GI == 0 || GI == 1 && GI_TEMPORAL_ACCUMULATION == 1
        vec3  currPosition = vec3(textureCoords, depth);
        vec2  prevCoords   = vertexCoords + getVelocity(currPosition).xy * RENDER_SCALE;
        vec4  history      = texture(LIGHTING_BUFFER, prevCoords);

        color.a  = history.a;
        color.a *= float(clamp(prevCoords, 0.0, RENDER_SCALE) == prevCoords);
        color.a *= float(!isHand(vertexCoords));

        temporalData = texture(TEMPORAL_DATA_BUFFER, prevCoords).rg;

        #if RENDER_MODE == 0
            color.a *= pow(exp(-abs(linearizeDepthFast(depth) - linearizeDepthFast(exp2(temporalData.g)))), TEMPORAL_DEPTH_WEIGHT_SIGMA);

            vec2 pixelCenterDist = 1.0 - abs(2.0 * fract(prevCoords * viewSize) - 1.0);
                 color.a        *= sqrt(pixelCenterDist.x * pixelCenterDist.y) * 0.1 + 0.9;

            temporalData.g = log2(depth);
        #else
            color.a *= float(hideGUI);
        #endif

        color.a++;
    #endif

    #if GI == 0
        color.rgb = vec3(0.0);

        if(material.F0 * maxVal8 <= 229.5) {
            vec3 skyIlluminance = vec3(0.0), directIlluminance = vec3(0.0);
            float cloudsShadows = 1.0; vec4 shadowmap = vec4(1.0, 1.0, 1.0, 0.0);

            #if defined WORLD_OVERWORLD || defined WORLD_END
                directIlluminance = texelFetch(ILLUMINANCE_BUFFER, ivec2(0), 0).rgb;

                #if defined WORLD_OVERWORLD && CLOUDS_SHADOWS == 1 && CLOUDS_LAYER0_ENABLED == 1
                    cloudsShadows = getCloudsShadows(viewToScene(viewPosition0));
                #endif

                skyIlluminance = texelFetch(ILLUMINANCE_BUFFER, ivec2(gl_FragCoord.xy), 0).rgb;

                #if SHADOWS == 1
                    shadowmap = texelFetch(SHADOWMAP_BUFFER, ivec2(gl_FragCoord.xy), 0);
                #endif
            #endif

            float ao = 1.0;
            #if AO == 1
                ao = texture(AO_BUFFER, vertexCoords).a;
            #endif

            color.rgb = computeDiffuse(viewPosition0, shadowVec, material, shadowmap, directIlluminance, skyIlluminance, ao, cloudsShadows);
        }
    #else
        vec3 direct   = vec3(0.0);
        vec3 indirect = vec3(1.0);

        pathtrace(color.rgb, vec3(vertexCoords, depth), direct, indirect);

        #if GI_TEMPORAL_ACCUMULATION == 1
            float weight = saturate(1.0 / max(color.a * float(linearizeDepthFast(material.depth0) >= MC_HAND_DEPTH), 1.0));

            color.rgb = clamp16(mix(history.rgb, color.rgb, weight));

            uvec2 packedFirstBounceData = texture(GI_DATA_BUFFER, prevCoords).rg;

            direct   = clamp16(mix(logLuvDecode(unpackUnormArb(packedFirstBounceData[0], uvec4(8))), direct  , weight));
            indirect = clamp16(mix(logLuvDecode(unpackUnormArb(packedFirstBounceData[1], uvec4(8))), indirect, weight));

            #if GI_FILTER == 1
                float luminance      = luminance(color.rgb);
                      temporalData.r = mix(temporalData.r, luminance * luminance, weight);
            #endif
        #endif

        firstBounceData.x = packUnormArb(logLuvEncode(direct  ), uvec4(8));
        firstBounceData.y = packUnormArb(logLuvEncode(indirect), uvec4(8));
    #endif
}
