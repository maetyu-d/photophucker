#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#include <algorithm>
#include <cmath>

struct SlitUniforms {
    float mode;
    float slitWidth;
    float drift;
    float blend;
    float wave;
    float phase;
    float grain;
    float colorShift;
    float canvasWidth;
    float exportScale;
    float chaos;
    float crush;
    float sourceFight;
    float time;
    float aspect;
};

static NSString *ShaderSource() {
    return @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct SlitUniforms {
    float mode;
    float slitWidth;
    float drift;
    float blend;
    float wave;
    float phase;
    float grain;
    float colorShift;
    float canvasWidth;
    float exportScale;
    float chaos;
    float crush;
    float sourceFight;
    float time;
    float aspect;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 uvs[6] = {
        float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
        float2(1.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float3 shifted(texture2d<float> tex, sampler s, float2 uv, float amount) {
    float r = tex.sample(s, uv + float2(amount, 0.0)).r;
    float g = tex.sample(s, uv).g;
    float b = tex.sample(s, uv - float2(amount, 0.0)).b;
    return float3(r, g, b);
}

static float3 paletteShock(float3 color, float amount) {
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float3 hot = float3(1.0, 0.12 + color.r * 0.55, 0.62 + color.b * 0.25);
    float3 cold = float3(0.08 + color.b * 0.35, 0.92, 1.0);
    float3 bruised = float3(color.b, color.r * 0.55, color.g);
    float3 mapped = mix(mix(hot, cold, smoothstep(0.18, 0.84, luma)), bruised, smoothstep(0.45, 0.95, color.r));
    return mix(color, mapped, amount);
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    texture2d<float> imageA [[texture(0)]],
    texture2d<float> imageB [[texture(1)]],
    constant SlitUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(address::repeat, filter::linear);
    float2 uv = in.uv;
    float2 centered = uv - 0.5;
    centered.x *= u.aspect;

    float phase = u.phase * 6.2831853 + u.time * 0.15;
    float slit = max(u.slitWidth, 1.0);
    float drift = u.drift / 900.0;
    float wave = u.wave / 900.0;
    float colorAmount = u.colorShift / 900.0;
    float stretch = max(1.0, u.canvasWidth / 100.0);
    float chaos = clamp(u.chaos / 100.0, 0.0, 1.0);
    float crush = clamp(u.crush / 100.0, 0.0, 1.0);
    float fight = clamp(u.sourceFight / 100.0, 0.0, 1.0);

    float2 uvA = uv;
    float2 uvB = uv;
    float selector = 0.0;

    if (u.mode < 0.5) {
        float wobble = sin(uv.x * 42.0 / slit + phase) * wave;
        uvB.x += drift + wobble;
        selector = fmod(floor(uv.x * 1100.0 / slit), 2.0);
    } else if (u.mode < 1.5) {
        float wobble = sin(uv.y * 42.0 / slit + phase) * wave;
        uvB.y += drift + wobble;
        selector = fmod(floor(uv.y * 1100.0 / slit), 2.0);
    } else if (u.mode < 2.5) {
        float tear = sin(uv.y * 31.0 + phase) * wave * 2.0;
        uvB.x += drift + tear;
        selector = fmod(floor((uv.x + uv.y + tear) * 900.0 / slit), 2.0);
    } else if (u.mode < 3.5) {
        float distance = length(centered);
        float angle = atan2(centered.y, centered.x);
        float ripple = sin(angle * 9.0 + phase) * wave;
        uvB += normalize(centered + 0.0001) * drift;
        selector = fmod(floor((distance + ripple) * 1000.0 / slit), 2.0);
    } else if (u.mode < 4.5) {
        float wx = sin(uv.y * 28.0 + phase) * (wave + drift);
        float wy = cos(uv.x * 28.0 + phase) * wave;
        uvA.y += wy;
        uvB.x += wx;
        selector = fmod(floor((uv.x + wx) * 800.0 / slit) + floor((uv.y + wy) * 800.0 / slit), 2.0);
    } else if (u.mode < 5.5) {
        float strip = floor(uv.x * 1100.0 / slit);
        float jump = (hash21(float2(strip, u.phase)) - 0.5) * drift * 5.0;
        float lift = (hash21(float2(strip, u.phase + 13.0)) - 0.5) * wave * 4.0;
        uvB += float2(jump, lift);
        selector = fmod(strip + step(0.42, hash21(float2(strip, 5.0))), 2.0);
    } else if (u.mode < 6.5) {
        float scan = floor(uv.x * 1800.0 / slit);
        float melt = sin(uv.y * 36.0 + phase + hash21(float2(scan, 4.0)) * 6.0) * wave * 1.8;
        float pull = (hash21(float2(scan, 17.0)) - 0.5) * drift * 3.0;
        uvA.x = clamp(0.5 + (uv.x - 0.5) / stretch + melt + pull, 0.0, 1.0);
        uvB.x = clamp(0.5 + (uv.x - 0.5) / (stretch * 1.35) - melt + pull * 0.5, 0.0, 1.0);
        uvA.y = clamp(uv.y + sin(uv.x * 26.0 + phase) * wave * 0.7, 0.0, 1.0);
        uvB.y = clamp(uv.y + cos(uv.x * 19.0 + phase) * wave * 0.7, 0.0, 1.0);
        selector = 0.25 + 0.75 * smoothstep(0.16, 0.86, hash21(float2(scan, floor(uv.y * 24.0))));
    } else if (u.mode < 7.5) {
        float scan = floor(uv.x * 2200.0 / max(1.0, slit * 0.45));
        float tooth = hash21(float2(scan, u.phase * 100.0));
        float drop = pow(tooth, 2.4) * (0.18 + wave * 2.4);
        float edge = smoothstep(drop, drop - 0.08, uv.y);
        float saw = abs(fract(uv.x * 900.0 / max(1.0, slit)) - 0.5) * 2.0;
        uvA.x = clamp((scan + 0.5) / (2200.0 / max(1.0, slit * 0.45)), 0.0, 1.0);
        uvB.x = clamp(uvA.x + (hash21(float2(scan, 9.0)) - 0.5) * drift * 2.5, 0.0, 1.0);
        uvA.y = clamp(uv.y * (0.35 + drop) + sin(uv.x * 90.0 + phase) * wave, 0.0, 1.0);
        uvB.y = clamp(uvA.y + (saw - 0.5) * wave * 1.8, 0.0, 1.0);
        selector = 0.18 + 0.82 * max(edge, step(0.58, hash21(float2(scan, 22.0))));
    } else if (u.mode < 8.5) {
        float side = sign(uv.x - 0.5);
        float coreWidth = max(0.08, 0.42 / stretch);
        float mirrorX = 0.5 + abs(uv.x - 0.5) * coreWidth * 2.0;
        float oppositeX = 0.5 - abs(uv.x - 0.5) * coreWidth * 2.0;
        float neck = smoothstep(0.16, 0.82, uv.y) * smoothstep(1.0, 0.58, uv.y);
        float bend = side * neck * (0.16 + wave * 2.0) * smoothstep(0.04, 0.48, abs(uv.x - 0.5));
        uvA.x = clamp(mirrorX + bend + sin(uv.y * 34.0 + phase) * wave * 0.8, 0.0, 1.0);
        uvB.x = clamp(oppositeX - bend * 0.45 + drift * 0.7, 0.0, 1.0);
        uvA.y = clamp(uv.y + cos(uv.x * 20.0 + phase) * wave * 0.7, 0.0, 1.0);
        uvB.y = clamp(uv.y - sin(uv.x * 18.0 + phase) * wave * 0.7, 0.0, 1.0);
        selector = 0.22 + 0.78 * smoothstep(0.05, 0.52, abs(uv.x - 0.5));
    } else if (u.mode < 9.5) {
        float2 fromCenter = centered;
        float distance = length(fromCenter);
        float angle = atan2(fromCenter.y, fromCenter.x);
        float verticalBand = floor(uv.x * 1450.0 / slit);
        float horizontalBand = floor(uv.y * 1000.0 / max(1.0, slit * 1.35));
        float torn = hash21(float2(verticalBand, floor(uv.y * 18.0) + u.phase * 31.0));
        float diagonal = floor((uv.x + uv.y + sin(uv.y * 30.0 + phase) * wave * 3.2) * 1050.0 / slit);
        float radial = floor((distance + sin(angle * 9.0 + phase) * wave * 1.8) * 1200.0 / slit);
        float drip = pow(hash21(float2(verticalBand, 55.0 + u.phase * 19.0)), 2.0);
        float dripMask = smoothstep(drip * (0.25 + wave * 3.0), drip * (0.25 + wave * 3.0) - 0.08, uv.y);
        float mirrorPull = smoothstep(0.08, 0.52, abs(uv.x - 0.5));
        float stripJitter = (torn - 0.5) * drift * 4.0;

        float2 elasticA = uv;
        elasticA.x = 0.5 + (uv.x - 0.5) / stretch + stripJitter + sin(uv.y * 32.0 + phase) * wave * 1.3;
        elasticA.y += cos(uv.x * 28.0 + phase) * wave * 0.9;

        float2 radialB = uv + normalize(fromCenter + 0.0001) * drift * 1.6;
        radialB.x = mix(radialB.x, 0.5 - (uv.x - 0.5) / max(1.0, stretch * 0.9), mirrorPull * 0.65);
        radialB.x += sin(uv.y * 54.0 + phase + torn * 6.28) * wave * 1.6;
        radialB.y += (dripMask - 0.5) * wave * 2.0;

        uvA = clamp(elasticA, 0.0, 1.0);
        uvB = clamp(radialB, 0.0, 1.0);

        float bandMix = fmod(verticalBand + horizontalBand + diagonal + radial, 2.0);
        float softMix = smoothstep(0.18, 0.82, hash21(float2(verticalBand + radial, horizontalBand + u.phase * 100.0)));
        selector = mix(softMix, 1.0 - softMix, bandMix);
        selector = clamp(mix(selector, dripMask, 0.34) + mirrorPull * 0.18, 0.08, 0.96);
    } else if (u.mode < 10.5) {
        float cells = mix(28.0, 260.0, chaos);
        float2 cell = floor(uv * cells);
        float cellNoise = hash21(cell + u.phase * 71.0);
        float2 cellUv = (cell + 0.5) / cells;
        float fracture = sin((uv.x + uv.y) * (34.0 + chaos * 180.0) + phase + cellNoise * 6.28);
        float2 jump = float2(cellNoise - 0.5, hash21(cell.yx + 11.0) - 0.5) * (0.03 + chaos * 0.34);
        uvA = clamp(mix(uv, cellUv, 0.35 + chaos * 0.55) + jump + float2(fracture, -fracture) * wave * 2.2, 0.0, 1.0);
        uvB = clamp(1.0 - uvA + float2(drift, -drift) * 2.0 + sin(uv.yx * 48.0 + phase) * wave * 2.0, 0.0, 1.0);
        selector = smoothstep(0.18, 0.88, cellNoise + fracture * 0.18);
    } else if (u.mode < 11.5) {
        float row = floor(uv.y * mix(80.0, 900.0, chaos));
        float sync = hash21(float2(row, u.phase * 100.0));
        float tearLine = step(0.78 - chaos * 0.45, sync);
        float sweep = sin(uv.y * 420.0 + phase + sync * 8.0);
        float2 smear = float2((sync - 0.5) * (0.15 + chaos * 0.85) + drift * 2.0, sweep * wave * 3.2);
        uvA = clamp(float2(0.5 + (uv.x - 0.5) / stretch, uv.y) + smear * tearLine, 0.0, 1.0);
        uvB = clamp(float2(uv.x + sin(uv.y * 55.0 + phase) * wave * 2.4, 1.0 - uv.y) - smear * (1.0 - tearLine * 0.4), 0.0, 1.0);
        selector = clamp(0.5 + sweep * 0.35 + tearLine * (sync - 0.5), 0.04, 0.96);
    } else if (u.mode < 12.5) {
        float2 polar = float2(length(centered), atan2(centered.y, centered.x) / 6.2831853 + 0.5);
        float radiusBand = floor(polar.x * mix(160.0, 900.0, chaos) / max(1.0, slit * 0.18));
        float angleBand = floor(polar.y * mix(30.0, 180.0, chaos));
        float shatter = hash21(float2(radiusBand, angleBand) + u.phase * 23.0);
        float spin = (shatter - 0.5) * (0.4 + chaos * 2.5) + phase * 0.08;
        float r = clamp(polar.x * mix(1.8, 0.38, shatter) + sin(angleBand + phase) * wave * 2.5, 0.0, 0.9);
        float theta = polar.y * 6.2831853 + spin;
        float2 rebuilt = float2(cos(theta), sin(theta)) * r / max(float2(u.aspect, 1.0), float2(0.001));
        uvA = clamp(0.5 + rebuilt + float2(drift, 0.0), 0.0, 1.0);
        uvB = clamp(0.5 - rebuilt.yx + sin(uv * 60.0 + phase) * wave * 1.8, 0.0, 1.0);
        selector = clamp(mix(fract(radiusBand * 0.5 + angleBand), shatter, 0.6), 0.08, 0.94);
    } else {
        float margin = 0.028;
        float2 inner = (uv - margin) / (1.0 - margin * 2.0);
        inner = clamp(inner, 0.0, 1.0);
        float stripScale = mix(95.0, 230.0, chaos);
        float strip = floor(inner.x * stripScale / max(1.0, slit * 0.18));
        float stripSeed = hash21(float2(strip, u.phase * 97.0));
        float widthJitter = hash21(float2(strip, 31.0)) * 0.006;
        float seam = smoothstep(0.012 + widthJitter, 0.0, min(fract(inner.x * stripScale / max(1.0, slit * 0.18)), 1.0 - fract(inner.x * stripScale / max(1.0, slit * 0.18))));
        float yJump = (hash21(float2(strip, 11.0)) - 0.5) * (0.16 + chaos * 0.38);
        float xSource = clamp((strip + 0.5) / (stripScale / max(1.0, slit * 0.18)) + (stripSeed - 0.5) * drift * 1.6, 0.0, 1.0);
        float2 stripUv = float2(xSource, clamp(inner.y + yJump + sin(inner.y * 18.0 + stripSeed * 6.28 + phase) * wave * 0.65, 0.0, 1.0));
        float2 altUv = float2(clamp(1.0 - xSource + (hash21(float2(strip, 61.0)) - 0.5) * drift, 0.0, 1.0),
                              clamp(inner.y - yJump * 0.65 + cos(inner.x * 44.0 + phase) * wave * 0.5, 0.0, 1.0));
        uvA = stripUv;
        uvB = altUv;
        selector = step(0.46, stripSeed);

        float3 stripA = shifted(imageA, s, uvA, 0.0);
        float3 stripB = shifted(imageB, s, uvB, 0.0);
        float3 stripColor = mix(stripA, stripB, selector);
        float gray = dot(stripColor, float3(0.299, 0.587, 0.114));
        float exposure = mix(0.72, 1.34, hash21(float2(strip, 7.0)));
        float fog = hash21(floor(inner * float2(85.0, 65.0)) + strip) * 0.18;
        gray = clamp((gray - 0.5) * (1.8 + crush * 2.2) + 0.5, 0.0, 1.0);
        gray = clamp(gray * exposure + fog - seam * (0.18 + chaos * 0.22), 0.0, 1.0);
        float paper = 0.92 + (hash21(floor(uv * 150.0)) - 0.5) * 0.08;
        float inside = step(margin, uv.x) * step(margin, uv.y) * step(uv.x, 1.0 - margin) * step(uv.y, 1.0 - margin);
        float3 collage = mix(float3(paper), float3(gray), inside);
        float verticalScratch = step(0.985, hash21(float2(floor(uv.x * 520.0), 4.0))) * inside * 0.22;
        collage = clamp(collage - verticalScratch, 0.0, 1.0);
        return float4(collage, 1.0);
    }

    float fightMask = smoothstep(0.1, 0.92, hash21(floor((uv + chaos * 0.02) * mix(24.0, 220.0, fight)) + u.phase * 47.0));
    selector = clamp(mix(selector, 1.0 - selector, fight * fightMask), 0.0, 1.0);

    float chaosShift = colorAmount * (1.0 + chaos * 7.0);
    float3 a = shifted(imageA, s, uvA + (hash21(floor(uv * 180.0)) - 0.5) * chaos * 0.02, chaosShift);
    float3 b = shifted(imageB, s, uvB - (hash21(floor(uv.yx * 180.0)) - 0.5) * chaos * 0.02, -chaosShift);
    float3 color = mix(a, b, selector);
    float3 difference = abs(a - b);
    float3 burned = 1.0 - (1.0 - a) * (1.0 - b);
    color = mix(color, mix(difference, burned, selector), fight * 0.65);
    color = mix(color, b, clamp(u.blend / 100.0, 0.0, 1.0));

    float noise = (hash21(uv * 1800.0 + u.time) - 0.5) * (u.grain / 100.0);
    color = clamp(color + noise, 0.0, 1.0);
    float levels = mix(255.0, 3.0, crush);
    color = floor(color * levels) / max(1.0, levels);
    color = paletteShock(color, chaos * 0.35 + crush * 0.25);
    color = clamp((color - 0.5) * (1.0 + crush * 1.8) + 0.5, 0.0, 1.0);
    return float4(color, 1.0);
}
)METAL";
}

@interface SlitRenderer : NSObject <MTKViewDelegate>
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, strong) id<MTLTexture> textureA;
@property(nonatomic, strong) id<MTLTexture> textureB;
@property(nonatomic) SlitUniforms uniforms;
@property(nonatomic) CFTimeInterval startTime;
- (instancetype)initWithView:(MTKView *)view;
- (BOOL)loadImageAtURL:(NSURL *)url slot:(NSInteger)slot error:(NSError **)error;
- (BOOL)exportToURL:(NSURL *)url size:(CGSize)size error:(NSError **)error;
@end

@implementation SlitRenderer
- (instancetype)initWithView:(MTKView *)view {
    self = [super init];
    if (!self) return nil;
    self.device = view.device;
    self.queue = [self.device newCommandQueue];
    NSError *error = nil;
    id<MTLLibrary> library = [self.device newLibraryWithSource:ShaderSource() options:nil error:&error];
    if (!library) {
        NSLog(@"Shader compile failed: %@", error);
        return nil;
    }
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [library newFunctionWithName:@"vertex_main"];
    desc.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
    desc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    self.pipeline = [self.device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!self.pipeline) {
        NSLog(@"Pipeline failed: %@", error);
        return nil;
    }
    self.uniforms = {0, 18, 60, 18, 34, 0, 7, 4, 220, 2, 35, 12, 40, 0, 1};
    self.startTime = CACurrentMediaTime();
    return self;
}

- (BOOL)loadImageAtURL:(NSURL *)url slot:(NSInteger)slot error:(NSError **)error {
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:self.device];
    NSDictionary *options = @{
        MTKTextureLoaderOptionSRGB: @NO,
        MTKTextureLoaderOptionOrigin: MTKTextureLoaderOriginTopLeft
    };
    id<MTLTexture> texture = [loader newTextureWithContentsOfURL:url options:options error:error];
    if (!texture) return NO;
    if (slot == 0) self.textureA = texture;
    else self.textureB = texture;
    return YES;
}

