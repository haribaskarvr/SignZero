/**
 * Extracts the ink from an uploaded signature photo or scan, as PDF readers do: paper becomes transparent and the
 * result is cropped to the signature. The paper is estimated with a morphological closing, so shadows and uneven
 * light are not mistaken for ink. Pure pixel maths, no DOM.
 */

// Darkness relative to the local paper: below LOW is paper, above HIGH is solid ink, in between is a soft edge.
const LOW = 0.12;
const HIGH = 0.35;
// Pixels at least this opaque count as ink when measuring the signature.
const INK_ALPHA = 128;
// Blobs at least this share of all ink form the signature; smaller ones count only within NEAR of it, so distant
// dust does not stretch the crop.
const MAIN_BLOB = 0.01;
const NEAR = 0.15;
// Padding around the strokes, as a share of the signature's size (plus 2 px for soft edges).
const PADDING = 0.01;
// Below this many ink pixels, or above this share of the image, it is not a signature.
const MIN_INK_PIXELS = 40;
const MAX_INK_SHARE = 0.6;

/**
 * @param {{ data: Uint8ClampedArray, width: number, height: number }} image RGBA pixels
 * @returns the image with transparent paper and darkened ink, plus the signature's crop; null when none is found
 */
export function extractInk(image) {
    const { data, width, height } = image;
    const luminance = new Float32Array(width * height);
    for (let p = 0, i = 0; p < luminance.length; p++, i += 4) {
        luminance[p] = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    }
    const paper = paperBrightness(luminance, width, height);

    const out = new Uint8ClampedArray(data.length);
    const ink = new Uint8Array(width * height);
    let inkPixels = 0;
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const p = y * width + x;
            const i = p * 4;
            const bg = paper[p];
            const darkness = bg < 1 ? 0 : (bg - luminance[p]) / bg;
            const alpha = Math.round(255 * smoothstep(LOW, HIGH, darkness));
            if (alpha === 0) {
                continue;
            }
            // Deepen the ink, keeping its colour, so a pale pen still reads clearly.
            const deepen = Math.min(1, 45 / Math.max(luminance[p], 1));
            out[i] = data[i] * deepen;
            out[i + 1] = data[i + 1] * deepen;
            out[i + 2] = data[i + 2] * deepen;
            out[i + 3] = alpha;
            if (alpha >= INK_ALPHA) {
                ink[p] = 1;
                inkPixels++;
            }
        }
    }
    if (inkPixels < MIN_INK_PIXELS || inkPixels > MAX_INK_SHARE * width * height) {
        return null;
    }

    const box = signatureBox(ink, width, height, inkPixels);
    const { left, top, right, bottom } = box;
    const padX = Math.round((right - left + 1) * PADDING) + 2;
    const padY = Math.round((bottom - top + 1) * PADDING) + 2;
    const x0 = Math.max(0, left - padX);
    const y0 = Math.max(0, top - padY);
    const x1 = Math.min(width - 1, right + padX);
    const y1 = Math.min(height - 1, bottom + padY);
    return {
        data: out,
        width,
        height,
        crop: { x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 }
    };
}

/** Paper brightness at every pixel: a closing erases strokes thinner than the window but keeps shadows. */
function paperBrightness(luminance, width, height) {
    // Strokes up to twice this wide count as ink: a bold marker photographed close up is about 4% of the image.
    const radius = Math.max(6, Math.round(Math.max(width, height) / 50));
    const a = new Float32Array(luminance.length);
    const b = new Float32Array(luminance.length);
    filterRows(luminance, a, width, height, radius, true);
    filterColumns(a, b, width, height, radius, true);
    filterRows(b, a, width, height, radius, false);
    filterColumns(a, b, width, height, radius, false);
    return b;
}

function filterRows(src, dst, width, height, radius, takeMax) {
    for (let y = 0; y < height; y++) {
        slidingExtreme(src, dst, y * width, 1, width, radius, takeMax);
    }
}

function filterColumns(src, dst, width, height, radius, takeMax) {
    for (let x = 0; x < width; x++) {
        slidingExtreme(src, dst, x, width, height, radius, takeMax);
    }
}

// Max (or min) over a +-radius window along a row or column, in linear time.
function slidingExtreme(src, dst, start, step, length, radius, takeMax) {
    const queue = new Int32Array(length);
    let head = 0;
    let tail = 0;
    const better = takeMax ? (u, v) => u >= v : (u, v) => u <= v;
    for (let k = 0; k < length + radius; k++) {
        if (k < length) {
            const value = src[start + k * step];
            while (tail > head && better(value, src[start + queue[tail - 1] * step])) {
                tail--;
            }
            queue[tail++] = k;
        }
        const centre = k - radius;
        if (centre >= 0) {
            while (queue[head] < centre - radius) {
                head++;
            }
            dst[start + centre * step] = src[start + queue[head] * step];
        }
    }
}

/** Bounding box of the large ink blobs, grown to take in nearby small ones (an i-dot) but not distant specks. */
function signatureBox(ink, width, height, inkPixels) {
    const blobs = [];
    const seen = new Uint8Array(ink.length);
    const stack = new Int32Array(ink.length);
    for (let start = 0; start < ink.length; start++) {
        if (!ink[start] || seen[start]) {
            continue;
        }
        const blob = { size: 0, left: width, top: height, right: 0, bottom: 0 };
        let depth = 0;
        stack[depth++] = start;
        seen[start] = 1;
        while (depth > 0) {
            const p = stack[--depth];
            const x = p % width;
            const y = (p - x) / width;
            blob.size++;
            blob.left = Math.min(blob.left, x);
            blob.right = Math.max(blob.right, x);
            blob.top = Math.min(blob.top, y);
            blob.bottom = Math.max(blob.bottom, y);
            for (let dy = -1; dy <= 1; dy++) {
                for (let dx = -1; dx <= 1; dx++) {
                    const nx = x + dx;
                    const ny = y + dy;
                    if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
                        continue;
                    }
                    const q = ny * width + nx;
                    if (ink[q] && !seen[q]) {
                        seen[q] = 1;
                        stack[depth++] = q;
                    }
                }
            }
        }
        blobs.push(blob);
    }

    const main = blobs.filter((b) => b.size >= inkPixels * MAIN_BLOB);
    const box = main.reduce(
        (acc, b) => ({
            left: Math.min(acc.left, b.left),
            top: Math.min(acc.top, b.top),
            right: Math.max(acc.right, b.right),
            bottom: Math.max(acc.bottom, b.bottom)
        }),
        { left: width, top: height, right: 0, bottom: 0 }
    );
    const reach = NEAR * Math.max(box.right - box.left, box.bottom - box.top);
    for (const b of blobs) {
        if (b.size >= inkPixels * MAIN_BLOB) {
            continue;
        }
        const gapX = Math.max(0, box.left - b.right, b.left - box.right);
        const gapY = Math.max(0, box.top - b.bottom, b.top - box.bottom);
        if (Math.max(gapX, gapY) <= reach) {
            box.left = Math.min(box.left, b.left);
            box.top = Math.min(box.top, b.top);
            box.right = Math.max(box.right, b.right);
            box.bottom = Math.max(box.bottom, b.bottom);
        }
    }
    return box;
}

function smoothstep(edge0, edge1, value) {
    const t = Math.min(Math.max((value - edge0) / (edge1 - edge0), 0), 1);
    return t * t * (3 - 2 * t);
}
