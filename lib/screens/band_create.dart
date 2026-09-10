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
import '../widgets/form_bits.dart';

enum _CreateArtworkRole { avatar, banner }

class BandCreateScreen extends StatefulWidget {
  const BandCreateScreen({super.key});

  @override
  State<BandCreateScreen> createState() => _BandCreateScreenState();
}

class _BandCreateScreenState extends State<BandCreateScreen> {
  final _form = GlobalKey<EpFormState>();
  String? _validationError;
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _bio = TextEditingController();
  final _customGenre = TextEditingController();
  final _instagram = TextEditingController();
  final _bandcamp = TextEditingController();
  final _youtube = TextEditingController();
  final _credits = TextEditingController();

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
    _credits.text = app.nbCredits;
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
    _credits.dispose();
    super.dispose();
  }

  Future<void> _pickArtwork(_CreateArtworkRole role) async {
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
    if (role == _CreateArtworkRole.avatar) {
      app.setNbPhoto(picked);
    } else {
      app.setNbBanner(picked);
    }
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

  void _create() {
    final valid = _form.currentState?.validate() ?? false;
    final app = context.read<AppState>();
    setState(
      () => _validationError = app.nbGenres.isEmpty
          ? 'Choose at least one genre.'
          : null,
    );
    if (valid && app.canCreateBand) app.createBand();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_wasCreated && !app.nbCreated && !app.nbEditingCreated) {
      _syncControllers(app);
    }
    _wasCreated = app.nbCreated;
    if (app.nbCreated) return const _CreatedView();

    return EpFormLayout(
      body: EpForm(
        key: _form,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleIconButton(icon: Icons.close, onTap: app.back),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Create band',
                      style: Theme.of(context).textTheme.epFormHeading,
                    ),
                  ),
                  ReadyPill(ready: app.canCreateBand),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Build the profile fans will see. You can keep refining it after creation.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              const SizedBox(height: 18),
              EpLabeledField(
                fieldKey: const ValueKey('create-band-name'),
                label: 'Band name',
                hint: 'Your band name',
                controller: _name,
                required: true,
                onChanged: app.setNbName,
              ),
              const SizedBox(height: EpLayout.fieldGap),
              EpLabeledField(
                fieldKey: const ValueKey('create-home-base'),
                label: 'Home base',
                hint: 'Neighborhood or city',
                controller: _area,
                required: true,
                onChanged: app.setNbArea,
              ),
              const SizedBox(height: EpLayout.fieldGap),

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
              EpDisclosure(
                title: 'About',
                summary: _bio.text.isEmpty ? 'Optional biography' : _bio.text,
                child: EpLabeledField(
                  fieldKey: const ValueKey('create-about'),
                  label: 'About',
                  hint: 'Tell fans about the band',
                  controller: _bio,
                  minLines: 4,
                  maxLines: 7,
                  onChanged: app.setNbBio,
                ),
              ),
              EpDisclosure(
                title: 'Images',
                summary: 'Optional profile and header images',
                child: Column(
                  children: [
                    BandIdentityHeader(
                      name: app.nbName,
                      area: app.nbArea ?? '',
                      initials: bandInitialsFor(app.nbName),
                      color: Ep.brand,
                      avatarBytes: app.nbPhoto?.bytes,
                      bannerBytes: app.nbBanner?.bytes,
                      onAvatarTap: () =>
                          _pickArtwork(_CreateArtworkRole.avatar),
                      onBannerTap: () =>
                          _pickArtwork(_CreateArtworkRole.banner),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Profile image and header image are separate. Changing one will not replace the other.',
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                    if (app.nbPhoto != null || app.nbBanner != null) ...[
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (app.nbPhoto != null)
                            TextAction(
                              'REMOVE PHOTO',
                              key: const ValueKey('clear-band-photo'),
                              onTap: () => app.setNbPhoto(null),
                              color: context.epColors.contentSecondary,
                            ),
                          if (app.nbBanner != null)
                            TextAction(
                              'REMOVE HEADER IMAGE',
                              key: const ValueKey('clear-band-banner'),
                              onTap: () => app.setNbBanner(null),
                              color: context.epColors.contentSecondary,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              EpDisclosure(
                title: 'Links',
                summary:
                    [
                      _instagram.text,
                      _bandcamp.text,
                      _youtube.text,
                    ].where((v) => v.isNotEmpty).join(' · ').isEmpty
                    ? 'Optional listening and social links'
                    : 'Links added',
                child: Column(
                  children: [
                    EpLabeledField(
                      fieldKey: const ValueKey('create-instagram'),
                      label: 'Instagram',
                      hint: 'Instagram',
                      controller: _instagram,
                      onChanged: app.setNbIg,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    EpLabeledField(
                      fieldKey: const ValueKey('create-bandcamp'),
                      label: 'Bandcamp',
                      hint: 'Bandcamp',
                      controller: _bandcamp,
                      onChanged: app.setNbBc,
                    ),
                    const SizedBox(height: EpLayout.fieldGap),
                    EpLabeledField(
                      fieldKey: const ValueKey('create-youtube'),
                      label: 'Youtube or video',
                      hint: 'YouTube or video',
                      controller: _youtube,
                      onChanged: app.setNbYt,
                    ),
                  ],
                ),
              ),
              EpDisclosure(
                title: 'Credits',
                summary: _credits.text.isEmpty
                    ? 'Optional collaborators and acknowledgments'
                    : _credits.text,
                child: EpLabeledField(
                  fieldKey: const ValueKey('create-credits'),
                  label: 'Credits',
                  hint: 'Who helped make the work',
                  controller: _credits,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: app.setNbCredits,
                ),
              ),
              if (app.nbEditingCreated)
                _PostCreateRow(
                  icon: Icons.group_outlined,
                  label: 'Invite band members',
                  enabled: app.nbEditingCreated,
                  onTap: app.openInvitationPanel,
                  disabledMessage:
                      'Create your band first, then invite band members.',
                ),
            ],
          ),
        ),
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InlineFormFeedback(
            error: app.nbGenres.isEmpty ? _validationError : null,
          ),
          _CreateBar(onCreate: _create),
        ],
      ),
    );
  }
}

