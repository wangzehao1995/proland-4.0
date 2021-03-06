/*
 * Proland: a procedural landscape rendering library.
 * Copyright (c) 2008-2011 INRIA
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Proland is distributed under a dual-license scheme.
 * You can obtain a specific license from Inria: proland-licensing@inria.fr.
 */

/*
 * Authors: Eric Bruneton, Antoine Begault, Guillaume Piolat.
 */

const float BORDER = 2.0; // tile border size

uniform vec4 tileWSDF; // size in pixels of one tile (including borders), size in meters of a pixel of the elevation texture, (tileWidth - 2*BORDER) / grid mesh size for display, 1 to flip quad diagonals during rendering with a geometry shader (to avoid geometry aliasing), 0 otherwise

uniform sampler2DArray coarseLevelSampler; // coarse level texture
uniform vec4 coarseLevelOSL; // lower left corner of patch to upsample, one over size in pixels of coarse level texture, layer id

uniform sampler2D residualSampler; // residual texture
uniform vec4 residualOSH; // lower left corner of residual patch to use, scaling factor of residual texture coordinates, scaling factor of residual texture values

uniform sampler2DArray noiseSampler; // noise texture
uniform vec4 noiseUVLH; // noise texture rotation, noise texture layer, scaling factor of noise texture values

uniform mat4 deformation;

#ifdef _VERTEX_

layout(location=0) in vec4 vertex;
out vec2 st;

void main() {
    st = (vertex.xy * 0.5 + 0.5) * tileWSDF.x;
    gl_Position = vertex;
}

#endif

#ifdef _FRAGMENT_

in vec2 st;
layout(location=0) out vec4 data;

const mat4 slopexMatrix[4] = mat4[4]  (
    mat4(0.0, 0.0, 0.0, 0.0,
         1.0, 0.0, -1.0, 0.0,
         0.0, 0.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.0, 0.0, 0.0,
         0.5, 0.5, -0.5, -0.5,
         0.0, 0.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.0, 0.0, 0.0,
         0.5, 0.0, -0.5, 0.0,
         0.5, 0.0, -0.5, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.0, 0.0, 0.0,
         0.25, 0.25, -0.25, -0.25,
         0.25, 0.25, -0.25, -0.25,
         0.0, 0.0, 0.0, 0.0)
);

const mat4 slopeyMatrix[4] = mat4[4]  (
    mat4(0.0, 1.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0,
         0.0, -1.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.5, 0.5, 0.0,
         0.0, 0.0, 0.0, 0.0,
         0.0, -0.5, -0.5, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.5, 0.0, 0.0,
         0.0, 0.5, 0.0, 0.0,
         0.0, -0.5, 0.0, 0.0,
         0.0, -0.5, 0.0, 0.0),
    mat4(0.0, 0.25, 0.25, 0.0,
         0.0, 0.25, 0.25, 0.0,
         0.0, -0.25, -0.25, 0.0,
         0.0, -0.25, -0.25, 0.0)
);

const mat4 curvatureMatrix[4] = mat4[4]  (
    mat4(0.0, -1.0, 0.0, 0.0,
         -1.0, 4.0, -1.0, 0.0,
         0.0, -1.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, -0.5, -0.5, 0.0,
         -0.5, 1.5, 1.5, -0.5,
         0.0, -0.5, -0.5, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, -0.5, 0.0, 0.0,
         -0.5, 1.5, -0.5, 0.0,
         -0.5, 1.5, -0.5, 0.0,
         0.0, -0.5, 0.0, 0.0),
    mat4(0.0, -0.25, -0.25, 0.0,
         -0.25, 0.5, 0.5, -0.25,
         -0.25, 0.5, 0.5, -0.25,
         0.0, -0.25, -0.25, 0.0)
);

mat4 upsampleMatrix[4] = mat4[4]  (
    mat4(0.0, 0.0, 0.0, 0.0,
         0.0, 1.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, 0.0, 0.0, 0.0,
         -1.0/16.0, 9.0/16.0, 9.0/16.0, -1.0/16.0,
         0.0, 0.0, 0.0, 0.0,
         0.0, 0.0, 0.0, 0.0),
    mat4(0.0, -1.0/16.0, 0.0, 0.0,
         0.0, 9.0/16.0, 0.0, 0.0,
         0.0, 9.0/16.0, 0.0, 0.0,
         0.0, -1.0/16.0, 0.0, 0.0),
    mat4(1.0/256.0, -9.0/256.0, -9.0/256.0, 1.0/256.0,
         -9.0/256.0, 81.0/256.0, 81.0/256.0, -9.0/256.0,
         -9.0/256.0, 81.0/256.0, 81.0/256.0, -9.0/256.0,
         1.0/256.0, -9.0/256.0, -9.0/256.0, 1.0/256.0)
);

