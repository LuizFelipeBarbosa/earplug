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
import '../widgets/band_identity_editor.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
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

enum _ApplicationStep { venue, contact }

class _OrgApplyScreenState extends State<OrgApplyScreen> {
  static const _autosaveDelay = Duration(milliseconds: 600);

  final _scroll = ScrollController();
  final _orgName = TextEditingController();
  final _capacity = TextEditingController();
  final _contactName = TextEditingController();
  final _businessEmail = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();

  final _capacityFocus = FocusNode();
  final _contactNameFocus = FocusNode();
  final _businessEmailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _websiteFocus = FocusNode();

  String? _applicationId;
  int _revision = 0;
  String? _kind;
  VenueLocationDraft _venueLocation = const VenueLocationDraft();
  List<ApplicationDocument> _documents = const [];
  bool _venueNameEdited = false;
  int _venueEditorGeneration = 0;
  _ApplicationStep _step = _ApplicationStep.venue;
  bool _contactVisited = false;
  bool _agreed = false;
  bool _redirected = false;

  late final MediaPicker _mediaPicker;
  Timer? _autosaveTimer;
  Completer<bool>? _saveCompleter;
  bool _saveRequested = false;
  bool _savingDraft = false;
  bool _draftSaveFailed = false;
  bool _blockingSave = false;
  bool _documentWorking = false;
  bool _submitting = false;
  int _editVersion = 0;
  int _savedVersion = 0;
  String? _error;

  bool get _hasUnsavedChanges => _editVersion > _savedVersion;
  bool get _busy => _blockingSave || _documentWorking || _submitting;
  List<({String label, bool complete})> get _venueRequirements => [
    (label: 'Organization name', complete: _orgName.text.trim().isNotEmpty),
    (label: 'Bar or club selection', complete: _kind != null),
    (label: 'Venue name', complete: _venueLocation.isNamed),
    (label: 'Street address and map pin', complete: _venueLocation.isComplete),
  ];

  List<({String label, bool complete})> get _contactRequirements => [
    (label: 'Contact name', complete: _contactName.text.trim().isNotEmpty),
    (label: 'Business email', complete: _businessEmail.text.contains('@')),
    (label: 'One verification photo', complete: _documents.isNotEmpty),
    (label: 'Organizer Agreement', complete: _agreed),
  ];

  bool get _venueComplete => _venueRequirements.every((item) => item.complete);
  bool get _canSubmit =>
      _venueComplete &&
      _contactRequirements.every((item) => item.complete) &&
      !_busy;

  String get _saveState {
    if (_savingDraft || _documentWorking) return 'Saving…';
    if (_draftSaveFailed) return 'Save failed';
    if (_autosaveTimer?.isActive == true || _hasUnsavedChanges) {
      return 'Saving…';
    }
    return 'Draft saved';
  }

  @override
  void initState() {
    super.initState();
    _mediaPicker = widget.mediaPicker ?? MediaPicker();
    for (final node in [
      _capacityFocus,
      _contactNameFocus,
      _businessEmailFocus,
      _phoneFocus,
      _websiteFocus,
    ]) {
      node.addListener(_saveOnBlur);
    }

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

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _scroll.dispose();
    _orgName.dispose();
    _capacity.dispose();
    _contactName.dispose();
    _businessEmail.dispose();
    _phone.dispose();
    _website.dispose();
    _capacityFocus.dispose();
    _contactNameFocus.dispose();
    _businessEmailFocus.dispose();
    _phoneFocus.dispose();
    _websiteFocus.dispose();
    super.dispose();
  }

