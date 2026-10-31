/**
 * Appends the pages of one PDF to another without touching the first file's bytes, by writing a PDF
 * incremental update (the mechanism PDF digital signatures rely on). The combined file therefore starts
 * with the executed agreement byte-for-byte, and its SHA-256 still verifies against the first N bytes.
 *
 * Apex cannot inflate compressed PDF structures, so both inputs must use a classic cross-reference table
 * with uncompressed object dictionaries. SignZero guarantees this for its own output (pdf-lib saves with
 * object streams off; Blob.toPdf writes classic files). Anything else raises UnsupportedPdfException and
 * the caller falls back to sending the files separately.
 *
 * Bytes are handled as hex strings, so every offset below is a byte offset and is doubled to index hex.
 */
public inherited sharing class SignZeroPdfAppender {
  /** The PDF uses a structure SignZero cannot append to without inflating it. */
  public class UnsupportedPdfException extends Exception {
  }

  private static final Pattern REFERENCE = Pattern.compile(
    '(\\d+)\\s+(\\d+)\\s+R(?![A-Za-z0-9])'
  );

  private class ParsedPdf {
    String data; // hex
    Integer size;
    Integer rootNum;
    Integer startXref;
    String idEntry;
    Map<Integer, Integer> offsets = new Map<Integer, Integer>();
  }

  /**
   * Adds the pages of appendix after the pages of base.
   * @param base the PDF to keep byte-for-byte
   * @param appendix the PDF whose pages are added
   * @return base followed by an incremental update that adds the pages
   */
  public static Blob append(Blob base, Blob appendix) {
    ParsedPdf b = parse(EncodingUtil.convertToHex(base));
    ParsedPdf a = parse(EncodingUtil.convertToHex(appendix));

    Integer basePagesNum = refAfter(objectDict(b, b.rootNum), '/Pages');
    Integer appPagesNum = refAfter(objectDict(a, a.rootNum), '/Pages');
    Integer baseCount = intAfter(objectDict(b, basePagesNum), '/Count');
    Integer appCount = intAfter(objectDict(a, appPagesNum), '/Count');

    // Appendix objects are renumbered after the base's; one more number for the new page-tree root.
    Integer shift = b.size - 1;
    Integer newTopNum = b.size + a.size - 1;

    Map<Integer, String> written = new Map<Integer, String>(); // object number -> hex of "n 0 obj ... endobj\n"
    String catalog = objectDict(b, b.rootNum)
      .replaceFirst(
        '/Pages\\s+\\d+\\s+\\d+\\s+R',
        '/Pages ' + newTopNum + ' 0 R'
      );
    written.put(
      b.rootNum,
      hex(b.rootNum + ' 0 obj\n' + catalog + '\nendobj\n')
    );
    String basePages = objectDict(b, basePagesNum)
      .replaceFirst('<<', '<</Parent ' + newTopNum + ' 0 R ');
    written.put(
      basePagesNum,
      hex(basePagesNum + ' 0 obj\n' + basePages + '\nendobj\n')
    );
    written.put(
      newTopNum,
      hex(
        newTopNum +
          ' 0 obj\n<</Type/Pages/Kids[' +
          basePagesNum +
          ' 0 R ' +
          (appPagesNum + shift) +
          ' 0 R]/Count ' +
          (baseCount + appCount) +
          '>>\nendobj\n'
      )
    );

    Integer appRootNum = a.rootNum;
    for (Integer num : a.offsets.keySet()) {
      if (num == appRootNum || num == 0) {
        continue; // the appendix catalog is replaced by the base's
      }
      written.put(
        num + shift,
        renumberedObject(a, num, shift, num == appPagesNum ? newTopNum : null)
      );
    }

    // Lay out the update after the base file and build its cross-reference section.
    Integer cursor = b.data.length() / 2;
    List<String> out = new List<String>{ hex('\n') };
    cursor += 1;
    List<Integer> nums = new List<Integer>(written.keySet());
    nums.sort();
    Map<Integer, Integer> newOffsets = new Map<Integer, Integer>();
    for (Integer num : nums) {
      newOffsets.put(num, cursor);
      out.add(written.get(num));
      cursor += written.get(num).length() / 2;
    }
    Integer xrefOffset = cursor;
    out.add(hex(xrefSection(nums, newOffsets)));
    String trailer =
      'trailer\n<</Size ' +
      (newTopNum + 1) +
      '/Root ' +
      b.rootNum +
      ' 0 R/Prev ' +
      b.startXref +
      (b.idEntry == null ? '' : '/ID ' + b.idEntry) +
      '>>\nstartxref\n' +
      xrefOffset +
      '\n%%EOF\n';
    out.add(hex(trailer));

    return EncodingUtil.convertFromHex(b.data + String.join(out, ''));
  }

  // ---------- parsing ----------

  private static ParsedPdf parse(String data) {
    ParsedPdf pdf = new ParsedPdf();
    pdf.data = data;
    Integer sx = lastFind(data, 'startxref');
    if (sx < 0) {
      throw new UnsupportedPdfException('No startxref');
    }
    pdf.startXref = Integer.valueOf(
      ascii(data, sx + 9, Math.min(sx + 40, data.length() / 2))
        .substringBefore('%%EOF')
        .trim()
    );

    Integer sectionOffset = pdf.startXref;
    Boolean newest = true;
    while (sectionOffset != null) {
      if (!ascii(data, sectionOffset, sectionOffset + 4).equals('xref')) {
        throw new UnsupportedPdfException(
          'Cross-reference stream (compressed PDF) is not supported'
        );
      }
      Integer trailerAt = require(data, 'trailer', sectionOffset);
      Integer trailerEnd = require(data, 'startxref', trailerAt);
      readXrefTable(ascii(data, sectionOffset + 4, trailerAt), pdf.offsets);
      String trailer = ascii(data, trailerAt + 7, trailerEnd);
      if (newest) {
        pdf.size = intAfter(trailer, '/Size');
        pdf.rootNum = refAfter(trailer, '/Root');
        Matcher id = Pattern.compile('/ID\\s*(\\[[^\\]]*\\])').matcher(trailer);
        pdf.idEntry = id.find() ? id.group(1) : null;
        newest = false;
      }
      sectionOffset = trailer.contains('/Prev')
        ? intAfter(trailer, '/Prev')
        : null;
    }
    return pdf;
  }

  private static void readXrefTable(
    String table,
    Map<Integer, Integer> offsets
  ) {
    List<String> tokens = table.trim().split('\\s+');
    Integer i = 0;
    while (i + 1 < tokens.size()) {
      Integer first = Integer.valueOf(tokens[i]);
      Integer count = Integer.valueOf(tokens[i + 1]);
      i += 2;
      for (Integer k = 0; k < count; k++) {
        Integer num = first + k;
        // Older sections never override newer ones.
        if (tokens[i + 2] == 'n' && !offsets.containsKey(num)) {
          offsets.put(num, Integer.valueOf(tokens[i]));
        }
        i += 3;
      }
    }
  }

  /**
   * The dictionary text of an object (no header, no stream data).
   * @param pdf the parsed PDF
   * @param num object number
   * @return the dictionary text
   */
  private static String objectDict(ParsedPdf pdf, Integer num) {
    Integer[] bounds = objectBounds(pdf, num);
    return ascii(pdf.data, bounds[1], bounds[2] >= 0 ? bounds[2] : bounds[3])
      .trim();
  }

  /**
   * Where an object's parts are.
   * @param pdf the parsed PDF
   * @param num object number
   * @return [start, body start, stream keyword or -1, endobj] in bytes
   */
  private static Integer[] objectBounds(ParsedPdf pdf, Integer num) {
    Integer start = pdf.offsets.get(num);
    if (start == null) {
      throw new UnsupportedPdfException(
        'Object ' + num + ' is not in the cross-reference table'
      );
    }
    Integer endObj = require(pdf.data, 'endobj', start);
    Integer bodyStart = require(pdf.data, 'obj', start) + 3;
    Integer streamAt = find(pdf.data, 'stream', bodyStart);
    if (streamAt > endObj) {
      // belongs to a later object
      streamAt = -1;
    }
    return new List<Integer>{ start, bodyStart, streamAt, endObj };
  }

  private static String renumberedObject(
    ParsedPdf pdf,
    Integer num,
    Integer shift,
    Integer newParent
  ) {
    Integer[] bounds = objectBounds(pdf, num);
    String dict = ascii(
        pdf.data,
        bounds[1],
        bounds[2] >= 0 ? bounds[2] : bounds[3]
      )
      .trim();
    dict = renumber(dict, shift);
    if (newParent != null) {
      dict = dict.replaceFirst('<<', '<</Parent ' + newParent + ' 0 R ');
    }
    String head = hex((num + shift) + ' 0 obj\n' + dict + '\n');
    String streamPart = bounds[2] >= 0
      ? pdf.data.substring(bounds[2] * 2, bounds[3] * 2)
      : '';
    return head + streamPart + hex('endobj\n');
  }

  private static String renumber(String dict, Integer shift) {
    Matcher m = REFERENCE.matcher(dict);
    List<String> parts = new List<String>();
    Integer last = 0;
    while (m.find()) {
      parts.add(dict.substring(last, m.start()));
      parts.add(
        (Integer.valueOf(m.group(1)) + shift) + ' ' + m.group(2) + ' R'
      );
      last = m.end();
    }
    parts.add(dict.substring(last));
    return String.join(parts, '');
  }

  private static String xrefSection(
    List<Integer> sortedNums,
    Map<Integer, Integer> offsets
  ) {
    List<String> lines = new List<String>{ 'xref\n' };
    Integer i = 0;
    while (i < sortedNums.size()) {
      Integer j = i;
      while (
        j + 1 < sortedNums.size() &&
        sortedNums[j + 1] == sortedNums[j] + 1
      ) {
        j++;
      }
      lines.add(sortedNums[i] + ' ' + (j - i + 1) + '\n');
      for (Integer k = i; k <= j; k++) {
        lines.add(
          String.valueOf(offsets.get(sortedNums[k])).leftPad(10, '0') +
          ' 00000 n\r\n'
        );
      }
      i = j + 1;
    }
    return String.join(lines, '');
  }

  // ---------- byte helpers ----------

  private static String hex(String text) {
    return EncodingUtil.convertToHex(Blob.valueOf(text));
  }

  private static String ascii(String data, Integer fromByte, Integer toByte) {
    try {
      return EncodingUtil.convertFromHex(
          data.substring(fromByte * 2, toByte * 2)
        )
        .toString();
    } catch (Exception e) {
      throw new UnsupportedPdfException(
        'Binary data where a PDF dictionary was expected'
      );
    }
  }

  /**
   * Finds text in the hex data.
   * @param data the PDF as hex
   * @param needle ASCII text to find
   * @param fromByte byte offset to search from
   * @return byte offset of needle at or after fromByte, or -1
   */
  private static Integer find(String data, String needle, Integer fromByte) {
    String n = hex(needle);
    Integer i = data.indexOf(n, fromByte * 2);
    while (i >= 0 && Math.mod(i, 2) == 1) {
      i = data.indexOf(n, i + 1);
    }
    return i < 0 ? -1 : i / 2;
  }

  private static Integer require(String data, String needle, Integer fromByte) {
    Integer at = find(data, needle, fromByte);
    if (at < 0) {
      throw new UnsupportedPdfException('Missing "' + needle + '"');
    }
    return at;
  }

  private static Integer lastFind(String data, String needle) {
    String n = hex(needle);
    Integer i = data.lastIndexOf(n);
    while (i > 0 && Math.mod(i, 2) == 1) {
      i = data.lastIndexOf(n, i - 1);
    }
    return i < 0 ? -1 : i / 2;
  }

  private static Integer intAfter(String text, String key) {
    Matcher m = Pattern.compile(Pattern.quote(key) + '\\s*(\\d+)')
      .matcher(text);
    if (!m.find()) {
      throw new UnsupportedPdfException('Missing ' + key);
    }
    return Integer.valueOf(m.group(1));
  }

  private static Integer refAfter(String text, String key) {
    Matcher m = Pattern.compile(Pattern.quote(key) + '\\s*(\\d+)\\s+\\d+\\s+R')
      .matcher(text);
    if (!m.find()) {
      throw new UnsupportedPdfException('Missing reference ' + key);
    }
    return Integer.valueOf(m.group(1));
  }
}
