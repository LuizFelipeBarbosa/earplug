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
  const OrgSettingsScreen({super.key});

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  final MediaPicker _mediaPicker = MediaPicker();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _legalName = TextEditingController();
  final TextEditingController _businessEmail = TextEditingController();
  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final List<({String storageId, PickedMedia media})> _sessionPhotos = [];

  OrganizationDashboard? _dashboard;
  List<String> _existingPhotoUrls = const [];
  Object? _error;
  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPrivate = false;
  bool _addingPhoto = false;
  bool _savingPhotos = false;
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _dashboard = null;
    _existingPhotoUrls = const [];
    _sessionPhotos.clear();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _website.dispose();
    _legalName.dispose();
    _businessEmail.dispose();
    _contactName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveOriginalPhotos = false}) async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      final organization = dashboard.organization;
      final privateDetails = dashboard.privateDetails;
      _name.text = organization.name;
      _description.text = organization.description ?? '';
      _website.text = organization.website ?? '';
      _legalName.text = privateDetails?.legalName ?? '';
      _businessEmail.text = privateDetails?.businessEmail ?? '';
      _contactName.text = privateDetails?.contactName ?? '';
      _phone.text = privateDetails?.phone ?? '';
      setState(() {
        _dashboard = dashboard;
        if (!preserveOriginalPhotos) {
          _existingPhotoUrls = List.of(organization.photoUrls);
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    final app = context.read<AppState>();
    setState(() => _savingProfile = true);
    try {
      await app.repository.updateOrganizationProfile(
        organizationId: app.organizationId,
        name: _name.text.trim(),
        description: _description.text.trim(),
        website: _website.text.trim(),
      );
      await _load(preserveOriginalPhotos: true);
      if (mounted) app.say('Organization profile saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePrivate() async {
    if (_savingPrivate) return;
    final app = context.read<AppState>();
    setState(() => _savingPrivate = true);
    try {
      await app.repository.updateOrganizationPrivateDetails(
        organizationId: app.organizationId,
        legalName: _legalName.text.trim(),
        businessEmail: _businessEmail.text.trim(),
        contactName: _contactName.text.trim(),
        phone: _phone.text.trim(),
      );
      await _load(preserveOriginalPhotos: true);
      if (mounted) app.say('Private details saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingPrivate = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_addingPhoto ||
        _existingPhotoUrls.length + _sessionPhotos.length >= 10) {
      return;
    }
    setState(() => _addingPhoto = true);
    final app = context.read<AppState>();
    try {
      final media = await _mediaPicker.pickPhoto();
      if (media == null || !mounted) return;
      final storageId = await _uploadOrganizationPhoto(
        app: app,
        organizationId: app.organizationId,
        media: media,
      );
      if (!mounted) return;
      setState(() => _sessionPhotos.add((storageId: storageId, media: media)));
      app.say('Photo ready to save.');
    } catch (_) {
      if (mounted) app.say('Could not upload the photo. Please retry.');
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  Future<void> _savePhotos() async {
    if (_savingPhotos) return;
    final app = context.read<AppState>();
    setState(() => _savingPhotos = true);
    try {
      await app.repository.setOrganizationPhotos(
        organizationId: app.organizationId,
        storageIds: [for (final photo in _sessionPhotos) photo.storageId],
      );
      if (mounted) app.say('Organization photos saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingPhotos = false);
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

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('ORGANIZATION SETTINGS', style: epDisplay(size: 22)),
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
        else if (_error != null)
          _LoadError(onRetry: _load)
        else if (dashboard != null) ...[
          FormSection(
            title: 'Public profile',
            description: 'These details are visible to artists and fans.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('org-settings-name'),
                  controller: _name,
                  enabled: canManage,
                  decoration: labeledInputDecoration(
                    context,
                    'Organization name',
                    'Organization name',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('org-settings-description'),
                  controller: _description,
                  enabled: canManage,
                  minLines: 3,
                  maxLines: 6,
                  decoration: labeledInputDecoration(
                    context,
                    'Description',
                    'About the organization',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('org-settings-website'),
                  controller: _website,
                  enabled: canManage,
                  keyboardType: TextInputType.url,
                  decoration: labeledInputDecoration(
                    context,
                    'Website',
                    'https://',
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 12),
                  EpButton(
                    _savingProfile ? 'SAVING…' : 'SAVE PUBLIC PROFILE',
                    key: const Key('org-settings-save-profile'),
                    kind: _savingProfile
                        ? EpButtonKind.disabled
                        : EpButtonKind.filled,
                    onTap: _savingProfile ? null : _saveProfile,
                  ),
                ],
              ],
            ),
          ),
          FormSection(
            title: 'Photos',
            description:
                'Current photos are shown below. Re-saving only keeps photos added in this session because existing photo storage IDs are not available.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_existingPhotoUrls.isNotEmpty) ...[
                  Text(
                    'CURRENT PHOTOS',
                    style: Theme.of(context).textTheme.epLabel.copyWith(
                      fontSize: 11,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
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
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_sessionPhotos.isNotEmpty) ...[
                  Text(
                    'ADDED THIS SESSION',
                    style: Theme.of(context).textTheme.epLabel.copyWith(
                      fontSize: 11,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final photo in _sessionPhotos)
                        _PhotoTile(
                          child: Image.memory(
                            photo.media.bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (canManage) ...[
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
                  const SizedBox(height: 8),
                  EpButton(
                    _savingPhotos ? 'SAVING…' : 'SAVE PHOTOS',
                    key: const Key('org-settings-save-photos'),
                    kind: _savingPhotos
                        ? EpButtonKind.disabled
                        : EpButtonKind.outline,
                    onTap: _savingPhotos ? null : _savePhotos,
                  ),
                ],
              ],
            ),
          ),
          if (isOwner)
            FormSection(
              title: 'Private details',
              description:
                  'Business and contact information is visible only to authorized operations.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('org-settings-legal-name'),
                    controller: _legalName,
                    decoration: labeledInputDecoration(
                      context,
                      'Legal name',
                      'Optional',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('org-settings-business-email'),
                    controller: _businessEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: labeledInputDecoration(
                      context,
                      'Business email',
                      'name@example.com',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('org-settings-contact-name'),
                    controller: _contactName,
                    decoration: labeledInputDecoration(
                      context,
                      'Contact name',
                      'Primary contact',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('org-settings-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: labeledInputDecoration(
                      context,
                      'Phone',
                      'Optional',
                    ),
                  ),
                  const SizedBox(height: 12),
                  EpButton(
                    _savingPrivate ? 'SAVING…' : 'SAVE PRIVATE DETAILS',
                    key: const Key('org-settings-save-private'),
                    kind: _savingPrivate
                        ? EpButtonKind.disabled
                        : EpButtonKind.filled,
                    onTap: _savingPrivate ? null : _savePrivate,
                  ),
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
        ],
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
