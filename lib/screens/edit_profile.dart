import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/band_identity_editor.dart';
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
  late final TextEditingController _homeLocationController;
  late final FocusNode _homeLocationFocusNode;
  late final MediaPicker _mediaPicker;
  late final Set<String> _genres;
  FanCity? _homeLocation;
  var _locationPersonalizationEnabled = false;
  var _followedBandUpdatesEnabled = true;
  PickedMedia? _pickedAvatar;
  var _removeAvatar = false;
  var _locatingHome = false;
  LocationFailure? _homeLocationFailure;
  String? _homeLocationNotice;
  String? _homeLocationValidation;
  var _updatingHomeLocationText = false;
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
    _homeLocationController = TextEditingController(
      text: _homeLocation?.autocompleteLabel ?? '',
    )..addListener(_homeLocationTextChanged);
    _homeLocationFocusNode = FocusNode()
      ..addListener(_homeLocationFocusChanged);
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
    _homeLocationController
      ..removeListener(_homeLocationTextChanged)
      ..dispose();
    _homeLocationFocusNode
      ..removeListener(_homeLocationFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _homeLocationTextChanged() {
    if (_updatingHomeLocationText || !mounted) return;
    setState(() {
      _homeLocation = fanCityFromLocationInput(_homeLocationController.text);
      _homeLocationFailure = null;
      _homeLocationNotice = null;
      _homeLocationValidation = null;
    });
  }

  void _homeLocationFocusChanged() {
    if (mounted) setState(() {});
  }

  void _setHomeLocation(FanCity? city, {String? notice}) {
    _updatingHomeLocationText = true;
    _homeLocationController.value = TextEditingValue(
      text: city?.autocompleteLabel ?? '',
      selection: TextSelection.collapsed(
        offset: city?.autocompleteLabel.length ?? 0,
      ),
    );
    _updatingHomeLocationText = false;
    setState(() {
      _homeLocation = city;
      _homeLocationFailure = null;
      _homeLocationNotice = notice;
      _homeLocationValidation = null;
    });
  }

  void _selectHomeLocation(FanCity city) {
    _setHomeLocation(city);
    _homeLocationFocusNode.unfocus();
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

  Future<void> _useCurrentLocation() async {
    if (_locatingHome) return;
    setState(() {
      _locatingHome = true;
      _homeLocationFailure = null;
      _homeLocationNotice = null;
    });
    LocationResult result;
    try {
      result = await context
          .read<AppState>()
          .locationService
          .requestCurrentLocation();
    } catch (_) {
      result = const LocationFailure(LocationFailureReason.unavailable);
    }
    if (!mounted) return;
    switch (result) {
      case LocationSuccess(:final location):
        final city = _nearestFanCity(location);
        _setHomeLocation(
          city,
          notice:
              'Using ${city.autocompleteLabel}, the nearest supported scene.',
        );
        setState(() => _locatingHome = false);
      case final LocationFailure failure:
        setState(() {
          _locatingHome = false;
          _homeLocationFailure = failure;
        });
    }
  }

  Future<void> _openLocationRecovery() async {
    final app = context.read<AppState>();
    final recovery = switch (_homeLocationFailure?.reason) {
      LocationFailureReason.servicesDisabled =>
        app.locationService.openLocationSettings(),
      LocationFailureReason.permissionDeniedForever =>
        app.locationService.openAppSettings(),
      _ => null,
    };
    if (recovery != null) await recovery;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Add the name you want shown on your profile.');
      return;
    }
    final locationInput = _homeLocationController.text.trim();
    final resolvedHomeLocation = locationInput.isEmpty
        ? null
        : fanCityFromLocationInput(locationInput);
    if (locationInput.isNotEmpty && resolvedHomeLocation == null) {
      setState(() {
        _homeLocationValidation =
            'Choose a suggested location, or clear this field to keep it undisclosed.';
      });
      _homeLocationFocusNode.requestFocus();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _homeLocation = resolvedHomeLocation;
      _homeLocationValidation = null;
    });
    final app = context.read<AppState>();
    final saved = await app.saveFanProfile(
      name: name,
      bio: switch (_bioController.text.trim()) {
        '' => null,
        final value => value,
      },
      homeLocation: resolvedHomeLocation,
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
              Text(
                'Shape the identity fans see while keeping your scene and preferences private.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: Listenable.merge([_nameController]),
                builder: (context, _) => _FanIdentityPreview(
                  name: _nameController.text,
                  scene: _sceneName(_homeLocation),
                  imageUrl: _removeAvatar ? null : profile?.avatarUrl,
                  picked: _pickedAvatar,
                  onChooseAvatar: _saving ? null : _pickAvatar,
                  onRemoveAvatar:
                      _pickedAvatar != null ||
                          (!_removeAvatar && profile?.avatarUrl != null)
                      ? _saving
                            ? null
                            : () => setState(() {
                                _pickedAvatar = null;
                                _removeAvatar = true;
                              })
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              BandIdentityTextField(
                fieldKey: const Key('fan-name-field'),
                label: 'DISPLAY NAME',
                hint: 'Your name',
                controller: _nameController,
                required: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {},
              ),
              const SizedBox(height: 14),
              _FanSelectionField(
                key: const Key('fan-home-location-field'),
                label: 'HOME LOCATION',
                caption:
                    'Private to your account. Personalization below decides whether this scene tunes discovery.',
                child: _HomeLocationEditor(
                  controller: _homeLocationController,
                  focusNode: _homeLocationFocusNode,
                  enabled: !_saving && !_locatingHome,
                  locating: _locatingHome,
                  selectedLocation: _homeLocation,
                  failure: _homeLocationFailure,
                  notice: _homeLocationNotice,
                  validationMessage: _homeLocationValidation,
                  onSelected: _selectHomeLocation,
                  onUseCurrentLocation: _useCurrentLocation,
                  onClear: () => _setHomeLocation(null),
                  onRetry: _useCurrentLocation,
                  onRecovery: _openLocationRecovery,
                ),
              ),
              const SizedBox(height: 14),
              BandIdentityTextField(
                fieldKey: const Key('fan-bio-field'),
                label: 'ABOUT',
                hint: 'A little about your taste in music',
                controller: _bioController,
                enabled: !_saving,
                minLines: 4,
                maxLines: 6,
                maxLength: 280,
                onChanged: (_) {},
              ),
              const SizedBox(height: 14),
              _FanSelectionField(
                key: const Key('fan-favorite-genres-field'),
                label: 'FAVORITE GENRES · ${_genres.length}',
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final genre in kGenres)
                      EpChip(
                        key: ValueKey('profile-genre-$genre'),
                        label: genre,
                        active: _genres.contains(genre),
                        neutralSelected: true,
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
              ),
              const SectionBar(label: 'Preferences'),
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
                    style: Theme.of(context).textTheme.epBody.copyWith(
                      color: context.epColors.destructive,
                    ),
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

String _sceneName(FanCity? city) =>
    city == null ? 'Scene undisclosed' : '${city.label} scene';

FanCity _nearestFanCity(UserLocation location) {
  var nearest = FanCity.values.first;
  var nearestDistance = double.infinity;
  for (final city in FanCity.values) {
    final distance = distanceInMiles(
      startLatitude: location.latitude,
      startLongitude: location.longitude,
      endLatitude: city.center.latitude,
      endLongitude: city.center.longitude,
    );
    if (distance < nearestDistance) {
      nearest = city;
      nearestDistance = distance;
    }
  }
  return nearest;
}

String _locationFailureMessage(
  LocationFailure failure,
) => switch (failure.reason) {
  LocationFailureReason.servicesDisabled =>
    'Location services are off. Turn them on or choose a place.',
  LocationFailureReason.permissionDenied =>
    'Location access was not granted. Try again or choose a place.',
  LocationFailureReason.permissionDeniedForever =>
    'Location access is blocked. Allow it in app settings or choose a place.',
  LocationFailureReason.unavailable =>
    failure.message ??
        'Your location is unavailable. Try again or choose a place.',
};

class _HomeLocationEditor extends StatelessWidget {
  const _HomeLocationEditor({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.locating,
    required this.selectedLocation,
    required this.failure,
    required this.notice,
    required this.validationMessage,
    required this.onSelected,
    required this.onUseCurrentLocation,
    required this.onClear,
    required this.onRetry,
    required this.onRecovery,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool locating;
  final FanCity? selectedLocation;
  final LocationFailure? failure;
  final String? notice;
  final String? validationMessage;
  final ValueChanged<FanCity> onSelected;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onClear;
  final VoidCallback onRetry;
  final VoidCallback onRecovery;

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim();
    final exactMatch = fanCityFromLocationInput(query);
    final suggestions = focusNode.hasFocus && exactMatch == null
        ? fanCitySuggestions(query).toList(growable: false)
        : const <FanCity>[];
    final hasNoResults =
        focusNode.hasFocus &&
        query.isNotEmpty &&
        exactMatch == null &&
        suggestions.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('home-location-input'),
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.addressCity],
          onSubmitted: (_) => focusNode.unfocus(),
          decoration: InputDecoration(
            hintText: 'Type a city or location',
            hintStyle: Theme.of(context).textTheme.epBody.copyWith(
              color: context.epColors.contentDisabled,
            ),
            prefixIcon: Icon(
              Icons.location_city_outlined,
              color: context.epColors.contentSecondary,
              size: 20,
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    key: const Key('clear-home-location'),
                    tooltip: 'Clear home location',
                    onPressed: enabled ? onClear : null,
                    icon: Icon(Icons.close, size: 18),
                  ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        if (suggestions.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.epColors.border)),
            ),
            child: Column(
              children: [
                for (final city in suggestions)
                  TextButton.icon(
                    key: ValueKey('home-location-suggestion-${city.name}'),
                    onPressed: () => onSelected(city),
                    style: TextButton.styleFrom(
                      foregroundColor: context.epColors.contentPrimary,
                      minimumSize: const Size.fromHeight(48),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: const RoundedRectangleBorder(),
                    ),
                    icon: Icon(Icons.place_outlined, size: 18),
                    label: Text(city.autocompleteLabel),
                  ),
              ],
            ),
          ),
        Divider(color: context.epColors.border, height: 1),
        if (hasNoResults)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'No supported locations match “$query”. Try a city name or City, CA.',
              key: const Key('home-location-no-results'),
              style: Theme.of(context).textTheme.epCaption,
            ),
          ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const Key('use-current-home-location'),
              onPressed: enabled ? onUseCurrentLocation : null,
              style: TextButton.styleFrom(
                foregroundColor: context.epColors.contentPrimary,
                minimumSize: const Size(48, 48),
              ),
              icon: locating
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: context.epColors.contentSecondary,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(Icons.my_location, size: 19),
              label: Text(
                locating ? 'FINDING YOUR LOCATION…' : 'USE CURRENT LOCATION',
              ),
            ),
            if (selectedLocation != null && query.isNotEmpty)
              Text(
                'SELECTED',
                style: Theme.of(context).textTheme.epChipLabel.copyWith(
                  color: context.epColors.contentSecondary,
                ),
              ),
          ],
        ),
        if (notice case final message?)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const Key('home-location-notice'),
              style: Theme.of(context).textTheme.epCaption,
            ),
          ),
        if (validationMessage case final message?)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const Key('home-location-validation'),
              style: Theme.of(context).textTheme.epCaption.copyWith(
                color: context.epColors.destructive,
              ),
            ),
          ),
        if (failure case final locationFailure?) ...[
          Text(
            _locationFailureMessage(locationFailure),
            key: const Key('home-location-error'),
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(color: context.epColors.destructive),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton(
                key: const Key('retry-current-home-location'),
                onPressed: locating ? null : onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: context.epColors.contentPrimary,
                  minimumSize: const Size(48, 48),
                ),
                child: Text('RETRY'),
              ),
              if (locationFailure.reason ==
                      LocationFailureReason.servicesDisabled ||
                  locationFailure.reason ==
                      LocationFailureReason.permissionDeniedForever)
                TextButton(
                  key: const Key('open-home-location-settings'),
                  onPressed: onRecovery,
                  style: TextButton.styleFrom(
                    foregroundColor: context.epColors.contentPrimary,
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(
                    locationFailure.reason ==
                            LocationFailureReason.servicesDisabled
                        ? 'OPEN LOCATION SETTINGS'
                        : 'OPEN APP SETTINGS',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FanIdentityPreview extends StatelessWidget {
  const _FanIdentityPreview({
    required this.name,
    required this.scene,
    required this.imageUrl,
    required this.picked,
    required this.onChooseAvatar,
    required this.onRemoveAvatar,
  });

  final String name;
  final String scene;
  final String? imageUrl;
  final PickedMedia? picked;
  final VoidCallback? onChooseAvatar;
  final VoidCallback? onRemoveAvatar;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'Your display name' : name.trim();
    return Container(
      key: const Key('fan-identity-preview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.epColors.surfaceRaised,
        border: Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IDENTITY PREVIEW',
            style: Theme.of(context).textTheme.epChipLabel.copyWith(
              color: context.epColors.contentSecondary,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                button: true,
                enabled: onChooseAvatar != null,
                label: 'Change profile image',
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('fan-avatar-preview-control'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: onChooseAvatar,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      child: _AvatarPreview(
                        name: name,
                        imageUrl: imageUrl,
                        picked: picked,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      key: const Key('fan-preview-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epDisplay.copyWith(
                        color: context.epColors.contentPrimary,
                        fontSize: 25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      scene.toUpperCase(),
                      key: const Key('fan-preview-scene'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epBody.copyWith(
                        color: context.epColors.contentSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextAction(
                      'CHANGE PROFILE IMAGE',
                      key: const Key('choose-fan-avatar'),
                      color: context.epColors.contentPrimary,
                      padding: EdgeInsets.zero,
                      onTap: onChooseAvatar,
                    ),
                    if (onRemoveAvatar != null)
                      TextAction(
                        'REMOVE PHOTO',
                        key: const Key('remove-fan-avatar'),
                        color: context.epColors.destructive,
                        padding: EdgeInsets.zero,
                        onTap: onRemoveAvatar,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanSelectionField extends StatelessWidget {
  const _FanSelectionField({
    super.key,
    required this.label,
    required this.child,
    this.caption,
  });

  final String label;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.epColors.surface,
        border: Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.epChipLabel.copyWith(
              color: context.epColors.contentSecondary,
              letterSpacing: 1.1,
            ),
          ),
          if (caption case final caption?) ...[
            const SizedBox(height: 5),
            Text(caption, style: Theme.of(context).textTheme.epCaption),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
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
    final cacheSize = (88 * MediaQuery.devicePixelRatioOf(context)).round();
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
                cacheWidth: cacheSize,
                cacheHeight: cacheSize,
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
                color: context.epColors.volt,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.epColors.background,
                  width: 3,
                ),
              ),
              child: Icon(Icons.edit, size: 14, color: context.epColors.dark),
            ),
          ),
        ),
      ],
    );
  }
}
