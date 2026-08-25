import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class BandEditScreen extends StatefulWidget {
  const BandEditScreen({super.key});

  @override
  State<BandEditScreen> createState() => _BandEditScreenState();
}

class _BandEditScreenState extends State<BandEditScreen> {
  final _scrollController = ScrollController();
  final _requiredKey = GlobalKey();
  final _linksKey = GlobalKey();
  final _membersKey = GlobalKey();

  final _name = TextEditingController();
  final _area = TextEditingController();
  final _bio = TextEditingController();
  final _instagram = TextEditingController();
  final _bandcamp = TextEditingController();
  final _youtube = TextEditingController();
  final _credits = TextEditingController();
  final _customGenre = TextEditingController();

  String? _loadedBandId;
  String? _lastSection;
  List<String> _genres = [];
  bool _detailsApplied = false;
  bool _instagramDirty = false;
  bool _bandcampDirty = false;
  bool _youtubeDirty = false;
  bool _creditsDirty = false;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final band = app.myBand;
    if (band != null && _loadedBandId != band.id) {
      _loadedBandId = band.id;
      _name.text = band.name;
      _area.text = band.area;
      _bio.text = band.bio;
      _instagram.text = band.linkIg ?? '';
      _bandcamp.text = band.linkBc ?? '';
      _youtube.text = band.linkYt ?? '';
      _credits.text =
          app.profileDetailsFor(band.id)?.credits ?? band.credits ?? '';
      _genres = List.of(band.genres);
      _detailsApplied = false;
      _instagramDirty = false;
      _bandcampDirty = false;
      _youtubeDirty = false;
      _creditsDirty = false;
    }
    final details = band == null ? null : app.profileDetailsFor(band.id);
    if (details != null && !_detailsApplied) {
      if (!_instagramDirty) {
        _instagram.text = details.linkIg ?? band!.linkIg ?? '';
      }
      if (!_bandcampDirty) {
        _bandcamp.text = details.linkBc ?? band!.linkBc ?? '';
      }
      if (!_youtubeDirty) {
        _youtube.text = details.linkYt ?? band!.linkYt ?? '';
      }
      if (!_creditsDirty) {
        _credits.text = details.credits ?? band!.credits ?? '';
      }
      _detailsApplied = true;
    }

