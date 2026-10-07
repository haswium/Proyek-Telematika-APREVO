import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/playful.dart';

/// Form satu soal. Mengembalikan [Question] lewat Navigator.pop.
class QuestionFormScreen extends StatefulWidget {
  const QuestionFormScreen({super.key, required this.type, this.initial});

  final GameType type;
  final Question? initial;

  @override
  State<QuestionFormScreen> createState() => _QuestionFormScreenState();
}

class _QuestionFormScreenState extends State<QuestionFormScreen> {
  final _prompt = TextEditingController();
  final _explanation = TextEditingController();
  final _imageDescription = TextEditingController();
  final _answer = TextEditingController();
  final List<TextEditingController> _options = List.generate(
    4,
    (_) => TextEditingController(),
  );
  int _correct = 0;

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    if (q == null) return;
    _prompt.text = q.prompt;
    _explanation.text = q.explanation ?? '';
    _imageDescription.text = q.imageDescription ?? '';
    _answer.text = q.answerText;
    _correct = q.correctIndex;
    if (widget.type != GameType.trueFalse) {
      for (var i = 0; i < q.options.length && i < _options.length; i++) {
        _options[i].text = q.options[i];
      }
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _explanation.dispose();
    _imageDescription.dispose();
    _answer.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _orNull(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  void _save() {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      _error('Pertanyaan belum diisi.');
      return;
    }
    final filled = _options
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    var options = <String>[];
    var correctIndex = 0;
    var answerText = '';

    switch (widget.type) {
      case GameType.quiz:
        if (filled.length < 4) {
          _error('Isi keempat pilihan jawaban.');
          return;
        }
        options = filled;
        correctIndex = _correct;
      case GameType.trueFalse:
        options = const ['Benar', 'Salah'];
        correctIndex = _correct > 1 ? 0 : _correct;
      case GameType.shortAnswer:
        answerText = _answer.text.trim();
        if (answerText.isEmpty) {
          _error('Jawaban benar belum diisi.');
          return;
        }
      case GameType.ordering:
        if (filled.length < 2) {
          _error('Isi minimal dua langkah.');
          return;
        }
        options = filled;
    }

    Navigator.pop(
      context,
      Question(
        prompt: prompt,
        options: options,
        correctIndex: correctIndex,
        answerText: answerText,
        explanation: _orNull(_explanation),
        imageDescription: _orNull(_imageDescription),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isStatement = widget.type == GameType.trueFalse;
    return PurpleScaffold(
      appBar: aprevoAppBar('Soal ${widget.type.label}'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _prompt,
              maxLines: 3,
              style: AppType.bodyLarge,
              decoration: fieldDecoration(
                isStatement ? 'Pernyataan' : 'Pertanyaan',
              ),
            ),
            const SizedBox(height: 16),
            ..._answerFields(text),
            const SizedBox(height: 16),
            TextField(
              controller: _imageDescription,
              maxLines: 3,
              decoration: fieldDecoration(
                'Deskripsi gambar (opsional)',
                hint: 'Dibacakan ke siswa sebagai pengganti gambar',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _explanation,
              maxLines: 3,
              decoration: fieldDecoration(
                'Penjelasan jawaban',
                hint: 'Dibacakan Odi saat siswa menjawab, terutama kalau salah',
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Simpan soal',
              icon: Icons.check,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _answerFields(TextTheme text) {
    switch (widget.type) {
      case GameType.quiz:
        return [
          for (var i = 0; i < 4; i++) ...[
            TextField(
              controller: _options[i],
              decoration: fieldDecoration(
                'Pilihan ${String.fromCharCode(65 + i)}',
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SectionTitle('Jawaban benar'),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 4; i++)
                ChoiceChip(
                  label: Text('Pilihan ${String.fromCharCode(65 + i)}'),
                  selected: _correct == i,
                  onSelected: (_) => setState(() => _correct = i),
                ),
            ],
          ),
        ];
      case GameType.trueFalse:
        return [
          const SectionTitle('Jawaban benar'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Benar'),
                selected: _correct == 0,
                onSelected: (_) => setState(() => _correct = 0),
              ),
              ChoiceChip(
                label: const Text('Salah'),
                selected: _correct == 1,
                onSelected: (_) => setState(() => _correct = 1),
              ),
            ],
          ),
        ];
      case GameType.shortAnswer:
        return [
          TextField(
            controller: _answer,
            decoration: fieldDecoration(
              'Jawaban benar',
              hint: 'Huruf besar dan kecil tidak dibedakan',
            ),
          ),
        ];
      case GameType.ordering:
        return [
          Text(
            'Tulis langkah dalam urutan yang benar. Aplikasi akan '
            'mengacaknya untuk siswa.',
            style: AppType.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 4; i++) ...[
            TextField(
              controller: _options[i],
              decoration: fieldDecoration('Langkah ${i + 1}'),
            ),
            const SizedBox(height: 12),
          ],
        ];
    }
  }
}
