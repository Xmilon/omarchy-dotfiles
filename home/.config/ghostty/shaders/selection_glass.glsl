// Glass selection for Ghostty: a frosted fill, a thin light outline and a
// bright bar at each end of the selection.
//
// How it finds the selection: the selection colour (selection-background in
// overrides.conf, #4b5266) reaches this shader multiplied by the window's
// background opacity (0.38). Pixels of exactly that colour are selection
// background; near-black pixels are ordinary terminal background. Text keeps
// its own pixels, so letters are never touched.
//
// Only pixels at or next to the selection do any work; everything else is
// passed straight through. Needs custom-shader-animation = false (it doesn't
// animate), so Ghostty only runs it when the screen actually changes.

const vec3  SEL_COLOR   = vec3(75.0, 82.0, 102.0) / 255.0;
const float BG_OPACITY  = 0.38;
const float MATCH       = 0.06;             // colour tolerance
const vec3  GLASS       = vec3(0.86, 0.91, 1.0);

vec4 px(vec2 p) {
    return texture(iChannel0, p / iResolution.xy);
}

bool isSel(vec2 p) {
    return distance(px(p).rgb, SEL_COLOR * BG_OPACITY) < MATCH;
}

// Plain terminal background: (near) black.
bool isBg(vec2 p) {
    return dot(px(p).rgb, vec3(1.0)) < 0.06;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 c = px(fragCoord);
    fragColor = c;

    // Cheap exit: nothing selected here or right beside us.
    bool here = isSel(fragCoord);
    bool near = here
        || isSel(fragCoord + vec2(1.0, 0.0)) || isSel(fragCoord + vec2(2.0, 0.0))
        || isSel(fragCoord - vec2(1.0, 0.0)) || isSel(fragCoord - vec2(2.0, 0.0));
    if (!near) return;

    vec2 L1 = fragCoord - vec2(1.0, 0.0), L2 = fragCoord - vec2(2.0, 0.0), L3 = fragCoord - vec2(3.0, 0.0);
    vec2 R1 = fragCoord + vec2(1.0, 0.0), R2 = fragCoord + vec2(2.0, 0.0), R3 = fragCoord + vec2(3.0, 0.0);
    bool bgHere = isBg(fragCoord);

    // End bars: the first / last 2 px of the selection where it meets background.
    bool leftBar  = !bgHere && (isBg(L1) || isBg(L2)) && (here || isSel(R1) || isSel(R2));
    bool rightBar = !bgHere && (isBg(R1) || isBg(R2)) && (here || isSel(L1) || isSel(L2));
    if (leftBar || rightBar) {
        float a = 0.95;
        fragColor = vec4(vec3(0.95, 0.97, 1.0) * a, a);
        return;
    }

    if (!here) return;

    // Thin outline where the selection meets background above or below.
    bool edgeTop    = isBg(fragCoord + vec2(0.0, 1.0));
    bool edgeBottom = isBg(fragCoord - vec2(0.0, 1.0));
    if (edgeTop || edgeBottom) {
        float a = 0.55;
        fragColor = vec4(GLASS * a, a);
        return;
    }

    // Frosted fill: lift the tint towards a cool white, a little more at the top
    // of each line for a glassy sheen.
    float sheen = 0.16;
    if (isBg(fragCoord + vec2(0.0, 3.0)) || isBg(fragCoord + vec2(0.0, 2.0))) sheen = 0.26;
    float a = max(c.a, 0.42);
    vec3 base = c.rgb / max(c.a, 0.001);
    vec3 frosted = mix(base, GLASS, sheen);
    fragColor = vec4(frosted * a, a);
}
