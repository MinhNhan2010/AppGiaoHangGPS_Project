import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<({String fileName, String? textContent})?> pickBrowserFile({
  required String accept,
  required bool readAsText,
}) async {
  final completer = Completer<({String fileName, String? textContent})?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..style.display = 'none';
  web.document.body?.appendChild(input);

  StreamSubscription<web.Event>? changeSub;
  void cleanup() {
    changeSub?.cancel();
    input.remove();
  }

  changeSub = input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.length == 0) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    if (!readAsText) {
      final pickedName = file.name;
      cleanup();
      if (!completer.isCompleted) {
        completer.complete((fileName: pickedName, textContent: null));
      }
      return;
    }
    final reader = web.FileReader();
    StreamSubscription<web.ProgressEvent>? loadSub;
    loadSub = reader.onLoadEnd.listen((_) {
      loadSub?.cancel();
      final rawResult = reader.result;
      final text = (rawResult as JSString?)?.toDart ?? '';
      final pickedName = file.name;
      cleanup();
      if (!completer.isCompleted) {
        completer.complete((fileName: pickedName, textContent: text));
      }
    });
    reader.readAsText(file);
  });

  input.click();
  return completer.future;
}

void triggerBrowserFileDownload({
  required String fileName,
  required String content,
  required String mimeType,
}) {
  try {
    final parts = <JSAny>[content.toJS].toJS;
    final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
    final objUrl = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = objUrl
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(objUrl);
  } catch (_) {}
}
