import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/announce.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/load_view.dart';
import '../../widgets/playful.dart';

/// Siswa melihat nama guru dan teman sekelasnya. Tiap baris satu fokus TalkBack.
class ClassmatesScreen extends StatefulWidget {
  const ClassmatesScreen({super.key, required this.subject});

  final Subject subject;

  @override
  State<ClassmatesScreen> createState() => _ClassmatesScreenState();
}

class _ClassmatesScreenState extends State<ClassmatesScreen> {
  bool _announced = false;

  /// Jumlah siswa diumumkan sekali, tidak diulang saat data dimuat ulang.
  void _announceCount(int count) {
    if (_announced) return;
    _announced = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        announce('Anggota kelas ${widget.subject.name}: $count siswa');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PurpleScaffold(
      appBar: aprevoAppBar('Anggota kelas'),
      body: SafeArea(
        child: LoadView<ClassmateList>(
          loadingMessage: 'Memuat anggota ${widget.subject.name}.',
          load: () => store.classmates(widget.subject.id),
          builder: (context, data, _) {
            _announceCount(data.count);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    widget.subject.name,
                    style: AppType.headlineMedium,
                  ),
                ),
                if (data.teacherName != null) ...[
                  const SectionTitle('Guru'),
                  ListRow(
                    icon: Icons.school_outlined,
                    title: data.teacherName!,
                    semanticLabel: 'Guru: ${data.teacherName}',
                  ),
                ],
                SectionTitle('Teman sekelas (${data.count} siswa)'),
                for (final classmate in data.classmates)
                  ListRow(
                    icon: Icons.person_outline,
                    title: classmate.label,
                    semanticLabel: classmate.label,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