- (void)drawIntoRenderPass:(MTLRenderPassDescriptor *)pass commandBuffer:(id<MTLCommandBuffer>)commandBuffer viewport:(MTLViewport)viewport {
    if (!pass) return;
    id<MTLRenderCommandEncoder> enc = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!self.textureA || !self.textureB) {
        [enc endEncoding];
        return;
    }
    SlitUniforms u = self.uniforms;
    u.time = CACurrentMediaTime() - self.startTime;
    u.aspect = viewport.width / std::max(1.0, viewport.height);
    [enc setViewport:viewport];
    [enc setRenderPipelineState:self.pipeline];
    [enc setFragmentTexture:self.textureA atIndex:0];
    [enc setFragmentTexture:self.textureB atIndex:1];
    [enc setFragmentBytes:&u length:sizeof(SlitUniforms) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [enc endEncoding];
}

- (void)drawInMTKView:(MTKView *)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    if (!drawable || !pass) return;
    id<MTLCommandBuffer> commandBuffer = [self.queue commandBuffer];
    MTLViewport viewport = {0, 0, view.drawableSize.width, view.drawableSize.height, 0, 1};
    [self drawIntoRenderPass:pass commandBuffer:commandBuffer viewport:viewport];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (BOOL)exportToURL:(NSURL *)url size:(CGSize)size error:(NSError **)error {
    if (!self.textureA || !self.textureB) return NO;
    NSUInteger width = std::max<NSUInteger>(1, (NSUInteger)size.width);
    NSUInteger height = std::max<NSUInteger>(1, (NSUInteger)size.height);

    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> target = [self.device newTextureWithDescriptor:textureDesc];

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.02, 0.025, 1);

    id<MTLCommandBuffer> commandBuffer = [self.queue commandBuffer];
    MTLViewport viewport = {0, 0, (double)width, (double)height, 0, 1};
    [self drawIntoRenderPass:pass commandBuffer:commandBuffer viewport:viewport];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    [target getBytes:data.mutableBytes bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, colorSpace,
                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    NSString *extension = url.pathExtension.lowercaseString;
    CFStringRef type = (__bridge CFStringRef)([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"] ? UTTypeJPEG.identifier : UTTypePNG.identifier);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
    BOOL ok = NO;
    if (destination && image) {
        CGImageDestinationAddImage(destination, image, NULL);
        ok = CGImageDestinationFinalize(destination);
    }
    if (destination) CFRelease(destination);
    if (image) CGImageRelease(image);
    if (provider) CGDataProviderRelease(provider);
    if (colorSpace) CGColorSpaceRelease(colorSpace);
    return ok;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) MTKView *metalView;
@property(nonatomic, strong) SlitRenderer *renderer;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSTextField *labelA;
@property(nonatomic, strong) NSTextField *labelB;
@property(nonatomic, strong) NSSecureTextField *streetViewKeyField;
@end

@implementation AppDelegate
- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = message ?: @"Unknown error.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        [self showAlertTitle:@"Slitscan" message:@"This Mac does not report a Metal-capable GPU."];
        [NSApp terminate:nil];
        return;
    }

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 1180, 760)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Slitscan Found Image Lab";
    self.window.minSize = NSMakeSize(980, 640);
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    NSView *content = self.window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.93 alpha:1].CGColor;

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.spacing = 0;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    NSView *sidebar = [NSView new];
    sidebar.wantsLayer = YES;
    sidebar.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.96 alpha:1].CGColor;
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar.widthAnchor constraintEqualToConstant:350].active = YES;
    [root addArrangedSubview:sidebar];

    NSScrollView *scrollView = [NSScrollView new];
    scrollView.hasVerticalScroller = YES;
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = [NSColor colorWithCalibratedWhite:0.96 alpha:1];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor],
    ]];

    NSStackView *controls = [NSStackView stackViewWithViews:@[]];
    controls.orientation = NSUserInterfaceLayoutOrientationVertical;
    controls.alignment = NSLayoutAttributeLeading;
    controls.spacing = 10;
    controls.edgeInsets = NSEdgeInsetsMake(18, 16, 18, 16);
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = controls;
    [NSLayoutConstraint activateConstraints:@[
        [controls.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:scrollView.contentView.trailingAnchor],
        [controls.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],
        [controls.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
    ]];

    NSTextField *title = [self label:@"Slitscan Found Image Lab" size:20 bold:YES];
    [controls addArrangedSubview:title];
    [controls addArrangedSubview:[self label:@"GPU-driven two-image experiments" size:12 bold:NO]];

    self.labelA = [self label:@"Image A: empty" size:12 bold:NO];
    self.labelB = [self label:@"Image B: empty" size:12 bold:NO];
    [controls addArrangedSubview:[self button:@"Load Image A" action:@selector(loadA:)]];
    [controls addArrangedSubview:self.labelA];
    [controls addArrangedSubview:[self button:@"Load Image B" action:@selector(loadB:)]];
    [controls addArrangedSubview:self.labelB];
    [controls addArrangedSubview:[self label:@"Local images: use Load Image A and Load Image B above." size:11 bold:NO]];

    self.streetViewKeyField = [NSSecureTextField new];
    self.streetViewKeyField.placeholderString = @"Google Street View API key";
    self.streetViewKeyField.stringValue = [NSProcessInfo processInfo].environment[@"GOOGLE_STREET_VIEW_API_KEY"] ?: @"";
    [self.streetViewKeyField.widthAnchor constraintEqualToConstant:310].active = YES;
    [controls addArrangedSubview:self.streetViewKeyField];
    NSButton *commonsButton = [NSButton buttonWithTitle:@"Random Open Tokyo Pair" target:self action:@selector(loadOpenTokyoPair:)];
    commonsButton.bezelStyle = NSBezelStyleRounded;
    commonsButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    [commonsButton.widthAnchor constraintEqualToConstant:310].active = YES;
    [controls addArrangedSubview:commonsButton];
    NSButton *streetViewButton = [NSButton buttonWithTitle:@"Google Street View Pair" target:self action:@selector(loadTokyoStreetViewPair:)];
    streetViewButton.bezelStyle = NSBezelStyleRounded;
    streetViewButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    [streetViewButton.widthAnchor constraintEqualToConstant:310].active = YES;
    [controls addArrangedSubview:streetViewButton];

    NSPopUpButton *mode = [NSPopUpButton new];
    [mode addItemsWithTitles:@[
        @"Vertical Time Slits",
        @"Horizontal Time Slits",
        @"Diagonal Tear",
        @"Radial Scan",
        @"Wave Loom",
        @"Torn Contact Sheet",
        @"Elastic Panorama",
        @"Vertical Pull Drips",
        @"Mirror Stretch Portrait",
        @"All Modes Composite",
        @"Fracture Collider",
        @"Sync Smear",
        @"Radial Shatter",
        @"Photocopy Strip Collage"
    ]];
    mode.target = self;
    mode.action = @selector(modeChanged:);
    [mode.widthAnchor constraintEqualToConstant:310].active = YES;
    [controls addArrangedSubview:mode];

    [self addSliderTo:controls title:@"Slit Width" min:1 max:120 value:18 tag:1];
    [self addSliderTo:controls title:@"Drift" min:-300 max:300 value:60 tag:2];
    [self addSliderTo:controls title:@"Blend Back" min:0 max:100 value:18 tag:3];
    [self addSliderTo:controls title:@"Wave" min:0 max:180 value:34 tag:4];
    [self addSliderTo:controls title:@"Phase" min:0 max:100 value:0 tag:5];
    [self addSliderTo:controls title:@"Grain" min:0 max:40 value:7 tag:6];
    [self addSliderTo:controls title:@"Color Shift" min:-40 max:40 value:4 tag:7];
    [self addSliderTo:controls title:@"Canvas Width" min:100 max:420 value:220 tag:8];
    [self addSliderTo:controls title:@"Export Upscale" min:1 max:4 value:2 tag:9];
    [self addSliderTo:controls title:@"Chaos" min:0 max:100 value:35 tag:10];
    [self addSliderTo:controls title:@"Crush" min:0 max:100 value:12 tag:11];
    [self addSliderTo:controls title:@"Source Fight" min:0 max:100 value:40 tag:12];

    NSStackView *actions = [NSStackView stackViewWithViews:@[[self button:@"Randomize" action:@selector(randomize:)], [self button:@"Export" action:@selector(exportImage:)]]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8;
    [controls addArrangedSubview:actions];

    self.status = [self label:@"Load two images to begin." size:12 bold:NO];
    [controls addArrangedSubview:self.status];

    self.metalView = [[MTKView alloc] initWithFrame:NSZeroRect device:device];
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalView.clearColor = MTLClearColorMake(0.08, 0.085, 0.095, 1);
    self.metalView.preferredFramesPerSecond = 60;
    self.metalView.enableSetNeedsDisplay = NO;
    [root addArrangedSubview:self.metalView];

    self.renderer = [[SlitRenderer alloc] initWithView:self.metalView];
    self.metalView.delegate = self.renderer;

    [self.window makeKeyAndOrderFront:nil];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [NSTextField labelWithString:text];
    field.textColor = bold ? [NSColor colorWithCalibratedWhite:0.08 alpha:1] : [NSColor colorWithCalibratedWhite:0.24 alpha:1];
    field.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    field.lineBreakMode = NSLineBreakByWordWrapping;
    field.maximumNumberOfLines = 3;
    [field.widthAnchor constraintLessThanOrEqualToConstant:315].active = YES;
    return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.contentTintColor = [NSColor controlTextColor];
    [button.widthAnchor constraintEqualToConstant:152].active = YES;
    return button;
}

- (void)addSliderTo:(NSStackView *)controls title:(NSString *)title min:(double)min max:(double)max value:(double)value tag:(NSInteger)tag {
    [controls addArrangedSubview:[self label:title size:12 bold:NO]];
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:self action:@selector(sliderChanged:)];
    slider.tag = tag;
    [slider.widthAnchor constraintEqualToConstant:310].active = YES;
    [controls addArrangedSubview:slider];
}

