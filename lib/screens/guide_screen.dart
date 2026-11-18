import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../data/guide.dart';
import '../models/models.dart';
import '../services/a11y_focus.dart';
import '../services/announce.dart';
import '../services/settings.dart';
import '../services/sound_effects.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import '../widgets/playful.dart';

/// Lama animasi membalik halaman.
const Duration kPageFlipDuration = Duration(milliseconds: 320);

/// Satu halaman buku: bab dan langkahnya. Daftar isi bukan bagian dari daftar
/// ini; ia selalu halaman 1.
class _BookPage {
  const _BookPage(this.chapter, this.chapterIndex, this.page);

  final GuideChapter chapter;
  final int chapterIndex;
  final GuidePage page;
}

/// Panduan sebagai buku interaktif. Halaman 1 berisi daftar isi; setiap
/// halaman berikutnya satu langkah: bab, judul, penjelasan, dan ilustrasi
/// (dekoratif, disembunyikan dari screen reader).
///
/// Pindah halaman lewat tombol "Halaman sebelumnya", "Halaman berikutnya",
/// dan "Daftar isi". Panah kiri dan kanan di keyboard dan geser juga bisa,
/// tetapi bukan satu-satunya cara. Setiap pindah: suara membalik halaman
/// (ikut saklar efek bunyi), pengumuman "Halaman 2 dari 8: [judul]", dan
/// fokus TalkBack pindah ke judul halaman. Animasi membalik halaman berhenti
/// kalau animasi dimatikan.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final List<GuideChapter> _chapters = guideFor(widget.role);
  late final List<_BookPage> _pages = [
    for (var c = 0; c < _chapters.length; c++)
      for (final page in _chapters[c].pages) _BookPage(_chapters[c], c, page),
  ];

  /// Indeks halaman; 0 adalah daftar isi.
  int _index = 0;
  bool _forward = true;

  /// Satu kunci per halaman: selama animasi, halaman lama dan baru ada
  /// bersamaan.
  late final List<GlobalKey> _titleKeys = List.generate(
    _total,
    (i) => GlobalKey(debugLabel: 'judul halaman panduan ${i + 1}'),
  );
  final _keyboard = FocusNode(debugLabel: 'buku panduan');

  int get _total => _pages.length + 1;

  String _titleOf(int index) =>
      index == 0 ? 'Daftar isi' : _pages[index - 1].page.title;

  /// Indeks halaman pertama sebuah bab (0 = daftar isi).
  int _firstPageOf(int chapterIndex) =>
      1 + _pages.indexWhere((p) => p.chapterIndex == chapterIndex);

  @override
  void dispose() {
    _keyboard.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index < 0 || index >= _total || index == _index) return;
    setState(() {
      _forward = index > _index;
      _index = index;
    });
    soundEffects.playPageTurn();
    announce('Halaman ${index + 1} dari $_total: ${_titleOf(index)}');
    moveScreenReaderFocus(_titleKeys[index]);
  }

  void _next() => _go(_index + 1);
  void _previous() => _go(_index - 1);

  @override
  Widget build(BuildContext context) {
    final last = _index == _total - 1;
    return PurpleScaffold(
      appBar: aprevoAppBar('Panduan ${widget.role.label}'),
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
          },
          child: Focus(
            focusNode: _keyboard,
            autofocus: true,
            child: GestureDetector(
              // Tambahan untuk pengguna yang melihat layar. TalkBack memakai
              // geser untuk dirinya sendiri, jadi tombol tetap cara utama.
              onHorizontalDragEnd: (details) {
                final speed = details.primaryVelocity ?? 0;
                if (speed < -300) _next();
                if (speed > 300) _previous();
              },
              child: Column(
                children: [
                  Expanded(child: _flipping(context)),
                  _navigation(last),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Animasi membalik halaman: halaman baru berputar masuk dari tepi,
  /// halaman lama memudar. Halaman lama disembunyikan dari screen reader.
  Widget _flipping(BuildContext context) {
    final current = ValueKey(_index);
    return AnimatedSwitcher(
      duration: reduceMotion(context) ? Duration.zero : kPageFlipDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == current;
        return ExcludeSemantics(
          excluding: !incoming,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              final turn = (1 - animation.value) * math.pi / 2;
              return Opacity(
                opacity: animation.value.clamp(0.0, 1.0),
                child: Transform(
                  alignment: _forward
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(incoming ? (_forward ? turn : -turn) : 0),
                  child: child,
                ),
              );
            },
          ),
        );
      },
      layoutBuilder: (currentChild, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?currentChild],
      ),
      child: KeyedSubtree(
        key: current,
        child: _index == 0 ? _contents() : _stepPage(_pages[_index - 1]),
      ),
    );
  }

  Widget _title(String text) => Semantics(
    key: _titleKeys[_index],
    container: true,
    header: true,
    child: Text(text, style: AppType.headlineMedium),
  );

  Widget _pageNumber() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      'Halaman ${_index + 1} dari $_total',
      textAlign: TextAlign.center,
      style: AppType.bodySmall.copyWith(color: AppColors.white),
    ),
  );

  Widget _contents() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ExcludeSemantics(
          child: Center(child: Mascot(size: 110, decorative: true)),
        ),
        const SizedBox(height: 8),
        _title('Daftar isi'),
        const SizedBox(height: 8),
        Text(
          'Ada ${_chapters.length} bab. Pilih bab untuk langsung membukanya, '
          'atau tekan Halaman berikutnya untuk membaca dari awal.',
          style: AppType.bodyMedium.copyWith(color: AppColors.white),
        ),
        const SizedBox(height: 16),
        for (var c = 0; c < _chapters.length; c++)
          ListRow(
            key: ValueKey('bab-$c'),
            icon: _chapters[c].icon,
            title: 'Bab ${c + 1}: ${_chapters[c].title}',
            subtitle:
                '${_chapters[c].pages.length} halaman, mulai halaman '
                '${_firstPageOf(c) + 1}',
            semanticLabel:
                'Bab ${c + 1}: ${_chapters[c].title}. '
                '${_chapters[c].pages.length} halaman, mulai halaman '
                '${_firstPageOf(c) + 1}',
            onTap: () => _go(_firstPageOf(c)),
          ),
        _pageNumber(),
      ],
    );
  }

  Widget _stepPage(_BookPage entry) {
    final art = entry.page.art;
    final mood = art.mood;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Bab ${entry.chapterIndex + 1}: ${entry.chapter.title}',
            style: AppType.titleMedium.copyWith(color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 8),
        _title(entry.page.title),
        const SizedBox(height: 16),
        // Ilustrasi hanya hiasan; isinya sudah ada di judul dan penjelasan.
        ExcludeSemantics(
          child: Center(
            child: mood != null
                ? Mascot(size: 140, mood: mood, decorative: true)
                : Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.lilac,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.ink, width: 3),
                    ),
                    child: Icon(art.icon, size: 72, color: AppColors.ink),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(child: Text(entry.page.body, style: AppType.bodyLarge)),
        _pageNumber(),
      ],
    );
  }

  Widget _navigation(bool last) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (last)
            PrimaryButton(
              label: 'Selesai membaca panduan',
              icon: Icons.check,
              onPressed: () => Navigator.pop(context),
            )
          else
            PrimaryButton(
              label: 'Halaman berikutnya',
              icon: Icons.arrow_forward,
              onPressed: _next,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Halaman sebelumnya'),
                  onPressed: _index == 0 ? null : _previous,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.list),
                  label: const Text('Daftar isi'),
                  onPressed: _index == 0 ? null : () => _go(0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void openGuide(BuildContext context, UserRole role) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => GuideScreen(role: role)),
  );
}

/// Menawarkan panduan sekali per akun di perangkat ini, saat pertama kali
/// sampai di beranda. Dialog dibuka setelah layar beranda tampil, supaya
/// TalkBack membaca judul dialog, bukan judul beranda.
Future<void> offerGuideOnce(BuildContext context) async {
  final account = store.currentUser;
  if (!Settings.offerGuide || account == null) return;
  if (Settings.guideOffered(account.email)) return;
  await Settings.markGuideOffered(account.email);
  if (!context.mounted) return;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mau membaca panduan dulu?'),
      semanticLabel: 'Mau membaca panduan dulu?',
      content: const Text(
        'Panduan berisi langkah demi langkah memakai setiap fitur, seperti '
        'buku. Panduan juga bisa dibuka kapan saja dari Profil.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nanti saja'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Buka panduan'),
        ),
      ],
    ),
  );
  if (open == true && context.mounted) openGuide(context, account.role);
}
