// "Warp speed" style of the native screen saver: hand-written Metal, not
// shared with the app (unlike the impellerc-generated styles), because it
// needs two passes and a texture:
//
//   0. backdropFragment - a distant, stationary nebula at full resolution,
//      rendered once into a texture (not every frame): domain-warped fBm,
//      filaments, dust lanes, distant stars. Visible in cruise only. The
//      stars twinkle: the pass also stores, per pixel, which star dominates
//      it (its rhythm) and how much of the light is starlight.
//   1. nebulaFragment - gas clouds at a quarter of the resolution into a
//      texture: value-noise fBm in log-polar coordinates flowing outward,
//      sampled on a cylinder so it is seamless around the center; far
//      clouds, and in cruise a faint near layer streaming past with the
//      stars.
//   2. warpFragment - the gas, blurred along the radius (motion blur), plus
//      the stars: soft capsules on a scrolling log-polar grid (like
//      Hyperspace), with size, brightness and tint varying per star, a few
//      bright flare stars, a layer of thin, faint speed lines, and now and
//      then a lens flare (one warm star with an anamorphic streak). At warp
//      the previous frame is blended in (temporal feedback): it writes the
//      drawable and a history texture, and reads last frame's history.
//
// Cruise and warp come from the same JumpCycle as Hyperspace: `travel`
// (speed) and `blur` / `lines` (the stretch) change, the shader does not.
//
// Coordinates: `uv` 0..1 over the view, y down; positions in logical pixels.

#include <metal_stdlib>
using namespace metal;

struct WarpUniforms {
  float2 size;      // logical pixels
  float travel;     // distance travelled, in rho at layer speed 1
  float density;    // probability that a star cell holds a star
  float nebula;     // gas cloud brightness
  float emerge;     // 1: stars emerge small and faint from the center
  float blur;       // motion blur: 0 (cruise, short tails) .. 1 (warp)
  float lines;      // speed line brightness: 0 (cruise) .. 1 (warp)
  float cloudTravel;  // the clouds' own travel (integrated on the CPU)
  float tunnel;     // clouds: 0 far away (cruise) .. 1 travelling through (warp)
  float feedbackDecay;  // previous frame's weight: 0 (cruise, no feedback) .. <1 (warp)
  float feedbackZoom;   // previous frame sampled at this scale towards the center (<= 1)
  float2 lensPos;       // lens flare (WarpLensFlare.swift): its head, logical pixels
  float2 lensDir;       // outward, unit
  float lensRho;        // its head's rho
  float lensSize;       // core radius, logical pixels
  float lensBright;     // 0: none
  float lensFlicker;    // ~0.7..1.3, changing fast
  float lensStreaks;    // streak strength: 1 at warp .. faint in cruise
  float seed;           // per display: its own stars and clouds (0..100)
  float colorTime;      // the clouds' color drift clock (fast at warp)
  float nearTravel;     // the near clouds' travel: the stars' (integrated on the CPU)
  float4 cloudColors[3];  // the biome (WarpBiomes.swift): base, second, accent
  float backdrop;       // the backdrop's brightness (0: off)
  float backdropZoom;   // drift with jumps off: the backdrop magnified (>= 1) ...
  float backdropNextZoom;  // ... the next layout's ...
  float backdropMix;    // ... cross-fading in (0: none)
  float twinkleTime;    // seconds
  float padding4;
  float padding5;
  float padding6;
};

struct FullScreenOut {
  float4 position [[position]];
  float2 uv;
};

vertex FullScreenOut warpVertex(uint id [[vertex_id]]) {
  float2 uv = float2((id << 1) & 2, id & 2);
  FullScreenOut out;
  out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
  out.uv = float2(uv.x, 1.0 - uv.y);
  return out;
}

constant float kTwoPi = 6.28318530718;

// --- Hashes and noise ----------------------------------------------------

