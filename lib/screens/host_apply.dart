import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../services/media_upload_service.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/application_document_tiles.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/form_bits.dart';

class HostApplyScreen extends StatefulWidget {
  const HostApplyScreen({super.key, this.mediaPicker, this.launch});

  final MediaPicker? mediaPicker;
  final ExternalUrlLauncher? launch;

  @override
  State<HostApplyScreen> createState() => _HostApplyScreenState();
}

class _HostApplyScreenState extends State<HostApplyScreen> {
  static const _autosaveDelay = Duration(milliseconds: 600);

  final _scroll = ScrollController();
  final _agreementRecognizer = TapGestureRecognizer();
  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _email = TextEditingController();
  final _displayNameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _areaFocus = FocusNode();
  final _emailFocus = FocusNode();

  late final MediaPicker _mediaPicker;
  String? _applicationId;
  int _revision = 0;
  List<ApplicationDocument> _documents = const [];
  bool _agreed = false;
  bool _applicationLoaded = false;
  bool _emailPrefilled = false;
  bool _redirected = false;
  Timer? _autosaveTimer;
  Completer<bool>? _saveCompleter;
  bool _saveRequested = false;
  bool _savingDraft = false;
  bool _draftSaveFailed = false;
  bool _documentWorking = false;
  bool _submitting = false;
  int _editVersion = 0;
  int _savedVersion = 0;
  String? _error;

