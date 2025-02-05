/***********************************************/
/*          Copyright (C) 2023 Belmu           */
/*       GNU General Public License V3.0       */
/***********************************************/

#if defined WORLD_OVERWORLD || defined WORLD_END
    #include "/include/common.glsl"
    #include "/include/atmospherics/constants.glsl"
    #include "/include/atmospherics/atmosphere.glsl"
#endif

#if defined STAGE_VERTEX

    out vec2 textureCoords;
    out vec3 skyIlluminance;

    void main() {
        gl_Position   = vec4(gl_Vertex.xy * 2.0 - 1.0, 1.0, 1.0);
        textureCoords = gl_Vertex.xy;

        #if defined WORLD_OVERWORLD || defined WORLD_END
            skyIlluminance = evaluateUniformSkyIrradianceApproximation();
        #endif
    }

#elif defined STAGE_FRAGMENT

    /* RENDERTARGETS: 6 */

    layout (location = 0) out vec3 sky;

    in vec2 textureCoords;
    in vec3 skyIlluminance;

    void main() {
        #if defined WORLD_OVERWORLD || defined WORLD_END
            vec3 skyRay = normalize(unprojectSphere(textureCoords));
                 sky    = evaluateAtmosphericScattering(skyRay, skyIlluminance);
        #endif
    }
#endif
