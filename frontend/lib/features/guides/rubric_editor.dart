import 'package:flutter/material.dart';

import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// One rubric: the author types the rule in words ("gaps between the notes
/// more than 0.5 sec"), the server's keyword parser shows what it
/// understood and fills in the structured rule, and every field of that
/// rule can still be set by hand. The structured rule is what is saved.
class RubricEditor extends StatefulWidget {
  final Rubric rubric;
  final RubricVocabulary vocabulary;
  final Future<RubricParse> Function(String text) parse;
  final ValueChanged<Rubric> onChanged;
  final VoidCallback onRemove;

  const RubricEditor({
    super.key,
    required this.rubric,
    required this.vocabulary,
    required this.parse,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<RubricEditor> createState() => _RubricEditorState();
}

class _RubricEditorState extends State<RubricEditor> {
  late final _source = TextEditingController(text: widget.rubric.sourceText);
  late final _value = TextEditingController(text: _number(widget.rubric.value));
  late final _valueMax = TextEditingController(
    text: _number(widget.rubric.valueMax),
  );
  late final _passRate = TextEditingController(
    text: _number(widget.rubric.passRate * 100),
  );
  late final _label = TextEditingController(text: widget.rubric.label);
  late final _failMessage = TextEditingController(
    text: widget.rubric.failMessage,
  );
  late final _suggestion = TextEditingController(
    text: widget.rubric.suggestion,
  );

  RubricParse? _lastParse;
  bool _parsing = false;
  String? _parseError;

  Rubric get _rubric => widget.rubric;
  RubricVocabulary get _vocab => widget.vocabulary;

  static String _number(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _source,
      _value,
      _valueMax,
      _passRate,
      _label,
      _failMessage,
      _suggestion,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit(Rubric rubric) => widget.onChanged(rubric);

  Future<void> _understand() async {
    final text = _source.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _parsing = true;
      _parseError = null;
    });
    try {
      final result = await widget.parse(text);
      if (!mounted) return;
      final updated = result.apply(_rubric, text);
      _value.text = _number(updated.value);
      _valueMax.text = _number(updated.valueMax);
      setState(() => _lastParse = result);
      _emit(updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _parseError = e.message);
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metric = _vocab.metric(_rubric.metric);
    final units = metric?.units ?? const <String>[];
    return Card(
      color: PracticePalette.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardRadius,
        side: BorderSide(
          color: PracticePalette.lightGold.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _source,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Rule in words',
                      hintText: 'gaps between the notes more than 0.5 sec',
                    ),
                    onSubmitted: (_) => _understand(),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove rubric',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _parsing ? null : _understand,
                icon: _parsing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('Understand'),
              ),
            ),
            if (_parseError != null)
              Text(
                _parseError!,
                style: const TextStyle(color: PracticePalette.alert),
              ),
            if (_lastParse case final parse?) _understood(parse),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _dropdown(
                  label: 'Measure',
                  value: _rubric.metric,
                  items: {for (final m in _vocab.metrics) m.name: m.label},
                  onChanged: (name) {
                    final next = _vocab.metric(name);
                    final unit =
                        next != null && next.units.contains(_rubric.unit)
                        ? _rubric.unit
                        : (next?.units.first ?? _rubric.unit);
                    _emit(_rubric.copyWith(metric: name, unit: unit));
                  },
                ),
                _dropdown(
                  label: 'Rule',
                  value: _rubric.operator,
                  items: {
                    for (final o in _vocab.operators)
                      o: RubricVocabulary.operatorLabels[o] ?? o,
                  },
                  onChanged: (o) => _emit(
                    _rubric.copyWith(
                      operator: o,
                      valueMax: o == 'between' ? null : () => null,
                    ),
                  ),
                ),
                _numberField(
                  'Value',
                  _value,
                  (v) => _emit(_rubric.copyWith(value: v)),
                ),
                if (_rubric.operator == 'between')
                  _numberField(
                    'Up to',
                    _valueMax,
                    (v) => _emit(_rubric.copyWith(valueMax: () => v)),
                  ),
                _dropdown(
                  label: 'Unit',
                  value: units.contains(_rubric.unit) ? _rubric.unit : null,
                  items: {for (final u in units) u: _vocab.unitLabels[u] ?? u},
                  onChanged: (u) => _emit(_rubric.copyWith(unit: u)),
                ),
                _dropdown(
                  label: 'Notes',
                  value: _rubric.appliesTo,
                  items: {for (final a in _vocab.appliesTo) a: a},
                  onChanged: (a) => _emit(_rubric.copyWith(appliesTo: a)),
                ),
                _numberField(
                  'Pass when % of notes',
                  _passRate,
                  (v) => _emit(
                    _rubric.copyWith(passRate: (v / 100).clamp(0.01, 1.0)),
                  ),
                  width: 150,
                ),
                _dropdown(
                  label: 'Severity',
                  value: _rubric.severity,
                  items: {for (final s in _vocab.severities) s: s},
                  onChanged: (s) => _emit(_rubric.copyWith(severity: s)),
                ),
              ],
            ),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Short label (optional)',
              ),
              onChanged: (v) => _emit(_rubric.copyWith(label: v)),
            ),
            TextField(
              controller: _failMessage,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Message when it fails (optional)',
              ),
              onChanged: (v) => _emit(_rubric.copyWith(failMessage: v)),
            ),
            TextField(
              controller: _suggestion,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'What to practise'),
              onChanged: (v) => _emit(_rubric.copyWith(suggestion: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Checked'),
              value: _rubric.enabled,
              onChanged: (v) => _emit(_rubric.copyWith(enabled: v)),
            ),
          ],
        ),
      ),
    );
  }

  /// What the parser recognised, one chip per part, or what it still needs.
  Widget _understood(RubricParse parse) {
    final text = _source.text;
    String part(ParsedSpan s) => s.end <= text.length && s.start < s.end
        ? text.substring(s.start, s.end)
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.xxs,
            runSpacing: Space.xxs,
            children: [
              for (final s in parse.spans)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: PracticePalette.gold.withValues(alpha: 0.12),
                  label: Text(
                    '${s.role}: ${part(s)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (parse.rule == null && parse.message.isNotEmpty)
            Text(
              parse.message,
              style: const TextStyle(
                color: PracticePalette.alert,
                fontSize: 12,
              ),
            )
          else if (parse.rule != null)
            const Text(
              'Filled in below — check it before saving.',
              style: TextStyle(color: PracticePalette.mutedBrown, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 150,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            value: items.containsKey(value) ? value : null,
            items: [
              for (final e in items.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller,
    ValueChanged<double> onChanged, {
    double width = 100,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (text) {
          final value = double.tryParse(text.trim());
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
