#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

struct ViewportUniforms {
    float2 viewportScale;
    float2 viewportOffset;
    uint scalingMode; // 0 = Nearest (Retro crisp), 1 = Bilinear (Smooth), 2 = CRT Scanline
    float crtIntensity;
};

// MARK: - Vertex Shader
vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant float4* vertices [[buffer(0)]],
                              constant ViewportUniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    // Quad vertices: (posX, posY, texU, texV)
    float4 v = vertices[vertexID];
    
    // Position mapped to normalized device coordinates [-1.0, 1.0] with aspect fit scaling
    float2 transformedPos = v.xy * uniforms.viewportScale + uniforms.viewportOffset;
    out.position = float4(transformedPos, 0.0, 1.0);
    out.texCoords = v.zw;
    return out;
}

// MARK: - Fragment Shader
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> guestTexture [[texture(0)]],
                               sampler nearestSampler [[sampler(0)]],
                               sampler linearSampler [[sampler(1)]],
                               constant ViewportUniforms& uniforms [[buffer(1)]]) {
    float4 color;
    
    if (uniforms.scalingMode == 0) {
        // Crisp Nearest Neighbor (Authentic AoE2 1999 pixel rendering)
        color = guestTexture.sample(nearestSampler, in.texCoords);
    } else if (uniforms.scalingMode == 1) {
        // High quality Bilinear
        color = guestTexture.sample(linearSampler, in.texCoords);
    } else {
        // Retro CRT with subtle scanlines
        color = guestTexture.sample(linearSampler, in.texCoords);
        float scanline = sin(in.position.y * 3.14159265 * 1.5) * 0.5 + 0.5;
        color.rgb *= mix(1.0, (1.0 - uniforms.crtIntensity * (1.0 - scanline)), 0.5);
    }
    
    return color;
}
