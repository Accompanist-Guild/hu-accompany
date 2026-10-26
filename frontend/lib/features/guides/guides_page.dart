import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/guides/guideline_editor_page.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_repository.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The Guides tab. Everyone reads the published how-to-play guidelines
/// here. Admins and verified contributors also get "Mine"/"All" (drafts
/// included) and the editor; the server refuses changes from anyone else.
class GuidesPage extends StatefulWidget {
  final AuthController auth;
  final GuidelineRepository repository;

  const GuidesPage({
    super.key,
    required this.auth,
    this.repository = const ApiGuidelineRepository(),
  });

  @override
  State<GuidesPage> createState() => _GuidesPageState();
}

class _GuidesPageState extends State<GuidesPage> {
  bool _mine = true;
  List<Guideline>? _guidelines;
  String? _error;

  bool get _canAuthor =>
      (widget.auth.user?.canAuthorGuidelines ?? false) &&
      widget.auth.token != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GuidesPage old) {
    super.didUpdateWidget(old);
    // Signing in as an author (or out) changes what the list shows.
    final wasAuthor = _authorWhenLoaded;
    if (wasAuthor != null && wasAuthor != _canAuthor) _load();
  }

  bool? _authorWhenLoaded;

  Future<void> _load() async {
    final author = _canAuthor;
    _authorWhenLoaded = author;
    setState(() => _error = null);
    try {
      final list = author
          ? await widget.repository.list(token: widget.auth.token, mine: _mine)
          : await widget.repository.list();
      if (mounted) setState(() => _guidelines = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit([Guideline? guideline]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GuidelineEditorPage(
          auth: widget.auth,
          repository: widget.repository,
          initial: guideline,
        ),
      ),
    );
    if (saved == true) _load();
  }

  void _read(Guideline guideline) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (_) => _GuidelineReader(guideline: guideline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = _canAuthor;
    return Scaffold(
      backgroundColor: PracticePalette.ivory,
      appBar: AppBar(
        title: const Text('Guides'),
        backgroundColor: PracticePalette.ivory,
        foregroundColor: PracticePalette.brown,
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: author
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              backgroundColor: PracticePalette.brown,
              foregroundColor: PracticePalette.paper,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New guideline'),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (author)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.xs,
                  Space.md,
                  Space.xs,
                ),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Mine')),
                    ButtonSegment(value: false, label: Text('All')),
                  ],
                  selected: {_mine},
                  onSelectionChanged: (value) {
                    setState(() {
                      _mine = value.first;
                      _guidelines = null;
                    });
                    _load();
                  },
                ),
              ),
            Expanded(child: _list(author)),
          ],
        ),
      ),
    );
  }

  Widget _list(bool author) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final guidelines = _guidelines;
    if (guidelines == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (guidelines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(
            author
                ? 'No guidelines yet. Write one for an era, a composer or a '
                      'piece, and add rubrics the feedback can check.'
                : 'No guidelines yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: PracticePalette.mutedBrown),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: guidelines.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final g = guidelines[i];
          final rubrics = g.rubrics.length;
          return ListTile(
            title: Text(g.title),
            subtitle: Text(
              [
                if (g.tags.isNotEmpty) g.tags.join(', '),
                if (rubrics > 0)
                  '$rubrics ${rubrics == 1 ? 'rubric' : 'rubrics'}',
                if (g.ownerName.isNotEmpty) 'by ${g.ownerName}',
              ].join(' · '),
            ),
            trailing: author ? _StatusBadge(published: g.published) : null,
            onTap: () => author && g.editable ? _edit(g) : _read(g),
          );
        },
      ),
    );
  }
}

/// One guideline to read: its text, what it applies to, and what the
/// feedback listens for.
class _GuidelineReader extends StatelessWidget {
  final Guideline guideline;
  const _GuidelineReader({required this.guideline});

  @override
  Widget build(BuildContext context) {
    final rubrics = guideline.rubrics.where((r) => r.enabled).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Text(
            guideline.title,
            style: const TextStyle(
              color: PracticePalette.brown,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (guideline.tags.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.xxs,
              runSpacing: Space.xxs,
              children: [
                for (final t in guideline.tags)
                  Chip(label: Text(t), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: Space.sm),
          if (guideline.body.isNotEmpty)
            Text(
              guideline.body,
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          if (rubrics.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            const Text(
              'WHAT THE FEEDBACK LISTENS FOR',
              style: TextStyle(
                color: PracticePalette.gold,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final r in rubrics)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.hearing_rounded,
                      size: 16,
                      color: PracticePalette.mutedBrown,
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        r.sourceText.isNotEmpty
                            ? r.sourceText
                            : (r.label.isNotEmpty ? r.label : r.metric),
                        style: const TextStyle(
                          color: PracticePalette.mutedBrown,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool published;
  const _StatusBadge({required this.published});

  @override
  Widget build(BuildContext context) {
    final color = published ? PracticePalette.gold : PracticePalette.mutedBrown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.pillRadius,
      ),
      child: Text(
        published ? 'Published' : 'Draft',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
