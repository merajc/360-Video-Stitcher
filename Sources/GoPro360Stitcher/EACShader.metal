#include <metal_stdlib>
using namespace metal;

// 3D rotation matrix builder
float3x3 eulerToRotationMatrix(float3 euler) {
    float cX = cos(euler.x);
    float sX = sin(euler.x);
    float cY = cos(euler.y);
    float sY = sin(euler.y);
    float cZ = cos(euler.z);
    float sZ = sin(euler.z);

    float3x3 rX = float3x3(float3(1, 0, 0), float3(0, cX, -sX), float3(0, sX, cX));
    float3x3 rY = float3x3(float3(cY, 0, sY), float3(0, 1, 0), float3(-sY, 0, cY));
    float3x3 rZ = float3x3(float3(cZ, -sZ, 0), float3(sZ, cZ, 0), float3(0, 0, 1));

    return rZ * rX * rY;
}

// GoPro MAX EAC Mapping Constants
// Typically stored in two 3x1 strips (total 3x2)
float2 dirToEAC(float3 dir) {
    float3 aDir = abs(dir);
    float2 uv;
    int faceIndex = 0;

    // Standard Cube Mapping to face selection
    if (aDir.x >= aDir.y && aDir.x >= aDir.z) {
        faceIndex = dir.x > 0.0 ? 0 : 1;
        uv = float2(dir.x > 0.0 ? -dir.z : dir.z, dir.y) / aDir.x;
    } else if (aDir.y >= aDir.x && aDir.y >= aDir.z) {
        faceIndex = dir.y > 0.0 ? 2 : 3;
        uv = float2(dir.x, dir.y > 0.0 ? dir.z : -dir.z) / aDir.y;
    } else {
        faceIndex = dir.z > 0.0 ? 4 : 5;
        uv = float2(dir.x, -dir.y) / aDir.z;
    }

    // Equi-Angular Warp (Core of EAC)
    const float PI = 3.14159265359;
    uv = (2.0 / PI) * atan(uv);
    uv = uv * 0.5 + 0.5; // Map to 0...1 within face

    // Map to 3x2 atlas
    float col = float(faceIndex % 3);
    float row = float(faceIndex / 3);
    return (uv + float2(col, row)) / float2(3.0, 2.0);
}

kernel void renderStackedView(texture2d<float, access::sample> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            constant float3& userEuler [[buffer(0)]],
                            constant float& fov [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
                           
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float width = outTexture.get_width();
    float height = outTexture.get_height();
    float midY = height / 2.0;
    
    // Determine if we are in the Top half (Front) or Bottom half (Rear)
    bool isRear = gid.y >= midY;
    float localY = isRear ? gid.y - midY : gid.y;
    
    // Normalize coordinates for the specific viewport
    float2 uv = float2(gid.x, localY) / float2(width, midY) * 2.0 - 1.0;
    uv.y = -uv.y;
    
    float aspect = width / midY;
    uv.x *= aspect;
    
    // Compute focal length from FOV
    float z = 1.0 / tan(fov * 0.5);
    float3 dir = normalize(float3(uv.x, uv.y, -z));
    
    // Framing Rotations
    float3x3 userRot = eulerToRotationMatrix(userEuler);
    dir = userRot * dir;
    
    // Apply 180 degree flip for the rear view
    if (isRear) {
        float3x3 rearFlip = eulerToRotationMatrix(float3(0, M_PI_F, 0));
        dir = rearFlip * dir;
    }
    
    // Map to EAC Atlas
    float2 eacUV = dirToEAC(dir);
    
    // Sample with bi-linear filtering
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = inTexture.sample(s, eacUV);
    
    // Apply a subtle separator line if exactly at midY
    if (abs(float(gid.y) - midY) < 1.0) {
        color = float4(0.2, 0.2, 0.2, 1.0);
    }
    
    outTexture.write(color, gid);
}
