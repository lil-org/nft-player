// ∅ 2026 lil org

#include <metal_stdlib>
using namespace metal;

struct PonchoDrifellaVertex {
    float2 position;
    float2 uv;
};

struct PonchoDrifellaVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct PonchoDrifellaUniforms {
    float2 pointer;
    float2 background;
    float2 cardSize;
    float pointerFromCenter;
    float opacity;
    float maskUsesAlpha;
    int effectKind;
    int glowKind;
    float padding;
};

vertex PonchoDrifellaVertexOut ponchoDrifellaVertex(
    const device PonchoDrifellaVertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    PonchoDrifellaVertexOut out;
    out.position = float4(vertices[vertexID].position, 0, 1);
    out.uv = vertices[vertexID].uv;
    return out;
}

static float luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

static float hslHueChannel(float p, float q, float t) {
    t = fract(t);
    if (t < 1.0 / 6.0) { return p + (q - p) * 6.0 * t; }
    if (t < 0.5) { return q; }
    if (t < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - t) * 6.0; }
    return p;
}

static float3 hslToRgb(float3 hsl) {
    float hue = fract(hsl.x);
    float saturation = saturate(hsl.y);
    float lightness = saturate(hsl.z);

    if (saturation <= 0.0001) {
        return float3(lightness);
    }

    float q = lightness < 0.5 ? lightness * (1.0 + saturation) : lightness + saturation - lightness * saturation;
    float p = 2.0 * lightness - q;
    return float3(
        hslHueChannel(p, q, hue + 1.0 / 3.0),
        hslHueChannel(p, q, hue),
        hslHueChannel(p, q, hue - 1.0 / 3.0)
    );
}

static float3 hslDegrees(float hue, float saturation, float lightness) {
    return hslToRgb(float3(hue / 360.0, saturation, lightness));
}

static float3 screenBlend(float3 base, float3 blend) {
    return 1.0 - (1.0 - base) * (1.0 - blend);
}

static float3 multiplyBlend(float3 base, float3 blend) {
    return base * blend;
}

static float3 overlayBlend(float3 base, float3 blend) {
    return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), step(float3(0.5), base));
}

static float3 hardLightBlend(float3 base, float3 blend) {
    return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), step(float3(0.5), blend));
}

static float3 softLightBlend(float3 base, float3 blend) {
    float3 low = 2.0 * base * blend + base * base * (1.0 - 2.0 * blend);
    float3 high = sqrt(max(base, 0.0)) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend);
    return mix(low, high, step(float3(0.5), blend));
}

static float3 colorDodgeBlend(float3 base, float3 blend) {
    return saturate(base / max(1.0 - blend, 0.025));
}

static float3 colorBurnBlend(float3 base, float3 blend) {
    return saturate(1.0 - (1.0 - base) / max(blend, 0.025));
}

static float3 exclusionBlend(float3 base, float3 blend) {
    return base + blend - 2.0 * base * blend;
}

static float3 lightenBlend(float3 base, float3 blend) {
    return max(base, blend);
}

static float cssLum(float3 color) {
    return dot(color, float3(0.30, 0.59, 0.11));
}

static float cssSat(float3 color) {
    return max(max(color.r, color.g), color.b) - min(min(color.r, color.g), color.b);
}

static float3 cssClipColor(float3 color) {
    float lum = cssLum(color);
    float minChannel = min(min(color.r, color.g), color.b);
    float maxChannel = max(max(color.r, color.g), color.b);

    if (minChannel < 0.0) {
        color = lum + (color - lum) * lum / max(lum - minChannel, 0.0001);
    }
    if (maxChannel > 1.0) {
        color = lum + (color - lum) * (1.0 - lum) / max(maxChannel - lum, 0.0001);
    }

    return color;
}

static float3 cssSetLum(float3 color, float lum) {
    return cssClipColor(color + (lum - cssLum(color)));
}

static float3 cssSetSat(float3 color, float saturation) {
    float minChannel = min(min(color.r, color.g), color.b);
    float maxChannel = max(max(color.r, color.g), color.b);
    float delta = maxChannel - minChannel;

    if (delta <= 0.0001) {
        return float3(0.0);
    }

    return (color - minChannel) * saturation / delta;
}

static float3 hueBlend(float3 base, float3 blend) {
    base = saturate(base);
    blend = saturate(blend);
    return cssSetLum(cssSetSat(blend, cssSat(base)), cssLum(base));
}

static float3 luminosityBlend(float3 base, float3 blend) {
    base = saturate(base);
    blend = saturate(blend);
    return cssSetLum(base, cssLum(blend));
}

