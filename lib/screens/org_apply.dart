import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import '../widgets/slot_card.dart';
import '../widgets/venue_location_editor.dart';

Future<String> _uploadApplicationDocument(
  EarplugRepository repository,
  PickedMedia media,
) async {
  final uploadUri = Uri.parse(
    await repository.generateApplicationDocumentUploadUrl(),
  );
  if (uploadUri.scheme == 'demo') {
    return 'demo-application-doc-${DateTime.now().microsecondsSinceEpoch}';
  }
  final response = await http.post(
    uploadUri,
    headers: {'Content-Type': media.contentType},
    body: media.bytes,
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Upload failed with status ${response.statusCode}');
  }
  return (jsonDecode(response.body) as Map<String, dynamic>)['storageId']
      as String;
}

String _extractErrorMessage(Object error) {
  final text = error.toString();
  const uncaughtErrorPrefix = 'Uncaught Error:';
  final uncaughtErrorIndex = text.lastIndexOf(uncaughtErrorPrefix);
  if (uncaughtErrorIndex >= 0) {
    return text
        .substring(uncaughtErrorIndex + uncaughtErrorPrefix.length)
        .trim();
  }
  return text
      .replaceFirst(RegExp(r'^(Bad state: |Exception: |ConvexError: )'), '')
      .trim();
}

class OrgApplyScreen extends StatefulWidget {
  const OrgApplyScreen({super.key, this.mediaPicker});

  final MediaPicker? mediaPicker;

  @override
  State<OrgApplyScreen> createState() => _OrgApplyScreenState();
}

class _OrgApplyScreenState extends State<OrgApplyScreen> {
  String? _applicationId;
  int _revision = 0;

  String _orgName = '';
  OrganizationType? _orgType;
  String? _kind;
  String _website = '';

  VenueLocationDraft _venueLocation = const VenueLocationDraft();
  String _neighborhood = '';
  String _city = '';
  int? _capacity;
  VenueType? _venueType;

  String _contactName = '';
  String _businessEmail = '';
  String _phone = '';
  List<ApplicationDocument> _documents = const [];
  bool _agreed = false;

  late final MediaPicker _mediaPicker;
  bool _redirected = false;

  bool get _organizationComplete =>
      _orgName.trim().isNotEmpty && _orgType != null;
  bool get _locationComplete => _venueLocation.isComplete;
  bool get _contactComplete =>
      _contactName.trim().isNotEmpty &&
      _businessEmail.trim().isNotEmpty &&
      _businessEmail.contains('@');
  bool get _documentsComplete => _documents.isNotEmpty;
  bool get _readyToSubmit =>
      _organizationComplete &&
      _locationComplete &&
      _contactComplete &&
      _documentsComplete &&
      _agreed;

  @override
  void initState() {
    super.initState();
    _mediaPicker = widget.mediaPicker ?? MediaPicker();
    final app = context.read<AppState>();
    final application = app.myOrganizationApplication;
    if (application == null) {
      unawaited(app.refreshOrganizationApplication());
    } else if (application.editable) {
      _loadApplication(application);
    } else if (application.status != OrganizationApplicationStatus.withdrawn) {
      _scheduleStatusRedirect();
    }
  }

  void _loadApplication(OrganizationApplication application) {
    final venue = application.venue;
    _applicationId = application.id;
    _revision = application.revision;
    _orgName = application.orgName;
    _orgType = application.orgType;
    _kind = venue?.venueType == VenueType.club ? 'club' : 'bar';
    _website = application.website ?? '';
    _venueLocation = VenueLocationDraft(
      name: venue?.name ?? '',
      address: venue?.addr ?? '',
      area: venue?.area ?? '',
      pin: venue?.point,
    );
    _neighborhood = venue?.neighborhood ?? '';
    _city = venue?.city ?? '';
    _capacity = venue?.capacity;
    _venueType = venue?.venueType;
    _contactName = application.contactName;
    _businessEmail = application.businessEmail;
    _phone = application.phone ?? '';
    _documents = List.of(application.documents);
  }