- (void)modeChanged:(NSPopUpButton *)sender {
    SlitUniforms u = self.renderer.uniforms;
    u.mode = sender.indexOfSelectedItem;
    self.renderer.uniforms = u;
}

- (void)sliderChanged:(NSSlider *)sender {
    SlitUniforms u = self.renderer.uniforms;
    switch (sender.tag) {
        case 1: u.slitWidth = sender.doubleValue; break;
        case 2: u.drift = sender.doubleValue; break;
        case 3: u.blend = sender.doubleValue; break;
        case 4: u.wave = sender.doubleValue; break;
        case 5: u.phase = sender.doubleValue / 100.0; break;
        case 6: u.grain = sender.doubleValue; break;
        case 7: u.colorShift = sender.doubleValue; break;
        case 8: u.canvasWidth = sender.doubleValue; break;
        case 9: u.exportScale = sender.doubleValue; break;
        case 10: u.chaos = sender.doubleValue; break;
        case 11: u.crush = sender.doubleValue; break;
        case 12: u.sourceFight = sender.doubleValue; break;
    }
    self.renderer.uniforms = u;
}

- (void)loadA:(id)sender { [self loadSlot:0]; }
- (void)loadB:(id)sender { [self loadSlot:1]; }

- (double)randomDoubleBetween:(double)minimum maximum:(double)maximum {
    return minimum + ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * (maximum - minimum);
}