class _PostCreateRow extends StatelessWidget {
  const _PostCreateRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.disabledMessage,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final String disabledMessage;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: context.epColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: context.epColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled ? onTap : () => app.say(disabledMessage),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: enabled
                        ? context.epColors.volt
                        : context.epColors.contentDisabled,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.epLabel.copyWith(
                        color: enabled
                            ? context.epColors.contentPrimary
                            : context.epColors.contentDisabled,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.epColors.mute),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateBar extends StatelessWidget {
  const _CreateBar({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StickyActionBar(
      primaryLabel: app.nbSaving
          ? 'Saving…'
          : app.nbEditingCreated
          ? 'Save changes'
          : 'Create band',
      onPrimary: app.nbSaving ? null : onCreate,
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
                style: epText(
                  size: 10.5,
                  weight: FontWeight.w900,
                  letterSpacing: 2,
                  color: context.epColors.accent,
                ),
              ),
              const SizedBox(height: 18),
              BandIdentityHeader(
                name: app.nbName,
                area: app.nbArea ?? '',
                initials: bandInitialsFor(app.nbName),
                color: Ep.brand,
                avatarBytes: app.nbPhoto?.bytes,
                bannerBytes: app.nbBanner?.bytes,
              ),
              if (app.nbPhotoUploading || app.nbPhotoError != null)
                _UploadRecovery(
                  uploading: app.nbPhotoUploading,
                  label: 'Profile image',
                  onRetry: app.retryNbPhoto,
                ),
              if (app.nbBannerUploading || app.nbBannerError != null)
                _UploadRecovery(
                  uploading: app.nbBannerUploading,
                  label: 'Header image',
                  onRetry: app.retryNbBanner,
                ),
              const SizedBox(height: 18),
              Text("You're on the map.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(
                profileUrl,
                style: epText(
                  size: 12,
                  color: context.epColors.contentSecondary,
                ),
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
              style: epText(size: 11, weight: FontWeight.w800),
            )
          : TextAction(
              'RETRY $label',
              onTap: onRetry,
              color: context.epColors.accent,
            ),
    );
  }
}
