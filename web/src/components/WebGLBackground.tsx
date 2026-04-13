"use client";

import { useRef, useMemo } from "react";
import { Canvas, useFrame, extend } from "@react-three/fiber";
import * as THREE from "three";

// ---------------------------------------------------------------------------
// Custom shader material for the animated gradient mesh
// ---------------------------------------------------------------------------

const vertexShader = /* glsl */ `
  uniform float uTime;
  uniform float uAmplitude;
  uniform float uFrequency;
  varying vec2 vUv;
  varying float vElevation;

  //
  // Simplex-style 3D noise (compact GLSL implementation)
  //
  vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec4 permute(vec4 x) { return mod289(((x * 34.0) + 10.0) * x); }
  vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

  float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g  = step(x0.yzx, x0.xyz);
    vec3 l  = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
              i.z + vec4(0.0, i1.z, i2.z, 1.0))
            + i.y + vec4(0.0, i1.y, i2.y, 1.0))
            + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j  = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x  = x_ * ns.x + ns.yyyy;
    vec4 y  = y_ * ns.x + ns.yyyy;
    vec4 h  = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(
      dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)
    ));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(0.6 - vec4(
      dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)
    ), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(
      dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)
    ));
  }

  void main() {
    vUv = uv;

    // Layer multiple octaves of noise for organic, flowing distortion
    float slowTime = uTime * 0.15;
    float noise1 = snoise(vec3(position.x * uFrequency, position.y * uFrequency, slowTime));
    float noise2 = snoise(vec3(
      position.x * uFrequency * 2.0 + 100.0,
      position.y * uFrequency * 2.0 + 100.0,
      slowTime * 1.3
    )) * 0.5;
    float noise3 = snoise(vec3(
      position.x * uFrequency * 0.5 + 200.0,
      position.y * uFrequency * 0.5 + 200.0,
      slowTime * 0.7
    )) * 0.3;

    float elevation = (noise1 + noise2 + noise3) * uAmplitude;
    vElevation = elevation;

    vec3 newPos = position;
    newPos.z += elevation;

    gl_Position = projectionMatrix * modelViewMatrix * vec4(newPos, 1.0);
  }
`;

const fragmentShader = /* glsl */ `
  uniform float uTime;
  uniform vec3 uColorA;    // Brand orange   #FF9230
  uniform vec3 uColorB;    // Warm coral     #FFAB58
  uniform vec3 uColorC;    // Amber          #FFC580
  uniform vec3 uColorD;    // Soft peach     #FFDDB3
  uniform float uOpacity;
  varying vec2 vUv;
  varying float vElevation;

  void main() {
    float slowTime = uTime * 0.1;

    // Blend factor from UV + elevation for organic color mixing
    float mixA = vUv.x + sin(slowTime + vUv.y * 3.0) * 0.15;
    float mixB = vUv.y + cos(slowTime * 0.8 + vUv.x * 2.5) * 0.2;

    // Remap elevation from [-1,1] to [0,1] range for color mixing
    float elevNorm = (vElevation + 1.0) * 0.5;

    // Four-way gradient blend driven by UV position, elevation, and time
    vec3 gradAB = mix(uColorA, uColorB, smoothstep(0.2, 0.8, mixA));
    vec3 gradCD = mix(uColorC, uColorD, smoothstep(0.3, 0.7, mixA + elevNorm * 0.3));
    vec3 finalColor = mix(gradAB, gradCD, smoothstep(0.25, 0.75, mixB));

    // Add a subtle highlight shimmer at elevated peaks
    float shimmer = smoothstep(0.55, 0.85, elevNorm) * 0.15;
    finalColor += shimmer;

    // Bottom-edge fade to white: linearly ramp alpha toward bottom
    float bottomFade = smoothstep(0.0, 0.35, vUv.y);
    vec3 white = vec3(1.0);
    finalColor = mix(white, finalColor, bottomFade);

    gl_FragColor = vec4(finalColor, uOpacity * bottomFade + uOpacity * (1.0 - bottomFade) * 0.6);
  }
`;

// ---------------------------------------------------------------------------
// Hex color string to THREE.Color helper
// ---------------------------------------------------------------------------

function hexToVec3(hex: string): THREE.Color {
  return new THREE.Color(hex);
}

// ---------------------------------------------------------------------------
// Animated gradient mesh (inner scene component)
// ---------------------------------------------------------------------------

function GradientMesh() {
  const meshRef = useRef<THREE.Mesh>(null);

  const uniforms = useMemo(
    () => ({
      uTime: { value: 0 },
      uAmplitude: { value: 0.35 },
      uFrequency: { value: 0.8 },
      uColorA: { value: hexToVec3("#FF9230") }, // Brand orange
      uColorB: { value: hexToVec3("#FFAB58") }, // Warm coral
      uColorC: { value: hexToVec3("#FFC580") }, // Amber
      uColorD: { value: hexToVec3("#FFDDB3") }, // Soft peach
      uOpacity: { value: 0.85 },
    }),
    []
  );

  // Advance time uniform every frame
  useFrame((_state, delta) => {
    uniforms.uTime.value += delta;
  });

  return (
    <mesh ref={meshRef} rotation={[-Math.PI * 0.15, 0, 0]} position={[0, 0, -1]}>
      {/*
        PlaneGeometry with 48x48 segments -- enough for smooth noise
        displacement without being expensive. The plane is oversized (8x6)
        so it fills the viewport after the slight tilt.
      */}
      <planeGeometry args={[8, 6, 48, 48]} />
      <shaderMaterial
        vertexShader={vertexShader}
        fragmentShader={fragmentShader}
        uniforms={uniforms}
        transparent
        side={THREE.DoubleSide}
        depthWrite={false}
      />
    </mesh>
  );
}

// ---------------------------------------------------------------------------
// Public component: full-viewport Canvas wrapper
// ---------------------------------------------------------------------------

export default function WebGLBackground() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed inset-0 -z-10 h-full w-full"
    >
      <Canvas
        // Flat (no tone-mapping) to preserve our exact shader colors
        flat
        // Lower DPR cap for performance on retina screens
        dpr={[1, 1.5]}
        // Orthographic camera keeps the plane filling the viewport
        // regardless of aspect ratio changes
        camera={{ position: [0, 0, 3], fov: 50, near: 0.1, far: 10 }}
        gl={{
          alpha: true,
          antialias: false,
          powerPreference: "low-power",
          // Preserve drawing buffer not needed -- saves memory
          preserveDrawingBuffer: false,
        }}
        style={{ background: "transparent" }}
      >
        <GradientMesh />
      </Canvas>

      {/*
        CSS gradient overlay that reinforces the bottom fade-to-white,
        ensuring content readability regardless of WebGL render state.
      */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "linear-gradient(to bottom, transparent 50%, rgba(255,255,255,0.7) 80%, rgba(255,255,255,1) 100%)",
          pointerEvents: "none",
        }}
      />
    </div>
  );
}