- (NSURL *)streetViewURLWithPath:(NSString *)path items:(NSArray<NSURLQueryItem *> *)items {
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"https";
    components.host = @"maps.googleapis.com";
    components.path = path;
    components.queryItems = items;
    return components.URL;
}

- (NSURL *)commonsURLWithItems:(NSArray<NSURLQueryItem *> *)items {
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"https";
    components.host = @"commons.wikimedia.org";
    components.path = @"/w/api.php";
    components.queryItems = items;
    return components.URL;
}

- (BOOL)isUsableImageURL:(NSString *)url {
    NSString *lower = url.lowercaseString;
    return [lower hasSuffix:@".jpg"] || [lower hasSuffix:@".jpeg"] || [lower hasSuffix:@".png"] || [lower containsString:@".jpg?"] || [lower containsString:@".jpeg?"] || [lower containsString:@".png?"];
}

- (NSDictionary *)fetchRandomOpenTokyoImageForSlot:(NSInteger)slot error:(NSError **)error {
    NSArray<NSString *> *queries = @[
        @"Tokyo street",
        @"Tokyo city street",
        @"Tokyo urban",
        @"Shibuya street",
        @"Shinjuku street",
        @"Tokyo alley",
        @"Tokyo night street"
    ];
    NSString *query = queries[arc4random_uniform((uint32_t)queries.count)];
    NSURL *apiURL = [self commonsURLWithItems:@[
        [NSURLQueryItem queryItemWithName:@"action" value:@"query"],
        [NSURLQueryItem queryItemWithName:@"generator" value:@"search"],
        [NSURLQueryItem queryItemWithName:@"gsrsearch" value:query],
        [NSURLQueryItem queryItemWithName:@"gsrnamespace" value:@"6"],
        [NSURLQueryItem queryItemWithName:@"gsrlimit" value:@"50"],
        [NSURLQueryItem queryItemWithName:@"prop" value:@"imageinfo"],
        [NSURLQueryItem queryItemWithName:@"iiprop" value:@"url"],
        [NSURLQueryItem queryItemWithName:@"iiurlwidth" value:@"1280"],
        [NSURLQueryItem queryItemWithName:@"format" value:@"json"],
        [NSURLQueryItem queryItemWithName:@"formatversion" value:@"2"],
    ]];

    NSData *apiData = [NSData dataWithContentsOfURL:apiURL options:0 error:error];
    if (!apiData) return nil;
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:apiData options:0 error:error];
    NSArray *pages = response[@"query"][@"pages"];
    if (![pages isKindOfClass:NSArray.class] || pages.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SlitscanCommons"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"No open Tokyo images came back from Wikimedia Commons."}];
        }
        return nil;
    }

    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (NSDictionary *page in pages) {
        NSArray *imageInfo = page[@"imageinfo"];
        NSDictionary *firstInfo = imageInfo.firstObject;
        NSString *urlString = firstInfo[@"thumburl"] ?: firstInfo[@"url"];
        if ([urlString isKindOfClass:NSString.class] && [self isUsableImageURL:urlString]) {
            [candidates addObject:@{@"url": urlString, @"title": page[@"title"] ?: @"Wikimedia Commons"}];
        }
    }

    if (candidates.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SlitscanCommons"
                                         code:415
                                     userInfo:@{NSLocalizedDescriptionKey: @"Commons returned files, but none were usable bitmap images."}];
        }
        return nil;
    }

    NSDictionary *chosen = candidates[arc4random_uniform((uint32_t)candidates.count)];
    NSURL *imageURL = [NSURL URLWithString:chosen[@"url"]];
    NSData *imageData = [NSData dataWithContentsOfURL:imageURL options:0 error:error];
    if (!imageData || imageData.length < 4096) return nil;

    NSString *name = [NSString stringWithFormat:@"open-tokyo-%ld-%@.jpg", (long)slot, NSUUID.UUID.UUIDString];
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![imageData writeToURL:fileURL options:NSDataWritingAtomic error:error]) return nil;
    return @{
        @"url": fileURL,
        @"caption": [NSString stringWithFormat:@"Open Tokyo: %@", chosen[@"title"]],
    };
}