static float3 saturationBlend(float3 base, float3 blend) {
    base = saturate(base);
    blend = saturate(blend);
    return cssSetLum(cssSetSat(base, cssSat(blend)), cssLum(base));
}

static float3 saturationColor(float3 color, float amount) {
    float value = luminance(color);
    return saturate(mix(float3(value), color, amount));
}

static float3 filterColor(float3 color, float brightness, float contrast, float saturation) {
    color *= brightness;
    color = (color - 0.5) * contrast + 0.5;
    return saturationColor(color, saturation);
}

struct PonchoCssLayer {
    float3 color;
    float alpha;
};

static PonchoCssLayer cssLayer(float3 color, float alpha) {
    PonchoCssLayer layer;
    layer.color = color;
    layer.alpha = saturate(alpha);
    return layer;
}

static float linearStep(float start, float end, float value) {
    return saturate((value - start) / max(end - start, 0.0001));
}

static float3 sunpillarColor(float value) {
    float segment = fract(value) * 6.0;
    float3 c1 = float3(1.0, 0.48, 0.46);
    float3 c2 = float3(1.0, 0.92, 0.38);
    float3 c3 = float3(0.63, 1.0, 0.38);
    float3 c4 = float3(0.52, 1.0, 0.97);
    float3 c5 = float3(0.48, 0.58, 1.0);
    float3 c6 = float3(0.82, 0.46, 1.0);

    if (segment < 1.0) { return mix(c1, c2, segment); }
    if (segment < 2.0) { return mix(c2, c3, segment - 1.0); }
    if (segment < 3.0) { return mix(c3, c4, segment - 2.0); }
    if (segment < 4.0) { return mix(c4, c5, segment - 3.0); }
    if (segment < 5.0) { return mix(c5, c6, segment - 4.0); }
    return mix(c6, c1, segment - 5.0);
}

static float positiveModulo(float value, float period) {
    return value - floor(value / period) * period;
}

static float2 cssBackgroundLocalPixel(float2 uv, float2 cardSize, float2 tileSize, float2 position) {
    float2 pixel = uv * cardSize;
    float2 offset = (cardSize - tileSize) * position;
    return pixel - offset;
}

static float2 cssBackgroundImageUV(float2 uv, float2 cardSize, float2 tileSize, float2 position) {
    return cssBackgroundLocalPixel(uv, cardSize, tileSize, position) / max(tileSize, float2(1.0));
}

static float cssLinearGradientPercent(
    float2 uv,
    float2 cardSize,
    float2 tileScale,
    float2 position,
    float angleDegrees
) {
    float2 tileSize = max(cardSize * tileScale, float2(1.0));
    float2 localPixel = cssBackgroundLocalPixel(uv, cardSize, tileSize, position);
    float angle = angleDegrees * 0.017453292519943295;
    float2 axis = normalize(float2(sin(angle), -cos(angle)));
    float lineLength = max(abs(axis.x) * tileSize.x + abs(axis.y) * tileSize.y, 1.0);
    return (dot(localPixel - tileSize * 0.5, axis) + lineLength * 0.5) / lineLength;
}

static float cssPixelRadialProgress(float2 uv, float2 pointer, float2 cardSize) {
    float2 pixel = uv * cardSize;
    float2 center = pointer * cardSize;
    float d0 = distance(center, float2(0.0, 0.0));
    float d1 = distance(center, float2(cardSize.x, 0.0));
    float d2 = distance(center, float2(0.0, cardSize.y));
    float d3 = distance(center, cardSize);
    return distance(pixel, center) / max(max(max(d0, d1), max(d2, d3)), 1.0);
}

static PonchoCssLayer cssPixelRadialAlphaStops(
    float2 uv,
    float2 pointer,
    float2 cardSize,
    float3 color0,
    float alpha0,
    float stop0,
    float3 color1,
    float alpha1,
    float stop1,
    float3 color2,
    float alpha2,
    float stop2
) {
    float d = cssPixelRadialProgress(uv, pointer, cardSize);
    float midMix = linearStep(stop0, stop1, d);
    float outerMix = linearStep(stop1, stop2, d);
    float3 color = mix(mix(color0, color1, midMix), color2, outerMix);
    float alpha = mix(mix(alpha0, alpha1, midMix), alpha2, outerMix);
    return cssLayer(color, alpha);
}

