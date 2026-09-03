part of '../app_state.dart';

enum _BandArtworkRole { avatar, banner }

/// The band creation form (the cassette canvas): its fields, validation,
/// the create/save action and the artwork uploads that follow it.
mixin _BandCreateState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  abstract String bandId;
  abstract List<String> myBands;
  Map<String, Band> get _bands;
  Map<String, String> get _bandRoles;
  List<String> get exploreBandIds;
  List<Venue> get venues;
  Band? band(String id);
  void go(Screen s, [String? param]);
  void resetTo(Screen s);
  void startGigCreate();
  Future<void> saveBandProfile(BandProfileUpdate update);
  Future<void> refreshBandSetupStatus(String id);
  Future<void> refreshBandDiscoveryReadiness(String id);

  // ---- band create form (the cassette canvas)
  String nbName = '';
  final List<String> nbGenres = []; // insertion order shows on the tape, max 3
  String? nbArea;
  String nbBio = '';
  String nbCredits = '';
  String nbIg = '';
  String nbBc = '';
  String nbYt = '';

  /// Kept as `nbPhoto` for compatibility with the existing creation recovery
  /// path; it is now the avatar/profile image only.
  PickedMedia? nbPhoto;
  String? nbPhotoError;
  bool nbPhotoUploading = false;
  PickedMedia? nbBanner;
  String? nbBannerError;
  bool nbBannerUploading = false;
  bool _nbPhotoUploaded = false;
  bool _nbBannerUploaded = false;
  String? _nbPhotoMediaId;
  String? _nbBannerMediaId;
  bool nbCreated = false;

  /// Set once the band lands; later saves update this record instead of
  /// creating another band.
  String? _nbBandId;

  /// The server-issued slug for the created band — unique, and stable across
  /// renames so shared links keep resolving.
  String? _nbCreatedSlug;

  /// Blocks a second create/save while one is already in flight, and puts the
  /// create bar into its pending state so the block is visible rather than
  /// just correct.
  bool _nbSaving = false;
  bool get nbSaving => _nbSaving;

  // ========================= band create =========================

  void startBandCreate() {
    _resetBandForm();
    go(Screen.bandCreate);
  }

  @override
  void _resetBandForm() {
    nbName = '';
    nbGenres.clear();
    nbArea = null;
    nbBio = '';
    nbCredits = '';
    nbIg = '';
    nbBc = '';
    nbYt = '';
    nbPhoto = null;
    nbPhotoError = null;
    nbPhotoUploading = false;
    nbBanner = null;
    nbBannerError = null;
    nbBannerUploading = false;
    _nbPhotoUploaded = false;
    _nbBannerUploaded = false;
    _nbPhotoMediaId = null;
    _nbBannerMediaId = null;
    nbCreated = false;
    _nbBandId = null;
    _nbCreatedSlug = null;
  }

  void setNbName(String v) => _set(() => nbName = v);

  void setNbBio(String v) => _set(() => nbBio = v);

  void setNbCredits(String v) => _set(() => nbCredits = v);

  void setNbArea(String v) =>
      _set(() => nbArea = v.trim().isEmpty ? null : v.trim());

  void setNbIg(String v) => _set(() => nbIg = v);

  void setNbBc(String v) => _set(() => nbBc = v);

  void setNbYt(String v) => _set(() => nbYt = v);

  void setNbPhoto(PickedMedia? photo) => _set(() {
    nbPhoto = photo;
    nbPhotoError = null;
    _nbPhotoUploaded = false;
    _nbPhotoMediaId = null;
  });

  void setNbBanner(PickedMedia? photo) => _set(() {
    nbBanner = photo;
    nbBannerError = null;
    _nbBannerUploaded = false;
    _nbBannerMediaId = null;
  });

  void toggleNbGenre(String g) {
    if (nbGenres.contains(g)) {
      nbGenres.remove(g);
    } else if (nbGenres.length >= 3) {
      say('Three genres max. It keeps discovery honest.');
      return;
    } else {
      nbGenres.add(g);
    }
    notifyListeners();
  }

  bool addNbGenre(String raw) {
    final g = raw.trim().toLowerCase();
    if (g.isEmpty) return false;
    if (nbGenres.contains(g)) return false;
    if (nbGenres.length >= 3) {
      say('Three genres max.');
      return false;
    }
    _set(() => nbGenres.add(g));
    return true;
  }

  bool get canCreateBand =>
      nbName.trim().isNotEmpty && nbGenres.isNotEmpty && nbArea != null;

  /// What the create bar still asks for, in reading order.
  List<String> get bandMissing => [
    if (nbName.trim().isEmpty) 'a name',
    if (nbGenres.isEmpty) 'a genre',
    if (nbArea == null) 'a home base',
  ];

  String get nbSlug {
    final slug = _slugify(nbName.trim().isEmpty ? 'your-band' : nbName);
    return slug.isEmpty ? 'your-band' : slug;
  }

  /// Whether the form is re-editing a band that already landed — the create
  /// bar saves changes then instead of creating another band.
  bool get nbEditingCreated => _nbBandId != null;

  /// The slug shown on shareable URLs: the server-issued one once the band
  /// exists, the client-side preview before that.
  String get nbShareSlug => _nbCreatedSlug ?? nbSlug;

  /// Every area the feed knows (venues and bands), with how much scene lives
  /// there — the home-base sheet offers these before the free-text field.
  List<({String name, String sub})> get knownAreas {
    final bandCounts = <String, int>{};
    for (final id in exploreBandIds) {
      final area = band(id)?.area;
      if (area != null && area.isNotEmpty) {
        bandCounts[area] = (bandCounts[area] ?? 0) + 1;
      }
    }
    final venueCounts = <String, int>{};
    for (final venue in venues) {
      if (venue.area.isNotEmpty) {
        venueCounts[venue.area] = (venueCounts[venue.area] ?? 0) + 1;
      }
    }

    String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    final names = {...bandCounts.keys, ...venueCounts.keys}.toList()
      ..sort((a, b) => (bandCounts[b] ?? 0).compareTo(bandCounts[a] ?? 0));
    return [
      for (final name in names)
        (
          name: name,
          sub:
              '${count(bandCounts[name] ?? 0, 'band')} · '
              '${count(venueCounts[name] ?? 0, 'venue')}',
        ),
      if (nbArea case final area? when !names.contains(area))
        (name: area, sub: 'Added by you'),
    ];
  }

  Future<void> createBand() async {
    if (_nbSaving) return;
    if (!canCreateBand) {
      say('Add ${bandMissing.join(' + ')} first. Tap any line.');
      return;
    }

    _nbSaving = true;
    notifyListeners();
    final name = nbName.trim();
    try {
      if (_nbBandId case final existingId?) {
        // "Keep editing" after a successful create: save onto the same band.
        await saveBandProfile(
          BandProfileUpdate(
            bandId: existingId,
            name: name,
            genres: List.of(nbGenres),
            area: nbArea!,
            bio: nbBio,
            linkIg: nbIg,
            linkBc: nbBc,
            linkYt: nbYt,
            credits: nbCredits,
          ),
        );
      } else {
        final created = await repository.createBand(
          name: name,
          genres: List.of(nbGenres),
          bio: nbBio.trim(),
          area: nbArea!,
          linkIg: nbIg.trim().isEmpty ? null : nbIg.trim(),
          linkBc: nbBc.trim().isEmpty ? null : nbBc.trim(),
          linkYt: nbYt.trim().isEmpty ? null : nbYt.trim(),
          credits: nbCredits.trim().isEmpty ? null : nbCredits.trim(),
        );
        final band = created.band;
        bandId = band.id;
        _bands[band.id] = band;
        _bandRoles[band.id] = 'admin';
        if (!myBands.contains(band.id)) myBands = [...myBands, band.id];
        _nbBandId = band.id;
        _nbCreatedSlug = created.slug;
      }
    } on Exception catch (error) {
      logError('createBand', error);
      say(genericErrorMessage);
      return;
    } finally {
      // Notifies on the failure path too, so the bar leaves its pending state
      // whichever way the save ended.
      _nbSaving = false;
      notifyListeners();
    }

    final media = _media;
    if (media != null) {
      if (nbPhoto case final photo? when !_nbPhotoUploaded) {
        unawaited(_uploadBandArtwork(photo, _BandArtworkRole.avatar));
      }
      if (nbBanner case final banner? when !_nbBannerUploaded) {
        unawaited(_uploadBandArtwork(banner, _BandArtworkRole.banner));
      }
    }
    nbCreated = true;
    notifyListeners();
    unawaited(refreshBandSetupStatus(bandId));
    unawaited(refreshBandDiscoveryReadiness(bandId));
    _refreshExploreBands();
  }

  Future<void> _uploadBandArtwork(
    PickedMedia photo,
    _BandArtworkRole role,
  ) async {
    final media = _media;
    final targetBandId = _nbBandId;
    if (media == null || targetBandId == null) return;

    if (role == _BandArtworkRole.avatar) {
      nbPhotoUploading = true;
      nbPhotoError = null;
    } else {
      nbBannerUploading = true;
      nbBannerError = null;
    }
    notifyListeners();

    final pending = role == _BandArtworkRole.avatar
        ? _nbPhotoMediaId
        : _nbBannerMediaId;
    final mediaId = pending ?? await media.uploadHeldPhoto(targetBandId, photo);
    if (mediaId == null) {
      if (role == _BandArtworkRole.avatar) {
        nbPhotoUploading = false;
        nbPhotoError = 'upload failed';
      } else {
        nbBannerUploading = false;
        nbBannerError = 'upload failed';
      }
      notifyListeners();
      say(
        "Band's up. The ${role == _BandArtworkRole.avatar ? 'profile' : 'header'} image didn't upload. Retry it here.",
      );
      return;
    }
    if (role == _BandArtworkRole.avatar) {
      _nbPhotoMediaId = mediaId;
    } else {
      _nbBannerMediaId = mediaId;
    }

    final assigned = role == _BandArtworkRole.avatar
        ? await media.setAvatar(targetBandId, mediaId)
        : await media.setBanner(targetBandId, mediaId);
    if (role == _BandArtworkRole.avatar) {
      nbPhotoUploading = false;
      _nbPhotoUploaded = assigned;
      nbPhotoError = assigned ? null : 'assignment failed';
      if (assigned) _nbPhotoMediaId = null;
    } else {
      nbBannerUploading = false;
      _nbBannerUploaded = assigned;
      nbBannerError = assigned ? null : 'assignment failed';
      if (assigned) _nbBannerMediaId = null;
    }
    notifyListeners();
    unawaited(refreshBandSetupStatus(targetBandId));
    unawaited(refreshBandDiscoveryReadiness(targetBandId));
  }

  Future<void> retryNbPhoto() async {
    final photo = nbPhoto;
    if (photo == null) return;
    await _uploadBandArtwork(photo, _BandArtworkRole.avatar);
  }

  Future<void> retryNbBanner() async {
    final photo = nbBanner;
    if (photo == null) return;
    await _uploadBandArtwork(photo, _BandArtworkRole.banner);
  }

  /// "Keep editing" — back to the tape with everything still filled in.
  void editCreatedBand() => _set(() => nbCreated = false);

  void makeAnotherBand() => _set(_resetBandForm);

  /// The created view's headline action: straight into posting a gig.
  void postFirstGig() {
    resetTo(Screen.bandDash);
    startGigCreate();
  }

  /// The created view's quiet exit, for people who just want to see the band
  /// they made. The header ✕ is gone on that screen, and web has no system
  /// back, so without this the only ways off are the three loud ones.
  void openCreatedBand() => resetTo(Screen.bandDash);
}