- (NSDictionary *)fetchRandomTokyoStreetViewImageWithKey:(NSString *)key slot:(NSInteger)slot error:(NSError **)error {
    for (NSInteger attempt = 0; attempt < 14; attempt++) {
        double latitude = [self randomDoubleBetween:35.55 maximum:35.82];
        double longitude = [self randomDoubleBetween:139.58 maximum:139.90];
        double heading = [self randomDoubleBetween:0 maximum:360];
        double pitch = [self randomDoubleBetween:-12 maximum:10];
        NSString *location = [NSString stringWithFormat:@"%.7f,%.7f", latitude, longitude];

        NSURL *metadataURL = [self streetViewURLWithPath:@"/maps/api/streetview/metadata" items:@[
            [NSURLQueryItem queryItemWithName:@"location" value:location],
            [NSURLQueryItem queryItemWithName:@"radius" value:@"220"],
            [NSURLQueryItem queryItemWithName:@"key" value:key],
        ]];
        NSData *metadataData = [NSData dataWithContentsOfURL:metadataURL options:0 error:error];
        if (!metadataData) return nil;

        NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:metadataData options:0 error:error];
        if (![metadata isKindOfClass:NSDictionary.class]) continue;
        if (![metadata[@"status"] isEqualToString:@"OK"]) continue;

        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithArray:@[
            [NSURLQueryItem queryItemWithName:@"size" value:@"1280x720"],
            [NSURLQueryItem queryItemWithName:@"heading" value:[NSString stringWithFormat:@"%.2f", heading]],
            [NSURLQueryItem queryItemWithName:@"pitch" value:[NSString stringWithFormat:@"%.2f", pitch]],
            [NSURLQueryItem queryItemWithName:@"fov" value:@"92"],
            [NSURLQueryItem queryItemWithName:@"key" value:key],
        ]];

        NSString *panoID = metadata[@"pano_id"];
        if ([panoID isKindOfClass:NSString.class] && panoID.length > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:@"pano" value:panoID]];
        } else {
            NSDictionary *resolvedLocation = metadata[@"location"];
            NSNumber *resolvedLat = resolvedLocation[@"lat"];
            NSNumber *resolvedLng = resolvedLocation[@"lng"];
            NSString *resolved = resolvedLat && resolvedLng ? [NSString stringWithFormat:@"%.7f,%.7f", resolvedLat.doubleValue, resolvedLng.doubleValue] : location;
            [items addObject:[NSURLQueryItem queryItemWithName:@"location" value:resolved]];
        }

        NSURL *imageURL = [self streetViewURLWithPath:@"/maps/api/streetview" items:items];
        NSData *imageData = [NSData dataWithContentsOfURL:imageURL options:0 error:error];
        if (!imageData || imageData.length < 4096) continue;

        NSString *name = [NSString stringWithFormat:@"tokyo-streetview-%ld-%@.jpg", (long)slot, NSUUID.UUID.UUIDString];
        NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        if (![imageData writeToURL:fileURL options:NSDataWritingAtomic error:error]) return nil;
        return @{
            @"url": fileURL,
            @"caption": [NSString stringWithFormat:@"Tokyo Street View %.4f, %.4f", latitude, longitude],
        };
    }

    if (error) {
        *error = [NSError errorWithDomain:@"SlitscanStreetView"
                                     code:404
                                 userInfo:@{NSLocalizedDescriptionKey: @"Could not find usable Tokyo Street View imagery after several random tries."}];
    }
    return nil;
}

