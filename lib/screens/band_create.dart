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
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _bio = TextEditingController();
  final _customGenre = TextEditingController();
  final _instagram = TextEditingController();
  final _bandcamp = TextEditingController();
  final _youtube = TextEditingController();
  final _credits = TextEditingController();

  bool _loaded = false;
  bool _addingCustomGenre = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final app = context.read<AppState>();
    _name.text = app.nbName;
    _area.text = app.nbArea ?? '';
    _bio.text = app.nbBio;
    _instagram.text = app.nbIg;
    _bandcamp.text = app.nbBc;
    _youtube.text = app.nbYt;
    _credits.text = app.nbCredits;
    _loaded = true;
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
    context.read<AppState>().addNbGenre(value);
    if (value.trim().isEmpty) return;
    _customGenre.clear();
    setState(() => _addingCustomGenre = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.nbCreated) return const _CreatedView();

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              headerTopPad(context),
              16,
              154 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Row(
                children: [
                  CircleIconButton(icon: Icons.close, onTap: app.back),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'CREATE BAND',
                      style: Theme.of(context).textTheme.epPageHeading,
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
              BandIdentityHeader(
                name: app.nbName,
                area: app.nbArea ?? '',
                initials: bandInitialsFor(app.nbName),
                color: Ep.brand,
                avatarBytes: app.nbPhoto?.bytes,
                bannerBytes: app.nbBanner?.bytes,
                onAvatarTap: () => _pickArtwork(_CreateArtworkRole.avatar),
                onBannerTap: () => _pickArtwork(_CreateArtworkRole.banner),
              ),
              const SizedBox(height: 9),
              Text(
                'Profile image and header image are separate. Changing one will not replace the other.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              const SizedBox(height: 20),
              BandIdentityTextField(
                fieldKey: const ValueKey('create-band-name'),
                label: 'BAND NAME',
                hint: 'Your band name',
                controller: _name,
                required: true,
                onChanged: (value) {
                  app.setNbName(value);
                  setState(() {});
                },
              ),
              const SizedBox(height: 14),
              BandIdentityTextField(
                fieldKey: const ValueKey('create-home-base'),
                label: 'HOME BASE',
                hint: 'Neighborhood or city',
                controller: _area,
                required: true,
                onChanged: app.setNbArea,
              ),
              const SizedBox(height: 14),
              BandIdentityTextField(
                fieldKey: const ValueKey('create-about'),
                label: 'ABOUT',
                hint: 'Tell fans about the band',
                controller: _bio,
                minLines: 4,
                maxLines: 7,
                onChanged: app.setNbBio,
              ),
              const SizedBox(height: 14),
              BandGenreEditor(
                genres: app.nbGenres,
                onToggle: app.toggleNbGenre,
                customController: _customGenre,
                addingCustomGenre: _addingCustomGenre,
                onShowCustomGenre: () =>
                    setState(() => _addingCustomGenre = true),
                onAddCustomGenre: _addCustomGenre,
              ),
              const SizedBox(height: 24),
              _OptionalSection(
                title: 'Links',
                description:
                    'Add the places where fans can listen, watch, and follow.',
                boxed: false,
                child: Column(
                  children: [
                    _StandardField(
                      fieldKey: const ValueKey('create-instagram'),
                      label: 'INSTAGRAM',
                      hint: 'Instagram',
                      controller: _instagram,
                      onChanged: app.setNbIg,
                    ),
                    const SizedBox(height: 12),
                    _StandardField(
                      fieldKey: const ValueKey('create-bandcamp'),
                      label: 'BANDCAMP',
                      hint: 'Bandcamp',
                      controller: _bandcamp,
                      onChanged: app.setNbBc,
                    ),
                    const SizedBox(height: 12),
                    _StandardField(
                      fieldKey: const ValueKey('create-youtube'),
                      label: 'YOUTUBE OR VIDEO',
                      hint: 'YouTube or video',
                      controller: _youtube,
                      onChanged: app.setNbYt,
                    ),
                  ],
                ),
              ),
              _OptionalSection(
                title: 'Credits',
                description:
                    'Acknowledge producers, artists, labels, and collaborators.',
                child: _StandardField(
                  fieldKey: const ValueKey('create-credits'),
                  label: 'CREDITS',
                  hint: 'Who helped make the work',
                  controller: _credits,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: app.setNbCredits,
                ),
              ),
              _PostCreateRow(
                icon: Icons.group_outlined,
                label: 'INVITE BAND MEMBERS',
                enabled: app.nbEditingCreated,
                onTap: app.openInvitationPanel,
                disabledMessage:
                    'Create your band first, then invite band members.',
              ),
            ],
          ),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: _CreateBar()),
      ],
    );
  }
}