  void _loadApplication(OrganizationApplication application) {
    final venue = application.venue;
    final storedVenueName = venue?.name ?? '';
    final venueNameEdited =
        storedVenueName.trim().isNotEmpty &&
        storedVenueName != application.orgName;
    _autosaveTimer?.cancel();
    _step = _ApplicationStep.venue;
    _contactVisited = false;
    _applicationId = application.id;
    _revision = application.revision;
    _orgName.text = application.orgName;
    _kind = switch (venue?.venueType) {
      VenueType.bar => 'bar',
      VenueType.club => 'club',
      _ => null,
    };
    _venueLocation = VenueLocationDraft(
      name: venueNameEdited ? storedVenueName : application.orgName,
      address: venue?.addr ?? '',
      area: venue?.area ?? '',
      pin: venue?.point,
    );
    _venueNameEdited = venueNameEdited;
    _venueEditorGeneration++;
    _capacity.text = venue?.capacity?.toString() ?? '';
    _contactName.text = application.contactName;
    _businessEmail.text = application.businessEmail;
    _phone.text = application.phone ?? '';
    _website.text = application.website ?? '';
    _documents = List.of(application.documents);
    _editVersion = 0;
    _savedVersion = 0;
    _saveRequested = false;
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

  void _changed(VoidCallback update, {bool immediate = false}) {
    setState(() {
      update();
      _editVersion++;
    });
    if (immediate) {
      _autosaveTimer?.cancel();
      unawaited(_saveDraft());
    } else {
      _autosaveTimer?.cancel();
      _autosaveTimer = Timer(_autosaveDelay, () => unawaited(_saveDraft()));
    }
  }

  void _textChanged([String? _]) => _changed(() {});

  void _organizationNameChanged(String name) {
    _changed(() {
      if (!_venueNameEdited) {
        _venueLocation = _venueLocation.copyWith(name: name);
        _venueEditorGeneration++;
      }
    });
  }

  void _venueChanged(VenueLocationDraft location) {
    final pinChanged = location.pin != _venueLocation.pin;
    final nameChanged = location.name != _venueLocation.name;
    _changed(() {
      if (nameChanged) _venueNameEdited = true;
      _venueLocation = location;
    }, immediate: pinChanged);
  }

  void _selectKind(String kind) {
    if (_kind == kind) return;
    _changed(() => _kind = kind, immediate: true);
  }

  void _saveOnBlur() {
    if (_hasUnsavedChanges) unawaited(_saveDraft());
  }

  ApplicationVenueDraft? get _applicationVenue {
    final location = _venueLocation;
    if (!location.isComplete) return null;
    return ApplicationVenueDraft(
      name: location.name.trim(),
      addr: location.address.trim(),
      point: location.pin!,
      area: location.areaLabel,
      capacity: int.tryParse(_capacity.text.trim()),
      venueType: switch (_kind) {
        'bar' => VenueType.bar,
        'club' => VenueType.club,
        _ => null,
      },
    );
  }

  Future<bool> _saveDraft() {
    _autosaveTimer?.cancel();
    _saveRequested = true;
    if (_saveCompleter case final active?) return active.future;

    final completer = Completer<bool>();
    _saveCompleter = completer;
    unawaited(_runSaveLoop(completer));
    return completer.future;
  }

  Future<void> _runSaveLoop(Completer<bool> completer) async {
    if (mounted) setState(() => _savingDraft = true);
    var saved = false;
    while (mounted && _saveRequested) {
      _saveRequested = false;
      saved = await _performDraftSave();
    }
    if (mounted) setState(() => _savingDraft = false);
    if (identical(_saveCompleter, completer)) _saveCompleter = null;
    if (!completer.isCompleted) completer.complete(saved);
  }

  Future<bool> _performDraftSave() async {
    final savedEditVersion = _editVersion;
    final app = context.read<AppState>();
    try {
      final saved = await app.repository.saveOrganizationApplicationDraft(
        applicationId: _applicationId,
        expectedRevision: _applicationId == null ? null : _revision,
        orgName: _orgName.text.trim(),
        orgType: OrganizationType.venueOperator,
        website: _website.text.trim().isEmpty ? null : _website.text.trim(),
        contactName: _contactName.text.trim(),
        businessEmail: _businessEmail.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        venue: _applicationVenue,
      );
      if (!mounted) return false;
      setState(() {
        _draftSaveFailed = false;
        _applicationId = saved.applicationId;
        _revision = saved.revision;
        if (_savedVersion < savedEditVersion) {
          _savedVersion = savedEditVersion;
        }
        _error = null;
      });
      await app.refreshOrganizationApplication();
      return mounted;
    } catch (error) {
      if (mounted) setState(() => _draftSaveFailed = true);
      await _handleMutationError(app, error);
      return false;
    }
  }

  Future<void> _handleMutationError(AppState app, Object error) async {
    final message = _extractErrorMessage(error);
    final changedElsewhere = message.toLowerCase().contains(
      'changed elsewhere',
    );
    if (changedElsewhere) {
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
        _error = message;
      });
      return;
    }
    if (mounted) setState(() => _error = message);
  }

  Future<void> _addDocument() async {
    if (_documentWorking) return;
    if (_documents.length >= 5) {
      context.read<AppState>().say('Up to five documents can be attached.');
      return;
    }

    setState(() => _documentWorking = true);
    final PickedMedia? media;
    try {
      media = await _mediaPicker.pickPhoto();
    } on MediaPickException catch (error) {
      if (mounted) context.read<AppState>().say(error.message);
      if (mounted) setState(() => _documentWorking = false);
      return;
    }
    if (!mounted) return;
    if (media == null) {
      setState(() => _documentWorking = false);
      return;
    }
    final selectedMedia = media;

    if (!await _saveDraft()) {
      if (mounted) setState(() => _documentWorking = false);
      return;
    }
    if (!mounted || _applicationId == null) return;

    final app = context.read<AppState>();
    try {
      final storageId = await _uploadApplicationDocument(
        app.repository,
        selectedMedia,
      );
      final revision = await app.repository.attachApplicationDocument(
        applicationId: _applicationId!,
        storageId: storageId,
      );
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _documents = [
          ..._documents,
          ApplicationDocument(
            storageId: storageId,
            contentType: selectedMedia.contentType,
            sizeBytes: selectedMedia.sizeBytes,
          ),
        ];
        _error = null;
      });
      await app.refreshOrganizationApplication();
    } catch (error) {
      await _handleMutationError(app, error);
      if (mounted) revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _documentWorking = false);
    }
  }

  Future<void> _removeDocument(ApplicationDocument document) async {
    final applicationId = _applicationId;
    if (_documentWorking || applicationId == null) return;
    setState(() => _documentWorking = true);
    if (!await _saveDraft()) {
      if (mounted) setState(() => _documentWorking = false);
      return;
    }
    if (!mounted) return;
    final app = context.read<AppState>();
    try {
      final revision = await app.repository.removeApplicationDocument(
        applicationId: applicationId,
        storageId: document.storageId,
      );
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _documents = _documents
            .where((item) => item.storageId != document.storageId)
            .toList();
        _error = null;
      });
      await app.refreshOrganizationApplication();
    } catch (error) {
      await _handleMutationError(app, error);
      if (mounted) revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _documentWorking = false);
    }
  }

  void _showStep(_ApplicationStep step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      if (step == _ApplicationStep.contact) _contactVisited = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _continue() async {
    if (!_venueComplete || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _blockingSave = true;
      _error = null;
    });
    final saved = await _saveDraft();
    if (!mounted) return;
    setState(() => _blockingSave = false);
    if (!saved || !_venueComplete) {
      revealFormFeedback(this, _scroll);
      return;
    }
    _showStep(_ApplicationStep.contact);
  }

  Future<void> _saveForLater() async {
    if (_busy) return;
    setState(() {
      _blockingSave = true;
      _error = null;
    });
    final saved = await _saveDraft();
    if (!mounted) return;
    setState(() => _blockingSave = false);
    if (!saved) {
      revealFormFeedback(this, _scroll);
      return;
    }
    final app = context.read<AppState>();
    app.say('Draft saved. Find it in the account switcher.');
    app.toFanView();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final draftSaved = await _saveDraft();
    if (!mounted) return;
    if (!draftSaved || _applicationId == null) {
      setState(() => _submitting = false);
      revealFormFeedback(this, _scroll);
      return;
    }

    final app = context.read<AppState>();
    try {
      final revision = await app.repository.submitOrganizationApplication(
        applicationId: _applicationId!,
        expectedRevision: _revision,
      );
      if (!mounted) return;
      setState(() => _revision = revision);
      await app.refreshOrganizationApplication();
      if (!mounted) return;
      app.go(Screen.orgApplicationStatus);
    } catch (error) {
      await _handleMutationError(app, error);
      if (mounted) revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final application = context.watch<AppState>().myOrganizationApplication;
    if (_applicationId == null &&
        !_hasUnsavedChanges &&
        application?.editable == true) {
      _loadApplication(application!);
    }

    if (application != null &&
        application.status != OrganizationApplicationStatus.withdrawn &&
        !application.editable) {
      _scheduleStatusRedirect();
      return const Material(child: Center(child: CircularProgressIndicator()));
    }

    final venueStep = _step == _ApplicationStep.venue;
    final requirements = venueStep ? _venueRequirements : _contactRequirements;
    return Material(
      color: context.epColors.background,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 24),
              children: [
                _header(context),
                if (venueStep)
                  ..._venueFields(context)
                else
                  ..._contactFields(context),
                InlineFormFeedback(
                  error: _error,
                  errorKey: const ValueKey('org-apply-feedback'),
                ),
                if (venueStep &&
                    _contactVisited &&
                    _venueComplete &&
                    _error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('org-apply-edit-contact'),
                      onPressed: _busy
                          ? null
                          : () => _showStep(_ApplicationStep.contact),
                      child: const Text('EDIT CONTACT DETAILS'),
                    ),
                  ),
                if (!venueStep || !_venueComplete) ...[
                  const SizedBox(height: 18),
                  _RequirementsChecklist(requirements: requirements),
                ],
              ],
            ),
          ),
          StickyActionBar(
            key: ValueKey(
              venueStep ? 'org-apply-continue' : 'org-apply-submit',
            ),
            primaryLabel: _blockingSave
                ? 'SAVING…'
                : _submitting
                ? 'SUBMITTING…'
                : venueStep
                ? 'CONTINUE'
                : 'SUBMIT APPLICATION',
            onPrimary: venueStep
                ? (_venueComplete && !_busy ? _continue : null)
                : (_canSubmit ? _submit : null),
            secondaryKey: const ValueKey('org-apply-save'),
            secondaryLabel: 'SAVE FOR LATER',
            onSecondary: _busy ? null : _saveForLater,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final venueStep = _step == _ApplicationStep.venue;
    final colors = context.epColors;
    final textTheme = Theme.of(context).textTheme;
    final saveState = _saveState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleIconButton(
              key: const ValueKey('org-apply-back'),
              icon: venueStep ? Icons.close : Icons.chevron_left,
              tooltip: venueStep ? 'Close' : 'Back to venue',
              onTap: _busy
                  ? null
                  : venueStep
                  ? () => context.read<AppState>().back()
                  : () => _showStep(_ApplicationStep.venue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'BECOME AN ORGANIZER',
                style: textTheme.epPageHeading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    saveState == 'Save failed'
                        ? Icons.error_outline
                        : Icons.circle,
                    size: 10,
                    color: saveState == 'Save failed'
                        ? colors.destructive
                        : saveState == 'Saving…'
                        ? colors.warning
                        : colors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    saveState,
                    key: const ValueKey('org-apply-save-state'),
                    style: textTheme.epCaption,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          venueStep ? 'STEP 1 OF 2 · VENUE' : 'STEP 2 OF 2 · CONTACT',
          key: const ValueKey('org-apply-step'),
          style: textTheme.epLabel.copyWith(color: colors.contentSecondary),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: venueStep ? .5 : 1,
          minHeight: 4,
          borderRadius: BorderRadius.circular(99),
          color: colors.accent,
          backgroundColor: colors.border,
          semanticsLabel: venueStep
              ? 'Step 1 of 2: Venue'
              : 'Step 2 of 2: Contact',
        ),
      ],
    );
  }

  List<Widget> _venueFields(BuildContext context) {
    final enabled = !_busy;
    return [
      const SectionBar(label: 'YOUR VENUE'),
      Focus(
        onFocusChange: (focused) {
          if (!focused) _saveOnBlur();
        },
        child: BandIdentityTextField(
          fieldKey: const ValueKey('org-apply-name'),
          label: 'ORGANIZATION NAME',
          required: true,
          hint: 'Night Heron Club',
          controller: _orgName,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          onChanged: _organizationNameChanged,
        ),
      ),
      const SizedBox(height: 14),
      const FieldLabel('WHAT ARE YOU', required: true),
      const SizedBox(height: 7),
      SegmentedButton<String>(
        expandedInsets: EdgeInsets.zero,
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: 'bar',
            label: Text('BAR', key: ValueKey('org-apply-kind-bar')),
          ),
          ButtonSegment(
            value: 'club',
            label: Text('CLUB', key: ValueKey('org-apply-kind-club')),
          ),
        ],
        selected: {?_kind},
        onSelectionChanged: enabled
            ? (selection) {
                if (selection.isNotEmpty) _selectKind(selection.single);
              }
            : null,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.epLabel,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? context.epColors.surfaceSelected
                : context.epColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? context.epColors.contentDisabled
                : states.contains(WidgetState.selected)
                ? context.epColors.contentPrimary
                : context.epColors.contentSecondary,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: context.epColors.border),
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        'Promoters and student organizations are coming next.',
        style: Theme.of(context).textTheme.epCaption,
      ),
      const SizedBox(height: 14),
      Focus(
        onFocusChange: (focused) {
          if (!focused) _saveOnBlur();
        },
        child: VenueLocationEditor(
          key: ValueKey(_venueEditorGeneration),
          keyPrefix: 'org-apply-venue',
          compactMap: true,
          showNameField: true,
          initial: _venueLocation,
          onChanged: _venueChanged,
          helperText:
              'Fans only ever see the neighborhood. The exact '
              'address stays private.',
          enabled: enabled,
        ),
      ),
      const SizedBox(height: 14),
      EpLabeledField(
        fieldKey: const ValueKey('org-apply-capacity'),
        label: 'CAPACITY · OPTIONAL',
        hint: 'Roughly how many people fit',
        controller: _capacity,
        focusNode: _capacityFocus,
        enabled: enabled,
        keyboardType: TextInputType.number,
        onChanged: _textChanged,
        onEditingComplete: _saveOnBlur,
      ),
    ];
  }

  List<Widget> _contactFields(BuildContext context) {
    final enabled = !_busy;
    return [
      const SectionBar(label: 'CONTACT'),
      EpLabeledField(
        fieldKey: const ValueKey('org-apply-contact-name'),
        label: 'CONTACT NAME',
        required: true,
        hint: 'Who should we contact?',
        controller: _contactName,
        focusNode: _contactNameFocus,
        enabled: enabled,
        textCapitalization: TextCapitalization.words,
        onChanged: _textChanged,
        onEditingComplete: _saveOnBlur,
      ),
      const SizedBox(height: 14),
      EpLabeledField(
        fieldKey: const ValueKey('org-apply-email'),
        label: 'BUSINESS EMAIL',
        required: true,
        hint: 'bookings@example.com',
        controller: _businessEmail,
        focusNode: _businessEmailFocus,
        enabled: enabled,
        keyboardType: TextInputType.emailAddress,
        onChanged: _textChanged,
        onEditingComplete: _saveOnBlur,
      ),
      const SizedBox(height: 14),
      EpLabeledField(
        fieldKey: const ValueKey('org-apply-phone'),
        label: 'PHONE · OPTIONAL',
        hint: '(415) 555-0101',
        controller: _phone,
        focusNode: _phoneFocus,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        onChanged: _textChanged,
        onEditingComplete: _saveOnBlur,
      ),
      const SizedBox(height: 14),
      EpLabeledField(
        fieldKey: const ValueKey('org-apply-website'),
        label: 'WEBSITE · OPTIONAL',
        hint: 'https://…',
        controller: _website,
        focusNode: _websiteFocus,
        enabled: enabled,
        keyboardType: TextInputType.url,
        onChanged: _textChanged,
        onEditingComplete: _saveOnBlur,
      ),
      SectionBar(label: 'VERIFICATION', count: _documents.length),
      if (_documents.isNotEmpty) ...[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final document in _documents)
              _DocumentTile(
                document: document,
                enabled: enabled,
                onRemove: () => _removeDocument(document),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (_documents.length < 5)
        _AddDocumentTile(enabled: enabled, onTap: _addDocument),
      const SizedBox(height: 14),
      Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          key: const ValueKey('org-apply-agree'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agreed,
          onChanged: enabled
              ? (value) => setState(() => _agreed = value ?? false)
              : null,
          title: const Text(
            'I confirm this information is accurate and accept the '
            'Organizer Agreement.',
          ),
        ),
      ),
    ];
  }
}

