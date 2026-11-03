import 'dart:async';

import 'package:flutter/material.dart';

import '../services/announce.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Jeda setelah berhenti mengetik, supaya TalkBack tidak berisik.
const Duration kSearchDelay = Duration(milliseconds: 500);

/// Huruf kecil dan spasi rapi, supaya "  Geo  grafi" sama dengan "geo grafi".
String normalizeQuery(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// "3 materi ditemukan" atau "Tidak ada materi yang cocok".
String searchStatus(int count, String noun) =>
    count == 0 ? 'Tidak ada $noun yang cocok' : '$count $noun ditemukan';

/// Jumlah di judul daftar: "5", atau "3 dari 5" selama mencari.
String countLabel(int shown, int total) =>
    shown == total ? '$total' : '$shown dari $total';

/// Isi kolom pencarian. [value] baru berubah setelah [kSearchDelay], dan saat
/// itu pendengarnya dipanggil.
class SearchQuery extends ChangeNotifier {
  SearchQuery() {
    text.addListener(_onTyped);
  }

  final text = TextEditingController();
  final focus = FocusNode(debugLabel: 'kolom pencarian');
  String value = '';
  String _typed = '';
  Timer? _timer;

  void _onTyped() {
    final typed = normalizeQuery(text.text);
    if (typed == _typed) return;
    _typed = typed;
    _timer?.cancel();
    _timer = Timer(kSearchDelay, () {
      if (value == typed) return;
      value = typed;
      notifyListeners();
    });
  }

  void clear() {
    text.clear();
    _timer?.cancel();
    value = '';
    notifyListeners();
    focus.requestFocus();
    announce('Pencarian dihapus');
  }

  @override
  void dispose() {
    _timer?.cancel();
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// Kolom pencarian, tombol "Hapus pencarian", dan jumlah hasil.
class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.query,
    required this.label,
    this.status,
    this.live = true,
  });

  final SearchQuery query;
  final String label;

  /// Jumlah hasil, kosong kalau belum mencari.
  final String? status;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final message = status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: query.text,
          focusNode: query.focus,
          textInputAction: TextInputAction.search,
          style: AppType.bodyLarge,
          decoration: fieldDecoration(label),
        ),
        ListenableBuilder(
          listenable: query.text,
          builder: (context, _) => query.text.text.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Hapus pencarian'),
                    onPressed: query.clear,
                  ),
                ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            // TalkBack hanya membacakan liveRegion kalau labelnya berubah.
            // Key baru membuat jumlah yang sama tetap dibacakan untuk kata
            // yang berbeda.
            child: Semantics(
              key: ValueKey('$message|${query.value}'),
              container: true,
              liveRegion: live,
              child: Text(message, style: AppType.titleMedium),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Daftar yang disaring di aplikasi. Isi kolom disimpan di sini, di luar
/// `ListView`, supaya tidak hilang saat data dimuat ulang atau kolomnya tergulir
/// keluar layar. Kolom tidak ditampilkan kalau tidak ada data ([builder]
/// menerima null).
class FilteredList<T> extends StatefulWidget {
  const FilteredList({
    super.key,
    required this.items,
    required this.textOf,
    required this.label,
    required this.noun,
    required this.builder,
  });

  final List<T> items;
  final String Function(T item) textOf;
  final String label;
  final String noun;
  final Widget Function(
    BuildContext context,
    List<T> visible,
    Widget? searchBox,
  )
  builder;

  @override
  State<FilteredList<T>> createState() => _FilteredListState<T>();
}

class _FilteredListState<T> extends State<FilteredList<T>> {
  final _query = SearchQuery();

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.value;
    final visible = query.isEmpty
        ? widget.items
        : [
            for (final item in widget.items)
              if (normalizeQuery(widget.textOf(item)).contains(query)) item,
          ];
    return widget.builder(
      context,
      visible,
      widget.items.isEmpty
          ? null
          : SearchBox(
              query: _query,
              label: widget.label,
              status: query.isEmpty
                  ? null
                  : searchStatus(visible.length, widget.noun),
            ),
    );
  }
}
