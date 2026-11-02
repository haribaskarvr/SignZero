/*
 * SignZero PDF engine: the PDF work of the signing portal. It opens the document (a display copy without anchor
 * tags, page sizes and the text of every tag), draws pages as images, and stamps signatures into the PDF.
 * It runs in index.html of this static resource, which the portal loads in a hidden iframe outside Lightning Web
 * Security, where PDF.js has its Web Worker and canvas runs at full speed. If that page cannot be reached, the
 * portal loads these same files inside the component and calls the engine directly. It only transforms the bytes
 * it is given; it has no access to Salesforce data.
 *
 * Requires pdf-lib (window.PDFLib) and PDF.js (window.pdfjsLib).
 */
(function (global) {
    'use strict';

    // pdf-lib pauses every 50-100 objects to "yield"; browsers slow those timers down. Do the work in one go.
    const NO_YIELD_LOAD = { parseSpeed: Infinity };
    const NO_YIELD_SAVE = { objectsPerTick: Infinity };
    const SIG_WIDTH = 150;
    // A signature fills the width of its area; one taller than the area's shape rises above it, like a hand
    // signature above a line, up to this many times the area's height. Keep in step with signZeroPortal.
    const SIG_OVERFLOW = 2;
    const CAPTION_GAP = 7;

    function escapeRegExp(value) {
        return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    // PDF content streams are bytes; latin1 maps each byte to one character and back without loss.
    function bytesToLatin1(bytes) {
        let text = '';
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
            text += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return text;
    }

    function latin1ToBytes(text) {
        const bytes = new Uint8Array(text.length);
        for (let i = 0; i < text.length; i++) {
            bytes[i] = text.charCodeAt(i);
        }
        return bytes;
    }

    /**
     * Painting over text in a PDF only hides it; the text stays searchable and copyable. This rewrites the page's
     * content streams so the {{sig:role}} tags become spaces, which keeps the layout: first for plain single-byte
     * text, then glyph by glyph for embedded fonts (see blankTagGlyphs). A tag that can be found neither way (no
     * ToUnicode map, no space glyph) stays in place, and the caller covers it visually.
     * @param role signer role whose tags to remove; ignored when anyRole is true
     */
    function blankTagsInText(doc, page, role, anyRole) {
        const { PDFName, PDFArray, PDFRawStream, decodePDFRawStream } = global.PDFLib;
        const rolePattern = anyRole ? '[^}]*?' : escapeRegExp(role);
        const literalTag = new RegExp(`\\{\\{\\s*sig\\s*:\\s*${rolePattern}\\s*(?:\\|[^}]*)?\\}\\}`, 'gi');
        // The same tag as hex string bytes, matching either letter case.
        const hexTag = anyRole
            ? /7b7b7369673a(?:(?!7d7d)[0-9a-f]{2})*?7d7d/gi // "{{sig:" ... "}}"
            : new RegExp(
                  [...`{{sig:${role}`]
                      .map((ch) => {
                          const variants = new Set([ch.toLowerCase(), ch.toUpperCase()]);
                          return `(?:${[...variants].map((v) => v.charCodeAt(0).toString(16).padStart(2, '0')).join('|')})`;
                      })
                      .join('') + '(?:7c(?:(?!7d)[0-9a-f]{2})*)?7d7d', // optional "|options", then "}}"
                  'gi'
              );

        const fontMaps = fontGlyphMaps(doc, page);
        const contents = page.node.get(PDFName.of('Contents'));
        const refs = contents instanceof PDFArray ? contents.asArray() : [contents];
        refs.forEach((ref) => {
            const stream = doc.context.lookup(ref);
            if (!(stream instanceof PDFRawStream)) {
                return;
            }
            const original = bytesToLatin1(decodePDFRawStream(stream).decode());
            let blanked = original
                .replace(/\(((?:\\.|[^\\)])*)\)/g, (str) => str.replace(literalTag, (tag) => ' '.repeat(tag.length)))
                .replace(/<([0-9A-Fa-f\s]*)>/g, (str) => str.replace(hexTag, (tag) => '20'.repeat(tag.length / 2)));
            blanked = blankTagGlyphs(blanked, fontMaps, literalTag);
            if (blanked !== original) {
                doc.context.assign(ref, doc.context.flateStream(latin1ToBytes(blanked)));
            }
        });
    }

    /**
     * For embedded (Type0/CID) fonts, as written by Word, browsers and most PDF printers, text is stored as
     * font-specific glyph numbers, often one glyph per operator with positioning in between. Each font's ToUnicode
     * map turns glyphs back into characters, so the page's text can be rebuilt in drawing order, the tag found, and
     * exactly those glyphs swapped for the same font's space glyph. Every glyph keeps its own position.
     */
    function blankTagGlyphs(content, fontMaps, tag) {
        const glyphs = []; // { stringIndex, glyphIndex, char, font }
        const strings = []; // { start, end, codes, font }
        let font = null;
        const pattern = /\/([^\s/<>[\]()]+)\s+[-\d.]+\s+Tf|<([0-9A-Fa-f\s]*)>/g;
        let match;
        while ((match = pattern.exec(content)) !== null) {
            if (match[1]) {
                font = fontMaps[match[1]] || null;
                continue;
            }
            if (!font) {
                continue;
            }
            const hex = match[2].replace(/\s/g, '');
            const codes = hex.match(new RegExp(`.{${font.codeLength * 2}}`, 'g')) || [];
            const stringIndex = strings.length;
            strings.push({ start: match.index, end: match.index + match[0].length, codes, font });
            codes.forEach((code, glyphIndex) => {
                glyphs.push({ stringIndex, glyphIndex, char: font.toChar[code.toUpperCase()] || '\u0000', font });
            });
        }
        if (glyphs.length === 0) {
            return content;
        }
        const text = glyphs.map((g) => g.char).join('');
        let changed = false;
        tag.lastIndex = 0;
        while ((match = tag.exec(text)) !== null) {
            for (let i = match.index; i < match.index + match[0].length; i++) {
                const g = glyphs[i];
                if (g.font.spaceCode) {
                    strings[g.stringIndex].codes[g.glyphIndex] = g.font.spaceCode;
                    changed = true;
                }
            }
        }
        if (!changed) {
            return content;
        }
        let out = content;
        for (let i = strings.length - 1; i >= 0; i--) {
            const s = strings[i];
            out = out.slice(0, s.start) + `<${s.codes.join('')}>` + out.slice(s.end);
        }
        return out;
    }

    /** Per font resource on the page: glyph code -> character (from ToUnicode), code size and the space glyph. */
    function fontGlyphMaps(doc, page) {
        const { PDFName, PDFDict, PDFRawStream, decodePDFRawStream } = global.PDFLib;
        const maps = {};
        const fonts = page.node.Resources() && page.node.Resources().lookup(PDFName.of('Font'));
        if (!(fonts instanceof PDFDict)) {
            return maps;
        }
        fonts.entries().forEach(([name, ref]) => {
            const fontDict = doc.context.lookup(ref);
            const toUnicode = fontDict instanceof PDFDict ? fontDict.lookup(PDFName.of('ToUnicode')) : null;
            if (!(toUnicode instanceof PDFRawStream)) {
                return;
            }
            const cmap = bytesToLatin1(decodePDFRawStream(toUnicode).decode());
            const toChar = {};
            for (const block of cmap.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) {
                for (const [, code, uni] of block[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g)) {
                    toChar[code.toUpperCase()] = String.fromCharCode(parseInt(uni.slice(0, 4), 16));
                }
            }
            for (const block of cmap.matchAll(/beginbfrange([\s\S]*?)endbfrange/g)) {
                for (const [, from, to, uni] of block[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g)) {
                    const first = parseInt(from, 16);
                    for (let code = first; code <= parseInt(to, 16); code++) {
                        toChar[code.toString(16).toUpperCase().padStart(from.length, '0')] =
                            String.fromCharCode(parseInt(uni.slice(0, 4), 16) + code - first);
                    }
                }
            }
            const isType0 = String(fontDict.lookup(PDFName.of('Subtype'))) === '/Type0';
            const spaceCode = Object.keys(toChar).find((code) => toChar[code] === ' ');
            maps[String(name).replace(/^\//, '')] = { toChar, codeLength: isType0 ? 2 : 1, spaceCode };
        });
        return maps;
    }

    /** A copy for display only, with every {{sig:...}} tag taken out of the page text. */
    async function displayCopy(pdfBytes) {
        const doc = await global.PDFLib.PDFDocument.load(pdfBytes, NO_YIELD_LOAD);
        doc.getPages().forEach((page) => blankTagsInText(doc, page, null, true));
        return doc.save(NO_YIELD_SAVE);
    }

    // Only one document is open at a time; opening another closes it.
    let opened = null;
    let openCount = 0;
    let sharedWorker; // the host page's PDF.js Web Worker; none inside the component

    function loadForDrawing(bytes) {
        // In the host page PDF.js uses its Web Worker. Inside the component (the fallback) there is none, and
        // ImageBitmaps cannot be cloned under Lightning Web Security, so images must travel as raw pixels.
        return global.pdfjsLib.getDocument({
            data: bytes,
            worker: sharedWorker,
            isOffscreenCanvasSupported: Boolean(global.SIGNZERO_ENGINE_HOST)
        }).promise;
    }

    /**
     * Opens a document for viewing: page sizes for laying out the viewer, and every text item that holds an anchor
     * tag. Tags are read from the original; pages are drawn from a copy with the tags taken out, so no tag shows and
     * nothing is painted over (which could clip a signature).
     * @returns { docId, pages: [{ width, height, transform, view }] at scale 1, tagItems: [{ pageIndex, itemIndex, str, width, transform }] }
     */
    async function open({ pdfBytes }) {
        if (opened) {
            opened.textDoc.destroy();
            opened.drawDoc.destroy();
        }
        // PDF.js takes ownership of the buffer it is given, so hand it a copy.
        const textDoc = await loadForDrawing(pdfBytes.slice());
        let drawBytes;
        try {
            drawBytes = await displayCopy(pdfBytes);
        } catch (error) {
            drawBytes = pdfBytes.slice(); // show the original rather than nothing
        }
        const drawDoc = await loadForDrawing(drawBytes);
        openCount += 1;
        opened = { docId: openCount, textDoc, drawDoc };

        const pages = [];
        const tagItems = [];
        for (let pageNum = 1; pageNum <= textDoc.numPages; pageNum++) {
            const page = await textDoc.getPage(pageNum);
            const viewport = page.getViewport({ scale: 1 });
            pages.push({ width: viewport.width, height: viewport.height, transform: viewport.transform, view: page.view });
            const text = await page.getTextContent();
            text.items.forEach((item, itemIndex) => {
                if (item.str && /\{\{\s*sig\s*:/i.test(item.str)) {
                    tagItems.push({ pageIndex: pageNum - 1, itemIndex, str: item.str, width: item.width, transform: item.transform });
                }
            });
        }
        return { docId: opened.docId, pages, tagItems };
    }

    /**
     * Draws one page of the open document as a PNG.
     * @param scale  device pixels per PDF point (zoom times the screen's pixel ratio)
     * @returns { docId, pageIndex, image: Blob }
     */
    async function renderPage({ docId, pageIndex, scale }) {
        if (!opened || opened.docId !== docId) {
            throw new Error('document is no longer open');
        }
        const page = await opened.drawDoc.getPage(pageIndex + 1);
        const viewport = page.getViewport({ scale });
        const canvas = global.document.createElement('canvas');
        canvas.width = Math.floor(viewport.width);
        canvas.height = Math.floor(viewport.height);
        await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
        const image = await new Promise((resolve, reject) =>
            canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('page could not be drawn'))), 'image/png')
        );
        page.cleanup();
        return { docId, pageIndex, image };
    }

    /**
     * Writes the adopted signature into the PDF.
     * @param payload.spots      [{ pageIndex, pdfX, pdfY, height }] where this signer signs
     * @param payload.tagRects   [{ pageIndex, rect }] every anchor tag found, any role; all are covered visually
     * @param payload.clearAllTags  true for the last signer: also clear tags left for roles nobody signed as
     * @returns the PDF with a classic cross-reference table, so SignZeroPdfAppender can append the certificate in Apex
     */
    async function stamp({ pdfBytes, pngBytes, spots, tagRects, signerRole, clearAllTags, caption }) {
        const { PDFDocument, StandardFonts, rgb } = global.PDFLib;
        const doc = await PDFDocument.load(pdfBytes, NO_YIELD_LOAD);
        const png = await doc.embedPng(pngBytes);
        const font = await doc.embedFont(StandardFonts.Helvetica);
        const pages = doc.getPages();

        // Take tags out of the text layer before drawing anything new on the pages.
        new Set(tagRects.map((tag) => tag.pageIndex)).forEach((pageIndex) =>
            blankTagsInText(doc, pages[pageIndex], signerRole, clearAllTags)
        );
        // Cover every tag visually, any role, so none shows in the signed PDF even before it is cleared.
        tagRects.forEach((tag) => pages[tag.pageIndex].drawRectangle({ ...tag.rect, color: rgb(1, 1, 1) }));

        spots.forEach((spot) => {
            const page = pages[spot.pageIndex];
            // Signature resting on the bottom of its area, caption just underneath.
            const scale = Math.min(SIG_WIDTH / png.width, (SIG_OVERFLOW * spot.height) / png.height);
            page.drawImage(png, { x: spot.pdfX, y: spot.pdfY, width: png.width * scale, height: png.height * scale });
            page.drawText(caption, { x: spot.pdfX, y: spot.pdfY - CAPTION_GAP, size: 5, font, color: rgb(0.35, 0.35, 0.35) });
        });
        doc.setModificationDate(new Date());
        return doc.save({ ...NO_YIELD_SAVE, useObjectStreams: false });
    }

    /**
     * Replaces the browser's cached copies of this page's files at the plain address (without a version), which the
     * portal found older than the current deploy. Scripts are fetched again; the page itself is cached separately
     * when it loads in a frame, so it is loaded in a hidden frame and reloaded once, which fetches it again.
     * @param plainPage URL of index.html at the plain address
     */
    async function refreshPlainCopy({ plainPage }) {
        const scripts = ['engine.js', 'pdf.min.js', 'pdf.worker.min.js', 'pdf-lib.min.js'];
        await Promise.all(scripts.map((file) => global.fetch(new URL(file, plainPage), { cache: 'reload' })));
        const frame = global.document.createElement('iframe');
        frame.hidden = true;
        let reloaded = false;
        frame.addEventListener('load', () => {
            if (reloaded) {
                frame.remove();
                return;
            }
            reloaded = true;
            frame.contentWindow.location.reload();
        });
        frame.src = plainPage;
        global.document.body.appendChild(frame);
        return true;
    }

    const api = { open, renderPage, stamp, refreshPlainCopy };
    global.SignZeroPdfEngine = api;

    // index.html marks itself as the host page. Only there, inside the portal's iframe, answer requests from the
    // portal on the same site, and only those.
    global.SIGNZERO_ENGINE_HOST = Boolean(global.document && global.document.documentElement.hasAttribute('data-signzero-host'));
    if (global.SIGNZERO_ENGINE_HOST && global.pdfjsLib) {
        global.pdfjsLib.GlobalWorkerOptions.workerSrc = new URL('pdf.worker.min.js', global.document.baseURI).href;
        // Start the worker now, while the portal is still fetching the document; both copies share it.
        sharedWorker = new global.pdfjsLib.PDFWorker();
    }
    if (global.SIGNZERO_ENGINE_HOST && global.parent && global.parent !== global) {
        // Announce readiness until the portal's first request arrives, in case it was not listening yet.
        // The site sends the resource's last deploy time as Last-Modified, so the portal can tell a copy cached
        // before a deploy from the current one.
        const version = Date.parse(global.document.lastModified);
        const announce = () => global.parent.postMessage({ signZeroEngine: 'ready', version }, global.location.origin);
        let announcer;
        // index.html loads pdf-lib after this file, so announce only once every script on the page has run.
        const startAnnouncing = () => {
            announcer = global.setInterval(announce, 500);
            global.setTimeout(() => global.clearInterval(announcer), 20000);
            announce();
        };
        if (global.document.readyState === 'loading') {
            global.document.addEventListener('DOMContentLoaded', startAnnouncing);
        } else {
            startAnnouncing();
        }
        global.addEventListener('message', async (event) => {
            const data = event.data;
            if (event.origin !== global.location.origin || !data || data.signZeroEngine !== 'request' || !Object.prototype.hasOwnProperty.call(api, data.op)) {
                return;
            }
            global.clearInterval(announcer);
            try {
                const result = await api[data.op](data.payload);
                event.source.postMessage({ signZeroEngine: 'response', id: data.id, result }, event.origin);
            } catch (error) {
                event.source.postMessage({ signZeroEngine: 'response', id: data.id, error: String((error && error.message) || error) }, event.origin);
            }
        });
    }
})(typeof window !== 'undefined' ? window : globalThis);