static PonchoCssLayer premultipliedStopMix(
    float3 colorA,
    float alphaA,
    float3 colorB,
    float alphaB,
    float value
) {
    float alpha = mix(alphaA, alphaB, value);
    float3 premultiplied = mix(colorA * alphaA, colorB * alphaB, value);
    float3 color = alpha > 0.0001 ? premultiplied / alpha : float3(0.0);
    return cssLayer(color, alpha);
}

static PonchoCssLayer cssPixelRadialPremultipliedAlphaStops(
    float2 uv,
    float2 pointer,
    float2 cardSize,
    float3 color0,
    float alpha0,
    float stop0,
    float3 color1,
    float alpha1,
    float stop1,
    float3 color2,
    float alpha2,
    float stop2
) {
    float d = cssPixelRadialProgress(uv, pointer, cardSize);
    float midMix = linearStep(stop0, stop1, d);
    float outerMix = linearStep(stop1, stop2, d);
    PonchoCssLayer inner = premultipliedStopMix(color0, alpha0, color1, alpha1, midMix);
    return premultipliedStopMix(inner.color, inner.alpha, color2, alpha2, outerMix);
}

static PonchoCssLayer cssBackgroundRadialPremultipliedAlphaStops(
    float2 uv,
    float2 pointer,
    float2 cardSize,
    float2 tileScale,
    float2 position,
    float3 color0,
    float alpha0,
    float stop0,
    float3 color1,
    float alpha1,
    float stop1,
    float3 color2,
    float alpha2,
    float stop2
) {
    float2 tileSize = max(cardSize * tileScale, float2(1.0));
    float2 imageUV = cssBackgroundImageUV(uv, cardSize, tileSize, position);
    return cssPixelRadialPremultipliedAlphaStops(
        imageUV,
        pointer,
        tileSize,
        color0,
        alpha0,
        stop0,
        color1,
        alpha1,
        stop1,
        color2,
        alpha2,
        stop2
    );
}

static float3 rareHoloVDiagonalColor(float percent) {
    float phase = positiveModulo(percent, 0.12);
    float3 dark = float3(0.055, 0.082, 0.18);
    float3 muted = float3(0.56, 0.64, 0.64);
    float3 cyan = float3(0.55, 0.78, 0.80);

    if (phase < 0.038) { return mix(dark, muted, phase / 0.038); }
    if (phase < 0.045) { return mix(muted, cyan, (phase - 0.038) / 0.007); }
    if (phase < 0.052) { return mix(cyan, muted, (phase - 0.045) / 0.007); }
    if (phase < 0.10) { return mix(muted, dark, (phase - 0.052) / 0.048); }
    return dark;
}

static float3 rareHoloVCssDiagonal(float2 uv, float2 cardSize, float2 tileScale, float2 position) {
    return rareHoloVDiagonalColor(cssLinearGradientPercent(uv, cardSize, tileScale, position, 133.0));
}

static float3 rareHoloVCssSunpillar(float2 uv, float2 cardSize, float2 tileScale, float2 position) {
    float percent = cssLinearGradientPercent(uv, cardSize, tileScale, position, 0.0);
    float phase = positiveModulo(percent - 0.05, 0.30) / 0.30;
    return sunpillarColor(phase);
}

static PonchoCssLayer rareHoloVCssRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialAlphaStops(
        uv,
        pointer,
        cardSize,
        float3(0.0),
        0.10,
        0.12,
        float3(0.0),
        0.15,
        0.20,
        float3(0.0),
        0.25,
        1.20
    );
}

static PonchoCssLayer amazingRareShineRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        hslDegrees(150.0, 0.20, 0.10),
        1.0,
        0.10,
        hslDegrees(177.0, 0.22, 0.80),
        0.10,
        0.50,
        float3(0.95),
        0.98,
        0.90
    );
}

static PonchoCssLayer amazingRareBeforeRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        hslDegrees(50.0, 0.20, 0.90),
        0.95,
        0.10,
        float3(181.0 / 255.0, 139.0 / 255.0, 164.0 / 255.0),
        0.50,
        0.50,
        float3(0.0),
        1.0,
        0.60
    );
}

static float3 amazingRareAfterSunpillar(float2 uv, float2 background, float2 cardSize) {
    float2 position = 0.5 + (0.5 - background) * 3.0;
    float percent = cssLinearGradientPercent(uv, cardSize, float2(4.0, 8.0), position, 133.0);
    float phase = positiveModulo(percent - 0.05, 0.30) / 0.30;
    return sunpillarColor(phase + 5.0 / 6.0);
}