static float3 hash34(float4 p) {
  float4 p4 = fract(p * float4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

static float hash31(float3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

static float valueNoise(float3 x) {
  float3 i = floor(x);
  float3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  float n000 = hash31(i), n100 = hash31(i + float3(1, 0, 0));
  float n010 = hash31(i + float3(0, 1, 0)), n110 = hash31(i + float3(1, 1, 0));
  float n001 = hash31(i + float3(0, 0, 1)), n101 = hash31(i + float3(1, 0, 1));
  float n011 = hash31(i + float3(0, 1, 1)), n111 = hash31(i + float3(1, 1, 1));
  return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
             mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

static float fbm(float3 x) {
  float sum = 0.0, amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    sum += amplitude * valueNoise(x);
    x = x * 2.03 + 17.1;
    amplitude *= 0.5;
  }
  return sum;
}

// Polar position of a logical pixel: direction, distance (in units of the
// shortest side) and rho = ln(distance).
struct Polar {
  float2 dir;
  float r;
  float rho;
  float rPx;  // distance in logical pixels
};

static Polar polar(float2 p, float2 size) {
  float scale = min(size.x, size.y);
  float2 d = (p - size * 0.5) / scale;
  Polar result;
  result.r = max(length(d), 1e-5);
  result.dir = d / result.r;
  result.rho = log(result.r);
  result.rPx = result.r * scale;
  return result;
}

// --- Pass 1: gas clouds ----------------------------------------------------

fragment half4 nebulaFragment(FullScreenOut in [[stage_in]], constant WarpUniforms& u [[buffer(0)]]) {
  Polar q = polar(in.uv * u.size, u.size);
  // Radial coordinate. Cruise: sqrt(r) - far away, sizes growing only with
  // the square root of the distance (in rho they grow with it: too big at
  // the edges). Warp: rho - every cloud grows with its distance, as in a
  // tunnel: we travel through them. (Same scale around r = 0.3.)
  float radial = mix(3.6 * sqrt(q.r), q.rho + 2.4, u.tunnel);
  float flow = radial - u.cloudTravel;
  // On a cylinder (direction, flow): seamless around the center. The angular
  // frequency rises with r far away, so arcs stay bounded; low frequency
  // along the flow stretches the clouds radially.
  // The display's seed shifts the whole noise field: its own clouds.
  float3 seedOffset = u.seed * float3(1.37, 2.11, 0.73);
  float3 x = float3(q.dir * 2.2 * mix(0.5 + 1.7 * q.r, 1.0, u.tunnel), flow * 0.85) + seedOffset;
  float clouds = fbm(x);
  float detail = fbm(x * 1.9 + float3(11.3, 4.1, 7.7));
  // Color drift, part 1: the hue field moves slowly through the noise, so
  // patches change color over a minute or two.
  float3 drift = float3(0.7, 0.4, 0.25) * (u.colorTime * 0.012);
  float hue = fbm(float3(q.dir * 0.9, flow * 0.3 + 5.0) + seedOffset + drift);

  // Dark in the middle, strongest at mid distance, fading towards the edges.
  // In cruise the clouds reach closer to the center (the far direction).
  float shape = smoothstep(mix(0.0, 0.06, u.tunnel), mix(0.2, 0.32, u.tunnel), q.r) *
                (1.0 - 0.55 * smoothstep(0.7, 1.4, q.r));
  float density = smoothstep(0.42, 0.82, clouds * 0.75 + detail * 0.35) * shape;

  // The biome's three colors: base and second by the hue field, the accent
  // in the fine detail and in the rare high-hue patches.
  float3 base = u.cloudColors[0].rgb;
  float3 second = u.cloudColors[1].rgb;
  float3 accent = u.cloudColors[2].rgb;
  // Color drift, part 2: the mood - how much of the second color and the
  // accent - follows slow waves (5, 7 and 11 minutes of the drift clock),
  // with phases of the display's own.
  float t = u.colorTime * kTwoPi;
  float secondBias = 0.08 * sin(t / 300.0 + u.seed);
  float detailAccent = 0.8 * (0.75 + 0.35 * sin(t / 420.0 + u.seed * 1.7));
  float hueAccent = 0.7 * (0.7 + 0.4 * sin(t / 660.0 + u.seed * 2.3));
  float3 color = mix(base, second, smoothstep(0.42 - secondBias, 0.6 - secondBias, hue));
  color = mix(color, accent, smoothstep(0.55, 0.72, detail) * detailAccent);
  color = mix(color, accent, smoothstep(0.66, 0.8, hue) * hueAccent);
  // In cruise at half strength, so the distant backdrop shows through; at
  // warp in full - they are the tunnel then.
  color *= density * u.nebula * mix(0.5, 1.0, u.tunnel);

  // Near clouds, in cruise: faint wisps we drift through - mapped like the
  // stars (rho: they grow as they come closer), stretched along the radius,
  // streaming outward with the stars' travel. One more fBm and a cheap
  // one-octave hue; the biome's colors. At warp the far clouds become the
  // tunnel, so these fade out with it.
  float nearAmount = 1.0 - u.tunnel;
  if (nearAmount > 0.0) {
    float nearFlow = q.rho - u.nearTravel;
    float3 xn = float3(q.dir * 1.6, nearFlow * 0.55) + seedOffset * 1.3 + float3(31.7, 12.9, 4.3);
    float wisps = fbm(xn);
    // Like mist: thickest afar (light scattered through all of it), thin
    // when close and we are in it - emerging near the center, strongest
    // at mid distance, thinning to ~40 % at the edges (the long edges of a
    // 16:9 screen are at r ~0.9; to a fifth they all but vanished there).
    float mist = smoothstep(0.03, 0.15, q.r) * (1.0 - 0.6 * smoothstep(0.2, 1.0, q.r));
    float nearDensity = smoothstep(0.42, 0.72, wisps) * mist;
    float nearHue = valueNoise(xn * 0.6 + drift + float3(5.1, 9.3, 2.7));
    float3 nearColor = mix(base, second, smoothstep(0.35, 0.65, nearHue));
    nearColor = mix(nearColor, accent, smoothstep(0.72, 0.9, wisps) * 0.5);
    color += nearColor * nearDensity * 0.5 * nearAmount;
  }
  return half4(half3(color), 1.0h);
}

// --- Pass 0: the backdrop, rendered once ----------------------------------

static float3 starTint(float h);  // the stars' tints (pass 2)

// Distant stars on a fixed grid (logical pixels): one candidate per cell,
// at a hashed spot, kept inside the cell's middle so `reach` neighbour cells
// cover its light. `level` keys the hash per population.
struct StarField {
  float cell;      // logical pixels
  float chance;    // probability that a cell holds a star
  int reach;       // neighbour cells checked: 0 (own) or 1 (3x3)
  float level;
};

// A population's light at a pixel, and its brightest star there: how bright,
// and a code (0..1) its twinkle rhythm comes from.
struct StarLight {
  float3 light;
  float peak;
  float code;
};

static StarLight distantStars(float2 px, StarField f, float seed) {
  StarLight result = {float3(0.0), 0.0, 0.0};
  float2 base = floor(px / f.cell);
  for (int dy = -f.reach; dy <= f.reach; dy++) {
    for (int dx = -f.reach; dx <= f.reach; dx++) {
      float2 c = base + float2(dx, dy);
      float3 h = hash34(float4(c, f.level, 61.0 + seed));
      if (h.x >= f.chance) continue;
      float3 h2 = hash34(float4(c, f.level, 83.0 + seed));
      float2 v = px - (c + 0.25 + 0.5 * h.yz) * f.cell;
      float d2 = dot(v, v);
      float3 tint = starTint(fract(h2.y * 7.3 + h2.z * 3.1));
      float light;
      if (f.level < 1.5) {
        // Faint field: tiny points, mostly very faint.
        light = (0.04 + 0.4 * pow(h2.x, 4.0)) * exp(-d2 / 0.45);
      } else if (f.level < 2.5) {
        // Brighter stars: a small core and a faint glow.
        float size = 0.6 + 1.1 * pow(h2.x, 3.0);
        light = (0.2 + 0.55 * h2.z * h2.z) * (exp(-d2 / (size * size)) + 0.15 * exp(-d2 / (size * size * 16.0)));
      } else {
        // Flare stars: the flare formula (core and halo) and a faint
        // four-point diffraction cross, as in astrophotos.
        float core = 1.0 + 1.6 * h2.x;
        float halo = core * 5.0;
        float glow = 1.6 * exp(-d2 / (core * core)) + 0.35 * exp(-d2 / (halo * halo));
        float thickness2 = pow(0.45 + 0.15 * core, 2.0);
        float spikeReach = 9.0 * core;
        float spikes = exp(-v.y * v.y / thickness2) * exp(-abs(v.x) / spikeReach) +
                       exp(-v.x * v.x / thickness2) * exp(-abs(v.y) / spikeReach);
        light = (0.45 + 0.45 * h2.z) * (glow + 0.35 * spikes);
      }
      result.light += tint * light;
      if (light > result.peak) {
        result.peak = light;
        result.code = fract(h.y * 9.1 + h.z * 4.7 + h2.x * 3.3);
      }
    }
  }
  return result;
}

struct BackdropOut {
  half4 color [[color(0)]];  // the nebula and its distant stars
  half2 twinkle [[color(1)]];  // the dominant star's code, the starlight's share
};

static float fbmDetail(float3 x) {
  float sum = 0.0, amplitude = 0.5;
  for (int i = 0; i < 7; i++) {
    sum += amplitude * valueNoise(x);
    x = x * 2.03 + 17.1;
    amplitude *= 0.5;
  }
  return sum;
}

// A distant nebula, infinitely far away: plain screen coordinates (no
// travel, no perspective), so it stays put while everything else streams
// past. Too costly per frame at full resolution - so it is rendered once
// into a texture and only sampled per frame, and can afford detail: domain
// warping (noise bending noise: tendrils and filaments), ridges of the warp
// field as bright filaments, dark dust lanes, and a large-scale mask so
// dark sky remains between the clouds.
fragment BackdropOut backdropFragment(FullScreenOut in [[stage_in]], constant WarpUniforms& u [[buffer(0)]]) {
  float scale = min(u.size.x, u.size.y);
  float2 p = (in.uv * u.size - u.size * 0.5) / scale;  // shortest side = 1
  float3 s = u.seed * float3(0.71, 1.13, 0.37) + float3(41.0, 7.0, 19.0);
  float2 x = p * 1.6;
  float2 warp1 = float2(fbmDetail(float3(x, 0.0) + s), fbmDetail(float3(x + float2(5.2, 1.3), 0.0) + s));
  float2 warp2 = float2(fbmDetail(float3(x + 4.0 * warp1 + float2(1.7, 9.2), 1.0) + s),
                        fbmDetail(float3(x + 4.0 * warp1 + float2(8.3, 2.8), 1.0) + s));
  float n = fbmDetail(float3(x + 4.0 * warp2, 2.0) + s);

  float region = smoothstep(0.4, 0.62, fbm(float3(p * 0.8, 3.0) + s));  // where the nebula is
  float density = smoothstep(0.35, 0.8, n) * region;
  float ridge = 1.0 - abs(2.0 * warp2.x - 1.0);
  float filaments = pow(ridge, 8.0) * smoothstep(0.3, 0.6, n) * region;
  float dust = smoothstep(0.52, 0.72, fbmDetail(float3(x * 1.7 + 3.0 * warp1, 4.0) + s));

  float3 base = u.cloudColors[0].rgb;
  float3 second = u.cloudColors[1].rgb;
  float3 accent = u.cloudColors[2].rgb;
  float3 color = mix(base, second, smoothstep(0.35, 0.65, warp1.y));
  color = mix(color, accent, smoothstep(0.55, 0.8, warp2.y) * 0.7);
  float3 light = color * density + mix(second, accent, 0.5) * filaments * 0.8;

  // Distant stars: a faint field, brighter stars, a few flare stars with
  // diffraction crosses - fainter than the moving stars; the dust lanes
  // dim them too.
  float2 px = in.uv * u.size;
  StarLight faint = distantStars(px, StarField{7.0, 0.3, 0, 1.0}, u.seed);
  StarLight bright = distantStars(px, StarField{36.0, 0.45, 1, 2.0}, u.seed);
  StarLight flares = distantStars(px, StarField{150.0, 0.3, 1, 3.0}, u.seed);
  float3 stars = (faint.light + bright.light + flares.light) * 0.8;
  // Twinkle, baked: which star dominates this pixel (its rhythm, played in
  // the composite) and how much of the pixel is starlight - so only the
  // stars shimmer, each in its own rhythm, and the nebula stays put.
  StarLight top = faint.peak > bright.peak ? faint : bright;
  top = flares.peak > top.peak ? flares : top;
  float starLum = dot(stars, float3(0.3, 0.5, 0.2));
  float share = starLum / max(starLum + dot(light, float3(0.3, 0.5, 0.2)), 1e-4);
  light = (light + stars) * (1.0 - 0.75 * dust);
  BackdropOut out;
  out.color = half4(half3(light), 1.0h);
  out.twinkle = half2(top.code, share);
  return out;
}

// --- Pass 2: composite -----------------------------------------------------

// Star layers: outward speed (rho per unit of travel), angular columns,
// row height in rho, motion-blur length in rho, size factor.
constant int kStarLayers = 5;
constant float kStarSpeed[kStarLayers] = {0.45, 0.65, 0.9, 1.25, 1.7};
constant float kStarColumns = 360.0;  // few columns: room for big capsules
constant float kStarRow = 0.32;
constant float kStarBlur[kStarLayers] = {0.05, 0.07, 0.1, 0.14, 0.19};
constant float kStarSize[kStarLayers] = {0.55, 0.7, 0.9, 1.15, 1.5};
constant int kMaxRows = 5;
constant float kRowPeriod = 4096.0;

// Flare stars: sparse layers of big, bright stars at three speeds.
constant int kFlareLayers = 3;
constant float kFlareColumns = 40.0;
constant float kFlareRow = 0.6;
constant float kFlareSpeed[kFlareLayers] = {0.5, 0.8, 1.2};
constant float kFlareSize[kFlareLayers] = {0.65, 0.9, 1.2};
constant float kFlareDensity = 0.016;  // per layer; about as many as one layer at 0.045

// Speed lines: one sparse layer of thin, long, faint streaks.
constant float kLineSpeed = 2.2;
constant float kLineColumns = 1400.0;
constant float kLineRow = 0.45;
constant float kLineLength = 0.9;

struct WarpOut {
  half4 color [[color(0)]];    // the drawable
  half4 history [[color(1)]];  // read back next frame (the drawable can't be)
};

// A lens flare streak's falloff along its length: a bright inner part and a
// long faint reach.
static float streakProfile(float distance, float reach) {
  return 0.65 * exp(-distance / reach) + 0.35 * exp(-distance / (4.0 * reach));
}

// The backdrop at `uv`, magnified by its drift zoom, cross-fading into the
// next layout while one comes in (jumps off).
// The baked stars' twinkle: a slow shimmer in the rhythm of the pixel's
// dominant star (0.3-1.5 Hz, its own phase, a little uneven), on the
// starlight's share of the pixel only.
static float twinkleAt(texture2d<half> twinkle, float2 at, float time) {
  constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
  float2 t = float2(twinkle.sample(nearest, at).rg);
  float rate = 0.3 + 1.2 * fract(t.x * 13.7);
  float phase = 6.2832 * fract(t.x * 7.1);
  float wave = sin(6.2832 * rate * time + phase) * (0.6 + 0.4 * sin(6.2832 * rate * 0.37 * time + phase * 1.7));
  return 1.0 + 0.35 * wave * t.y;
}

static float3 skyAt(
  texture2d<half> current, texture2d<half> next, texture2d<half> twinkle, texture2d<half> nextTwinkle, float2 uv,
  constant WarpUniforms& u
) {
  constexpr sampler linear(filter::linear, address::clamp_to_edge);
  float2 center = float2(0.5);
  float2 at = center + (uv - center) / u.backdropZoom;
  float3 sky = float3(current.sample(linear, at).rgb) * twinkleAt(twinkle, at, u.twinkleTime);
  if (u.backdropMix > 0.0) {
    float2 nextAt = center + (uv - center) / u.backdropNextZoom;
    float3 coming = float3(next.sample(linear, nextAt).rgb) * twinkleAt(nextTwinkle, nextAt, u.twinkleTime);
    sky = mix(sky, coming, u.backdropMix);
  }
  return sky;
}

static float3 starTint(float h) {
  // Mostly blue-white and white, some cyan, a few warm.
  if (h < 0.45) return float3(0.72, 0.84, 1.0);
  if (h < 0.75) return float3(1.0, 1.0, 1.0);
  if (h < 0.93) return float3(0.65, 0.95, 1.0);
  return float3(1.0, 0.86, 0.72);
}

fragment WarpOut warpFragment(
  FullScreenOut in [[stage_in]], constant WarpUniforms& u [[buffer(0)]],
  texture2d<half> nebula [[texture(0)]], texture2d<half> history [[texture(1)]],
  texture2d<half> backdrop [[texture(2)]], texture2d<half> backdropNext [[texture(3)]],
  texture2d<half> twinkle [[texture(4)]], texture2d<half> twinkleNext [[texture(5)]]
) {
  constexpr sampler linear(filter::linear, address::clamp_to_edge);
  float2 p = in.uv * u.size;
  Polar q = polar(p, u.size);

  // Gas: a few taps inward along the radius - motion blur outward, longer at
  // warp than in cruise.
  float2 centerUV = float2(0.5, 0.5);
  float2 toCenter = centerUV - in.uv;
  float tapStep = 0.025 * mix(0.25, 1.0, u.blur);
  half3 gas = half3(0.0);
  for (int i = 0; i < 5; i++) {
    gas += nebula.sample(linear, in.uv + toCenter * (float(i) * tapStep)).rgb;
  }
  float3 color = float3(gas / 5.0h);
  // The distant backdrop, behind everything; in cruise only (at warp the
  // clouds are the tunnel and we are far from it). Entering the tunnel it
  // is pulled in with it while it fades: sampled at r^(1 + 1.5 tunnel) - the
  // image drawn outward from the center, stretched along the radius like the
  // far clouds' sqrt(r) -> rho - and smeared along the radius. Dropping out
  // it unwarps back into place.
  float backdropAmount = u.backdrop * (1.0 - u.tunnel);
  if (backdropAmount > 0.0) {
    float3 sky;
    if (u.tunnel <= 0.0) {
      sky = skyAt(backdrop, backdropNext, twinkle, twinkleNext, in.uv, u);
    } else {
      float pulled = q.r * pow(q.r, 1.5 * u.tunnel);  // distance to sample at (shortest side = 1)
      float scalePx = min(u.size.x, u.size.y);
      sky = float3(0.0);
      for (int i = 0; i < 5; i++) {
        float tapR = pulled * (1.0 - 0.04 * u.tunnel * float(i));
        float2 tapUV = (u.size * 0.5 + q.dir * tapR * scalePx) / u.size;
        sky += skyAt(backdrop, backdropNext, twinkle, twinkleNext, tapUV, u);
      }
      sky /= 5.0;
    }
    color += sky * backdropAmount;
  }

  // Stars: soft capsules on a scrolling log-polar grid.
  float dTheta = kTwoPi / kStarColumns;
  float u0 = (atan2(q.dir.y, q.dir.x) + kTwoPi * 0.5) / dTheta;
  float column = floor(u0);
  float3 stars = float3(0.0);
  // Low pass near the center: where a star cell is narrower than a couple of
  // pixels, several sub-pixel stars cross every pixel and flicker, and as
  // cells get smaller (stars per area ~ 1/r^2) they add up to a bright
  // patch. Fading by the square of the cell width keeps the brightness per
  // area even there: a faint, calm field of points (like a mipmap).
  float cellPx = dTheta * q.rPx;
  float lod = min(1.0, cellPx * cellPx / (1.8 * 1.8));
  for (int layer = 0; layer < kStarLayers; layer++) {
    float shift = fmod(kStarSpeed[layer] * u.travel, kStarRow * kRowPeriod);
    // Motion blur: short tails in cruise (like Hyperspace's), the full smear
    // at warp.
    float len = kStarBlur[layer] * mix(0.25, 1.0, u.blur);
    float rowPos = (q.rho - shift) / kStarRow;
    float row0 = floor(rowPos);
    // Rows whose stars can cover this pixel, including their soft ends.
    float rows = min(float(kMaxRows), floor(rowPos + (len + 0.06) / kStarRow) - row0 + 1.0);
    for (int dc = -1; dc <= 1; dc++) {
      float c = column + float(dc);
      float cellColumn = fmod(c + kStarColumns, kStarColumns);
      for (int b = 0; b < kMaxRows; b++) {
        if (float(b) >= rows) break;
        float row = row0 + float(b);
        float rowKey = row - kRowPeriod * floor(row / kRowPeriod);
        float3 h = hash34(float4(float(layer), cellColumn, rowKey, 3.0 + u.seed));
        if (h.x >= u.density) continue;
        float3 h2 = hash34(float4(float(layer), cellColumn, rowKey, 9.0 + u.seed));

        float head = (row + h.z) * kStarRow + shift;  // rho of the star's front
        float rHead = exp(head);
        // The blur is the star's own: far stars near the center keep the
        // crisp, round cruise look even at warp (points in the dark hole) and
        // streak as they come closer. Tied to the star, so it moves with it.
        float starBlur = u.blur * smoothstep(0.04, 0.15, rHead);
        float starLen = kStarBlur[layer] * mix(0.25, 1.0, starBlur);
        // Size: mostly small, a few big (power distribution); grows with
        // distance (perspective); emerges from the center.
        // Emerging: in cruise sooner, and the far stars near the center stay
        // at least half bright - a field of tiny points, not a void.
        float rFull = mix(mix(0.06, 0.2, h2.x), mix(0.12, 0.35, h2.x), starBlur);
        float grown = mix(1.0, smoothstep(0.02, rFull, rHead), u.emerge);
        // Far stars stay faintly lit near the center: half in cruise, 30 % at
        // warp - round points in the dark hole (their blur is tiny there).
        float lit = mix(mix(0.5, 1.0, grown), mix(0.3, 1.0, grown), starBlur);
        float size = kStarSize[layer] * (0.5 + 2.2 * pow(h2.y, 3.0)) * (0.6 + rHead * 3.5) * mix(0.3, 1.0, grown) *
                     mix(0.7, 1.0, starBlur);
        // At most 0.45 column: the neighbour columns then hold the whole
        // Gaussian (stars sit 0.2..0.8 into their column).
        size = min(size, 0.45 * dTheta * q.rPx);

        float offset = (u0 - c - (0.2 + 0.6 * h.y)) * dTheta * q.rPx;  // across, logical pixels
        float along = (q.rho - (head - starLen)) / starLen;  // 0 tail .. 1 head

        // Cruise: a crisp tail with round caps - the distance from the pixel
        // to the segment (beyond its ends along the radius, rho -> pixels, and
        // across) - at least about a pixel wide so the far stars show as
        // points; bright head, fading back.
        float alongPx = (q.rho - clamp(q.rho, head - starLen, head)) * q.rPx;
        float dist = sqrt(alongPx * alongPx + offset * offset);
        float halfWidth = max(size * 0.6, 0.5);
        float clampedAlong = clamp(along, 0.0, 1.0);
        float cruiseShape = clamp(halfWidth + 0.5 - dist, 0.0, 1.0) * clampedAlong * clampedAlong;
        // Warp: a motion-blurred capsule - Gaussian across, long soft ends.
        float soft = 0.06 / starLen;  // in units of the length
        float capsule = smoothstep(-soft, soft, along) * (1.0 - smoothstep(1.0 - soft, 1.0 + soft, along));
        float warpShape = exp(-offset * offset / (size * size)) * capsule;
        // A little glow around the head of the brightest stars (top ~30 %),
        // reaching a short way back along the tail and fading there; an inner
        // soft term blends it into the crisp edge (like the flares' core and
        // halo). Within reach of the neighbour columns.
        float glowRadius = min(halfWidth * 3.0 + 1.0, 0.4 * cellPx);
        float innerRadius = min(halfWidth * 1.6 + 0.5, 0.4 * cellPx);
        float bright = smoothstep(0.65, 0.9, h2.z);
        float glowBack = 0.35 * starLen;  // in rho
        float glowAt = clamp(q.rho, head - glowBack, head);
        float toGlowPx = (q.rho - glowAt) * q.rPx;
        float glowDist2 = toGlowPx * toGlowPx + offset * offset;
        float trail = mix(1.0, 0.4, (head - glowAt) / glowBack);  // fades back along the tail
        float glow = bright * trail * (0.35 * exp(-glowDist2 / (glowRadius * glowRadius)) +
                                       0.45 * exp(-glowDist2 / (innerRadius * innerRadius))) * (1.0 - starBlur);
        float shape = mix(cruiseShape, warpShape, starBlur) + glow;
        if (shape <= 0.0) continue;
        float brightness = (0.35 + 0.65 * h2.z) * lit * shape * lod;
        stars += starTint(fract(h2.x * 7.3 + h2.z * 3.1)) * brightness;
      }
    }
  }

  // Flare stars: rare, bright, with a wide soft halo, in three speed layers
  // (closer = faster = bigger) plus a size of their own; few, wide columns so
  // the halo fits within the neighbours.
  float flareDTheta = kTwoPi / kFlareColumns;
  float flareU = (atan2(q.dir.y, q.dir.x) + kTwoPi * 0.5) / flareDTheta;
  float flareColumn = floor(flareU);
  float flareLen = 0.12 * mix(0.03, 1.0, u.blur);
  float flareLod = smoothstep(2.0, 8.0, flareDTheta * q.rPx);  // low pass, as for the stars
  for (int layer = 0; layer < kFlareLayers; layer++) {
    float flareShift = fmod(kFlareSpeed[layer] * u.travel, kFlareRow * kRowPeriod);
    float flarePos = (q.rho - flareShift) / kFlareRow;
    float flareRow0 = floor(flarePos);
    float flareRows = floor(flarePos + (flareLen + 0.25) / kFlareRow) - flareRow0 + 1.0;
    for (int dc = -1; dc <= 1; dc++) {
      float c = flareColumn + float(dc);
      float cellColumn = fmod(c + kFlareColumns, kFlareColumns);
      for (int b = -1; b < 3; b++) {
        if (float(b) >= flareRows) break;
        float row = flareRow0 + float(b);
        float rowKey = row - kRowPeriod * floor(row / kRowPeriod);
        float3 h = hash34(float4(23.0 + float(layer), cellColumn, rowKey, 1.0 + u.seed));
        if (h.x >= kFlareDensity) continue;
        float head = (row + h.z) * kFlareRow + flareShift;
        float rHead = exp(head);
        // Emerging like the other stars: tiny and half bright from near the
        // center in cruise, full size at a distance of their own.
        float rFull = mix(mix(0.06, 0.2, h.y), mix(0.12, 0.35, h.y), u.blur);
        float grown = mix(1.0, smoothstep(0.02, rFull, rHead), u.emerge);
        float lit = mix(mix(0.2, 1.0, grown), grown, u.blur);
        // Distance from the pixel to the flare's motion-blurred core: along
        // the radius (in rho, converted to pixels) and across (pixels).
        float alongRho = q.rho - clamp(q.rho, head - flareLen, head);
        float alongPx = alongRho * q.rPx;
        float offset = (flareU - c - (0.3 + 0.4 * h.y)) * flareDTheta * q.rPx;
        float dist2 = alongPx * alongPx + offset * offset;
        // Size by layer and by flare (0.6..1.6); smaller at warp: stretched
        // by the motion blur they would read as huge.
        float ownSize = 0.6 + fract(h.y * 5.31 + h.z * 2.77);
        float core = max(0.7, (1.0 + rHead * 9.0) * kFlareSize[layer] * ownSize * mix(0.3, 1.0, grown) *
                                  mix(1.0, 0.55, u.blur));
        float halo = core * mix(4.0, 2.5, u.blur);
        // Near the center the columns are only a few pixels wide: keep core and
        // halo within reach of the neighbour columns, or they get cut off.
        float columnPx = flareDTheta * q.rPx;
        core = min(core, 0.2 * columnPx);
        halo = min(halo, 0.4 * columnPx);
        float light = 1.6 * exp(-dist2 / (core * core)) + 0.35 * exp(-dist2 / (halo * halo));
        stars += float3(0.92, 0.95, 1.0) * light * lit * flareLod;
      }
    }
  }

  // Speed lines: thin and faint, only the pixel's own column.
  float lineDTheta = kTwoPi / kLineColumns;
  float lineU = (atan2(q.dir.y, q.dir.x) + kTwoPi * 0.5) / lineDTheta;
  float lineColumn = floor(lineU);
  float lineShift = fmod(kLineSpeed * u.travel, kLineRow * kRowPeriod);
  float linePos = (q.rho - lineShift) / kLineRow;
  float lineRow0 = floor(linePos);
  for (int b = 0; b < 4; b++) {
    float row = lineRow0 + float(b);
    float rowKey = row - kRowPeriod * floor(row / kRowPeriod);
    float3 h = hash34(float4(9.0, lineColumn, rowKey, 5.0 + u.seed));
    if (h.x >= 0.18) continue;
    float head = (row + h.z) * kLineRow + lineShift;
    float along = (q.rho - (head - kLineLength)) / kLineLength;
    if (along < 0.0 || along > 1.0) continue;
    float offset = (lineU - lineColumn - (0.25 + 0.5 * h.y)) * lineDTheta * q.rPx;
    float coverage = clamp(0.9 - abs(offset), 0.0, 1.0);
    float grown = mix(1.0, smoothstep(0.05, 0.3, exp(head)), u.emerge);
    stars += float3(0.55, 0.65, 0.9) * (0.25 * along * coverage * grown * u.lines);
  }

  // Lens flare: one known star (tracked on the CPU), so it is drawn
  // directly - a warm core and halo, motion-blurred along the radius like the
  // flare stars, and anamorphic streaks: a thin horizontal line through the
  // head and a shorter vertical one, growing as it comes closer, flickering.
  // The streaks stay out of the trail (feedback): zoomed every frame, a line
  // would smear into a band.
  float3 streak = float3(0.0);
  if (u.lensBright > 0.0) {
    float2 d = p - u.size * 0.5;
    float across = d.x * u.lensDir.y - d.y * u.lensDir.x;
    float lensLen = 0.12 * mix(0.03, 1.0, u.blur);
    // Along the radius in pixels, from the real radii: a rho difference times
    // the pixel's own radius only holds near the head - near the center it
    // put every pixel within the halo (a glow at the center).
    float scale = min(u.size.x, u.size.y);
    float rHeadPx = exp(u.lensRho) * scale;
    float alongPx = q.rPx - clamp(q.rPx, exp(u.lensRho - lensLen) * scale, rHeadPx);
    if (dot(d, u.lensDir) < 0.0) alongPx = 1e4;  // the other side of the center
    float dist2 = alongPx * alongPx + across * across;
    // Less shrunk at warp than the flare stars: among the streaks it must
    // still stand out.
    float core = u.lensSize * mix(1.0, 0.8, u.blur);
    float halo = core * mix(5.0, 3.0, u.blur);
    float light = 2.2 * exp(-dist2 / (core * core)) + 0.45 * exp(-dist2 / (halo * halo));
    stars += float3(1.0, 0.86, 0.68) * light * u.lensBright * mix(1.0, u.lensFlicker, 0.5);

    float2 s = p - u.lensPos;
    float thickness2 = pow(0.5 + 0.08 * u.lensSize, 2.0);
    float reach = 12.5 * u.lensSize * mix(0.8, 1.0, u.lensFlicker);
    float horizontal = exp(-s.y * s.y / thickness2) * streakProfile(abs(s.x), reach);
    float vertical = exp(-s.x * s.x / thickness2) * streakProfile(abs(s.y), 0.75 * reach);
    float strength = 0.8 * mix(1.0, 1.6, u.blur) * u.lensStreaks;  // brighter at warp, among the speed streaks
    streak = float3(0.45, 0.65, 1.0) * (strength * (horizontal + 0.75 * vertical) * u.lensBright * u.lensFlicker);
  }

  color += stars;

  // Temporal feedback: the previous frame, zoomed outward a little (sampled
  // closer to the center), so what moved outward leaves a trail behind it -
  // smear along the motion, not just a fade. Max, not a sum: heads keep
  // their brightness and the clouds don't build up.
  float2 previousUV = centerUV + (in.uv - centerUV) * u.feedbackZoom;
  float3 previous = float3(history.sample(linear, previousUV).rgb) * u.feedbackDecay;
  color = max(color, previous);

  WarpOut out;
  out.history = half4(half3(color), 1.0h);
  out.color = half4(half3(color + streak), 1.0h);
  return out;
}
