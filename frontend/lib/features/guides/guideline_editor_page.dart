import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/guides/rubric_editor.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_repository.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Writing one guideline: its title and how-to-play text, the tags it
/// applies to ("baroque", "bach"), whether players see it yet, and the
/// rubrics the phrase feedback checks. Pops `true` once saved or deleted.
class GuidelineEditorPage extends StatefulWidget {
  final AuthController auth;
  final GuidelineRepository repository;
  final Guideline? initial;

  const GuidelineEditorPage({
    super.key,
    required this.auth,
    required this.repository,
    this.initial,
  });

  @override
  State<GuidelineEditorPage> createState() => _GuidelineEditorPageState();
}

class _GuidelineEditorPageState extends State<GuidelineEditorPage> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.initial?.body ?? '',
  );
  late List<String> _tags = [...?widget.initial?.tags];
  late bool _published = widget.initial?.published ?? false;

  /// Each rubric with a stable key, so editing one never resets another.
  late final List<(Key, Rubric)> _rubrics = [
    for (final r in widget.initial?.rubrics ?? const <Rubric>[])
      (UniqueKey(), r),
  ];

  RubricVocabulary? _vocabulary;
  List<String> _knownTags = const [];
  String? _loadError;
  bool _saving = false;

  static const int _maxTags = 20;
  static const int _maxRubrics = 20;

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadVocabulary() async {
    try {
      final vocabulary = await widget.repository.vocabulary();
      final tags = await widget.repository.tags();
      if (!mounted) return;
      setState(() {
        _vocabulary = vocabulary;
        _knownTags = tags;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  String get _token => widget.auth.token ?? '';

  Future<RubricParse> _parse(String text) =>
      widget.repository.parse(token: _token, text: text);

  Guideline get _draft => Guideline(
    id: widget.initial?.id,
    title: _title.text.trim(),
    body: _body.text,
    tags: _tags,
    status: _published ? 'published' : 'draft',
    rubrics: [for (final (_, r) in _rubrics) r],
  );

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _say('Give the guideline a title.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = widget.initial?.id;
      if (id == null) {
        await widget.repository.create(token: _token, guideline: _draft);
      } else {
        await widget.repository.update(
          token: _token,
          id: id,
          guideline: _draft,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this guideline?'),
        content: const Text('Players stop seeing it straight away.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await widget.repository.delete(token: _token, id: id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _say(e.message);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addTag(String raw) {
    final tag = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (tag.isEmpty || _tags.contains(tag) || _tags.length >= _maxTags) return;
    setState(() => _tags = [..._tags, tag]);
  }

  void _addRubric() {
    final vocabulary = _vocabulary;
    if (vocabulary == null || _rubrics.length >= _maxRubrics) return;
    final metric = vocabulary.metrics.first;
    setState(
      () => _rubrics.add((
        UniqueKey(),
        Rubric(
          metric: metric.name,
          operator: 'gt',
          value: 0,
          unit: metric.units.first,
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial?.id != null;
    return Scaffold(
      backgroundColor: PracticePalette.ivory,
      appBar: AppBar(
        title: Text(editing ? 'Edit guideline' : 'New guideline'),
        backgroundColor: PracticePalette.ivory,
        foregroundColor: PracticePalette.brown,
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete guideline',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.md),
          children: [
            TextField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Baroque: detached touch',
              ),
            ),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 12,
              maxLength: 20000,
              decoration: const InputDecoration(
                labelText: 'How to play',
                hintText: 'Notes should be highly detached in this era…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Space.sm),
            _tagsField(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              subtitle: const Text('Players see published guidelines only'),
              value: _published,
              onChanged: (value) => setState(() => _published = value),
            ),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'RUBRICS',
                    style: TextStyle(
                      color: PracticePalette.gold,
                      fontSize: 11,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _vocabulary == null ? null : _addRubric,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add rubric'),
                ),
              ],
            ),
            if (_loadError != null)
              Text(
                _loadError!,
                style: const TextStyle(color: PracticePalette.alert),
              )
            else if (_vocabulary == null)
              const Center(child: CircularProgressIndicator())
            else if (_rubrics.isEmpty)
              const Text(
                'No rubrics: the guideline is shown as text only. Add one to have '
                'the feedback check it, e.g. “gaps between the notes more than 0.5 sec”.',
                style: TextStyle(
                  color: PracticePalette.mutedBrown,
                  fontSize: 13,
                ),
              ),
            if (_vocabulary != null)
              for (var i = 0; i < _rubrics.length; i++)
                Padding(
                  key: _rubrics[i].$1,
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: RubricEditor(
                    rubric: _rubrics[i].$2,
                    vocabulary: _vocabulary!,
                    parse: _parse,
                    onChanged: (r) =>
                        setState(() => _rubrics[i] = (_rubrics[i].$1, r)),
                    onRemove: () => setState(() => _rubrics.removeAt(i)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _tagsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xxs,
          children: [
            for (final tag in _tags)
              InputChip(
                label: Text(tag),
                onDeleted: () =>
                    setState(() => _tags = [..._tags]..remove(tag)),
                deleteButtonTooltipMessage: 'Remove tag $tag',
              ),
          ],
        ),
        Autocomplete<String>(
          optionsBuilder: (value) {
            final text = value.text.trim().toLowerCase();
            if (text.isEmpty) return const Iterable<String>.empty();
            return _knownTags.where(
              (t) => t.contains(text) && !_tags.contains(t),
            );
          },
          onSelected: _addTag,
          fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            decoration: const InputDecoration(
              labelText: 'Add a tag',
              hintText: 'baroque, bach, fugue…',
              helperText: 'Applies to every piece with any of these tags',
            ),
            onSubmitted: (value) {
              _addTag(value);
              controller.clear();
            },
          ),
        ),
      ],
    );
  }
}
