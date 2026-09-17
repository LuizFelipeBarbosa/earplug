import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../band_identity.dart';
import '../band_media_state.dart';
import '../services/media_picker.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/band_identity_editor.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

/// The pinned create bar's height above the safe area: EpBottomCta's 20/32
/// vertical padding around one large pill, plus its readiness eyebrow.
const double _actionZoneHeight = 20 + 12 + 12 + 52 + 32;

/// Room the list keeps below its last control so it can scroll clear of the
/// pinned create bar (the bar plus a 16pt gap; the safe inset is added
/// separately).
const double _footerClearance = _actionZoneHeight + 16;

class BandCreateScreen extends StatefulWidget {
  const BandCreateScreen({super.key});

  @override
  State<BandCreateScreen> createState() => _BandCreateScreenState();
}

class _BandCreateScreenState extends State<BandCreateScreen> {
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _bio = TextEditingController();
  final _customGenre = TextEditingController();
  final _instagram = TextEditingController();
  final _bandcamp = TextEditingController();
  final _youtube = TextEditingController();

  bool _loaded = false;
  bool _wasCreated = false;
  bool _addingCustomGenre = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final app = context.read<AppState>();
    _syncControllers(app);
    _wasCreated = app.nbCreated;
    _loaded = true;
  }

  void _syncControllers(AppState app) {
    _name.text = app.nbName;
    _area.text = app.nbArea ?? '';
    _bio.text = app.nbBio;
    _instagram.text = app.nbIg;
    _bandcamp.text = app.nbBc;
    _youtube.text = app.nbYt;
  }

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _bio.dispose();
    _customGenre.dispose();
    _instagram.dispose();
    _bandcamp.dispose();
    _youtube.dispose();
    super.dispose();
  }

  /// The picked banner is held on the draft; AppState uploads and assigns it
  /// right after `createBand` succeeds (or on retry from the created view).
  Future<void> _pickBanner() async {
    final app = context.read<AppState>();
    final media = context.read<BandMediaController>();
    final PickedMedia? picked;
    try {
      picked = await media.pickFlyerArt();
    } on MediaPickException catch (error) {
      app.say(error.message);
      return;
    }
    if (!mounted || picked == null) return;
    app.setNbBanner(picked);
  }

  void _showArtworkSheet() {
    final app = context.read<AppState>();
    showEpActionSheet(
      context,
      header: 'Header image',
      items: [
        EpActionSheetItem(
          label: 'Replace',
          icon: Icons.photo_library_outlined,
          onPressed: _pickBanner,
        ),
        if (app.nbBanner != null)
          EpActionSheetItem(
            label: 'Use initials instead',
            icon: Icons.delete_outline,
            destructive: true,
            onPressed: () => app.setNbBanner(null),
          ),
      ],
    );
  }

  void _addCustomGenre() {
    final value = _customGenre.text;
    final app = context.read<AppState>();
    final genre = value.trim().toLowerCase();
    final alreadySelected = app.nbGenres.contains(genre);
    final added = app.addNbGenre(value);
    if (value.trim().isEmpty) return;
    if (!added && !alreadySelected) return;
    _customGenre.clear();
    setState(() => _addingCustomGenre = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_wasCreated && !app.nbCreated && !app.nbEditingCreated) {
      _syncControllers(app);
    }
    _wasCreated = app.nbCreated;
    if (app.nbCreated) return const _CreatedView();

    final saving = app.nbSaving;
    // The public preview needs a band id, so the eye only works once the
    // draft has landed and is being re-edited.
    final canPreview = app.nbEditingCreated;

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              headerTopPad(context),
              EpLayout.gutter,
              _footerClearance + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              EpBackHeading(
                title: 'CREATE BAND',
                backKey: const ValueKey('band-create-back'),
                onBack: app.back,
                trailing: EpIconPill(
                  key: const ValueKey('band-create-preview'),
                  icon: Icons.visibility_outlined,
                  semanticLabel: canPreview
                      ? 'Preview public page'
                      : 'Preview available after creating',
                  onPressed: canPreview ? app.previewPublicProfile : null,
                ),
              ),
              const SizedBox(height: 18),
              BandIdentityHeader(
                showAvatar: false,
                name: app.nbName,
                area: app.nbArea ?? '',
                initials: bandInitialsFor(app.nbName),
                color: context.epColors.accent,
                bannerBytes: app.nbBanner?.bytes,
                bannerBusy: app.nbBannerUploading,
                onBannerTap: saving ? null : _showArtworkSheet,
              ),
              const SizedBox(height: 9),
              EpMonoText(
                'Shown at the top of your public page.',
                color: context.epColors.contentSecondary,
                keepCase: true,
              ),
              const SizedBox(height: 20),
              _IdentityField(
                fieldKey: const ValueKey('create-band-name'),
                label: 'BAND NAME',
                hint: 'Your band name',
                controller: _name,
                enabled: !saving,
                onChanged: app.setNbName,
              ),
              const SizedBox(height: EpLayout.fieldGap),
              _IdentityField(
                fieldKey: const ValueKey('create-home-base'),
                label: 'HOME BASE',
                hint: 'Neighborhood or city',
                controller: _area,
                enabled: !saving,
                onChanged: app.setNbArea,
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
                      key: const ValueKey('create-short-bio-count'),
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                ],
              ),
              Semantics(
                label: 'ABOUT',
                child: TextField(
                  key: const ValueKey('create-about'),
                  controller: _bio,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 160,
                  onChanged: app.setNbBio,
                  style: Theme.of(context).textTheme.epInput,
                  decoration: InputDecoration(
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.epColors.border),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.epColors.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.epColors.accent),
                    ),
                    counterText: '',
                    hintText: 'Tell fans about the band',
                  ),
                ),
              ),
              const SizedBox(height: EpLayout.fieldGap),
              BandGenreEditor(
                genres: app.nbGenres,
                onToggle: app.toggleNbGenre,
                customController: _customGenre,
                addingCustomGenre: _addingCustomGenre,
                onShowCustomGenre: () =>
                    setState(() => _addingCustomGenre = true),
                onAddCustomGenre: _addCustomGenre,
              ),
              FormSection(
                title: 'Links',
                description:
                    'Add the places where fans can listen, watch, and follow.',
                child: Column(
                  children: [
                    EpLabeledField(
                      fieldKey: const ValueKey('create-instagram'),
                      label: 'INSTAGRAM',
                      hint: 'Instagram',
                      controller: _instagram,
                      onChanged: app.setNbIg,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    EpLabeledField(
                      fieldKey: const ValueKey('create-bandcamp'),
                      label: 'BANDCAMP',
                      hint: 'Bandcamp',
                      controller: _bandcamp,
                      onChanged: app.setNbBc,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    EpLabeledField(
                      fieldKey: const ValueKey('create-youtube'),
                      label: 'YOUTUBE OR VIDEO',
                      hint: 'YouTube or video',
                      controller: _youtube,
                      onChanged: app.setNbYt,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // No tab bar renders on this screen, so the bar sits on the
        // viewport's bottom edge and pads the safe inset itself.
        const Positioned(left: 0, right: 0, bottom: 0, child: _CreateBar()),
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

class _CreateBar extends StatelessWidget {
  const _CreateBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = app.bandMissing;
    final live = app.canCreateBand && !app.nbSaving;
    final label = app.nbSaving
        ? (app.nbEditingCreated ? 'Saving…' : 'Creating…')
        : app.nbEditingCreated
        ? 'Save changes'
        : 'Create band';
    return EpBottomCta(
      key: const ValueKey('create-band-submit'),
      hint: missing.isEmpty ? null : 'Still needs ${missing.join(' + ')}',
      child: EpPill(
        label: label,
        variant: EpPillVariant.primary,
        size: EpPillSize.large,
        expand: true,
        onPressed: live ? app.createBand : null,
      ),
    );
  }
}

class _CreatedView extends StatelessWidget {
  const _CreatedView();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profileUrl = publicWebDisplayUrl(app.nbShareSlug);
    return ColoredBox(
      color: context.epColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "YOU'RE LIVE",
                style: Theme.of(
                  context,
                ).textTheme.epSection.copyWith(color: context.epColors.accent),
              ),
              const SizedBox(height: 18),
              BandIdentityHeader(
                name: app.nbName,
                area: app.nbArea ?? '',
                initials: bandInitialsFor(app.nbName),
                color: context.epColors.accent,
                bannerBytes: app.nbBanner?.bytes,
              ),
              if (app.nbBannerUploading || app.nbBannerError != null)
                _UploadRecovery(
                  uploading: app.nbBannerUploading,
                  label: 'HEADER IMAGE',
                  onRetry: app.retryNbBanner,
                ),
              const SizedBox(height: 18),
              Text(
                "You're on the map.",
                style: Theme.of(context).textTheme.epDisplayAt(20),
              ),
              const SizedBox(height: 4),
              Text(
                profileUrl,
                style: Theme.of(
                  context,
                ).textTheme.epCaption.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EpButton('POST A MUSIC CLIP', onTap: app.openBandMedia),
                    const SizedBox(height: 8),
                    EpButton(
                      'PUBLISH A GIG',
                      kind: EpButtonKind.outline,
                      onTap: app.postFirstGig,
                    ),
                    const SizedBox(height: 8),
                    EpButton(
                      'INVITE BAND MEMBERS',
                      kind: EpButtonKind.outline,
                      onTap: app.openInvitationPanel,
                    ),
                    const SizedBox(height: 4),
                    TextAction(
                      'NOT NOW',
                      onTap: app.openCreatedBand,
                      color: context.epColors.contentSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 10,
                children: [
                  TextAction(
                    'KEEP EDITING',
                    onTap: app.editCreatedBand,
                    color: context.epColors.contentSecondary,
                  ),
                  TextAction(
                    'SHARE PROFILE',
                    onTap: () => copyForUser(
                      context,
                      publicWebUrl(app.nbShareSlug),
                      successMessage: 'Link copied: $profileUrl',
                    ),
                    color: context.epColors.contentSecondary,
                  ),
                  TextAction(
                    'START ANOTHER',
                    onTap: app.makeAnotherBand,
                    color: context.epColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadRecovery extends StatelessWidget {
  const _UploadRecovery({
    required this.uploading,
    required this.label,
    required this.onRetry,
  });

  final bool uploading;
  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: uploading
          ? Text(
              'ADDING $label…',
              style: Theme.of(context).textTheme.epChipLabel,
            )
          : TextAction(
              'RETRY $label',
              onTap: onRetry,
              color: context.epColors.accent,
            ),
    );
  }
}
