import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.mediaPicker});

  final MediaPicker? mediaPicker;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _scrollController = ScrollController();
  late final TextEditingController _nameController;
  late final TextEditingController _homeLocationController;
  late final FocusNode _homeLocationFocusNode;
  late final MediaPicker _mediaPicker;
  FanCity? _homeLocation;
  var _locationPersonalizationEnabled = false;
  var _followedBandUpdatesEnabled = true;
  var _shareRsvpsWithFriends = true;
  PickedMedia? _pickedAvatar;
  var _removeAvatar = false;
  var _locatingHome = false;
  LocationFailure? _homeLocationFailure;
  String? _homeLocationNotice;
  String? _homeLocationValidation;
  String? _nameValidation;
  var _updatingHomeLocationText = false;
  var _saving = false;
  String? _error;

  // Snapshot of the persisted profile, used to detect unsaved edits.
  String _initialName = '';
  FanCity? _initialHomeLocation;
  var _initialLocationPersonalization = false;
  var _initialFollowedBandUpdates = true;
  var _initialShareRsvpsWithFriends = true;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AppState>().profile;
    _initialName = profile?.name ?? '';
    _initialHomeLocation = profile?.homeLocation;
    _initialLocationPersonalization =
        profile?.locationPersonalizationEnabled ?? false;
    _initialFollowedBandUpdates = profile?.followedBandUpdatesEnabled ?? true;
    _initialShareRsvpsWithFriends = profile?.shareRsvpsWithFriends ?? true;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _homeLocation = profile?.homeLocation;
    _homeLocationController = TextEditingController(
      text: _homeLocation?.autocompleteLabel ?? '',
    )..addListener(_homeLocationTextChanged);
    _homeLocationFocusNode = FocusNode()
      ..addListener(_homeLocationFocusChanged);
    _locationPersonalizationEnabled =
        profile?.locationPersonalizationEnabled ?? false;
    _followedBandUpdatesEnabled = profile?.followedBandUpdatesEnabled ?? true;
    _shareRsvpsWithFriends = profile?.shareRsvpsWithFriends ?? true;
    _mediaPicker = widget.mediaPicker ?? MediaPicker();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
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

  bool get _isDirty =>
      _nameController.text.trim() != _initialName.trim() ||
      _homeLocation != _initialHomeLocation ||
      _locationPersonalizationEnabled != _initialLocationPersonalization ||
      _followedBandUpdatesEnabled != _initialFollowedBandUpdates ||
      _shareRsvpsWithFriends != _initialShareRsvpsWithFriends ||
      _pickedAvatar != null ||
      _removeAvatar;

  Future<void> _openAvatarOptions() async {
    final profile = context.read<AppState>().profile;
    final hasPhoto =
        _pickedAvatar != null || (!_removeAvatar && profile?.avatarUrl != null);
    await showEpActionSheet(
      context,
      header: 'Profile photo',
      items: [
        EpActionSheetItem(
          label: 'Change photo',
          icon: Icons.photo_library_outlined,
          onPressed: _pickAvatar,
        ),
        if (hasPhoto)
          EpActionSheetItem(
            label: 'Remove photo',
            icon: Icons.delete_outline,
            destructive: true,
            onPressed: () => setState(() {
              _pickedAvatar = null;
              _removeAvatar = true;
            }),
          ),
      ],
    );
  }

  Future<void> _attemptClose() async {
    if (_saving) return;
    final app = context.read<AppState>();
    if (!_isDirty) {
      app.back();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('discard-profile-dialog'),
        title: Text('DISCARD CHANGES?'),
        content: Text(
          'You have unsaved profile edits. Leaving now will lose them.',
          style: Theme.of(dialogContext).textTheme.epBody,
        ),
        actions: [
          TextButton(
            key: const Key('keep-editing-profile'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('KEEP EDITING'),
          ),
          FilledButton(
            key: const Key('discard-profile-changes'),
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(
                dialogContext.epColors.destructive,
              ),
              foregroundColor: WidgetStatePropertyAll(
                dialogContext.epColors.onAccent,
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('DISCARD'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) app.back();
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
      setState(
        () => _nameValidation = 'Add the name you want shown on your profile.',
      );
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          ),
        );
      }
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
    final profile = app.profile;
    final saved = await app.saveFanProfile(
      name: name,
      bio: profile?.bio,
      homeLocation: resolvedHomeLocation,
      genres: profile?.genres ?? const [],
      locationPersonalizationEnabled: _locationPersonalizationEnabled,
      followedBandUpdatesEnabled: _followedBandUpdatesEnabled,
      shareRsvpsWithFriends: _shareRsvpsWithFriends,
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
      revealFormFeedback(this, _scrollController);
      return;
    }
    app.back();
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
              EpLayout.gutter,
              EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
              EpLayout.gutter,
              actionBarClearance(context) +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Row(
                key: const ValueKey('edit-profile-header-row'),
                children: [
                  CircleIconButton(
                    key: const ValueKey('edit-profile-back-control'),
                    onTap: _saving ? null : _attemptClose,
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
              const SizedBox(height: EpLayout.fieldGap),
              ListenableBuilder(
                listenable: _nameController,
                builder: (context, _) => _FanIdentityPreview(
                  name: _nameController.text,
                  homeLocation: _homeLocation,
                  createdAt: profile?.createdAt,
                  imageUrl: _removeAvatar ? null : profile?.avatarUrl,
                  picked: _pickedAvatar,
                  onEditAvatar: _saving ? null : _openAvatarOptions,
                ),
              ),
              const EpSectionHeader(
                key: Key('fan-name-header'),
                label: 'Display name · Required',
                padding: EdgeInsets.only(
                  top: EpLayout.formSectionGap,
                  bottom: EpLayout.fieldGap,
                ),
              ),
              EpLabeledField(
                fieldKey: const Key('fan-name-field'),
                label: 'DISPLAY NAME',
                showLabel: false,
                hint: 'Your name',
                controller: _nameController,
                required: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_nameValidation != null) {
                    setState(() => _nameValidation = null);
                  }
                },
              ),
              if (_nameValidation case final nameError?) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    nameError,
                    key: const Key('fan-name-validation'),
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      color: context.epColors.destructive,
                    ),
                  ),
                ),
              ],
              const EpSectionHeader(
                key: Key('fan-home-location-header'),
                label: 'Home location',
                padding: EdgeInsets.only(
                  top: EpLayout.formSectionGap,
                  bottom: EpLayout.fieldGap,
                ),
              ),
              Column(
                key: const Key('fan-home-location-field'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Private to your account. Personalization below decides whether this scene tunes discovery.',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                  const SizedBox(height: 10),
                  _HomeLocationEditor(
                    controller: _homeLocationController,
                    focusNode: _homeLocationFocusNode,
                    enabled: !_saving && !_locatingHome,
                    locating: _locatingHome,
                    failure: _homeLocationFailure,
                    notice: _homeLocationNotice,
                    validationMessage: _homeLocationValidation,
                    onSelected: _selectHomeLocation,
                    onUseCurrentLocation: _useCurrentLocation,
                    onClear: () => _setHomeLocation(null),
                    onRetry: _useCurrentLocation,
                    onRecovery: _openLocationRecovery,
                  ),
                ],
              ),
              const EpSectionHeader.form(label: 'Preferences'),
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
              const SizedBox(height: 12),
              SwitchRow(
                key: const Key('edit-profile-share-rsvps'),
                label: 'Share my RSVPs with friends',
                caption: "Friends see the shows you're going to.",
                value: _shareRsvpsWithFriends,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _shareRsvpsWithFriends = value),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: EpLayout.fieldGap),
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
    final suggestions = exactMatch == null
        ? fanCitySuggestions(query).toList(growable: false)
        : const <FanCity>[];
    final hasNoResults =
        focusNode.hasFocus &&
        query.isNotEmpty &&
        exactMatch == null &&
        suggestions.isEmpty;

    final locationActionStyle = TextButton.styleFrom(
      foregroundColor: context.epColors.contentSecondary,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: const RoundedRectangleBorder(),
      textStyle: Theme.of(context).textTheme.epChipLabel,
    );

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
          decoration: epInputDecoration(context, 'City or neighbourhood')
              .copyWith(
                prefixIcon: Icon(
                  Icons.location_on_outlined,
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
              ),
        ),
        if (suggestions.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.epColors.border)),
            ),
            child: Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
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
          ),
        if (hasNoResults)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'No supported locations match “$query”. Try a city name or City, CA.',
              key: const Key('home-location-no-results'),
              style: Theme.of(context).textTheme.epCaption,
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('use-current-home-location'),
            onPressed: enabled ? onUseCurrentLocation : null,
            style: locationActionStyle,
            child: Text(
              locating ? 'FINDING YOUR LOCATION…' : 'USE CURRENT LOCATION',
              textAlign: TextAlign.right,
            ),
          ),
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
                style: locationActionStyle,
                child: Text('RETRY'),
              ),
              if (locationFailure.reason ==
                      LocationFailureReason.servicesDisabled ||
                  locationFailure.reason ==
                      LocationFailureReason.permissionDeniedForever)
                TextButton(
                  key: const Key('open-home-location-settings'),
                  onPressed: onRecovery,
                  style: locationActionStyle,
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
    required this.homeLocation,
    required this.createdAt,
    required this.imageUrl,
    required this.picked,
    required this.onEditAvatar,
  });

  final String name;
  final FanCity? homeLocation;
  final DateTime? createdAt;
  final String? imageUrl;
  final PickedMedia? picked;
  final VoidCallback? onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'Your profile' : name;
    return Container(
      key: const Key('fan-identity-preview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.epColors.surfaceRaised,
        border: Border.all(color: context.epColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE PREVIEW',
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
                enabled: onEditAvatar != null,
                label: 'Edit profile photo',
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('fan-avatar-preview-control'),
                    onTap: onEditAvatar,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      child: _AvatarPreview(
                        name: name,
                        imageUrl: imageUrl,
                        picked: picked,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FanIdentityLines(
                  name: displayName,
                  homeLocation: homeLocation,
                  createdAt: createdAt,
                  nameKey: const Key('fan-preview-name'),
                  sceneKey: const Key('fan-preview-scene'),
                  sinceKey: const Key('fan-preview-since'),
                  showUnknownScene: true,
                ),
              ),
            ],
          ),
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
    this.size = 88,
  });

  final String name;
  final String? imageUrl;
  final PickedMedia? picked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = picked;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final avatar = photo == null
        ? EpFanAvatar(name: name, imageUrl: imageUrl, size: size)
        : Semantics(
            image: true,
            label: 'Selected profile photo',
            child: Image.memory(
              photo.bytes,
              key: const Key('picked-fan-avatar-preview'),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: cacheSize,
              cacheHeight: cacheSize,
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
                color: context.epColors.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.epColors.background,
                  width: 3,
                ),
              ),
              child: Icon(
                Icons.edit,
                size: 14,
                color: context.epColors.onAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