static PonchoCssLayer amazingRareGlareRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        hslDegrees(50.0, 0.20, 0.90),
        0.45,
        0.0,
        hslDegrees(150.0, 0.20, 0.30),
        0.45,
        0.45,
        float3(0.0),
        0.90,
        1.20
    );
}

static PonchoCssLayer amazingRareGlareAfterRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        hslDegrees(50.0, 0.20, 0.90),
        0.75,
        0.0,
        hslDegrees(150.0, 0.20, 0.30),
        0.65,
        0.45,
        float3(0.0),
        1.0,
        0.90
    );
}

static float3 rareHoloRainbowStop(int index) {
    switch (index % 5) {
    case 0: return float3(201.0 / 255.0, 41.0 / 255.0, 241.0 / 255.0);
    case 1: return float3(13.0 / 255.0, 189.0 / 255.0, 233.0 / 255.0);
    case 2: return float3(33.0 / 255.0, 233.0 / 255.0, 133.0 / 255.0);
    case 3: return float3(238.0 / 255.0, 223.0 / 255.0, 16.0 / 255.0);
    default: return float3(248.0 / 255.0, 14.0 / 255.0, 53.0 / 255.0);
    }
}

static float3 rareHoloRainbowLayer(float2 uv, float2 background, float2 cardSize) {
    float2 position = float2(
        ((0.5 - background.x) * 2.6) + 0.5,
        ((0.5 - background.y) * 3.5) + 0.5
    );
    float percent = cssLinearGradientPercent(uv, cardSize, float2(4.0), position, 110.0);
    float value = positiveModulo(percent, 1.0) * 14.0;
    int index = min(int(floor(value)), 13);
    return mix(rareHoloRainbowStop(index), rareHoloRainbowStop(index + 1), value - float(index));
}

static float3 rareHoloScanlinesLayer(float2 uv, float2 cardSize) {
    float scanlineSpace = 1.0;
    float pixel = uv.x * cardSize.x / scanlineSpace;
    float phase = positiveModulo(pixel, 4.0);
    float antialias = max(fwidth(pixel), 0.001);
    float light = smoothstep(2.0 - antialias, 2.0 + antialias, phase)
        * (1.0 - smoothstep(4.0 - antialias, 4.0 + antialias, phase));
    return mix(float3(0.0), float3(102.0 / 255.0), light);
}

static float rareHoloBarValue(float percent, float period) {
    float phase = positiveModulo(percent, period);
    float value = 0.0;
    value = mix(value, 0.70, linearStep(0.06, 0.09, phase));
    value = mix(value, 0.0, linearStep(0.09, 0.105, phase));
    value = mix(value, 0.70, linearStep(0.105, 0.12, phase));
    value = mix(value, 0.0, linearStep(0.12, 0.15, phase));
    return value;
}

static float rareHoloBarLayer(float2 uv, float2 cardSize, float2 position, float period) {
    float percent = cssLinearGradientPercent(uv, cardSize, float2(2.0), position, 90.0);
    return rareHoloBarValue(percent, period);
}

static PonchoCssLayer rareHoloShineAfterRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        float3(0.90),
        0.80,
        0.0,
        float3(0.78),
        0.10,
        0.25,
        float3(0.0),
        1.0,
        0.90
    );
}

static PonchoCssLayer rareHoloGlareRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        float3(1.0),
        0.80,
        0.10,
        float3(1.0),
        0.65,
        0.20,
        float3(0.0),
        0.50,
        0.90
    );
}

static PonchoCssLayer rareHoloGlareAfterRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        hslDegrees(180.0, 1.0, 0.95),
        1.0,
        0.05,
        float3(0.39),
        0.25,
        0.55,
        float3(0.0),
        0.36,
        1.10
    );
}

static float3 blendModeColor(float3 base, float3 layer, int mode) {
    switch (mode) {
    case 0: return screenBlend(base, layer);
    case 1: return overlayBlend(base, layer);
    case 2: return hardLightBlend(base, layer);
    case 3: return softLightBlend(base, layer);
    case 4: return colorDodgeBlend(base, layer);
    case 5: return colorBurnBlend(base, layer);
    case 6: return exclusionBlend(base, layer);
    case 7: return multiplyBlend(base, layer);
    case 8: return lightenBlend(base, layer);
    case 9: return luminosityBlend(base, layer);
    case 10: return saturationBlend(base, layer);
    case 11: return hueBlend(base, layer);
    default: return layer;
    }
}

static float3 applyCssLayer(float3 base, float3 layer, float alpha, int mode) {
    alpha = saturate(alpha);
    return mix(base, blendModeColor(base, layer, mode), alpha);
}