  bool get _hasUnsavedChanges => _editVersion > _savedVersion;
  bool get _busy => _documentWorking || _submitting;
  bool get _canSubmit =>
      _displayName.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty &&
      _area.text.trim().isNotEmpty &&
      _email.text.contains('@') &&
      _documents.isNotEmpty &&
      _agreed &&
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
    _agreementRecognizer.onTap = () => openExternalForUser(
      context,
      legalHostAgreementUrl,
      launch: widget.launch,
    );
    for (final node in [
      _displayNameFocus,
      _phoneFocus,
      _areaFocus,
      _emailFocus,
    ]) {
      node.addListener(_saveOnBlur);
    }
    final app = context.read<AppState>();
    final application = app.myOrganizationApplication;
    if (application == null) {
      unawaited(_refreshApplication(app));
    } else {
      _applicationLoaded = true;
      if (application.kind == ApplicationKind.host && application.editable) {
        _loadApplication(application);
      }
    }
  }

  Future<void> _refreshApplication(AppState app) async {
    await app.refreshOrganizationApplication();
    if (mounted) setState(() => _applicationLoaded = true);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _agreementRecognizer.dispose();
    _scroll.dispose();
    _displayName.dispose();
    _phone.dispose();
    _area.dispose();
    _email.dispose();
    _displayNameFocus.dispose();
    _phoneFocus.dispose();
    _areaFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _loadApplication(OrganizationApplication application) {
    _autosaveTimer?.cancel();
    _applicationId = application.id;
    _revision = application.revision;
    _displayName.text = application.hostDisplayName ?? '';
    _phone.text = application.hostPhone ?? '';
    _area.text = application.hostArea ?? '';
    _email.text = application.businessEmail;
    _agreed = application.hostAgreementAcceptedAt != null;
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
      context.read<AppState>().resetTo(Screen.orgApplicationStatus);
    });
  }

  void _changed(VoidCallback update) {
    setState(() {
      update();
      _editVersion++;
    });
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () => unawaited(_saveDraft()));
  }

  void _textChanged([String? _]) => _changed(() {});

  void _saveOnBlur() {
    if (_hasUnsavedChanges) unawaited(_saveDraft());
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
    final application = app.myOrganizationApplication;
    if (application != null &&
        (_pendingOrganizerApplication(application) ||
            (application.kind == ApplicationKind.host &&
                !application.editable &&
                application.status !=
                    OrganizationApplicationStatus.withdrawn))) {
      return false;
    }
    try {
      final saved = await app.repository.saveOrganizationApplicationDraft(
        applicationId: _applicationId,
        expectedRevision: _applicationId == null ? null : _revision,
        kind: ApplicationKind.host,
        orgType: OrganizationType.privateHost,
        orgName: _displayName.text.trim(),
        contactName: _displayName.text.trim(),
        businessEmail: _email.text.trim(),
        phone: _phone.text.trim(),
        hostDisplayName: _displayName.text.trim(),
        hostPhone: _phone.text.trim(),
        hostArea: _area.text.trim(),
        hostAgreementAccepted: _agreed,
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
    final message = stripErrorPrefix(error);
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
          _documents = const [];
        } else if (current.kind == ApplicationKind.host && current.editable) {
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
      final storageId = await uploadApplicationDocument(
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
      app.resetTo(Screen.orgApplicationStatus);
    } catch (error) {
      await _handleMutationError(app, error);
      if (mounted) revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final application = app.myOrganizationApplication;
    if (application != null && _pendingOrganizerApplication(application)) {
      return Material(
        color: context.epColors.background,
        child: _ApplicationNotice(
          message: 'You already have an organizer application in progress.',
          action: 'OPEN APPLICATION',
          onTap: () => app.go(Screen.orgApplicationStatus),
        ),
      );
    }
    if (application?.kind == ApplicationKind.host &&
        !application!.editable &&
        application.status != OrganizationApplicationStatus.withdrawn) {
      _scheduleStatusRedirect();
      return Material(
        color: context.epColors.background,
        child: const Center(child: Text('Opening application…')),
      );
    }
    if (_applicationId == null &&
        !_hasUnsavedChanges &&
        application?.kind == ApplicationKind.host &&
        application!.editable) {
      _loadApplication(application);
    }
    // Wait for the initial application lookup before using the profile email.
    // A saved draft owns its email, even when that value is empty.
    if (_applicationLoaded &&
        application == null &&
        !_emailPrefilled &&
        app.profile?.email != null) {
      if (_email.text.isEmpty) _email.text = app.profile!.email;
      _emailPrefilled = true;
    }

    final enabled = !_busy;
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
                const EpSectionHeader.form(label: 'YOUR DETAILS'),
                EpLabeledField(
                  fieldKey: const ValueKey('host-apply-display-name'),
                  label: 'DISPLAY NAME',
                  required: true,
                  hint: 'Your name',
                  controller: _displayName,
                  focusNode: _displayNameFocus,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  onChanged: _textChanged,
                  onEditingComplete: _saveOnBlur,
                ),
                const SizedBox(height: EpLayout.fieldGap),
                EpLabeledField(
                  fieldKey: const ValueKey('host-apply-phone'),
                  label: 'PHONE',
                  required: true,
                  hint: '(415) 555-0101',
                  controller: _phone,
                  focusNode: _phoneFocus,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  onChanged: _textChanged,
                  onEditingComplete: _saveOnBlur,
                ),
                const SizedBox(height: EpLayout.fieldGap),
                EpLabeledField(
                  fieldKey: const ValueKey('host-apply-area'),
                  label: 'AREA',
                  required: true,
                  hint: 'Mission District, San Francisco',
                  controller: _area,
                  focusNode: _areaFocus,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  onChanged: _textChanged,
                  onEditingComplete: _saveOnBlur,
                ),
                const SizedBox(height: EpLayout.fieldGap),
                EpLabeledField(
                  fieldKey: const ValueKey('host-apply-email'),
                  label: 'EMAIL',
                  required: true,
                  hint: 'you@example.com',
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: enabled,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _textChanged,
                  onEditingComplete: _saveOnBlur,
                ),
                EpSectionHeader.form(
                  label: 'ID DOCUMENT',
                  count: _documents.length,
                ),
                if (_documents.isNotEmpty) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final document in _documents)
                        ApplicationDocumentTile(
                          document: document,
                          enabled: enabled,
                          onRemove: () => _removeDocument(document),
                          removeKey: ValueKey(
                            'host-apply-doc-remove-${document.storageId}',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_documents.length < 5)
                  AddApplicationDocumentTile(
                    tileKey: const ValueKey('host-apply-doc-add'),
                    enabled: enabled,
                    onTap: _addDocument,
                    title: 'ADD ID DOCUMENT',
                    caption: 'A photo of your ID. Visible to reviewers only.',
                  ),
                const SizedBox(height: EpLayout.fieldGap),
                CheckboxListTile(
                  key: const ValueKey('host-apply-agree'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _agreed,
                  onChanged: enabled
                      ? (value) => _changed(() => _agreed = value ?? false)
                      : null,
                  title: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      children: [
                        TextSpan(
                          text: 'Host Agreement',
                          style: TextStyle(
                            color: context.epColors.accent,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: _agreementRecognizer,
                        ),
                        const TextSpan(text: ' and booking protection terms'),
                      ],
                    ),
                  ),
                ),
                InlineFormFeedback(
                  error: _error,
                  errorKey: const ValueKey('host-apply-feedback'),
                ),
              ],
            ),
          ),
          StickyActionBar(
            key: const ValueKey('host-apply-submit'),
            primaryLabel: _submitting ? 'SUBMITTING…' : 'SUBMIT APPLICATION',
            onPrimary: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleIconButton(
              key: const ValueKey('host-apply-back'),
              icon: Icons.close,
              tooltip: 'Close',
              onTap: _busy ? null : () => context.read<AppState>().back(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('BECOME A HOST', style: textTheme.epPageHeading),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Hosts book artists for private events. Artists see your area until '
          'the deposit is paid; your exact address is shared only with the '
          'booked artist.',
          style: textTheme.epBody,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            liveRegion: true,
            child: Text(
              _saveState,
              key: const ValueKey('host-apply-save-state'),
              style: textTheme.epCaption.copyWith(
                color: _draftSaveFailed
                    ? context.epColors.destructive
                    : context.epColors.contentSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApplicationNotice extends StatelessWidget {
  const _ApplicationNotice({
    required this.message,
    required this.action,
    required this.onTap,
  });

  final String message;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epBody,
            ),
            const SizedBox(height: 18),
            EpButton(action, onTap: onTap),
          ],
        ),
      ),
    );
  }
}

/// An organizer application still under way blocks a host application; a
/// decided (approved or rejected) or withdrawn one does not, because the
/// backend keeps one open application per person and reports the newest.
bool _pendingOrganizerApplication(OrganizationApplication application) =>
    application.kind != ApplicationKind.host &&
    switch (application.status) {
      OrganizationApplicationStatus.draft ||
      OrganizationApplicationStatus.submitted ||
      OrganizationApplicationStatus.underReview ||
      OrganizationApplicationStatus.needsInfo => true,
      OrganizationApplicationStatus.approved ||
      OrganizationApplicationStatus.rejected ||
      OrganizationApplicationStatus.withdrawn => false,
    };
