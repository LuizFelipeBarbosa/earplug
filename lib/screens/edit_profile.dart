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
  final _scrollController = ScrollController();
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
    _scrollController.dispose();
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
      _revealFeedback();
      return;
    }
    app.back();
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
    final profile = app.profile;
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              headerTopPad(context),
              16,
              112 + MediaQuery.paddingOf(context).bottom,
            ),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  _AvatarPreview(
                    name: _nameController.text,
                    imageUrl: _removeAvatar ? null : profile?.avatarUrl,
                    picked: _pickedAvatar,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextAction(
                          'CHOOSE PHOTO',
                          key: const Key('choose-fan-avatar'),
                          padding: EdgeInsets.zero,
                          onTap: _saving ? null : _pickAvatar,
                        ),
                        if (_pickedAvatar != null ||
                            (!_removeAvatar && profile?.avatarUrl != null))
                          TextAction(
                            'REMOVE',
                            key: const Key('remove-fan-avatar'),
                            color: Ep.destructive,
                            padding: EdgeInsets.zero,
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                    _pickedAvatar = null;
                                    _removeAvatar = true;
                                  }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Name',
                textField: true,
                child: TextField(
                  key: const Key('fan-name-field'),
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: _labelledInput('YOUR NAME', 'Your name'),
                ),
              ),
              const SectionBar(label: 'Home location'),
              Text(
                'Private to your account. Turn on personalization below if you want this scene to tune discovery.',
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
              SectionBar(label: 'Favorite genres', count: _genres.length),
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
              const SizedBox(height: 20),
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
                  decoration: _labelledInput(
                    'ABOUT YOU · OPTIONAL',
                    'A little about your taste in music',
                  ),
                ),
              ),
              const SectionBar(label: 'Privacy & updates'),
              SwitchRow(
                key: const Key('location-personalization'),
                label: 'Personalize with home location',
                caption:
                    'Uses your selected scene to tune show discovery. Your location stays private.',
                value: _locationPersonalizationEnabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _locationPersonalizationEnabled = value,
                      ),
              ),
              const SizedBox(height: 12),
              SwitchRow(
                key: const Key('followed-band-updates'),
                label: 'Show followed-band updates',
                caption:
                    'Includes upcoming shows from bands you follow on your profile.',
                value: _followedBandUpdatesEnabled,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _followedBandUpdatesEnabled = value),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 14),
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
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StickyActionBar(
            key: const Key('save-fan-profile'),
            primaryLabel: _saving ? 'SAVING…' : 'SAVE CHANGES',
            onPrimary: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

InputDecoration _labelledInput(String label, String hint) =>
    epInputDecoration(hint).copyWith(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );

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
    final avatar = photo == null
        ? EpFanAvatar(name: name, imageUrl: imageUrl, size: 88, radius: 24)
        : Semantics(
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -4,
          bottom: -4,
          child: ExcludeSemantics(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Ep.volt,
                shape: BoxShape.circle,
                border: Border.all(color: Ep.background, width: 3),
              ),
              child: const Icon(Icons.edit, size: 14, color: Ep.dark),
            ),
          ),
        ),
      ],
    );
  }
}