- (void)loadTokyoStreetViewPair:(id)sender {
    NSString *key = self.streetViewKeyField.stringValue;
    if (key.length == 0) {
        [self showAlertTitle:@"Street View API key needed" message:@"Paste a Google Street View Static API key into the field first, or launch with GOOGLE_STREET_VIEW_API_KEY set."];
        return;
    }

    self.status.stringValue = @"Finding random Tokyo Street View images...";
    __weak AppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        NSDictionary *first = [strongSelf fetchRandomTokyoStreetViewImageWithKey:key slot:0 error:&error];
        NSDictionary *second = first ? [strongSelf fetchRandomTokyoStreetViewImageWithKey:key slot:1 error:&error] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainSelf = weakSelf;
            if (!mainSelf) return;
            if (!first || !second) {
                [mainSelf showAlertTitle:@"Street View failed" message:error.localizedDescription];
                mainSelf.status.stringValue = @"Street View load failed.";
                return;
            }

            NSError *loadError = nil;
            BOOL loadedA = [mainSelf.renderer loadImageAtURL:first[@"url"] slot:0 error:&loadError];
            BOOL loadedB = loadedA ? [mainSelf.renderer loadImageAtURL:second[@"url"] slot:1 error:&loadError] : NO;
            if (!loadedA || !loadedB) {
                [mainSelf showAlertTitle:@"Could not use Street View images" message:loadError.localizedDescription];
                mainSelf.status.stringValue = @"Street View images could not be loaded.";
                return;
            }

            mainSelf.labelA.stringValue = [@"Image A: " stringByAppendingString:first[@"caption"]];
            mainSelf.labelB.stringValue = [@"Image B: " stringByAppendingString:second[@"caption"]];
            mainSelf.status.stringValue = @"Loaded random Tokyo Street View pair.";
        });
    });
}

