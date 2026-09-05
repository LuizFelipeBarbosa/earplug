import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/slot_card.dart';

class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({super.key, this.mediaPicker});

  final MediaPicker? mediaPicker;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  final _scrollController = ScrollController();
  late final MediaPicker _mediaPicker = widget.mediaPicker ?? MediaPicker();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _legalName = TextEditingController();
  final TextEditingController _businessEmail = TextEditingController();
  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final List<PickedMedia> _sessionPhotos = [];

  OrganizationDashboard? _dashboard;
  List<String> _existingPhotoUrls = const [];
  Object? _loadError;
  String? _saveError;
  String? _stripeError;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  bool _addingPhoto = false;
  String? _loadedOrganizationId;

  String _loadedName = '';
  String _loadedDescription = '';
  String _loadedWebsite = '';
  String _loadedLegalName = '';
  String _loadedBusinessEmail = '';
  String _loadedContactName = '';
  String _loadedPhone = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _dashboard = null;
    _existingPhotoUrls = const [];
    _sessionPhotos.clear();
    _saveError = null;
    _stripeError = null;
    _saved = false;
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || app.organizationId != organizationId) return;
      unawaited(app.refreshOrganizationStripeStatus());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _name.dispose();
    _description.dispose();
    _website.dispose();
    _legalName.dispose();
    _businessEmail.dispose();
    _contactName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seedDashboard(
    OrganizationDashboard dashboard, {
    required bool preserveOriginalPhotos,
  }) {
    final organization = dashboard.organization;
    final privateDetails = dashboard.privateDetails;
    final name = organization.name;
    final description = organization.description ?? '';
    final website = organization.website ?? '';
    final legalName = privateDetails?.legalName ?? '';
    final businessEmail = privateDetails?.businessEmail ?? '';
    final contactName = privateDetails?.contactName ?? '';
    final phone = privateDetails?.phone ?? '';

    _dashboard = dashboard;
    _name.text = name;
    _description.text = description;
    _website.text = website;
    _legalName.text = legalName;
    _businessEmail.text = businessEmail;
    _contactName.text = contactName;
    _phone.text = phone;
    _loadedName = name;
    _loadedDescription = description;
    _loadedWebsite = website;
    _loadedLegalName = legalName;
    _loadedBusinessEmail = businessEmail;
    _loadedContactName = contactName;
    _loadedPhone = phone;
    if (!preserveOriginalPhotos) {
      _existingPhotoUrls = List.of(organization.photoUrls);
    }
  }

  Future<void> _load({bool preserveOriginalPhotos = false}) async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _seedDashboard(
          dashboard,
          preserveOriginalPhotos: preserveOriginalPhotos,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _runStripeAction(Future<void> Function() action) async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() => _stripeError = null);
    try {
      await action();
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() => _stripeError = error.toString());
    }
  }

  ({bool publicProfile, bool privateDetails}) get _changesSinceLoad => (
    publicProfile:
        _name.text != _loadedName ||
        _description.text != _loadedDescription ||
        _website.text != _loadedWebsite,
    privateDetails:
        _legalName.text != _loadedLegalName ||
        _businessEmail.text != _loadedBusinessEmail ||
        _contactName.text != _loadedContactName ||
        _phone.text != _loadedPhone,
  );

  void _draftChanged(String _) {
    if (!_saved && _saveError == null) return;
    setState(() {
      _saved = false;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    final role = app.organizerRoleFor(organizationId) ?? _dashboard?.role;
    final isOwner = role == OrganizationRole.owner;
    final changes = _changesSinceLoad;

    setState(() {
      _saving = true;
      _saved = false;
      _saveError = null;
    });
    try {
      // The public profile is intentionally sent for every save, including a
      // no-op save, while private details only write when their fields changed.
      await app.repository.updateOrganizationProfile(
        organizationId: organizationId,
        name: _name.text.trim(),
        description: _description.text.trim(),
        website: _website.text.trim(),
      );
      if (isOwner && changes.privateDetails) {
        await app.repository.updateOrganizationPrivateDetails(
          organizationId: organizationId,
          legalName: _legalName.text.trim(),
          businessEmail: _businessEmail.text.trim(),
          contactName: _contactName.text.trim(),
          phone: _phone.text.trim(),
        );
      }

      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _seedDashboard(dashboard, preserveOriginalPhotos: true);
        _saved = true;
      });
      revealFormFeedback(this, _scrollController);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saveError =
            'Changes could not be saved. Check your connection and retry.';
      });
      revealFormFeedback(this, _scrollController);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_addingPhoto ||
        _existingPhotoUrls.length + _sessionPhotos.length >= 10) {
      return;
    }
    setState(() => _addingPhoto = true);
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    try {
      final media = await _mediaPicker.pickPhoto();
      if (media == null || !mounted || app.organizationId != organizationId) {
        return;
      }
      final storageId = await _uploadOrganizationPhoto(
        app: app,
        organizationId: organizationId,
        media: media,
      );
      if (!mounted || app.organizationId != organizationId) return;
      await app.repository.addOrganizationPhoto(
        organizationId: organizationId,
        storageId: storageId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() => _sessionPhotos.add(media));
      app.say('Organization photo saved.');
    } catch (_) {
      if (mounted) app.say('Could not upload the photo. Please retry.');
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  void _confirmDeactivate() {
    final app = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (_) =>
          _DeactivateOrganizationDialog(organizationId: app.organizationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dashboard = _dashboard;
    final role = app.organizerRoleFor(app.organizationId) ?? dashboard?.role;
    final canManage =
        role == OrganizationRole.owner || role == OrganizationRole.manager;
    final isOwner = role == OrganizationRole.owner;

    final listView = ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          'ORGANIZATION SETTINGS',
          style: Theme.of(context).textTheme.epPageHeading,
        ),
        const SizedBox(height: 4),
        Text(
          'Update the organization profile and private business details.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          _LoadError(onRetry: _load)
        else if (dashboard != null) ...[
          FormSection(
            title: 'Public profile',
            description: 'These details are visible to artists and fans.',
            boxed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EpLabeledField(
                  label: 'NAME',
                  hint: 'Organization name',
                  fieldKey: const Key('org-settings-name'),
                  controller: _name,
                  required: true,
                  enabled: canManage,
                  onChanged: _draftChanged,
                ),
                const SizedBox(height: 12),
                EpLabeledField(
                  label: 'ABOUT',
                  hint: 'About the organization',
                  fieldKey: const Key('org-settings-description'),
                  controller: _description,
                  enabled: canManage,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: _draftChanged,
                ),
                const SizedBox(height: 12),
                EpLabeledField(
                  label: 'WEBSITE',
                  hint: 'https://',
                  fieldKey: const Key('org-settings-website'),
                  controller: _website,
                  enabled: canManage,
                  keyboardType: TextInputType.url,
                  onChanged: _draftChanged,
                ),
              ],
            ),
          ),
          FormSection(
            title: 'Photos',
            description: 'Add up to 10 photos of your organization.',
            boxed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_existingPhotoUrls.isNotEmpty ||
                    _sessionPhotos.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final url in _existingPhotoUrls)
                        _PhotoTile(
                          child: EpNetworkImage(
                            url: url,
                            cacheWidth: 110,
                            cacheHeight: 90,
                            fallback: const Icon(Icons.photo_outlined),
                          ),
                        ),
                      for (final photo in _sessionPhotos)
                        _PhotoTile(
                          child: Image.memory(
                            photo.bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (canManage)
                  SlotShell(
                    key: const Key('org-settings-add-photo'),
                    state: SlotState.needed,
                    onTap:
                        _addingPhoto ||
                            _existingPhotoUrls.length + _sessionPhotos.length >=
                                10
                        ? null
                        : _addPhoto,
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color:
                              _existingPhotoUrls.length +
                                      _sessionPhotos.length >=
                                  10
                              ? context.epColors.contentDisabled
                              : context.epColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _addingPhoto ? 'ADDING…' : 'ADD PHOTO',
                            style: Theme.of(context).textTheme.epLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (isOwner)
            FormSection(
              title: 'Private details',
              description: 'Only EarPlug and your team see these.',
              boxed: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EpLabeledField(
                    label: 'LEGAL NAME',
                    hint: 'Optional',
                    fieldKey: const Key('org-settings-legal-name'),
                    controller: _legalName,
                    enabled: canManage,
                    onChanged: _draftChanged,
                  ),
                  const SizedBox(height: 12),
                  EpLabeledField(
                    label: 'BUSINESS EMAIL',
                    hint: 'name@example.com',
                    fieldKey: const Key('org-settings-business-email'),
                    controller: _businessEmail,
                    enabled: canManage,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _draftChanged,
                  ),
                  const SizedBox(height: 12),
                  EpLabeledField(
                    label: 'CONTACT NAME',
                    hint: 'Primary contact',
                    fieldKey: const Key('org-settings-contact-name'),
                    controller: _contactName,
                    enabled: canManage,
                    onChanged: _draftChanged,
                  ),
                  const SizedBox(height: 12),
                  EpLabeledField(
                    label: 'PHONE',
                    hint: 'Optional',
                    fieldKey: const Key('org-settings-phone'),
                    controller: _phone,
                    enabled: canManage,
                    keyboardType: TextInputType.phone,
                    onChanged: _draftChanged,
                  ),
                ],
              ),
            ),
          if (isOwner)
            FormSection(
              title: 'Stripe',
              description:
                  'Needed to sell tickets later; bookings are paid to EarPlug.',
              boxed: false,
              child: Column(
                key: const Key('org-settings-stripe'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(switch (app.organizationStripeStatus?.state) {
                    StripeAccountState.enabled => 'Connected',
                    StripeAccountState.onboarding => 'Setup in progress',
                    StripeAccountState.restricted => 'Needs information',
                    _ => 'Not connected',
                  }, style: Theme.of(context).textTheme.epBody),
                  if (app.organizationStripeStatus?.state ==
                      StripeAccountState.restricted)
                    for (final requirement
                        in app.organizationStripeStatus!.requirementsDue)
                      Text(
                        requirement,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                  const SizedBox(height: 12),
                  if (app.organizationStripeStatus?.state ==
                      StripeAccountState.enabled)
                    EpButton(
                      'OPEN STRIPE DASHBOARD',
                      key: const Key('org-settings-stripe-dashboard'),
                      onTap: () => _runStripeAction(
                        app.openOrganizationExpressDashboard,
                      ),
                    )
                  else
                    EpButton(
                      switch (app.organizationStripeStatus?.state) {
                        StripeAccountState.onboarding ||
                        StripeAccountState.restricted => 'CONTINUE SETUP',
                        _ => 'SET UP STRIPE',
                      },
                      key: const Key('org-settings-stripe-setup'),
                      onTap: () => _runStripeAction(() async {
                        await app.startOrganizationOnboarding();
                        await app.refreshOrganizationStripeStatus();
                      }),
                    ),
                  const SizedBox(height: 8),
                  EpButton(
                    'REFRESH',
                    key: const Key('org-settings-stripe-refresh'),
                    kind: EpButtonKind.outline,
                    onTap: () =>
                        _runStripeAction(app.refreshOrganizationStripeStatus),
                  ),
                  if (_stripeError != null) ...[
                    const SizedBox(height: 8),
                    InlineFormFeedback(
                      error: _stripeError,
                      errorKey: const Key('org-settings-stripe-error'),
                    ),
                  ],
                ],
              ),
            ),
          if (canManage) ...[
            const SectionBar(label: 'DANGER ZONE'),
            EpCard(
              variant: EpCardVariant.raised,
              child: DangerZone(
                key: const Key('org-settings-deactivate'),
                label: 'Deactivate organization',
                consequence:
                    'Deactivation removes the organization from active marketplace management.',
                onPressed: _confirmDeactivate,
              ),
            ),
          ],
          if (_saveError != null || _saved) ...[
            const SizedBox(height: 16),
            InlineFormFeedback(
              error: _saveError,
              success: _saved ? 'Changes saved.' : null,
              errorKey: const Key('org-settings-save-error'),
              successKey: const Key('org-settings-save-success'),
            ),
          ],
        ],
      ],
    );

    if (!canManage || dashboard == null || _loading || _loadError != null) {
      return listView;
    }
    return Stack(
      children: [
        Positioned.fill(child: listView),
        Positioned(
          left: 0,
          right: 0,
          bottom: 66,
          child: StickyActionBar(
            key: const Key('org-settings-save'),
            primaryLabel: _saving ? 'SAVING…' : 'SAVE CHANGES',
            onPrimary: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: context.epColors.surface,
        child: SizedBox(width: 104, height: 82, child: Center(child: child)),
      ),
    );
  }
}

class _DeactivateOrganizationDialog extends StatefulWidget {
  const _DeactivateOrganizationDialog({required this.organizationId});

  final String organizationId;

  @override
  State<_DeactivateOrganizationDialog> createState() =>
      _DeactivateOrganizationDialogState();
}

class _DeactivateOrganizationDialogState
    extends State<_DeactivateOrganizationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == 'DEACTIVATE';
    return AlertDialog(
      title: const Text('DEACTIVATE ORGANIZATION?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This removes the organization from active marketplace management.',
          ),
          const SizedBox(height: 14),
          const Text('Type DEACTIVATE to confirm.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('org-settings-deactivate-confirmation'),
            controller: _controller,
            enabled: !_working,
            onChanged: (_) => setState(() {}),
            decoration: epInputDecoration(context, 'DEACTIVATE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('KEEP ORGANIZATION'),
        ),
        FilledButton(
          onPressed: !matches || _working ? null : _deactivate,
          style: FilledButton.styleFrom(
            backgroundColor: context.epColors.destructive,
            foregroundColor: context.epColors.dark,
          ),
          child: Text(_working ? 'DEACTIVATING…' : 'DEACTIVATE'),
        ),
      ],
    );
  }

  Future<void> _deactivate() async {
    final app = context.read<AppState>();
    setState(() => _working = true);
    try {
      await app.repository.deactivateOrganization(widget.organizationId);
      if (!mounted) return;
      Navigator.pop(context);
      app.toFanView();
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      app.say('Could not deactivate. Please retry.');
    }
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          const Text('Could not load organization settings.'),
          const SizedBox(height: 12),
          EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ),
    );
  }
}

int _demoOrganizationPhotoCounter = 0;

Future<String> _uploadOrganizationPhoto({
  required AppState app,
  required String organizationId,
  required PickedMedia media,
}) async {
  final uploadUri = Uri.parse(
    await app.repository.generateOrganizationPhotoUploadUrl(organizationId),
  );
  if (uploadUri.scheme == 'demo') {
    return 'demo-organization-storage-${++_demoOrganizationPhotoCounter}';
  }

  final response = await http.post(
    uploadUri,
    headers: {'Content-Type': media.contentType},
    body: media.bytes,
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final body = response.body.length > 200
        ? response.body.substring(0, 200)
        : response.body;
    final detail = body.isEmpty ? '' : ': $body';
    throw StateError('Upload failed with status ${response.statusCode}$detail');
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map || decoded['storageId'] is! String) {
    throw const FormatException('Upload response did not include storageId.');
  }
  return decoded['storageId'] as String;
}