static float3 applyBrowserLayer(float3 base, float3 layer, float alpha, int mode) {
    alpha = saturate(alpha);
    float3 backdrop = saturate(base);
    float3 source = saturate(layer);
    float3 blended = saturate(blendModeColor(backdrop, source, mode));
    return saturate(mix(backdrop, blended, alpha));
}

static PonchoCssLayer compositeCssBackground(PonchoCssLayer backdrop, PonchoCssLayer source, int mode) {
    float sourceAlpha = saturate(source.alpha);
    float backdropAlpha = saturate(backdrop.alpha);
    float outputAlpha = sourceAlpha + backdropAlpha * (1.0 - sourceAlpha);
    if (outputAlpha <= 0.0001) {
        return cssLayer(float3(0.0), 0.0);
    }

    float3 blended = blendModeColor(backdrop.color, source.color, mode);
    float3 color = (
        source.color * sourceAlpha * (1.0 - backdropAlpha) +
        blended * sourceAlpha * backdropAlpha +
        backdrop.color * backdropAlpha * (1.0 - sourceAlpha)
    ) / outputAlpha;
    return cssLayer(color, outputAlpha);
}

static float3 supporterCssSunpillar(
    float2 uv,
    float2 cardSize,
    float2 tileScale,
    float2 position,
    bool isAfter
) {
    float percent = cssLinearGradientPercent(uv, cardSize, tileScale, position, 0.0);
    float phase = positiveModulo(percent - 0.05, 0.30) / 0.30;
    return sunpillarColor(phase + (isAfter ? 5.0 / 6.0 : 0.0));
}

static PonchoCssLayer supporterPointerRadial(
    float2 uv,
    float2 pointer,
    float2 background,
    float2 cardSize
) {
    return cssBackgroundRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        float2(2.0, 1.0),
        background,
        float3(0.0),
        0.10,
        0.12,
        float3(0.0),
        0.15,
        0.20,
        float3(0.0),
        0.25,
        1.20
    );
}

static PonchoCssLayer supporterFoilLayer(
    float2 uv,
    float2 pointer,
    float2 background,
    float2 cardSize,
    float3 foil,
    bool isAfter
) {
    float sunHeightScale = isAfter ? 4.0 : 7.0;
    float diagonalWidthScale = isAfter ? 1.95 : 3.0;
    float diagonalX = background.x + background.y * 0.20;
    float2 diagonalPosition = isAfter ? float2(-diagonalX, -background.y) : float2(diagonalX, background.y);

    PonchoCssLayer layer = supporterPointerRadial(uv, pointer, background, cardSize);
    float3 diagonalColor = rareHoloVCssDiagonal(
        uv,
        cardSize,
        float2(diagonalWidthScale, 1.0),
        diagonalPosition
    );
    if (isAfter) {
        float diagonalBand = smoothstep(0.42, 0.72, luminance(diagonalColor));
        diagonalColor = mix(diagonalColor, max(diagonalColor, float3(0.82)), diagonalBand * 0.35);
    }

    PonchoCssLayer diagonal = cssLayer(diagonalColor, 1.0);
    layer = compositeCssBackground(layer, diagonal, 2);

    PonchoCssLayer sun = cssLayer(
        supporterCssSunpillar(
            uv,
            cardSize,
            float2(2.0, sunHeightScale),
            float2(0.0, background.y),
            isAfter
        ),
        1.0
    );
    layer = compositeCssBackground(layer, sun, 11);
    layer = compositeCssBackground(layer, cssLayer(saturate(foil), 1.0), 3);
    return layer;
}

static PonchoCssLayer supporterShineBeforeRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssPixelRadialAlphaStops(
        uv,
        pointer,
        cardSize,
        float3(1.0),
        1.0,
        0.0,
        float3(0.0),
        0.0,
        0.80,
        float3(0.0),
        0.0,
        1.0
    );
}

static PonchoCssLayer supporterGlareRadial(float2 uv, float2 pointer, float2 cardSize) {
    return cssBackgroundRadialPremultipliedAlphaStops(
        uv,
        pointer,
        cardSize,
        float2(1.7),
        float2(0.5),
        float3(0.75),
        1.0,
        0.05,
        hslDegrees(200.0, 0.05, 0.35),
        1.0,
        0.60,
        hslDegrees(320.0, 0.40, 0.10),
        1.0,
        1.50
    );
}

