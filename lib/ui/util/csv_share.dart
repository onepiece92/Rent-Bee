import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, Offset;

import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:share_plus/share_plus.dart';

/// Global rect of the widget at [context], used to anchor the share popover on
/// iPad/macOS. Returns null when the box isn't laid out yet (phones ignore the
/// origin anyway).
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Shares [csv] as an actual `.csv` file named [fileName] via the system
/// share sheet, so the user can save it to Files/Drive or attach it to email
/// as a spreadsheet.
///
/// The file is built in memory with [XFile.fromData]. We MUST pass the bytes as
/// [ShareParams.files] (not [ShareParams.text]) — sharing `text:` hands the
/// receiving app a raw string with no filename, which is why most targets
/// can't save it as a file. [ShareParams.fileNameOverrides] is required because
/// `cross_file` drops the `name` on every platform except web.
///
/// [origin] anchors the share popover on iPad/macOS; pass the source widget's
/// global rect where available (ignored on phones).
Future<ShareResult> shareCsv(
  String csv,
  String fileName, {
  Rect? origin,
}) {
  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(csv)),
    mimeType: 'text/csv',
    name: fileName,
  );
  return SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: fileName,
      sharePositionOrigin: origin,
    ),
  );
}