float mdot(mat4 a, mat4 b) {
    return dot(a[0], b[0]) + dot(a[1], b[1]) + dot(a[2], b[2]) + dot(a[3], b[3]);
}

void main() {
    vec2 p_uv = floor(st) * 0.5;

    vec2 residual_uv = p_uv * residualOSH.z + residualOSH.xy;
    float zf = residualOSH.w * textureLod(residualSampler, residual_uv, 0.0).x;

    vec2 offset = (p_uv - fract(p_uv) + vec2(0.5)) * coarseLevelOSL.z + coarseLevelOSL.xy;
    mat4 cz = mat4(
        textureLod(coarseLevelSampler, vec3(offset + vec2(0.0, 0.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(1.0, 0.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(2.0, 0.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(3.0, 0.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(0.0, 1.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(1.0, 1.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(2.0, 1.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(3.0, 1.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(0.0, 2.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(1.0, 2.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(2.0, 2.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(3.0, 2.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(0.0, 3.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(1.0, 3.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(2.0, 3.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x,
        textureLod(coarseLevelSampler, vec3(offset + vec2(3.0, 3.0) * coarseLevelOSL.z, coarseLevelOSL.w), 0.0).x
    );

    int i = int(dot(fract(p_uv), vec2(2.0, 4.0)));
    vec3 n = vec3(mdot(cz, slopexMatrix[i]), mdot(cz, slopeyMatrix[i]), 2.0 * tileWSDF.y);
    float slope = length(n.xy) / n.z;
    float curvature = mdot(cz, curvatureMatrix[i]) / tileWSDF.y;
    float noiseAmp = max(clamp(4.0 * curvature, 0.0, 1.5), clamp(2.0 * slope - 0.5, 0.1, 4.0));

    vec2 nuv = (floor(st) + vec2(0.5)) / tileWSDF.x;
    vec4 uvs = vec4(nuv, vec2(1.0) - nuv);
    float noise = textureLod(noiseSampler, vec3(uvs[int(noiseUVLH.x)], uvs[int(noiseUVLH.y)], noiseUVLH.z), 0.0).x;
    if (noiseUVLH.w < 0.0) {
        zf -= noiseUVLH.w * noise;
    } else {
        zf += noiseAmp * noiseUVLH.w * noise;
    }

    float zc = zf;
    if (coarseLevelOSL.x != -1.0) {
        zf = zf + mdot(cz, upsampleMatrix[i]);

        vec2 ij = floor(st - vec2(BORDER));
        vec4 uvc = vec4(BORDER + 0.5) + tileWSDF.z * floor((ij / (2.0 * tileWSDF.z)).xyxy + vec4(0.5, 0.0, 0.0, 0.5));
        float zc1 = textureLod(coarseLevelSampler, vec3(uvc.xy * coarseLevelOSL.z, 0.0) + coarseLevelOSL.xyw, 0.0).z;
        float zc3 = textureLod(coarseLevelSampler, vec3(uvc.zw * coarseLevelOSL.z, 0.0) + coarseLevelOSL.xyw, 0.0).z;
        if (tileWSDF.w > 0.0 && all(equal(mod(ij, 2.0 * tileWSDF.z), vec2(tileWSDF.z)))) {
            float zc0 = textureLod(coarseLevelSampler, vec3(uvc.zy * coarseLevelOSL.z, 0.0) + coarseLevelOSL.xyw, 0.0).z;
            float zc2 = textureLod(coarseLevelSampler, vec3(uvc.xw * coarseLevelOSL.z, 0.0) + coarseLevelOSL.xyw, 0.0).z;
            zc = (zc3 + zc1 >= zc0 + zc2 ? zc1 + zc3 : zc0 + zc2) * 0.5;
        } else {
            zc = (zc1 + zc3) * 0.5;
        }
    }

#ifdef NO_CLAMP
    data = vec4(zf, zc, zf, 0.0);
#else
    data = vec4(zf, zc, max(zf, 0.0), 0.0);
#endif
}

#endif