  void _scheduleStatusRedirect() {
    if (_redirected) return;
    _redirected = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.back();
      app.go(Screen.orgApplicationStatus);
    });
  }

  ApplicationVenueDraft? _applicationVenue(
    VenueLocationDraft location,
    String neighborhood,
    String city,
    int? capacity,
    VenueType? venueType,
  ) {
    if (!location.isComplete) return null;
    return ApplicationVenueDraft(
      name: location.name.trim(),
      addr: location.address.trim(),
      point: location.pin!,
      area: location.area.trim(),
      neighborhood: neighborhood.trim().isEmpty ? null : neighborhood.trim(),
      city: city.trim().isEmpty ? null : city.trim(),
      capacity: capacity,
      venueType: venueType,
    );
  }

  Future<bool> _saveDraft({
    String? orgName,
    OrganizationType? orgType,
    String? kind,
    String? website,
    VenueLocationDraft? venueLocation,
    String? neighborhood,
    String? city,
    int? capacity,
    VenueType? venueType,
    bool replaceVenueDetails = false,
    String? contactName,
    String? businessEmail,
    String? phone,
  }) async {
    final nextOrgName = orgName ?? _orgName;
    final nextOrgType = orgType ?? _orgType;
    final nextKind = kind ?? _kind;
    final nextWebsite = website ?? _website;
    final nextLocation = venueLocation ?? _venueLocation;
    final nextNeighborhood = neighborhood ?? _neighborhood;
    final nextCity = city ?? _city;
    final nextCapacity = replaceVenueDetails ? capacity : capacity ?? _capacity;
    final nextVenueType = replaceVenueDetails
        ? venueType
        : venueType ?? _venueType;
    final nextContactName = contactName ?? _contactName;
    final nextBusinessEmail = businessEmail ?? _businessEmail;
    final nextPhone = phone ?? _phone;
    final app = context.read<AppState>();

    try {
      final saved = await app.repository.saveOrganizationApplicationDraft(
        applicationId: _applicationId,
        expectedRevision: _applicationId == null ? null : _revision,
        orgName: nextOrgName.trim(),
        orgType: nextOrgType ?? OrganizationType.venueOperator,
        website: nextWebsite.trim().isEmpty ? null : nextWebsite.trim(),
        contactName: nextContactName.trim(),
        businessEmail: nextBusinessEmail.trim(),
        phone: nextPhone.trim().isEmpty ? null : nextPhone.trim(),
        venue: _applicationVenue(
          nextLocation,
          nextNeighborhood,
          nextCity,
          nextCapacity,
          nextVenueType,
        ),
      );
      if (!mounted) return false;
      setState(() {
        _applicationId = saved.applicationId;
        _revision = saved.revision;
        _orgName = nextOrgName.trim();
        _orgType = nextOrgType;
        _kind = nextKind;
        _website = nextWebsite.trim();
        _venueLocation = nextLocation;
        _neighborhood = nextNeighborhood.trim();
        _city = nextCity.trim();
        _capacity = nextCapacity;
        _venueType = nextVenueType;
        _contactName = nextContactName.trim();
        _businessEmail = nextBusinessEmail.trim();
        _phone = nextPhone.trim();
      });
      await app.refreshOrganizationApplication();
      return mounted;
    } catch (error) {
      final message = _extractErrorMessage(error);
      final changedElsewhere = message.toLowerCase().contains(
        'changed elsewhere',
      );
      if (changedElsewhere) {
        await _handleMutationError(app, error);
      } else {
        if (!mounted) return false;
        app.say("Couldn't save: $message");
        setState(() {
          _orgName = nextOrgName.trim();
          _orgType = nextOrgType;
          _kind = nextKind;
          _website = nextWebsite.trim();
          _venueLocation = nextLocation;
          _neighborhood = nextNeighborhood.trim();
          _city = nextCity.trim();
          _capacity = nextCapacity;
          _venueType = nextVenueType;
          _contactName = nextContactName.trim();
          _businessEmail = nextBusinessEmail.trim();
          _phone = nextPhone.trim();
        });
      }
      return false;
    }
  }

  Future<void> _handleMutationError(AppState app, Object error) async {
    final changedElsewhere = _extractErrorMessage(
      error,
    ).toLowerCase().contains('changed elsewhere');
    app.say(
      changedElsewhere
          ? 'This application changed elsewhere. Latest details restored.'
          : 'Could not update the application. Latest details restored.',
    );
    await app.refreshOrganizationApplication();
    if (!mounted) return;
    final current = app.myOrganizationApplication;
    setState(() {
      if (current == null ||
          current.status == OrganizationApplicationStatus.withdrawn) {
        _applicationId = null;
        _revision = 0;
      } else if (current.editable) {
        _loadApplication(current);
      }
    });
  }

  Future<ApplicationDocument?> _addDocument() async {
    if (_documents.length >= 5) {
      context.read<AppState>().say('Up to five documents can be attached.');
      return null;
    }

    final PickedMedia? media;
    try {
      media = await _mediaPicker.pickPhoto();
    } on MediaPickException catch (error) {
      if (mounted) context.read<AppState>().say(error.message);
      return null;
    }
    if (!mounted || media == null) return null;

    if (_applicationId == null && !await _saveDraft()) return null;
    if (!mounted || _applicationId == null) return null;
    final app = context.read<AppState>();
    try {
      final storageId = await _uploadApplicationDocument(app.repository, media);
      final revision = await app.repository.attachApplicationDocument(
        applicationId: _applicationId!,
        storageId: storageId,
      );
      final document = ApplicationDocument(
        storageId: storageId,
        contentType: media.contentType,
        sizeBytes: media.sizeBytes,
      );
      if (!mounted) return null;
      setState(() {
        _revision = revision;
        _documents = [..._documents, document];
      });
      await app.refreshOrganizationApplication();
      return mounted ? document : null;
    } catch (error) {
      await _handleMutationError(app, error);
      return null;
    }
  }

  Future<bool> _removeDocument(ApplicationDocument document) async {
    final applicationId = _applicationId;
    if (applicationId == null) return false;
    final app = context.read<AppState>();
    try {
      final revision = await app.repository.removeApplicationDocument(
        applicationId: applicationId,
        storageId: document.storageId,
      );
      if (!mounted) return false;
      setState(() {
        _revision = revision;
        _documents = _documents
            .where((item) => item.storageId != document.storageId)
            .toList();
      });
      await app.refreshOrganizationApplication();
      return mounted;
    } catch (error) {
      await _handleMutationError(app, error);
      return false;
    }
  }

  Future<bool> _submit() async {
    final applicationId = _applicationId;
    final app = context.read<AppState>();
    if (applicationId == null) {
      app.say('Save the application details before submitting.');
      return false;
    }
    try {
      final revision = await app.repository.submitOrganizationApplication(
        applicationId: applicationId,
        expectedRevision: _revision,
      );
      if (!mounted) return false;
      setState(() => _revision = revision);
      await app.refreshOrganizationApplication();
      if (!mounted) return false;
      app.go(Screen.orgApplicationStatus);
      return true;
    } catch (error) {
      await _handleMutationError(app, error);
      return false;
    }
  }

  void _openOrganizationSheet() {
    unawaited(
      showEpSheet(
        context,
        (_) => EpFormSheet(
          title: 'Organization',
          child: _OrganizationSheetBody(
            initialName: _orgName,
            initialType: _orgType,
            initialKind: _kind,
            initialWebsite: _website,
            onSave:
                ({
                  required name,
                  required orgType,
                  required kind,
                  required website,
                }) => _saveDraft(
                  orgName: name,
                  orgType: orgType,
                  kind: kind,
                  website: website,
                ),
          ),
        ),
      ),
    );
  }

  void _openLocationSheet() {
    unawaited(
      showEpSheet(
        context,
        (_) => EpFormSheet(
          title: 'Location',
          child: _LocationSheetBody(
            initialLocation: _venueLocation,
            initialNeighborhood: _neighborhood,
            initialCity: _city,
            initialCapacity: _capacity,
            initialVenueType: _venueType,
            onSave:
                ({
                  required location,
                  required neighborhood,
                  required city,
                  required capacity,
                  required venueType,
                }) => _saveDraft(
                  venueLocation: location,
                  neighborhood: neighborhood,
                  city: city,
                  capacity: capacity,
                  venueType: venueType,
                  replaceVenueDetails: true,
                ),
          ),
        ),
      ),
    );
  }

  void _openContactSheet() {
    unawaited(
      showEpSheet(
        context,
        (_) => EpFormSheet(
          title: 'Contact',
          child: _ContactSheetBody(
            initialName: _contactName,
            initialEmail: _businessEmail,
            initialPhone: _phone,
            onSave: ({required name, required email, required phone}) =>
                _saveDraft(
                  contactName: name,
                  businessEmail: email,
                  phone: phone,
                ),
          ),
        ),
      ),
    );
  }

  void _openDocumentsSheet() {
    unawaited(
      showEpSheet(
        context,
        (_) => EpFormSheet(
          title: 'Documents',
          child: _DocumentsSheetBody(
            initialDocuments: _documents,
            onAdd: _addDocument,
            onRemove: _removeDocument,
          ),
        ),
      ),
    );
  }

  void _openReviewSheet() {
    unawaited(
      showEpSheet(
        context,
        (_) => EpFormSheet(
          title: 'Review & submit',
          child: _ReviewSheetBody(
            orgName: _orgName,
            kind: _kind,
            website: _website,
            venueLocation: _venueLocation,
            neighborhood: _neighborhood,
            city: _city,
            capacity: _capacity,
            venueType: _venueType,
            contactName: _contactName,
            businessEmail: _businessEmail,
            phone: _phone,
            documentCount: _documents.length,
            initiallyAgreed: _agreed,
            formComplete:
                _organizationComplete &&
                _locationComplete &&
                _contactComplete &&
                _documentsComplete,
            onAgreementChanged: (value) {
              if (mounted) setState(() => _agreed = value);
            },
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }

  String get _missingLabel {
    final missing = <String>[
      if (!_organizationComplete) 'organization',
      if (!_locationComplete) 'location',
      if (!_contactComplete) 'contact',
      if (!_documentsComplete) 'documents',
    ];
    return missing.isEmpty ? '' : 'Still needs ${missing.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final application = context.watch<AppState>().myOrganizationApplication;
    if (_applicationId == null && application?.editable == true) {
      _loadApplication(application!);
    }

    if (application != null &&
        application.status != OrganizationApplicationStatus.withdrawn &&
        !application.editable) {
      _scheduleStatusRedirect();
      return const Material(child: Center(child: CircularProgressIndicator()));
    }

    return Material(
      color: context.epColors.background,
      child: Column(
        children: [
          ScreenHeader(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleIconButton(
                  icon: Icons.close,
                  onTap: () => context.read<AppState>().back(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BECOME AN ORGANIZER', style: epDisplay(size: 16)),
                      const SizedBox(height: 4),
                      Text(
                        'Bars and clubs that run their own room. Promoters '
                        'and student orgs are coming next.',
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              children: [
                SlotCard(
                  key: const Key('org-apply-step-organization'),
                  tag: 'ORGANIZATION',
                  value: _organizationComplete ? _orgName : 'REQUIRED',
                  sub: _organizationComplete
                      ? (_kind ?? 'bar').toUpperCase()
                      : 'Tell us which bar or club is applying.',
                  state: _organizationComplete
                      ? SlotState.done
                      : SlotState.needed,
                  onTap: _openOrganizationSheet,
                ),
                const SizedBox(height: 10),
                SlotCard(
                  key: const Key('org-apply-step-location'),
                  tag: 'LOCATION',
                  value: _locationComplete ? _venueLocation.name : 'REQUIRED',
                  sub: _locationComplete
                      ? _venueLocation.area
                      : 'Add the room and its private street address.',
                  state: _locationComplete ? SlotState.done : SlotState.needed,
                  onTap: _openLocationSheet,
                ),
                const SizedBox(height: 10),
                SlotCard(
                  key: const Key('org-apply-step-contact'),
                  tag: 'CONTACT',
                  value: _contactComplete ? _contactName : 'REQUIRED',
                  sub: _contactComplete
                      ? _businessEmail
                      : 'Who should EarPlug contact about the application?',
                  state: _contactComplete ? SlotState.done : SlotState.needed,
                  onTap: _openContactSheet,
                ),
                const SizedBox(height: 10),
                SlotCard(
                  key: const Key('org-apply-step-documents'),
                  tag: 'DOCUMENTS',
                  value: _documentsComplete
                      ? '${_documents.length} ATTACHED'
                      : 'REQUIRED',
                  sub: _documentsComplete
                      ? 'License or lease evidence'
                      : 'Add a photo of your license or lease.',
                  state: _documentsComplete ? SlotState.done : SlotState.needed,
                  onTap: _openDocumentsSheet,
                ),
                const SizedBox(height: 10),
                SlotCard(
                  key: const Key('org-apply-step-review'),
                  tag: 'REVIEW & SUBMIT',
                  value: _agreed ? 'READY' : 'REVIEW REQUIRED',
                  sub: _readyToSubmit
                      ? 'Everything is ready to submit.'
                      : 'Confirm the details and Organizer Agreement.',
                  state: _agreed ? SlotState.done : SlotState.needed,
                  onTap: _openReviewSheet,
                ),
                if (_missingLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _missingLabel,
                    style: epText(
                      size: 11,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _OrganizationSave =
    Future<bool> Function({
      required String name,
      required OrganizationType orgType,
      required String kind,
      required String website,
    });

class _OrganizationSheetBody extends StatefulWidget {
  const _OrganizationSheetBody({
    required this.initialName,
    required this.initialType,
    required this.initialKind,
    required this.initialWebsite,
    required this.onSave,
  });

  final String initialName;
  final OrganizationType? initialType;
  final String? initialKind;
  final String initialWebsite;
  final _OrganizationSave onSave;

  @override
  State<_OrganizationSheetBody> createState() => _OrganizationSheetBodyState();
}

class _OrganizationSheetBodyState extends State<_OrganizationSheetBody> {
  late final TextEditingController _name;
  late final TextEditingController _website;
  late OrganizationType _orgType;
  late String _kind;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _website = TextEditingController(text: widget.initialWebsite);
    _orgType = widget.initialType ?? OrganizationType.venueOperator;
    _kind = widget.initialKind ?? 'bar';
  }

  @override
  void dispose() {
    _name.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Organization name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(
      name: _name.text,
      orgType: _orgType,
      kind: _kind,
      website: _website.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('org-apply-name'),
          controller: _name,
          maxLength: 120,
          decoration: sheetInput(context, 'Organization name'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            EpChip(
              label: 'BAR',
              active: _kind == 'bar',
              onTap: () => setState(() {
                _orgType = OrganizationType.venueOperator;
                _kind = 'bar';
              }),
            ),
            EpChip(
              label: 'CLUB',
              active: _kind == 'club',
              onTap: () => setState(() {
                _orgType = OrganizationType.venueOperator;
                _kind = 'club';
              }),
            ),
            const EpChip(label: 'PROMOTER', active: false, onTap: null),
            const EpChip(label: 'STUDENT ORG', active: false, onTap: null),
          ],
        ),
        Text(
          'Promoters and student orgs: Coming soon',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('org-apply-website'),
          controller: _website,
          keyboardType: TextInputType.url,
          decoration: sheetInput(context, 'Website (optional)'),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(error, style: epText(color: context.epColors.warning)),
        ],
        const SizedBox(height: 14),
        EpButton(
          'DONE',
          key: const Key('org-apply-organization-done'),
          kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

typedef _LocationSave =
    Future<bool> Function({
      required VenueLocationDraft location,
      required String neighborhood,
      required String city,
      required int? capacity,
      required VenueType? venueType,
    });

class _LocationSheetBody extends StatefulWidget {
  const _LocationSheetBody({
    required this.initialLocation,
    required this.initialNeighborhood,
    required this.initialCity,
    required this.initialCapacity,
    required this.initialVenueType,
    required this.onSave,
  });

  final VenueLocationDraft initialLocation;
  final String initialNeighborhood;
  final String initialCity;
  final int? initialCapacity;
  final VenueType? initialVenueType;
  final _LocationSave onSave;

  @override
  State<_LocationSheetBody> createState() => _LocationSheetBodyState();
}

class _LocationSheetBodyState extends State<_LocationSheetBody> {
  late VenueLocationDraft _location;
  late final TextEditingController _neighborhood;
  late final TextEditingController _city;
  late final TextEditingController _capacity;
  VenueType? _venueType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    _neighborhood = TextEditingController(text: widget.initialNeighborhood);
    _city = TextEditingController(text: widget.initialCity);
    _capacity = TextEditingController(
      text: widget.initialCapacity?.toString() ?? '',
    );
    _venueType = widget.initialVenueType;
  }

  @override
  void dispose() {
    _neighborhood.dispose();
    _city.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_location.isComplete) {
      setState(() {
        _error = 'Venue name, address, area, and map pin are required.';
      });
      return;
    }
    final capacityText = _capacity.text.trim();
    final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
    if (capacityText.isNotEmpty && capacity == null) {
      setState(() => _error = 'Capacity must be a whole number.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(
      location: _location,
      neighborhood: _neighborhood.text,
      city: _city.text,
      capacity: capacity,
      venueType: _venueType,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VenueLocationEditor(
              initial: widget.initialLocation,
              onChanged: (location) => setState(() => _location = location),
              showNameField: true,
              keyPrefix: 'org-apply-venue',
              helperText:
                  'Fans only ever see the neighborhood. The exact address '
                  'stays private.',
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('org-apply-neighborhood'),
              controller: _neighborhood,
              decoration: sheetInput(context, 'Neighborhood (optional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('org-apply-city'),
              controller: _city,
              decoration: sheetInput(context, 'City (optional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('org-apply-capacity'),
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: sheetInput(context, 'Capacity (optional)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in VenueType.values)
                  EpChip(
                    label: type.name.toUpperCase(),
                    active: _venueType == type,
                    onTap: () => setState(() => _venueType = type),
                  ),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              Text(error, style: epText(color: context.epColors.warning)),
            ],
            const SizedBox(height: 14),
            EpButton(
              'DONE',
              key: const Key('org-apply-location-done'),
              kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

typedef _ContactSave =
    Future<bool> Function({
      required String name,
      required String email,
      required String phone,
    });

class _ContactSheetBody extends StatefulWidget {
  const _ContactSheetBody({
    required this.initialName,
    required this.initialEmail,
    required this.initialPhone,
    required this.onSave,
  });

  final String initialName;
  final String initialEmail;
  final String initialPhone;
  final _ContactSave onSave;

  @override
  State<_ContactSheetBody> createState() => _ContactSheetBodyState();
}

class _ContactSheetBodyState extends State<_ContactSheetBody> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _email = TextEditingController(text: widget.initialEmail);
    _phone = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    if (_name.text.trim().isEmpty || email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Contact name and a valid email are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(
      name: _name.text,
      email: email,
      phone: _phone.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('org-apply-contact-name'),
          controller: _name,
          decoration: sheetInput(context, 'Contact name'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('org-apply-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: sheetInput(context, 'Business email'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('org-apply-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: sheetInput(context, 'Phone (optional)'),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(error, style: epText(color: context.epColors.warning)),
        ],
        const SizedBox(height: 14),
        EpButton(
          'DONE',
          key: const Key('org-apply-contact-done'),
          kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _DocumentsSheetBody extends StatefulWidget {
  const _DocumentsSheetBody({
    required this.initialDocuments,
    required this.onAdd,
    required this.onRemove,
  });

  final List<ApplicationDocument> initialDocuments;
  final Future<ApplicationDocument?> Function() onAdd;
  final Future<bool> Function(ApplicationDocument document) onRemove;

  @override
  State<_DocumentsSheetBody> createState() => _DocumentsSheetBodyState();
}

class _DocumentsSheetBodyState extends State<_DocumentsSheetBody> {
  late List<ApplicationDocument> _documents;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _documents = List.of(widget.initialDocuments);
  }

  Future<void> _add() async {
    setState(() => _working = true);
    final document = await widget.onAdd();
    if (!mounted) return;
    setState(() {
      _working = false;
      if (document != null) _documents = [..._documents, document];
    });
  }

  Future<void> _remove(ApplicationDocument document) async {
    setState(() => _working = true);
    final removed = await widget.onRemove(document);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (removed) {
        _documents = _documents
            .where((item) => item.storageId != document.storageId)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = !_working && _documents.length < 5;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final document in _documents) ...[
              Row(
                children: [
                  SizedBox.square(
                    dimension: 48,
                    child: document.contentType?.startsWith('image/') == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: EpNetworkImage(
                              url: document.url,
                              fallback: const Icon(
                                Icons.image_outlined,
                                size: 28,
                              ),
                            ),
                          )
                        : const Icon(Icons.description_outlined, size: 28),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      document.contentType ?? 'Application document',
                      style: Theme.of(context).textTheme.epBody,
                    ),
                  ),
                  TextButton(
                    key: Key('org-apply-doc-remove-${document.storageId}'),
                    onPressed: _working ? null : () => _remove(document),
                    child: const Text('REMOVE'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            EpButton(
              'ADD PHOTO OF LICENSE / LEASE',
              key: const Key('org-apply-doc-add'),
              kind: canAdd ? EpButtonKind.outline : EpButtonKind.disabled,
              onTap: canAdd ? _add : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Phase 1 accepts photos only — PDF upload is coming later.',
              style: Theme.of(context).textTheme.epCaption,
            ),
            const SizedBox(height: 14),
            const DoneButton(),
          ],
        ),
      ),
    );
  }
}

class _ReviewSheetBody extends StatefulWidget {
  const _ReviewSheetBody({
    required this.orgName,
    required this.kind,
    required this.website,
    required this.venueLocation,
    required this.neighborhood,
    required this.city,
    required this.capacity,
    required this.venueType,
    required this.contactName,
    required this.businessEmail,
    required this.phone,
    required this.documentCount,
    required this.initiallyAgreed,
    required this.formComplete,
    required this.onAgreementChanged,
    required this.onSubmit,
  });

  final String orgName;
  final String? kind;
  final String website;
  final VenueLocationDraft venueLocation;
  final String neighborhood;
  final String city;
  final int? capacity;
  final VenueType? venueType;
  final String contactName;
  final String businessEmail;
  final String phone;
  final int documentCount;
  final bool initiallyAgreed;
  final bool formComplete;
  final ValueChanged<bool> onAgreementChanged;
  final Future<bool> Function() onSubmit;

  @override
  State<_ReviewSheetBody> createState() => _ReviewSheetBodyState();
}

class _ReviewSheetBodyState extends State<_ReviewSheetBody> {
  late bool _agreed;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _agreed = widget.initiallyAgreed;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final submitted = await widget.onSubmit();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (submitted && Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.formComplete && _agreed && !_submitting;
    final venueDetails = [
      widget.venueLocation.name,
      widget.venueLocation.address,
      widget.venueLocation.area,
      widget.neighborhood,
      widget.city,
      if (widget.capacity != null) 'Capacity ${widget.capacity}',
      widget.venueType?.name.toUpperCase() ?? '',
    ].where((value) => value.trim().isNotEmpty).join(' · ');
    final contactDetails = [
      widget.contactName,
      widget.businessEmail,
      widget.phone,
    ].where((value) => value.trim().isNotEmpty).join(' · ');

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewRow(
              label: 'ORGANIZATION',
              value: [
                widget.orgName,
                widget.kind?.toUpperCase() ?? '',
                widget.website,
              ].where((value) => value.trim().isNotEmpty).join(' · '),
            ),
            _ReviewRow(label: 'LOCATION', value: venueDetails),
            _ReviewRow(label: 'CONTACT', value: contactDetails),
            _ReviewRow(
              label: 'DOCUMENTS',
              value: '${widget.documentCount} attached',
            ),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: const Key('org-apply-agree'),
                contentPadding: EdgeInsets.zero,
                value: _agreed,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I confirm this information is accurate and accept the '
                  'Organizer Agreement',
                ),
                onChanged: (value) {
                  final agreed = value ?? false;
                  setState(() => _agreed = agreed);
                  widget.onAgreementChanged(agreed);
                },
              ),
            ),
            const SizedBox(height: 10),
            EpButton(
              'SUBMIT',
              key: const Key('org-apply-submit'),
              kind: enabled ? EpButtonKind.filled : EpButtonKind.disabled,
              onTap: enabled ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: epText(
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 1,
              color: context.epColors.contentSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? 'Not provided' : value,
            style: Theme.of(context).textTheme.epBody,
          ),
        ],
      ),
    );
  }
}
