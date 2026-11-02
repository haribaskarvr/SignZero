/*
 * Anchor tags and signature areas, shared by the signing page (signZeroPortal) and the Place Signatures screen
 * (signZeroFieldPlacer). Positions are in PDF points; an area's pdfX, pdfY is its bottom left corner.
 */

// Signature size in PDF points; the "Signed electronically by" caption goes just under it.
export const SIG_WIDTH = 150;
export const SIG_HEIGHT = 30;
export const MIN_SIG_HEIGHT = 16;
export const MAX_SIG_HEIGHT = 80;

const ANY_TAG = /\{\{\s*sig\s*:\s*([^}|]*?)\s*(?:\|[^}]*)?\}\}/gi;

/**
 * Where a signature goes relative to its tag:
 *   {{sig:Customer}}          on the tag's line
 *   {{sig:Customer|below}}    hanging below the tag, e.g. into an empty table cell
 *   {{sig:Customer|h=40}}     height in points (16-80); options combine: {{sig:Customer|below|h=40}}
 */
function placementFor(tagText, tagX, tagY, fontHeight) {
    const options = (tagText.match(/\|([^}]*)\}\}$/) || [null, ''])[1].toLowerCase().split('|').map((o) => o.trim());
    const heightOption = options.find((o) => /^h\s*=\s*\d+$/.test(o));
    const height = heightOption
        ? Math.min(MAX_SIG_HEIGHT, Math.max(MIN_SIG_HEIGHT, Number(heightOption.split('=')[1])))
        : SIG_HEIGHT;
    const imageY = options.includes('below')
        ? tagY + fontHeight * 0.8 - height // top of the signature level with the top of the tag
        : tagY - fontHeight * 0.2; // bottom of the signature on the tag's baseline
    return { pdfX: tagX, pdfY: imageY, height };
}

/**
 * Every {{sig:Role}} tag in the text items the PDF engine found, any role.
 * @param tagItems [{ pageIndex, itemIndex, str, width, transform }] from the engine's open
 * @returns [{ id, pageIndex, role, pdfX, pdfY, height, tagRect }]; tagRect covers the tag's text
 */
export function findAnchorTags(tagItems) {
    const tags = [];
    tagItems.forEach((item) => {
        ANY_TAG.lastIndex = 0;
        let match;
        while ((match = ANY_TAG.exec(item.str)) !== null) {
            const charWidth = item.str.length ? item.width / item.str.length : 0;
            const fontHeight = Math.hypot(item.transform[2], item.transform[3]) || 10;
            const tagX = item.transform[4] + match.index * charWidth;
            const tagY = item.transform[5];
            tags.push({
                id: `spot_${item.pageIndex + 1}_${item.itemIndex}_${match.index}`,
                pageIndex: item.pageIndex,
                role: match[1],
                ...placementFor(match[0], tagX, tagY, fontHeight),
                tagRect: { x: tagX, y: tagY - fontHeight * 0.3, width: match[0].length * charWidth, height: fontHeight * 1.3 }
            });
        }
    });
    return tags;
}
