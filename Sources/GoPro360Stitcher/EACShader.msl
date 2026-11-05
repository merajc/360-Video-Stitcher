#include <metal_stdlib>
using namespace metal;

// 3D rotation matrix builder
float3x3 eulerToRotationMatrix(float3 euler) {
    float cX = cos(euler.x); float sX = sin(euler.x);
    float cY = cos(euler.y); float sY = sin(euler.y);
    float cZ = cos(euler.z); float sZ = sin(euler.z);

    float3x3 rX = float3x3(float3(1, 0, 0), float3(0, cX, -sX), float3(0, sX, cX));
    float3x3 rY = float3x3(float3(cY, 0, -sY), float3(0, 1, 0), float3(sY, 0, cY)); // Inverted Y rotation for left-handed Pan
    float3x3 rZ = float3x3(float3(cZ, -sZ, 0), float3(sZ, cZ, 0), float3(0, 0, 1));

    return rZ * rX * rY;
}

struct EACResult {
    float2 uv;
    bool isTrack2;
    float faceWeight;
};

// Rotations
float2 rotate_cube_face(float2 uv, int rotation) {
    float2 ret_uv;
    switch (rotation) {
        case 0: ret_uv = uv; break;
        case 1: ret_uv = float2(-uv.y, uv.x); break;
        case 2: ret_uv = float2(-uv.x, -uv.y); break;
        case 3: ret_uv = float2(uv.y, -uv.x); break;
        default: ret_uv = uv; break;
    }
    return ret_uv;
}

// Maps a world direction to the correct texture track and UV coordinate
EACResult worldDirToEAC(float3 dir) {
    float3 aDir = abs(dir);
    float2 uv;
    int u_face = 0;
    int v_face = 0;
    int rot = 0;

    // Exact gopromax.cl coordinate mapping logic
    if (aDir.z >= aDir.x && aDir.z >= aDir.y) {
        if (dir.z > 0.0) {
            // FRONT
            uv.x = dir.x / dir.z;
            uv.y = dir.y / dir.z;
            u_face = 1; v_face = 0; rot = 0;
        } else {
            // BACK
            uv.x = dir.x / dir.z;
            uv.y = -dir.y / dir.z;
            u_face = 1; v_face = 1; rot = 1; // ROT_90
        }
    } else if (aDir.y >= aDir.x && aDir.y >= aDir.z) {
        if (dir.y < 0.0) {
            // UP (Mapped to GoPro's u_face=2)
            uv.x = -dir.x / dir.y;
            uv.y = -dir.z / dir.y;
            u_face = 2; v_face = 1; rot = 3; // ROT_270
        } else {
            // DOWN (Mapped to GoPro's u_face=0)
            uv.x = dir.x / dir.y;
            uv.y = -dir.z / dir.y;
            u_face = 0; v_face = 1; rot = 3; // ROT_270
        }
    } else {
        if (dir.x > 0.0) {
            // RIGHT
            uv.x = -dir.z / dir.x;
            uv.y = dir.y / dir.x;
            u_face = 2; v_face = 0; rot = 0;
        } else {
            // LEFT
            uv.x = -dir.z / dir.x;
            uv.y = -dir.y / dir.x;
            u_face = 0; v_face = 0; rot = 0;
        }
    }

    // Apply rotation for this specific face
    uv = rotate_cube_face(uv, rot);

    // Equi-Angular Unwarp
    const float PI = 3.14159265359;
    uv.x = (2.0 / PI) * atan(uv.x) + 0.5;
    uv.y = (2.0 / PI) * atan(uv.y) + 0.5;

    // Map to 3x1 seamless strip
    float u_pad = 2.0 / 3968.0;
    float v_pad = 2.0 / 1344.0;
    
    float strip_u = (uv.x + float(u_face)) * (1.0 - 2.0 * u_pad) / 3.0 + u_pad;
    float strip_v = uv.y * (1.0 - 2.0 * v_pad) + v_pad;

    // Apply GoPro MAX overlapping (64px overlap at cut 688 and 3280 in the 3968px seamless width)
    float un_x = strip_u * 3968.0;
    float src_x;
    if (un_x < 688.0) {
        src_x = un_x;
    } else if (un_x < (3968.0 - 688.0)) {
        src_x = un_x + 64.0;
    } else {
        src_x = un_x + 128.0;
    }
    
    EACResult res;
    res.uv = float2(src_x / 4096.0, strip_v);
    res.isTrack2 = (v_face == 1);
    res.faceWeight = 1.0; 
    return res;
}

kernel void renderStackedView(texture2d<float, access::sample> track0 [[texture(0)]],
                            texture2d<float, access::sample> track1 [[texture(1)]],
                            texture2d<float, access::write> outTexture [[texture(2)]],
                            constant float4& topParams [[buffer(0)]],
                            constant float4& bottomParams [[buffer(1)]],
                            constant float4& flipFlags [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]]) {
                            
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float width = outTexture.get_width();
    float height = outTexture.get_height();
    float midY = height / 2.0;
    
    bool isBottom = gid.y >= midY;
    float localY = isBottom ? gid.y - midY : gid.y;
    float4 params = isBottom ? bottomParams : topParams;
    
    // flipFlags: x=topFlipH, y=topFlipV, z=bottomFlipH, w=bottomFlipV
    bool flipH = isBottom ? (flipFlags.z > 0.5) : (flipFlags.x > 0.5);
    bool flipV = isBottom ? (flipFlags.w > 0.5) : (flipFlags.y > 0.5);
    
    float3 userEuler = params.xyz;
    float fov = params.w;
    
    // Normalized device coordinates (-1 to 1)
    float2 uv = float2(gid.x, localY) / float2(width, midY) * 2.0 - 1.0;
    uv.y = -uv.y;
    
    // Apply per-axis flip
    if (flipH) uv.x = -uv.x;
    if (flipV) uv.y = -uv.y;
    
    float windowAspect = width / midY;
    uv.x *= windowAspect;
    
    // Raycasting for perspective projection (inside the sphere)
    float targetZ = 1.0 / max(0.01, tan(fov * 0.5));
    float3 rayDir = normalize(float3(uv.x, uv.y, targetZ));
    
    float3x3 userRot = eulerToRotationMatrix(userEuler);
    float3 worldDir = userRot * rayDir;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    EACResult result = worldDirToEAC(worldDir);
    float4 color;
    
    if (result.isTrack2) {
        color = track1.sample(s, result.uv);
    } else {
        color = track0.sample(s, result.uv);
    }
    
    // Split line
    if (abs(float(gid.y) - midY) < 1.5) {
        color = float4(0.05, 0.05, 0.05, 1.0);
    }
    
    outTexture.write(color, gid);
}