- (void)loadOpenTokyoPair:(id)sender {
    self.status.stringValue = @"Finding open Tokyo images...";
    __weak AppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        NSDictionary *first = [strongSelf fetchRandomOpenTokyoImageForSlot:0 error:&error];
        NSDictionary *second = first ? [strongSelf fetchRandomOpenTokyoImageForSlot:1 error:&error] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainSelf = weakSelf;
            if (!mainSelf) return;
            if (!first || !second) {
                [mainSelf showAlertTitle:@"Open Tokyo image fetch failed" message:error.localizedDescription];
                mainSelf.status.stringValue = @"Open Tokyo image fetch failed.";
                return;
            }

            NSError *loadError = nil;
            BOOL loadedA = [mainSelf.renderer loadImageAtURL:first[@"url"] slot:0 error:&loadError];
            BOOL loadedB = loadedA ? [mainSelf.renderer loadImageAtURL:second[@"url"] slot:1 error:&loadError] : NO;
            if (!loadedA || !loadedB) {
                [mainSelf showAlertTitle:@"Could not use open images" message:loadError.localizedDescription];
                mainSelf.status.stringValue = @"Open images could not be loaded.";
                return;
            }

            mainSelf.labelA.stringValue = [@"Image A: " stringByAppendingString:first[@"caption"]];
            mainSelf.labelB.stringValue = [@"Image B: " stringByAppendingString:second[@"caption"]];
            mainSelf.status.stringValue = @"Loaded random open Tokyo pair.";
        });
    });
}