    final section = app.current.param;
    if (section != null && section != _lastSection) {
      _lastSection = section;
      final key = switch (section) {
        'required' => _requiredKey,
        'links' => _linksKey,
        'members' => _membersKey,
        _ => null,
      };
      if (key != null) _scrollToSection(key);
    }
  }

  void _scrollToSection(GlobalKey key, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .08,
        );
        return;
      }
      if (!_scrollController.hasClients || attempt >= 8) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _scrollToSection(key, attempt + 1);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _name.dispose();
    _area.dispose();
    _bio.dispose();
    _instagram.dispose();
    _bandcamp.dispose();
    _youtube.dispose();
    _credits.dispose();
    _customGenre.dispose();
    super.dispose();
  }

  void _draftChanged([String? _]) {
    if (!_saved && _error == null) return;
    setState(() {
      _saved = false;
      _error = null;
    });
  }

  void _toggleGenre(String genre) {
    setState(() {
      _saved = false;
      _error = null;
      if (_genres.contains(genre)) {
        _genres.remove(genre);
      } else if (_genres.length < 3) {
        _genres.add(genre);
      } else {
        _error = 'Choose no more than three genres.';
      }
    });
  }

  void _addCustomGenre() {
    final genre = _customGenre.text.trim().toLowerCase();
    if (genre.isEmpty || _genres.contains(genre)) return;
    if (_genres.length >= 3) {
      setState(() => _error = 'Choose no more than three genres.');
      return;
    }
    setState(() {
      _genres.add(genre);
      _customGenre.clear();
      _saved = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final area = _area.text.trim();
    if (name.isEmpty || _genres.isEmpty || area.isEmpty) {
      setState(() {
        _saved = false;
        _error = 'Band name, sound, and home base are required.';
      });
      return;
    }
    if (_genres.length > 3) {
      setState(() => _error = 'Choose no more than three genres.');
      return;
    }

    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await context.read<AppState>().saveBandProfile(
        BandProfileUpdate(
          bandId: _loadedBandId!,
          name: name,
          genres: List.of(_genres),
          area: area,
          bio: _bio.text,
          linkIg: _instagram.text,
          linkBc: _bandcamp.text,
          linkYt: _youtube.text,
          credits: _credits.text,
        ),
      );
      if (!mounted) return;
      setState(() => _saved = true);
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Changes could not be saved. Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null || !app.isAdminOf(band.id)) {
      return const SizedBox.shrink();
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance + 24,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'EDIT PROFILE',
              style: Theme.of(context).textTheme.epPageHeading,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: app.previewPublicProfile,
                child: const Text('PREVIEW PUBLIC PROFILE'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Update the public details fans use to recognize and discover your band.',
          style: epText(size: 12, color: Ep.contentSecondary, height: 1.4),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: _requiredKey,
          child: _EditorSection(
            title: 'Required details',
            description: 'These details keep your profile useful in discovery.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EditorField(
                  label: 'Band name',
                  child: TextField(
                    key: const ValueKey('edit-band-name'),
                    controller: _name,
                    onChanged: _draftChanged,
                    style: epText(size: 13),
                    decoration: epInputDecoration('Band name'),
                  ),
                ),
                const SizedBox(height: 14),
                const _FieldLabel('Sound / genres'),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final genre in {...kGenres, ..._genres})
                      EpChip(
                        label: genre,
                        active: _genres.contains(genre),
                        onTap: () => _toggleGenre(genre),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('edit-custom-genre'),
                        controller: _customGenre,
                        onSubmitted: (_) => _addCustomGenre(),
                        style: epText(size: 12.5),
                        decoration: epInputDecoration('Another genre'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addCustomGenre,
                      child: const Text('ADD'),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${_genres.length} of 3 selected',
                  style: epText(size: 10.5, color: Ep.contentDisabled),
                ),
                const SizedBox(height: 14),
                _EditorField(
                  label: 'Home base',
                  child: TextField(
                    key: const ValueKey('edit-home-base'),
                    controller: _area,
                    onChanged: _draftChanged,
                    style: epText(size: 13),
                    decoration: epInputDecoration('Neighborhood or city'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _EditorSection(
          title: 'Optional details',
          description: 'Add these now or come back whenever you are ready.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BandAvatar(band, size: 58, radius: 12, fontSize: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('Profile image'),
                        TextAction(
                          'CHANGE PROFILE IMAGE',
                          onTap: app.openBandMedia,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _EditorField(
                label: 'Short bio',
                child: TextField(
                  key: const ValueKey('edit-short-bio'),
                  controller: _bio,
                  onChanged: _draftChanged,
                  minLines: 3,
                  maxLines: 6,
                  style: epText(size: 13, height: 1.45),
                  decoration: epInputDecoration('Tell fans about the band'),
                ),
              ),
              const SizedBox(height: 14),
              KeyedSubtree(
                key: _linksKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('Links'),
                    const SizedBox(height: 7),
                    TextField(
                      key: const ValueKey('edit-instagram'),
                      controller: _instagram,
                      onChanged: (value) {
                        _instagramDirty = true;
                        _draftChanged(value);
                      },
                      style: epText(size: 12.5),
                      decoration: epInputDecoration('Instagram'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('edit-bandcamp'),
                      controller: _bandcamp,
                      onChanged: (value) {
                        _bandcampDirty = true;
                        _draftChanged(value);
                      },
                      style: epText(size: 12.5),
                      decoration: epInputDecoration('Bandcamp'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('edit-youtube'),
                      controller: _youtube,
                      onChanged: (value) {
                        _youtubeDirty = true;
                        _draftChanged(value);
                      },
                      style: epText(size: 12.5),
                      decoration: epInputDecoration('YouTube or video'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _EditorField(
                label: 'Credits',
                child: TextField(
                  key: const ValueKey('edit-credits'),
                  controller: _credits,
                  onChanged: (value) {
                    _creditsDirty = true;
                    _draftChanged(value);
                  },
                  minLines: 3,
                  maxLines: 6,
                  style: epText(size: 13, height: 1.45),
                  decoration: epInputDecoration(
                    'Producers, artists, labels, and collaborators',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Music and clips'),
              const SizedBox(height: 5),
              OutlinedButton.icon(
                onPressed: app.openBandMedia,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('MANAGE MUSIC AND MEDIA'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        KeyedSubtree(key: _membersKey, child: const _BandMembersSection()),
        const SizedBox(height: 16),
        if (_error case final error?) ...[
          Text(
            error,
            key: const ValueKey('profile-save-error'),
            style: epText(size: 11.5, color: Ep.warning, height: 1.4),
          ),
          const SizedBox(height: 8),
        ] else if (_saved) ...[
          Text(
            'Changes saved.',
            key: const ValueKey('profile-save-success'),
            style: epText(size: 11.5, color: Ep.accent),
          ),
          const SizedBox(height: 8),
        ],
        EpButton(
          _saving ? 'SAVING…' : 'SAVE CHANGES',
          kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: epDisplay(size: 15)),
          const SizedBox(height: 3),
          Text(
            description,
            style: epText(size: 10.5, color: Ep.contentSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_FieldLabel(label), const SizedBox(height: 7), child],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: epText(
        size: 10,
        weight: FontWeight.w900,
        letterSpacing: .8,
        color: Ep.contentSecondary,
      ),
    );
  }
}

class _BandMembersSection extends StatefulWidget {
  const _BandMembersSection();

  @override
  State<_BandMembersSection> createState() => _BandMembersSectionState();
}

class _BandMembersSectionState extends State<_BandMembersSection> {
  bool _working = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'The invitation could not be updated. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _expiryLabel(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = app.bandId;
    final invite = app.inviteFor(id);
    final loading = app.inviteLoadingFor(id);
    final members = app.profileDetailsFor(id)?.memberNames ?? const [];
    final expired = invite != null && DateTime.now().isAfter(invite.expiresAt);
    final active = invite != null && !invite.revoked && !expired;

    return _EditorSection(
      title: 'Band members',
      description:
          'Share one secure link. It can be used by multiple members for seven days.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Accepted members'),
          const SizedBox(height: 7),
          if (members.isEmpty)
            Text(
              'No additional members have joined yet.',
              style: epText(size: 11.5, color: Ep.contentSecondary),
            )
          else
            for (final member in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 17,
                      color: Ep.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(member, style: epText(size: 12.5))),
                  ],
                ),
              ),
          const SizedBox(height: 10),
          const _FieldLabel('Invitation link'),
          const SizedBox(height: 7),
          if (loading && invite == null)
            const Center(child: CircularProgressIndicator())
          else if (!active) ...[
            if (invite != null)
              Text(
                invite.revoked
                    ? 'The previous invitation was revoked.'
                    : 'The previous invitation expired.',
                style: epText(size: 11, color: Ep.contentSecondary),
              ),
            if (invite != null) const SizedBox(height: 8),
            EpButton(
              invite == null
                  ? 'CREATE INVITATION LINK'
                  : 'CREATE NEW INVITATION LINK',
              kind: _working ? EpButtonKind.disabled : EpButtonKind.outline,
              onTap: _working
                  ? null
                  : () => _run(() async {
                      await app.createBandInvitation();
                    }),
            ),
          ] else ...[
            EpCard(
              variant: EpCardVariant.selected,
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    invite.url,
                    key: const ValueKey('band-invite-url'),
                    style: epText(size: 11.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'ACTIVE · EXPIRES ${_expiryLabel(invite.expiresAt)}',
                    style: epText(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: Ep.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: invite.url));
                      app.say('Invitation link copied.');
                    },
              icon: const Icon(Icons.copy, size: 17),
              label: const Text('COPY INVITATION LINK'),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working
                        ? null
                        : () => _run(() async {
                            await app.rotateBandInvitation();
                          }),
                    child: const Text('ROTATE LINK'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working
                        ? null
                        : () => _run(app.revokeBandInvitation),
                    child: const Text('REVOKE LINK'),
                  ),
                ),
              ],
            ),
          ],
          if (_working) ...[
            const SizedBox(height: 9),
            const LinearProgressIndicator(),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              key: const ValueKey('invite-management-error'),
              style: epText(size: 11, color: Ep.warning),
            ),
          ],
        ],
      ),
    );
  }
}