class _StandardField extends StatelessWidget {
  const _StandardField({
    this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final Key? fieldKey;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      style: Theme.of(context).textTheme.epBody,
      decoration: epInputDecoration(hint).copyWith(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}

class _OptionalSection extends StatelessWidget {
  const _OptionalSection({
    required this.title,
    required this.description,
    required this.child,
    this.boxed = true,
  });

  final String title;
  final String description;
  final Widget child;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: title),
        Text(description, style: Theme.of(context).textTheme.epCaption),
        const SizedBox(height: 12),
        if (boxed)
          EpCard(
            variant: EpCardVariant.raised,
            padding: const EdgeInsets.all(15),
            child: child,
          )
        else
          child,
      ],
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
        color: Ep.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: Ep.border),
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
                  Icon(icon, color: enabled ? Ep.volt : Ep.contentDisabled),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.epLabel.copyWith(
                        color: enabled ? Ep.contentPrimary : Ep.contentDisabled,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Ep.mute),
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
  const _CreateBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = app.bandMissing;
    final live = app.canCreateBand && !app.nbSaving;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        30,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ep.background.withValues(alpha: 0), Ep.background],
          stops: const [0, .34],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            missing.isNotEmpty
                ? 'Still needs ${missing.join(' + ')}'
                : app.nbEditingCreated
                ? 'Your band is live. Save to publish these updates.'
                : 'Ready. Images, about, and links can be added any time.',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              color: missing.isEmpty ? Ep.accent : Ep.contentSecondary,
            ),
          ),
          const SizedBox(height: 9),
          EpButton(
            app.nbSaving
                ? 'SAVING…'
                : app.nbEditingCreated
                ? 'SAVE CHANGES'
                : 'CREATE BAND',
            fontSize: 14,
            kind: live ? EpButtonKind.filled : EpButtonKind.disabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: live ? app.createBand : null,
          ),
        ],
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
      color: Ep.background,
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
                  color: Ep.accent,
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
                  label: 'PROFILE IMAGE',
                  onRetry: app.retryNbPhoto,
                ),
              if (app.nbBannerUploading || app.nbBannerError != null)
                _UploadRecovery(
                  uploading: app.nbBannerUploading,
                  label: 'HEADER IMAGE',
                  onRetry: app.retryNbBanner,
                ),
              const SizedBox(height: 18),
              Text("You're on the map.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(
                profileUrl,
                style: epText(size: 12, color: Ep.contentSecondary),
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
                      color: Ep.contentSecondary,
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
                    color: Ep.contentSecondary,
                  ),
                  TextAction(
                    'SHARE PROFILE',
                    onTap: () => copyForUser(
                      context,
                      publicWebUrl(app.nbShareSlug),
                      successMessage: 'Link copied: $profileUrl',
                    ),
                    color: Ep.contentSecondary,
                  ),
                  TextAction(
                    'START ANOTHER',
                    onTap: app.makeAnotherBand,
                    color: Ep.accent,
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
          : TextAction('RETRY $label', onTap: onRetry, color: Ep.accent),
    );
  }
}