- (void)loadSlot:(NSInteger)slot {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypePNG, UTTypeJPEG, UTTypeTIFF, UTTypeGIF, UTTypeBMP, UTTypeWebP];
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSError *error = nil;
    if (![self.renderer loadImageAtURL:panel.URL slot:slot error:&error]) {
        [self showAlertTitle:@"Could not load image" message:error.localizedDescription];
        return;
    }
    NSString *name = panel.URL.lastPathComponent;
    if (slot == 0) self.labelA.stringValue = [@"Image A: " stringByAppendingString:name];
    else self.labelB.stringValue = [@"Image B: " stringByAppendingString:name];
    self.status.stringValue = self.renderer.textureA && self.renderer.textureB ? @"Rendering live on the GPU." : @"Load the second image to begin.";
}

- (void)randomize:(id)sender {
    SlitUniforms u = self.renderer.uniforms;
    u.mode = arc4random_uniform(14);
    u.slitWidth = 1 + arc4random_uniform(95);
    u.drift = (int)arc4random_uniform(441) - 220;
    u.blend = arc4random_uniform(58);
    u.wave = arc4random_uniform(181);
    u.phase = arc4random_uniform(101) / 100.0;
    u.grain = arc4random_uniform(38);
    u.colorShift = (int)arc4random_uniform(81) - 40;
    u.canvasWidth = 140 + arc4random_uniform(281);
    u.exportScale = 1 + arc4random_uniform(4);
    u.chaos = arc4random_uniform(101);
    u.crush = arc4random_uniform(62);
    u.sourceFight = 15 + arc4random_uniform(86);
    self.renderer.uniforms = u;
    self.status.stringValue = @"Randomized.";
}

- (void)exportImage:(id)sender {
    if (!self.renderer.textureA || !self.renderer.textureB) {
        self.status.stringValue = @"Load two images before exporting.";
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePNG, UTTypeJPEG];
    panel.nameFieldStringValue = @"slitscan.png";
    if ([panel runModal] != NSModalResponseOK) return;
    NSUInteger width = std::max(self.renderer.textureA.width, self.renderer.textureB.width);
    NSUInteger height = std::max(self.renderer.textureA.height, self.renderer.textureB.height);
    double stretch = std::max(1.0, (double)self.renderer.uniforms.canvasWidth / 100.0);
    double upscale = std::max(1.0, std::min(4.0, (double)self.renderer.uniforms.exportScale));
    width = (NSUInteger)std::round(width * stretch);
    height = (NSUInteger)std::round(height * upscale);
    width = (NSUInteger)std::round(width * upscale);
    double scale = std::min(1.0, 8192.0 / std::max(width, height));
    NSError *error = nil;
    BOOL ok = [self.renderer exportToURL:panel.URL size:CGSizeMake(width * scale, height * scale) error:&error];
    self.status.stringValue = ok ? [NSString stringWithFormat:@"Exported current frame at %.1fx.", upscale * scale] : @"Export failed.";
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