static PonchoCssLayer rareHoloVLayer(
    float2 uv,
    float2 pointer,
    float2 background,
    float2 cardSize,
    float3 grain,
    bool isAfter
) {
    float sunHeightScale = isAfter ? 4.0 : 7.0;
    float diagonalWidthScale = isAfter ? 1.95 : 3.0;
    float2 diagonalPosition = isAfter ? -background : background;

    PonchoCssLayer layer = rareHoloVCssRadial(uv, pointer, cardSize);
    PonchoCssLayer diagonal = cssLayer(
        rareHoloVCssDiagonal(
            uv,
            cardSize,
            float2(diagonalWidthScale, 1.0),
            diagonalPosition
        ),
        1.0
    );
    layer = compositeCssBackground(layer, diagonal, 2);

    PonchoCssLayer sun = cssLayer(
        rareHoloVCssSunpillar(
            uv,
            cardSize,
            float2(2.0, sunHeightScale),
            float2(0.0, background.y)
        ),
        1.0
    );
    layer = compositeCssBackground(layer, sun, 11);
    layer = compositeCssBackground(layer, cssLayer(saturate(grain), 1.0), 0);
    return layer;
}

static float roundedCardMask(float2 uv) {
    float2 radius = float2(0.0455, 0.035);
    float2 corner = min(uv, 1.0 - uv);
    if (corner.x >= radius.x || corner.y >= radius.y) {
        return 1.0;
    }

    float2 arc = (corner - radius) / radius;
    return step(length(arc), 1.0);
}

static float3 glowColor(int glowKind) {
    switch (glowKind) {
    case 1: return float3(0.12, 0.74, 1.0);
    case 2: return float3(1.0, 0.22, 0.13);
    case 3: return float3(0.45, 1.0, 0.18);
    case 4: return float3(1.0, 0.88, 0.18);
    case 5: return float3(0.68, 0.24, 0.98);
    case 6: return float3(0.56, 0.32, 0.12);
    case 7: return float3(0.05, 0.43, 0.48);
    case 8: return float3(0.62, 0.52, 0.14);
    case 9: return float3(1.0, 0.62, 0.9);
    default: return float3(0.62, 0.74, 0.75);
    }
}

