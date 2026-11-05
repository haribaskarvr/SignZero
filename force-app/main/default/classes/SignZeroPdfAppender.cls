/**
 * @description Appends one PDF's pages to another as an incremental update, so the result starts with the base file
 *   byte for byte and its hash still verifies. Only classic, uncompressed cross-reference tables are supported, as
 *   SignZero produces; anything else throws UnsupportedPdfException. Bytes are handled as hex, so byte offsets are
 *   doubled to index it.
 */
public inherited sharing class SignZeroPdfAppender {
  /**
   * @description The PDF uses a structure Apex cannot append to without inflating it.
   */
  public class UnsupportedPdfException extends Exception {
  }

  /**
   * @description A PDF's hex data and the cross-reference facts needed to append to it.
   */
  private class ParsedPdf {
    String data; // hex
    Integer size;
    Integer rootNum;
    Integer startXref;
    String idEntry;
    String infoEntry;
    Map<Integer, Integer> offsets = new Map<Integer, Integer>();
  }

  /**
   * @description Adds the pages of one PDF after the pages of another.
   * @param base the PDF to keep byte for byte
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

  // ---------- digital signature ----------

  /**
   * @description A PDF laid out for a digital signature: everything but the signature value is final, because the
   *   signature covers all the bytes around it.
   */
  public class PreparedSignature {
    private String head; // hex, up to and including the < of /Contents
    private String tail; // hex, from the > of /Contents to the end
    private Integer maxBytes;

    /**
     * @description The bytes the signature covers.
     * @return the file without the /Contents hex string
     */
    public Blob signedBytes() {
      return EncodingUtil.convertFromHex(
        head.left(head.length() - 2) + tail.substring(2)
      );
    }

    /**
     * @description Writes the signature into its reserved space.
     * @param signature the signature's DER, as hex
     * @return the signed PDF
     */
    public Blob withSignature(String signature) {
      if (signature.length() > maxBytes * 2) {
        throw new UnsupportedPdfException(
          'The signature does not fit its reserved space'
        );
      }
      // The signature is written in hex inside the file, so its hex is written as text.
      return EncodingUtil.convertFromHex(
        head + hex(signature.rightPad(maxBytes * 2, '0')) + tail
      );
    }
  }

  /**
   * @description Adds an invisible signature field and a signature dictionary as an incremental update.
   * @param pdf the PDF to sign
   * @param maxBytes room to keep for the signature
   * @param sealedBy the name shown with the signature
   * @param reason why it is signed
   * @return the laid-out PDF, waiting for its signature
   */
  public static PreparedSignature prepareSignature(
    Blob pdf,
    Integer maxBytes,
    String sealedBy,
    String reason
  ) {
    ParsedPdf b = parse(EncodingUtil.convertToHex(pdf));
    Integer signatureNum = b.size;
    Integer fieldNum = b.size + 1;
    String fieldRef = fieldNum + ' 0 R';

    Map<Integer, String> written = new Map<Integer, String>();
    String catalog = objectDict(b, b.rootNum);
    Integer pageNum = firstPage(b, refAfter(catalog, '/Pages'));
    written.put(
      fieldNum,
      hex(
        fieldNum +
          ' 0 obj\n<</Type/Annot/Subtype/Widget/FT/Sig/F 132/Rect[0 0 0 0]/T(SignZero Seal)/V ' +
          signatureNum +
          ' 0 R/P ' +
          pageNum +
          ' 0 R>>\nendobj\n'
      )
    );
    written.put(b.rootNum, hex(withSignatureField(b, written, catalog, fieldRef)));
    String page = objectDict(b, pageNum);
    Matcher annotsRef = Pattern.compile('/Annots\\s+(\\d+)\\s+\\d+\\s+R').matcher(page);
    if (annotsRef.find()) {
      Integer annotsNum = Integer.valueOf(annotsRef.group(1));
      written.put(
        annotsNum,
        hex(
          annotsNum +
            ' 0 obj\n' +
            objectDict(b, annotsNum).replaceFirst('\\[', '[' + fieldRef + ' ') +
            '\nendobj\n'
        )
      );
    } else {
      page = Pattern.compile('/Annots\\s*\\[').matcher(page).find()
        ? page.replaceFirst('/Annots\\s*\\[', '/Annots[' + fieldRef + ' ')
        : page.replaceFirst('<<', '<</Annots[' + fieldRef + '] ');
      written.put(pageNum, hex(pageNum + ' 0 obj\n' + page + '\nendobj\n'));
    }

    // Layout: the update's objects, the signature dictionary, then the cross-reference section.
    Integer cursor = b.data.length() / 2 + 1;
    List<String> objects = new List<String>{ hex('\n') };
    List<Integer> nums = new List<Integer>(written.keySet());
    nums.sort();
    Map<Integer, Integer> newOffsets = new Map<Integer, Integer>();
    for (Integer num : nums) {
      newOffsets.put(num, cursor);
      objects.add(written.get(num));
      cursor += written.get(num).length() / 2;
    }
    newOffsets.put(signatureNum, cursor);
    nums.add(signatureNum);
    nums.sort();

    // /ByteRange holds offsets of this very layout, so its numbers have a fixed width.
    String beforeRange =
      signatureNum +
      ' 0 obj\n<</Type/Sig/Filter/Adobe.PPKLite/SubFilter/ETSI.CAdES.detached/M(D:' +
      Datetime.now().formatGmt('yyyyMMddHHmmss') +
      '+00\'00\')/Name(' +
      pdfText(sealedBy) +
      ')/Reason(' +
      pdfText(reason) +
      ')/ByteRange[0 ';
    String afterRange = ']/Contents<';
    String afterContents = '>>>\nendobj\n';
    Integer rangeWidth = 10 + 1 + 10 + 1 + 10;
    Integer contentsAt =
      cursor +
      beforeRange.length() +
      rangeWidth +
      afterRange.length() -
      1; // the <
    Integer contentsEnd = contentsAt + 2 + maxBytes * 2;
    Integer xrefOffset = contentsEnd + afterContents.length() - 1;
    String trailer =
      'trailer\n<</Size ' +
      (fieldNum + 1) +
      '/Root ' +
      b.rootNum +
      ' 0 R/Prev ' +
      b.startXref +
      (b.infoEntry == null ? '' : '/Info ' + b.infoEntry) +
      (b.idEntry == null ? '' : '/ID ' + b.idEntry) +
      '>>\nstartxref\n' +
      xrefOffset +
      '\n%%EOF\n';
    String closing = afterContents.substring(1) + xrefSection(nums, newOffsets) + trailer;
    Integer fileEnd = xrefOffset + closing.length() - (afterContents.length() - 1);
    String range =
      String.valueOf(contentsAt).leftPad(10, '0') +
      ' ' +
      String.valueOf(contentsEnd).leftPad(10, '0') +
      ' ' +
      String.valueOf(fileEnd - contentsEnd).leftPad(10, '0');

    PreparedSignature prepared = new PreparedSignature();
    prepared.maxBytes = maxBytes;
    prepared.head =
      b.data +
      String.join(objects, '') +
      hex(beforeRange + range + afterRange);
    prepared.tail = hex('>' + closing);
    return prepared;
  }

  /**
   * @description Adds a signature field to the document's form, creating the form if it has none.
   * @param pdf the parsed PDF
   * @param written updated objects, to which a separate form object is added
   * @param catalog the catalog's dictionary
   * @param fieldRef reference to the new field
   * @return the updated catalog object, as text
   */
  private static String withSignatureField(
    ParsedPdf pdf,
    Map<Integer, String> written,
    String catalog,
    String fieldRef
  ) {
    String header = pdf.rootNum + ' 0 obj\n';
    Matcher formRef = Pattern.compile('/AcroForm\\s+(\\d+)\\s+\\d+\\s+R').matcher(catalog);
    if (formRef.find()) {
      Integer formNum = Integer.valueOf(formRef.group(1));
      written.put(
        formNum,
        hex(
          formNum +
            ' 0 obj\n' +
            formWithField(objectDict(pdf, formNum), fieldRef) +
            '\nendobj\n'
        )
      );
      return header + catalog + '\nendobj\n';
    }
    if (catalog.contains('/AcroForm')) {
      throw new UnsupportedPdfException(
        'A form written inside the catalog is not supported'
      );
    }
    return header +
      catalog.replaceFirst(
        '<<',
        '<</AcroForm<</Fields[' + fieldRef + ']/SigFlags 3>> '
      ) +
      '\nendobj\n';
  }

  /**
   * @description Adds a field to a form dictionary and marks the form as signed.
   * @param form the form's dictionary
   * @param fieldRef reference to the new field
   * @return the updated dictionary
   */
  private static String formWithField(String form, String fieldRef) {
    if (!Pattern.compile('/Fields\\s*\\[').matcher(form).find()) {
      throw new UnsupportedPdfException('The form has no list of fields');
    }
    String updated = form.replaceFirst('/Fields\\s*\\[', '/Fields[' + fieldRef + ' ');
    return Pattern.compile('/SigFlags\\s+\\d+').matcher(updated).find()
      ? updated.replaceFirst('/SigFlags\\s+\\d+', '/SigFlags 3')
      : updated.replaceFirst('<<', '<</SigFlags 3 ');
  }

  /**
   * @description Walks down the page tree to the first page.
   * @param pdf the parsed PDF
   * @param pagesNum the page tree's root
   * @return the first page's object number
   */
  private static Integer firstPage(ParsedPdf pdf, Integer pagesNum) {
    Integer num = pagesNum;
    for (Integer depth = 0; depth < 50; depth++) {
      Matcher kids = Pattern.compile('/Kids\\s*\\[\\s*(\\d+)\\s+\\d+\\s+R')
        .matcher(objectDict(pdf, num));
      if (!kids.find()) {
        return num;
      }
      num = Integer.valueOf(kids.group(1));
    }
    throw new UnsupportedPdfException('The page tree is too deep');
  }

  /**
   * @description Makes text safe inside a PDF literal string, in ASCII as the update is written.
   * @param text the text
   * @return the escaped text
   */
  private static String pdfText(String text) {
    return (text == null ? '' : text)
      .replaceAll('[^\\x20-\\x7E]', '?')
      .replace('\\', '\\\\')
      .replace('(', '\\(')
      .replace(')', '\\)');
  }

  // ---------- parsing ----------

  /**
   * @description Reads a PDF's trailer and cross-reference tables.
   * @param data the PDF as hex
   * @return the parsed PDF
   */
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
        Matcher info = Pattern.compile('/Info\\s*(\\d+\\s+\\d+\\s+R)').matcher(trailer);
        pdf.infoEntry = info.find() ? info.group(1) : null;
        newest = false;
      }
      sectionOffset = trailer.contains('/Prev')
        ? intAfter(trailer, '/Prev')
        : null;
    }
    return pdf;
  }

  /**
   * @description Reads one cross-reference table's object offsets. Older sections never override newer ones.
   * @param table the table's text
   * @param offsets object number to byte offset, filled in
   */
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
   * @description Reads an object's dictionary text.
   * @param pdf the parsed PDF
   * @param num object number
   * @return the dictionary text, without header or stream data
   */
  private static String objectDict(ParsedPdf pdf, Integer num) {
    Integer[] bounds = objectBounds(pdf, num);
    return ascii(pdf.data, bounds[1], bounds[2] >= 0 ? bounds[2] : bounds[3])
      .trim();
  }

  /**
   * @description Finds where an object's parts are.
   * @param pdf the parsed PDF
   * @param num object number
   * @return [start, body start, stream keyword or -1, endobj], in bytes
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

  /**
   * @description Copies an appendix object with its references shifted past the base's object numbers.
   * @param pdf the parsed appendix
   * @param num object number
   * @param shift amount added to every object number
   * @param newParent new parent page tree for page objects, or null
   * @return the object as hex, ready to write
   */
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

  /**
   * @description Shifts every object reference in a dictionary.
   * @param dict the dictionary text
   * @param shift amount added to every object number
   * @return the renumbered text
   */
  private static String renumber(String dict, Integer shift) {
    Matcher m = SignZeroConstants.PDF_REFERENCE.matcher(dict);
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

  /**
   * @description Builds a cross-reference section for the written objects.
   * @param sortedNums object numbers, ascending
   * @param offsets object number to byte offset
   * @return the section text
   */
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

  /**
   * @description Converts ASCII text to hex.
   * @param text the text
   * @return its hex
   */
  private static String hex(String text) {
    return EncodingUtil.convertToHex(Blob.valueOf(text));
  }

  /**
   * @description Reads a byte range as ASCII text.
   * @param data the PDF as hex
   * @param fromByte first byte
   * @param toByte byte after the last
   * @return the text; throws when the range is binary
   */
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
   * @description Finds text in the hex data.
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

  /**
   * @description Finds text that must be present.
   * @param data the PDF as hex
   * @param needle ASCII text to find
   * @param fromByte byte offset to search from
   * @return byte offset of needle; throws when missing
   */
  private static Integer require(String data, String needle, Integer fromByte) {
    Integer at = find(data, needle, fromByte);
    if (at < 0) {
      throw new UnsupportedPdfException('Missing "' + needle + '"');
    }
    return at;
  }

  /**
   * @description Finds the last occurrence of text in the hex data.
   * @param data the PDF as hex
   * @param needle ASCII text to find
   * @return byte offset of the last needle, or -1
   */
  private static Integer lastFind(String data, String needle) {
    String n = hex(needle);
    Integer i = data.lastIndexOf(n);
    while (i > 0 && Math.mod(i, 2) == 1) {
      i = data.lastIndexOf(n, i - 1);
    }
    return i < 0 ? -1 : i / 2;
  }

  /**
   * @description Reads the number after a dictionary key.
   * @param text the dictionary text
   * @param key the key, e.g. /Size
   * @return the number; throws when missing
   */
  private static Integer intAfter(String text, String key) {
    Matcher m = Pattern.compile(Pattern.quote(key) + '\\s*(\\d+)')
      .matcher(text);
    if (!m.find()) {
      throw new UnsupportedPdfException('Missing ' + key);
    }
    return Integer.valueOf(m.group(1));
  }

  /**
   * @description Reads the object number of the reference after a dictionary key.
   * @param text the dictionary text
   * @param key the key, e.g. /Root
   * @return the referenced object number; throws when missing
   */
  private static Integer refAfter(String text, String key) {
    Matcher m = Pattern.compile(Pattern.quote(key) + '\\s*(\\d+)\\s+\\d+\\s+R')
      .matcher(text);
    if (!m.find()) {
      throw new UnsupportedPdfException('Missing reference ' + key);
    }
    return Integer.valueOf(m.group(1));
  }
}