class _RequirementsChecklist extends StatelessWidget {
  const _RequirementsChecklist({required this.requirements});
  final List<({String label, bool complete})> requirements;

  @override
  Widget build(BuildContext context) {
    final completed = requirements.where((item) => item.complete).length;
    return Column(
      key: const ValueKey('org-apply-missing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          completed == requirements.length
              ? 'READY TO SUBMIT'
              : '$completed OF ${requirements.length} COMPLETE',
          style: Theme.of(context).textTheme.epLabel.copyWith(
            color: context.epColors.contentSecondary,
          ),
        ),
        for (final item in requirements.where((item) => !item.complete))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.radio_button_unchecked,
                  size: 16,
                  color: context.epColors.contentDisabled,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.enabled,
    required this.onRemove,
  });

  final ApplicationDocument document;
  final bool enabled;
  final VoidCallback onRemove;

  bool get _isImage {
    if (document.contentType?.startsWith('image/') == true) return true;
    final path = Uri.tryParse(document.url ?? '')?.path.toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|gif|webp|heic)$').hasMatch(path);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: context.epColors.surface,
      child: Icon(
        _isImage ? Icons.image_outlined : Icons.description_outlined,
        color: context.epColors.contentSecondary,
        size: 30,
      ),
    );
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _isImage
                  ? EpNetworkImage(
                      url: document.url,
                      fallback: fallback,
                      cacheWidth: 92,
                      cacheHeight: 92,
                    )
                  : fallback,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filled(
              key: ValueKey('org-apply-doc-remove-${document.storageId}'),
              tooltip: 'Remove document',
              onPressed: enabled ? onRemove : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              icon: const Icon(Icons.close, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddDocumentTile extends StatelessWidget {
  const _AddDocumentTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      key: const ValueKey('org-apply-doc-add'),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.add_a_photo_outlined,
                  color: enabled
                      ? context.epColors.accent
                      : context.epColors.contentDisabled,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a verification photo',
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Business license, lease, or utility bill. Visible to reviewers only.',
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
