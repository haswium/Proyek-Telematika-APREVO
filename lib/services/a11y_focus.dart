import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Meminta TalkBack memindahkan fokusnya ke widget dengan [key] setelah frame
/// berikutnya, misalnya ke judul halaman baru, soal baru, atau kartu hasil
/// yang baru muncul.
///
/// `FocusNode.requestFocus` hanya memindahkan fokus keyboard; TalkBack tidak
/// selalu mengikutinya. Widget tujuan sebaiknya `Semantics(container: true)`
/// supaya punya node sendiri. Kalau widgetnya tidak ada, tidak terjadi apa-apa.
void moveScreenReaderFocus(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return;
    context.findRenderObject()?.sendSemanticsEvent(const FocusSemanticEvent());
  });
}
