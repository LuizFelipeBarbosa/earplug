import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/band_identity_editor.dart';
import '../widgets/brand_icons.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/genre_autocomplete_field.dart';
import '../widgets/sheets.dart';

class BandEditScreen extends StatefulWidget {
  const BandEditScreen({super.key});

  @override
  State<BandEditScreen> createState() => _BandEditScreenState();
}

class _BandEditScreenState extends State<BandEditScreen> {
  final _scrollController = ScrollController();
  final _requiredKey = GlobalKey();
  final _linksKey = GlobalKey();

  final _name = TextEditingController();
  final _area = TextEditingController();
  final _bio = TextEditingController();
  final _instagram = TextEditingController();
  final _bandcamp = TextEditingController();
  final _youtube = TextEditingController();
  final _credits = TextEditingController();

  String? _loadedBandId;
  String? _lastSection;
  List<String> _genres = [];
  bool _detailsApplied = false;
  bool _instagramDirty = false;
  bool _bandcampDirty = false;
  bool _youtubeDirty = false;
  bool _saving = false;
  bool _saved = false;
  bool _bannerUploading = false;
  PickedMedia? _bannerPreview;
  String? _artworkError;
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
      _credits.text = details.credits ?? band!.credits ?? '';
      _detailsApplied = true;
    }

    final section = app.current.param;
    if (section != null && section != _lastSection) {
      _lastSection = section;
      final key = switch (section) {
        'required' => _requiredKey,
        'links' => _linksKey,
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
    super.dispose();
  }

  void _draftChanged([String? _]) {
    if (!_saved && _error == null) return;
    setState(() {
      _saved = false;
      _error = null;
    });
  }

  Future<void> _changeArtwork() async {
    final app = context.read<AppState>();
    final media = context.read<BandMediaController>();
    final band = app.myBand;
    if (band == null || !app.isAdminOf(band.id)) return;

    final PickedMedia? picked;
    try {
      picked = await media.pickFlyerArt();
    } on MediaPickException catch (error) {
      app.say(error.message);
      return;
    }
    if (!mounted || picked == null) return;

    setState(() {
      _artworkError = null;
      _bannerPreview = picked;
      _bannerUploading = true;
    });

    final mediaId = await media.uploadHeldPhoto(band.id, picked);
    final assigned = mediaId != null && await media.setBanner(band.id, mediaId);
    if (!mounted) return;
    setState(() {
      _bannerUploading = false;
      if (!assigned) _bannerPreview = null;
      if (!assigned) {
        _artworkError =
            'The header image could not be saved. Choose it again here; the failed upload remains available in Media.';
      }
    });
  }

  void _showArtworkSheet() {
    final app = context.read<AppState>();
    final band = app.myBand;
    if (band == null || !app.isAdminOf(band.id)) return;

    final hasArtwork = band.headerImageUrl != null || _bannerPreview != null;
    showEpActionSheet(
      context,
      header: 'Header image',
      items: [
        EpActionSheetItem(
          label: 'Replace',
          icon: Icons.photo_library_outlined,
          onPressed: _changeArtwork,
        ),
        if (hasArtwork)
          EpActionSheetItem(
            label: 'Use initials instead',
            icon: Icons.delete_outline,
            destructive: true,
            onPressed: _clearArtwork,
          ),
      ],
    );
  }

  Future<void> _clearArtwork() async {
    final app = context.read<AppState>();
    final media = context.read<BandMediaController>();
    final band = app.myBand;
    if (band == null || !app.isAdminOf(band.id)) return;

    setState(() {
      _artworkError = null;
      _bannerUploading = true;
    });

    final cleared = await media.clearBanner(band.id);
    if (!mounted) return;
    setState(() {
      _bannerUploading = false;
      if (cleared) _bannerPreview = null;
      if (!cleared) {
        _artworkError = 'The header image could not be removed. Try again.';
      }
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
      revealFormFeedback(this, _scrollController);
      return;
    }
    if (_genres.length > 3) {
      setState(() => _error = 'Choose no more than three genres.');
      revealFormFeedback(this, _scrollController);
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
      revealFormFeedback(this, _scrollController);
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Changes could not be saved. Check your connection and retry.';
      });
      revealFormFeedback(this, _scrollController);
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

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              headerTopPad(context),
              16,
              tabBarClearance + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Row(
                children: [
                  EpIconPill(
                    key: const ValueKey('band-edit-back'),
                    icon: Icons.arrow_back,
                    semanticLabel: 'Back',
                    onPressed: app.back,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'EDIT BAND',
                      style: Theme.of(context).textTheme.epPageHeading,
                    ),
                  ),
                  EpIconPill(
                    key: const ValueKey('band-edit-preview'),
                    icon: Icons.visibility_outlined,
                    semanticLabel: 'Preview public page',
                    onPressed: app.previewPublicProfile,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: EpPill(
                      key: const ValueKey('save-band-profile'),
                      label: _saving ? 'Saving…' : 'Save',
                      variant: EpPillVariant.primary,
                      size: EpPillSize.chip,
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              KeyedSubtree(
                key: _requiredKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([_name, _area]),
                      builder: (context, _) => BandIdentityHeader(
                        showAvatar: false,
                        name: _name.text,
                        area: _area.text,
                        initials: band.initials,
                        color: band.color,
                        bannerUrl: band.headerImageUrl,
                        bannerBytes: _bannerPreview?.bytes,
                        bannerBusy: _bannerUploading,
                        onBannerTap: _saving ? null : _showArtworkSheet,
                      ),
                    ),
                    const SizedBox(height: 9),
                    EpMonoText(
                      'Shown at the top of your public page.',
                      color: context.epColors.contentSecondary,
                      keepCase: true,
                    ),
                    if (_artworkError case final error?) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: const ValueKey('band-artwork-error'),
                          style: Theme.of(context).textTheme.epCaption.copyWith(
                            fontSize: 11,
                            color: context.epColors.destructive,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _IdentityField(
                      fieldKey: const ValueKey('edit-band-name'),
                      label: 'BAND NAME',
                      hint: 'Your band name',
                      controller: _name,
                      enabled: !_saving,
                      onChanged: _draftChanged,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    _IdentityField(
                      fieldKey: const ValueKey('edit-home-base'),
                      label: 'HOME BASE',
                      hint: 'Neighborhood or city',
                      controller: _area,
                      enabled: !_saving,
                      onChanged: _draftChanged,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    Row(
                      children: [
                        const Expanded(
                          child: ExcludeSemantics(child: FieldLabel('ABOUT')),
                        ),
                        ListenableBuilder(
                          listenable: _bio,
                          builder: (context, _) => EpMonoText(
                            '${_bio.text.length} / 160',
                            key: const ValueKey('edit-short-bio-count'),
                            color: context.epColors.contentSecondary,
                          ),
                        ),
                      ],
                    ),
                    Semantics(
                      label: 'ABOUT',
                      child: TextField(
                        key: const ValueKey('edit-short-bio'),
                        controller: _bio,
                        enabled: !_saving,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 160,
                        onChanged: _draftChanged,
                        style: Theme.of(context).textTheme.epInput,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.epColors.border,
                            ),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.epColors.border,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.epColors.accent,
                            ),
                          ),
                          counterText: '',
                          hintText: 'Tell fans about the band',
                        ),
                      ),
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    IgnorePointer(
                      ignoring: _saving,
                      child: ExcludeFocus(
                        excluding: _saving,
                        child: GenreAutocompleteField(
                          selected: _genres,
                          onChanged: (value) => setState(() {
                            _genres = value;
                            _saved = false;
                            _error = null;
                          }),
                          keyPrefix: 'edit-genres',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: EpLayout.formSectionGap),
              KeyedSubtree(
                key: _linksKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('LINKS'),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(EpLayout.cardRadius),
                      clipBehavior: Clip.antiAlias,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.epColors.surface,
                          border: Border.all(color: context.epColors.border),
                          borderRadius: BorderRadius.circular(
                            EpLayout.cardRadius,
                          ),
                        ),
                        child: Column(
                          children: [
                            _LinkField(
                              fieldKey: const ValueKey('edit-instagram'),
                              glyph: BrandGlyph.instagram,
                              hint: 'Instagram',
                              controller: _instagram,
                              enabled: !_saving,
                              onChanged: (value) {
                                _instagramDirty = true;
                                _draftChanged(value);
                              },
                            ),
                            const EpHairline(),
                            _LinkField(
                              fieldKey: const ValueKey('edit-bandcamp'),
                              glyph: BrandGlyph.bandcamp,
                              hint: 'Bandcamp',
                              controller: _bandcamp,
                              enabled: !_saving,
                              onChanged: (value) {
                                _bandcampDirty = true;
                                _draftChanged(value);
                              },
                            ),
                            const EpHairline(),
                            _LinkField(
                              fieldKey: const ValueKey('edit-youtube'),
                              glyph: BrandGlyph.youtube,
                              hint: 'YouTube',
                              controller: _youtube,
                              enabled: !_saving,
                              onChanged: (value) {
                                _youtubeDirty = true;
                                _draftChanged(value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null || _saved) ...[
                const SizedBox(height: 16),
                InlineFormFeedback(
                  error: _error,
                  success: _saved ? 'Changes saved.' : null,
                  errorKey: const ValueKey('profile-save-error'),
                  successKey: const ValueKey('profile-save-success'),
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  height: 44,
                  child: TextButton(
                    key: const Key('archive-band'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.epColors.destructive,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ArchiveBandDialog(band: band),
                    ),
                    child: const Text('Archive band'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdentityField extends StatelessWidget {
  const _IdentityField({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: FieldLabel(label, required: true)),
        const SizedBox(height: 8),
        // EpUnderlineField uses ink for its idle rule. Scope the quieter rule
        // to this field; its input text keeps the surrounding text theme.
        Theme(
          data: theme.copyWith(
            extensions: [
              ...theme.extensions.values.where((value) => value is! EpPalette),
              context.epColors.copyWith(
                contentPrimary: context.epColors.border,
              ),
            ],
          ),
          child: IgnorePointer(
            ignoring: !enabled,
            child: ExcludeFocus(
              excluding: !enabled,
              child: Semantics(
                label: '$label · REQUIRED',
                child: EpUnderlineField(
                  fieldKey: fieldKey,
                  controller: controller,
                  hint: hint,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkField extends StatelessWidget {
  const _LinkField({
    required this.fieldKey,
    required this.glyph,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final BrandGlyph glyph;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Row(
      children: [
        BrandIcon(glyph: glyph, color: context.epColors.contentSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            onChanged: onChanged,
            keyboardType: TextInputType.url,
            style: Theme.of(context).textTheme.epInput,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Theme.of(
                context,
              ).textTheme.epInput.copyWith(color: context.epColors.muted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    ),
  );
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
      title: Text('ARCHIVE BAND?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This removes the band from public pages and management, revokes invitations, and cancels future gigs it owns. You cannot restore the band in EarPlug. Historical and shared records are preserved.',
          ),
          const SizedBox(height: EpLayout.fieldGap),
          Text('Type ${widget.band.name} to confirm.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('archive-band-confirmation'),
            controller: _controller,
            enabled: !_working,
            onChanged: (_) => setState(() {}),
            decoration: epInputDecoration(context, widget.band.name),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text('KEEP BAND'),
        ),
        FilledButton(
          onPressed: !matches || _working ? null : _archive,
          style: FilledButton.styleFrom(
            backgroundColor: context.epColors.destructive,
            foregroundColor: context.epColors.dark,
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