fragment float4 ponchoDrifellaFragment(
    PonchoDrifellaVertexOut in [[stage_in]],
    constant PonchoDrifellaUniforms &uniforms [[buffer(0)]],
    texture2d<float> faceTexture [[texture(0)]],
    texture2d<float> foilTexture [[texture(1)]],
    texture2d<float> maskTexture [[texture(2)]],
    texture2d<float> grainTexture [[texture(3)]],
    texture2d<float> glitterTexture [[texture(4)]]
) {
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler clampMipSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler repeatSampler(filter::linear, address::repeat);
    constexpr sampler repeatMipSampler(filter::linear, mip_filter::linear, address::repeat);

    float2 uv = in.uv;
    if (roundedCardMask(uv) < 0.5) {
        discard_fragment();
    }

    float3 base = faceTexture.sample(clampSampler, uv).rgb;
    float opacity = saturate(uniforms.opacity);
    if (opacity <= 0.0001) {
        return float4(saturate(base), 1.0);
    }

    float2 cardSize = max(uniforms.cardSize, float2(1.0));
    float2 maskOffset = 0.5 / cardSize;
    float4 maskCenter = maskTexture.sample(clampMipSampler, uv);
    float4 maskLeft = maskTexture.sample(clampMipSampler, uv + float2(-maskOffset.x, 0.0));
    float4 maskRight = maskTexture.sample(clampMipSampler, uv + float2(maskOffset.x, 0.0));
    float4 maskTop = maskTexture.sample(clampMipSampler, uv + float2(0.0, -maskOffset.y));
    float4 maskBottom = maskTexture.sample(clampMipSampler, uv + float2(0.0, maskOffset.y));
    float maskAlphaAverage = (
        maskCenter.a * 0.40 +
        (maskLeft.a + maskRight.a + maskTop.a + maskBottom.a) * 0.15
    );
    float rgbMaskAverage = (
        luminance(maskCenter.rgb) * 0.40 +
        (luminance(maskLeft.rgb) + luminance(maskRight.rgb) + luminance(maskTop.rgb) + luminance(maskBottom.rgb)) * 0.15
    );
    float maskAlpha = saturate(uniforms.maskUsesAlpha > 0.5 ? maskAlphaAverage : rgbMaskAverage);
    float2 pointer = uniforms.pointer;
    float2 background = uniforms.background;
    float pfc = saturate(uniforms.pointerFromCenter);

    switch (uniforms.effectKind) {
    case 1: {
        // rare ultra supporter
        float3 foilSharp = foilTexture.sample(clampSampler, uv).rgb;
        PonchoCssLayer shineGroup = supporterFoilLayer(uv, pointer, background, cardSize, foilSharp, false);
        shineGroup.color = filterColor(shineGroup.color, pfc * 0.05 + 0.80, 1.75, 1.20);

        PonchoCssLayer shineBefore = supporterShineBeforeRadial(uv, pointer, cardSize);
        shineGroup = compositeCssBackground(
            shineGroup,
            cssLayer(shineBefore.color, shineBefore.alpha * 0.50),
            0
        );

        PonchoCssLayer shineAfter = supporterFoilLayer(uv, pointer, background, cardSize, foilSharp, true);
        shineAfter.color = filterColor(shineAfter.color, pfc * 0.40 + 0.85, 2.0, 0.50);
        shineGroup = compositeCssBackground(
            shineGroup,
            cssLayer(shineAfter.color, shineAfter.alpha * 0.99),
            6
        );

        float supporterHotspot = maskAlpha * smoothstep(0.52, 0.82, luminance(shineGroup.color));
        float diagonalX = background.x + background.y * 0.20;
        float3 supporterMainDiagonal = rareHoloVCssDiagonal(
            uv,
            cardSize,
            float2(3.0, 1.0),
            float2(diagonalX, background.y)
        );
        float3 supporterAfterDiagonal = rareHoloVCssDiagonal(
            uv,
            cardSize,
            float2(1.95, 1.0),
            float2(-diagonalX, -background.y)
        );
        float supporterRibBand = smoothstep(
            0.48,
            0.70,
            max(luminance(supporterAfterDiagonal), luminance(supporterMainDiagonal) * 0.70)
        );
        float supporterRibHotspot = maskAlpha * supporterRibBand;

        base = applyBrowserLayer(base, shineGroup.color, maskAlpha * opacity * shineGroup.alpha, 4);
        base = applyBrowserLayer(base, float3(1.0), opacity * 0.08 * supporterHotspot * shineBefore.alpha, 0);

        PonchoCssLayer glare = supporterGlareRadial(uv, pointer, cardSize);
        glare.color = filterColor(glare.color, 1.50, 1.40, 1.0);
        float glareAlpha = opacity * 0.75 * glare.alpha * (1.0 - 0.25 * supporterHotspot - 0.45 * supporterRibHotspot);
        base = applyBrowserLayer(base, glare.color, glareAlpha, 7);
        base = applyBrowserLayer(base, float3(1.0, 0.96, 0.82), opacity * 0.16 * supporterRibHotspot, 0);
        break;
    }
    case 2: {
        // amazing rare
        float2 glitterTileSize = cardSize * 0.25;
        float3 glitterA = glitterTexture.sample(
            repeatSampler,
            cssBackgroundImageUV(uv, cardSize, glitterTileSize, float2(0.40, 0.45))
        ).rgb;
        float3 glitterB = glitterTexture.sample(
            repeatSampler,
            cssBackgroundImageUV(uv, cardSize, glitterTileSize, float2(0.55, 0.55))
        ).rgb;
        float3 foilSharp = foilTexture.sample(clampSampler, uv).rgb;

        PonchoCssLayer shine = amazingRareShineRadial(uv, pointer, cardSize);
        shine = compositeCssBackground(shine, cssLayer(glitterB, 1.0), 5);
        shine = compositeCssBackground(shine, cssLayer(glitterA, 1.0), 3);
        shine.color = filterColor(shine.color, 1.0, 1.0, 0.90);
        float shineCoverage = saturate(shine.alpha * maskAlpha);
        float3 shineGroup = saturate(shine.color);

        PonchoCssLayer shineBefore = amazingRareBeforeRadial(uv, pointer, cardSize);
        shineBefore = compositeCssBackground(shineBefore, cssLayer(foilSharp, 1.0), 5);
        shineGroup = applyBrowserLayer(
            shineGroup,
            shineBefore.color,
            shineBefore.alpha * 0.50,
            8
        );

        float3 shineAfter = amazingRareAfterSunpillar(uv, background, cardSize);
        shineAfter = filterColor(shineAfter, max(0.0, 0.75 - pfc * 0.50), 1.0, 1.0);
        float3 shineGroupColor = saturate(shineGroup);
        float3 saturationOnly = cssSetLum(
            cssSetSat(shineGroupColor, cssSat(saturate(shineAfter))),
            cssLum(shineGroupColor)
        );
        shineGroup = mix(shineGroupColor, saturationOnly, 0.99);

        base = applyBrowserLayer(base, shineGroup, opacity * shineCoverage, 4);

        PonchoCssLayer glare = amazingRareGlareRadial(uv, pointer, cardSize);
        glare.color = filterColor(glare.color, 0.90, 2.0, 1.0);
        base = applyBrowserLayer(base, glare.color, opacity * glare.alpha, 1);

        PonchoCssLayer glareAfter = amazingRareGlareAfterRadial(uv, pointer, cardSize);
        glareAfter.color = filterColor(glareAfter.color, 1.0, 1.5, 1.0);
        base = applyBrowserLayer(
            base,
            glareAfter.color,
            maskAlpha * opacity * 0.99 * glareAfter.alpha,
            1
        );
        break;
    }
    case 3: {
        // rare holo
        float3 rainbow = rareHoloRainbowLayer(uv, background, cardSize);
        float3 lines = rareHoloScanlinesLayer(uv, cardSize);
        float3 shine = overlayBlend(lines, rainbow);
        shine = filterColor(shine, 1.1, 1.1, 1.2);
        float3 shineGroup = shine;

        float2 barsAPosition = float2(
            (((0.5 - background.x) * 1.65) + 0.5) + (background.y * 0.5),
            background.x
        );
        float2 barsBPosition = float2(
            (((0.5 - background.x) * -0.9) + 0.5) - (background.y * 0.75),
            background.y
        );
        float barsA = rareHoloBarLayer(uv, cardSize, barsAPosition, 0.42);
        float barsB = rareHoloBarLayer(uv, cardSize, barsBPosition, 0.30);
        float3 shineBefore = screenBlend(float3(barsB), float3(barsA));
        shineBefore = filterColor(shineBefore, 1.15, 1.1, 1.0);
        shineGroup = applyBrowserLayer(shineGroup, shineBefore, 0.99, 2);

        PonchoCssLayer shineAfter = rareHoloShineAfterRadial(
            uv,
            pointer,
            cardSize
        );
        shineAfter.color = filterColor(shineAfter.color, 0.60, 4.0, 1.0);
        shineGroup = applyBrowserLayer(shineGroup, shineAfter.color, 0.99 * shineAfter.alpha, 9);

        base = applyBrowserLayer(base, shineGroup, maskAlpha * opacity, 4);

        PonchoCssLayer glare = rareHoloGlareRadial(
            uv,
            pointer,
            cardSize
        );
        glare.color = filterColor(glare.color, 0.80, 1.5, 1.0);
        base = applyBrowserLayer(base, glare.color, opacity * 0.80 * glare.alpha, 1);

        PonchoCssLayer glareAfter = rareHoloGlareAfterRadial(
            uv,
            pointer,
            cardSize
        );
        glareAfter.color = filterColor(glareAfter.color, 0.60, 3.0, 1.0);
        base = applyBrowserLayer(base, glareAfter.color, opacity * 0.80 * 0.99 * glareAfter.alpha, 1);
        break;
    }
    default: {
        // rare holo v
        float3 grain = grainTexture.sample(
            repeatMipSampler,
            cssBackgroundImageUV(uv, cardSize, float2(500.0, cardSize.y), float2(0.5))
        ).rgb;
        PonchoCssLayer shine = rareHoloVLayer(uv, pointer, background, cardSize, grain, false);
        shine.color = filterColor(shine.color, 0.80, 2.95, 0.65);
        base = applyCssLayer(base, shine.color, maskAlpha * opacity * shine.alpha, 4);

        PonchoCssLayer shineAfter = rareHoloVLayer(uv, pointer, background, cardSize, grain, true);
        shineAfter.color = filterColor(shineAfter.color, 1.0, 2.5, 1.75);
        base = applyCssLayer(base, shineAfter.color, maskAlpha * opacity * shineAfter.alpha, 3);

        PonchoCssLayer glare = cssPixelRadialAlphaStops(
            uv,
            pointer,
            cardSize,
            float3(1.0),
            1.0,
            0.0,
            float3(0.54),
            0.33,
            0.45,
            float3(0.20),
            0.90,
            1.30
        );
        glare.color = filterColor(glare.color, 0.90, 1.75, 1.0);
        base = applyCssLayer(base, glare.color, opacity * 0.50 * glare.alpha, 2);
        break;
    }
    }

    float edge = 1.0 - smoothstep(0.0, 0.08, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    base = screenBlend(base, glowColor(uniforms.glowKind) * edge * opacity * 0.10);

    return float4(saturate(base), 1.0);
}
