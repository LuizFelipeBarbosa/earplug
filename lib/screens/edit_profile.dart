import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.mediaPicker});

  final MediaPicker? mediaPicker;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final MediaPicker _mediaPicker;
  late final Set<String> _genres;
  FanCity? _homeLocation;
  var _locationPersonalizationEnabled = false;
  var _followedBandUpdatesEnabled = true;
  PickedMedia? _pickedAvatar;
  var _removeAvatar = false;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AppState>().profile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _bioController = TextEditingController(text: profile?.bio ?? '');
    _genres = Set.of(profile?.genres ?? const []);
    _homeLocation = profile?.homeLocation;
    _locationPersonalizationEnabled =
        profile?.locationPersonalizationEnabled ?? false;
    _followedBandUpdatesEnabled = profile?.followedBandUpdatesEnabled ?? true;
    _mediaPicker = widget.mediaPicker ?? MediaPicker();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _mediaPicker.pickPhoto();
      if (picked == null || !mounted) return;
      setState(() {
        _pickedAvatar = picked;
        _removeAvatar = false;
        _error = null;
      });
    } on MediaPickException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't open that photo. Try another one.");
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Add the name you want shown on your profile.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final saved = await app.saveFanProfile(
      name: name,
      bio: switch (_bioController.text.trim()) {
        '' => null,
        final value => value,
      },
      homeLocation: _homeLocation,
      genres: _genres.toList()..sort(),
      locationPersonalizationEnabled: _locationPersonalizationEnabled,
      followedBandUpdatesEnabled: _followedBandUpdatesEnabled,
    );
    if (!mounted) return;

    var avatarSaved = true;
    if (saved) {
      if (_pickedAvatar case final avatar?) {
        avatarSaved = await app.updateFanAvatar(avatar);
      } else if (_removeAvatar) {
        avatarSaved = await app.clearFanAvatar();
      }
    }
    if (!mounted) return;
    if (!saved || !avatarSaved) {
      setState(() {
        _saving = false;
        _error = !saved
            ? "Couldn't save your profile. Your changes are still here."
            : "Your details saved, but the photo didn't. Try saving again.";
      });
      return;
    }
    app.back();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profile = app.profile;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 32),
      children: [
        Row(
          children: [
            CircleIconButton(
              onTap: _saving ? null : app.back,
              tooltip: 'Back to profile',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'EDIT PROFILE',
                style: Theme.of(context).textTheme.epPageHeading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              _AvatarPreview(
                name: _nameController.text,
                imageUrl: _removeAvatar ? null : profile?.avatarUrl,
                picked: _pickedAvatar,
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextAction(
                    'CHOOSE PHOTO',
                    key: const Key('choose-fan-avatar'),
                    onTap: _saving ? null : _pickAvatar,
                  ),
                  if (_pickedAvatar != null ||
                      (!_removeAvatar && profile?.avatarUrl != null))
                    TextAction(
                      'REMOVE',
                      key: const Key('remove-fan-avatar'),
                      color: Ep.destructive,
                      onTap: _saving
                          ? null
                          : () => setState(() {
                              _pickedAvatar = null;
                              _removeAvatar = true;
                            }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Name',
          textField: true,
          child: TextField(
            key: const Key('fan-name-field'),
            controller: _nameController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: epInputDecoration('Your name'),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('HOME LOCATION'),
        const SizedBox(height: 4),
        Text(
          'Private to your account. You decide whether it tunes discovery.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            EpChip(
              key: const Key('profile-home-sf'),
              label: 'SAN FRANCISCO',
              active: _homeLocation == FanCity.sf,
              onTap: _saving
                  ? null
                  : () => setState(() => _homeLocation = FanCity.sf),
            ),
            EpChip(
              key: const Key('profile-home-oak'),
              label: 'OAKLAND',
              active: _homeLocation == FanCity.oak,
              onTap: _saving
                  ? null
                  : () => setState(() => _homeLocation = FanCity.oak),
            ),
            EpChip(
              key: const Key('profile-home-undisclosed'),
              label: 'UNDISCLOSED',
              active: _homeLocation == null,
              onTap: _saving
                  ? null
                  : () => setState(() => _homeLocation = null),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionLabel('FAVORITE GENRES'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final genre in kGenres)
              EpChip(
                key: ValueKey('profile-genre-$genre'),
                label: genre,
                active: _genres.contains(genre),
                onTap: _saving
                    ? null
                    : () => setState(() {
                        _genres.contains(genre)
                            ? _genres.remove(genre)
                            : _genres.add(genre);
                      }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          label: 'Bio, optional',
          textField: true,
          child: TextField(
            key: const Key('fan-bio-field'),
            controller: _bioController,
            enabled: !_saving,
            minLines: 3,
            maxLines: 5,
            maxLength: 280,
            decoration: epInputDecoration(
              'A little about your taste in music (optional)',
            ),
          ),
        ),
        const SizedBox(height: 8),
        const SectionLabel('PRIVACY & UPDATES'),
        const SizedBox(height: 6),
        _PreferenceSwitch(
          key: const Key('location-personalization'),
          title: 'PERSONALIZE WITH HOME LOCATION',
          subtitle: 'Use your selected scene to tune show discovery.',
          value: _locationPersonalizationEnabled,
          onChanged: _saving
              ? null
              : (value) =>
                    setState(() => _locationPersonalizationEnabled = value),
        ),
        const SizedBox(height: 8),
        _PreferenceSwitch(
          key: const Key('followed-band-updates'),
          title: 'SHOW FOLLOWED-BAND UPDATES',
          subtitle: 'Include upcoming shows from bands you follow.',
          value: _followedBandUpdatesEnabled,
          onChanged: _saving
              ? null
              : (value) => setState(() => _followedBandUpdatesEnabled = value),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: const Key('edit-profile-error'),
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: Ep.destructive),
            ),
          ),
        ],
        const SizedBox(height: 18),
        EpButton(
          _saving ? 'SAVING…' : 'SAVE PROFILE',
          key: const Key('save-fan-profile'),
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.name,
    required this.imageUrl,
    required this.picked,
  });

  final String name;
  final String? imageUrl;
  final PickedMedia? picked;

  @override
  Widget build(BuildContext context) {
    final photo = picked;
    if (photo == null) {
      return EpFanAvatar(name: name, imageUrl: imageUrl, size: 88, radius: 24);
    }
    return Semantics(
      image: true,
      label: 'Selected profile photo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.memory(
          photo.bytes,
          key: const Key('picked-fan-avatar-preview'),
          width: 88,
          height: 88,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        title: Text(title, style: Theme.of(context).textTheme.epLabel),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.epCaption),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
