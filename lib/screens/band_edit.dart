import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../services/user_actions.dart';
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
  bool _addingCustomGenre = false;
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
      _addingCustomGenre = false;
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
      _revealFeedback();
      return;
    }
    if (_genres.length > 3) {
      setState(() => _error = 'Choose no more than three genres.');
      _revealFeedback();
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
      _revealFeedback();
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Changes could not be saved. Check your connection and retry.';
      });
      _revealFeedback();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _revealFeedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null || !app.isAdminOf(band.id)) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              headerTopPad(context),
              16,
              tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'EDIT BAND',
                      style: Theme.of(context).textTheme.epPageHeading,
                    ),
                  ),
                  TextAction(
                    'PREVIEW →',
                    onTap: _saving ? null : app.previewPublicProfile,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ],
              ),
              Text(
                'Update the public details fans use to recognize and discover your band.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              KeyedSubtree(
                key: _requiredKey,
                child: _EditorSection(
                  title: 'Required details',
                  description:
                      'These details keep your profile useful in discovery.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        label: 'Band name',
                        textField: true,
                        child: TextField(
                          key: const ValueKey('edit-band-name'),
                          controller: _name,
                          enabled: !_saving,
                          onChanged: _draftChanged,
                          style: Theme.of(context).textTheme.epBody,
                          decoration: _bandInput('BAND NAME', 'Band name'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _FieldLabel('GENRES'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final genre in {...kGenres, ..._genres})
                            EpChip(
                              label: genre,
                              active: _genres.contains(genre),
                              onTap: _saving ? null : () => _toggleGenre(genre),
                            ),
                          EpChip(
                            key: const ValueKey('show-custom-genre'),
                            label: '+ ADD',
                            active: false,
                            ghost: true,
                            semanticLabel: 'Add custom genre',
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                    _addingCustomGenre = true;
                                    _error = null;
                                  }),
                          ),
                        ],
                      ),
                      if (_addingCustomGenre) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('edit-custom-genre'),
                                controller: _customGenre,
                                enabled: !_saving,
                                autofocus: true,
                                onSubmitted: (_) => _addCustomGenre(),
                                style: Theme.of(context).textTheme.epBody,
                                decoration: epInputDecoration('Another genre'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : _addCustomGenre,
                              child: const Text('ADD'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        '${_genres.length} of 3 selected',
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        label: 'Home base',
                        textField: true,
                        child: TextField(
                          key: const ValueKey('edit-home-base'),
                          controller: _area,
                          enabled: !_saving,
                          onChanged: _draftChanged,
                          style: Theme.of(context).textTheme.epBody,
                          decoration: _bandInput(
                            'HOME BASE',
                            'Neighborhood or city',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _EditorSection(
                title: 'Optional details',
                description:
                    'Add these now or come back whenever you are ready.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        BandAvatar(band, size: 58, radius: 12, fontSize: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextAction(
                            'CHANGE PROFILE IMAGE',
                            onTap: _saving ? null : app.openBandMedia,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      label: 'Short bio',
                      textField: true,
                      child: TextField(
                        key: const ValueKey('edit-short-bio'),
                        controller: _bio,
                        enabled: !_saving,
                        onChanged: _draftChanged,
                        minLines: 3,
                        maxLines: 6,
                        style: Theme.of(context).textTheme.epBody,
                        decoration: _bandInput(
                          'SHORT BIO',
                          'Tell fans about the band',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _MediaManagementRow(
                      onTap: _saving ? null : app.openBandMedia,
                    ),
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _linksKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FieldLabel('LINKS'),
                          const SizedBox(height: 7),
                          TextField(
                            key: const ValueKey('edit-instagram'),
                            controller: _instagram,
                            enabled: !_saving,
                            onChanged: (value) {
                              _instagramDirty = true;
                              _draftChanged(value);
                            },
                            style: Theme.of(context).textTheme.epBody,
                            decoration: _bandInput('INSTAGRAM', 'Instagram'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const ValueKey('edit-bandcamp'),
                            controller: _bandcamp,
                            enabled: !_saving,
                            onChanged: (value) {
                              _bandcampDirty = true;
                              _draftChanged(value);
                            },
                            style: Theme.of(context).textTheme.epBody,
                            decoration: _bandInput('BANDCAMP', 'Bandcamp'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const ValueKey('edit-youtube'),
                            controller: _youtube,
                            enabled: !_saving,
                            onChanged: (value) {
                              _youtubeDirty = true;
                              _draftChanged(value);
                            },
                            style: Theme.of(context).textTheme.epBody,
                            decoration: _bandInput(
                              'YOUTUBE OR VIDEO',
                              'YouTube or video',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      label: 'Credits',
                      textField: true,
                      child: TextField(
                        key: const ValueKey('edit-credits'),
                        controller: _credits,
                        enabled: !_saving,
                        onChanged: (value) {
                          _creditsDirty = true;
                          _draftChanged(value);
                        },
                        minLines: 3,
                        maxLines: 6,
                        style: Theme.of(context).textTheme.epBody,
                        decoration: _bandInput(
                          'CREDITS',
                          'Producers, artists, labels, and collaborators',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              KeyedSubtree(
                key: _membersKey,
                child: const _BandMembersSection(),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('profile-save-error'),
                    style: Theme.of(
                      context,
                    ).textTheme.epBody.copyWith(color: Ep.warning),
                  ),
                ),
              ] else if (_saved) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Changes saved.',
                    key: const ValueKey('profile-save-success'),
                    style: Theme.of(
                      context,
                    ).textTheme.epBody.copyWith(color: Ep.success),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _ArchiveBandAction(band: band),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 66,
          child: StickyActionBar(
            key: const ValueKey('save-band-profile'),
            primaryLabel: _saving ? 'SAVING…' : 'SAVE CHANGES',
            onPrimary: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

InputDecoration _bandInput(String label, String hint) =>
    epInputDecoration(hint).copyWith(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.description,
    required this.child,
    this.count,
  });

  final String title;
  final String description;
  final Widget child;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: title, count: count),
        Text(description, style: Theme.of(context).textTheme.epCaption),
        const SizedBox(height: 14),
        child,
      ],
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
      style: Theme.of(context).textTheme.epLabel.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: .8,
        color: Ep.contentSecondary,
      ),
    );
  }
}

class _MediaManagementRow extends StatelessWidget {
  const _MediaManagementRow({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Manage music and media',
      excludeSemantics: true,
      child: Material(
        color: Ep.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: Ep.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    color: onTap == null ? Ep.contentDisabled : Ep.volt,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'MANAGE MUSIC AND MEDIA',
                      style: Theme.of(context).textTheme.epLabel.copyWith(
                        color: onTap == null
                            ? Ep.contentDisabled
                            : Ep.contentPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: onTap == null ? Ep.contentDisabled : Ep.mute,
                  ),
                ],
              ),
            ),
          ),
        ),
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
  String? _loadedBandId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final id = app.bandId;
    if (id.isEmpty || _loadedBandId == id) return;
    _loadedBandId = id;
    Future.microtask(() => app.refreshBandInvite(id));
  }

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
    final active = invite != null && !invite.revoked && !invite.expired;

    return _EditorSection(
      title: 'Band members',
      count: members.length,
      description:
          'Share one secure link. It can be used by multiple members for seven days.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('ACCEPTED MEMBERS'),
          const SizedBox(height: 7),
          if (members.isEmpty)
            Text(
              'No additional members have joined yet.',
              style: epText(size: 11.5, color: Ep.contentSecondary),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final member in members)
                  EpChip(
                    key: ValueKey('accepted-member-$member'),
                    label: member,
                    active: false,
                    onTap: null,
                    semanticLabel: '$member, accepted member',
                  ),
              ],
            ),
          const SizedBox(height: 10),
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
                      size: 11,
                      weight: FontWeight.w800,
                      color: Ep.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _working
                  ? null
                  : () => copyForUser(
                      context,
                      invite.url,
                      successMessage: 'Invitation link copied.',
                    ),
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

class _ArchiveBandAction extends StatelessWidget {
  const _ArchiveBandAction({required this.band});

  final Band band;

  @override
  Widget build(BuildContext context) {
    return DangerZone(
      key: const Key('archive-band'),
      label: 'Archive band',
      consequence:
          'Archiving removes this band from public pages and management, revokes invitations, and cancels future gigs it owns. You cannot restore the band in EarPlug. Historical and shared records remain.',
      onPressed: () => _confirmArchive(context),
    );
  }

  Future<void> _confirmArchive(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ArchiveBandDialog(band: band),
    );
  }
}

class _ArchiveBandDialog extends StatefulWidget {
  const _ArchiveBandDialog({required this.band});

  final Band band;

  @override
  State<_ArchiveBandDialog> createState() => _ArchiveBandDialogState();
}

class _ArchiveBandDialogState extends State<_ArchiveBandDialog> {
  final _controller = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == widget.band.name;
    return AlertDialog(
      title: const Text('ARCHIVE BAND?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This removes the band from public pages and management, revokes invitations, and cancels future gigs it owns. You cannot restore the band in EarPlug. Historical and shared records are preserved.',
          ),
          const SizedBox(height: 14),
          Text('Type ${widget.band.name} to confirm.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('archive-band-confirmation'),
            controller: _controller,
            enabled: !_working,
            onChanged: (_) => setState(() {}),
            decoration: epInputDecoration(widget.band.name),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('KEEP BAND'),
        ),
        FilledButton(
          onPressed: !matches || _working ? null : _archive,
          style: FilledButton.styleFrom(
            backgroundColor: Ep.destructive,
            foregroundColor: Ep.dark,
          ),
          child: Text(_working ? 'ARCHIVING…' : 'ARCHIVE BAND'),
        ),
      ],
    );
  }

  Future<void> _archive() async {
    setState(() => _working = true);
    try {
      await context.read<AppState>().archiveCurrentBand();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Band could not be archived. Please retry.'),
        ),
      );
    }
  }
}
