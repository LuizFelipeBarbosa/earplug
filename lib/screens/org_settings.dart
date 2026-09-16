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
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/org_team_panel.dart';
import '../widgets/sheets.dart';
import '../widgets/slot_card.dart';

const _maxPhotos = 10;
const _descriptionMaxLength = 1000;

/// The ORGANIZATION hub: hairline rows under micro-labels, each editing in a
/// focused sheet that persists only its own field. Hosts reach the same
/// screen from their own tab; only the tab label differs.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({super.key, this.mediaPicker});

  final MediaPicker? mediaPicker;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  late final MediaPicker _mediaPicker = widget.mediaPicker ?? MediaPicker();
  final List<PickedMedia> _sessionPhotos = [];

  /// Bumped whenever the photo set changes so the open photos sheet, which
  /// lives on its own route, re-renders from this state.
  final _photosRevision = ValueNotifier<int>(0);

  OrganizationDashboard? _dashboard;
  List<String> _existingPhotoUrls = const [];
  Object? _loadError;
  String? _stripeError;
  bool _loading = true;
  bool _addingPhoto = false;
  String? _loadedOrganizationId;

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
    _stripeError = null;
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || app.organizationId != organizationId) return;
      unawaited(app.refreshOrganizationStripeStatus());
    });
  }

  @override
  void dispose() {
    _photosRevision.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
        _dashboard = dashboard;
        _existingPhotoUrls = List.of(dashboard.organization.photoUrls);
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

  /// Re-reads the dashboard after a sheet saved; photos added this session
  /// stay as previews until the next full load.
  Future<void> _reloadAfterSave() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    final dashboard = await app.repository.organizationDashboard(
      organizationId,
    );
    if (!mounted || app.organizationId != organizationId) return;
    setState(() => _dashboard = dashboard);
  }

  // ------------------------------ saving ------------------------------

  Future<void> _saveProfile({
    String? name,
    String? description,
    String? website,
  }) async {
    final app = context.read<AppState>();
    final organization = _dashboard!.organization;
    await app.repository.updateOrganizationProfile(
      organizationId: app.organizationId,
      name: name ?? organization.name,
      description: description ?? organization.description ?? '',
      website: website ?? organization.website ?? '',
    );
    await _reloadAfterSave();
  }

  Future<void> _savePrivateDetails({
    String? legalName,
    String? businessEmail,
    String? contactName,
    String? phone,
  }) async {
    final app = context.read<AppState>();
    final current = _dashboard!.privateDetails;
    await app.repository.updateOrganizationPrivateDetails(
      organizationId: app.organizationId,
      legalName: legalName ?? current?.legalName ?? '',
      businessEmail: businessEmail ?? current?.businessEmail ?? '',
      contactName: contactName ?? current?.contactName ?? '',
      phone: phone ?? current?.phone ?? '',
    );
    await _reloadAfterSave();
  }

  Future<void> _openEditSheet({
    required String field,
    required String title,
    required List<_EditField> fields,
    required Future<void> Function(List<String> values) onSave,
  }) {
    final app = context.read<AppState>();
    return showEpSheet(
      context,
      (_) => _EditSheet(
        key: Key('org-hub-sheet-$field'),
        title: title,
        fields: fields,
        onSave: (values) async {
          await onSave(values);
          app.say('Changes saved.');
        },
      ),
    );
  }

  void _editName() {
    final organization = _dashboard!.organization;
    _openEditSheet(
      field: 'name',
      title: 'Name',
      fields: [
        _EditField(
          label: 'NAME',
          hint: 'Organization name',
          fieldKey: const Key('org-settings-name'),
          initial: organization.name,
          required: true,
        ),
      ],
      onSave: (values) => _saveProfile(name: values[0]),
    );
  }

  void _editAbout() {
    final organization = _dashboard!.organization;
    _openEditSheet(
      field: 'about',
      title: 'About',
      fields: [
        _EditField(
          label: 'ABOUT',
          hint: 'About the organization',
          fieldKey: const Key('org-settings-description'),
          initial: organization.description ?? '',
          minLines: 4,
          maxLines: 8,
          maxLength: _descriptionMaxLength,
        ),
      ],
      onSave: (values) => _saveProfile(description: values[0]),
    );
  }

  void _editWebsite() {
    final organization = _dashboard!.organization;
    _openEditSheet(
      field: 'website',
      title: 'Website',
      fields: [
        _EditField(
          label: 'WEBSITE',
          hint: 'https://',
          fieldKey: const Key('org-settings-website'),
          initial: organization.website ?? '',
          keyboardType: TextInputType.url,
        ),
      ],
      onSave: (values) => _saveProfile(website: values[0]),
    );
  }

  void _editLegalName() {
    final details = _dashboard!.privateDetails;
    _openEditSheet(
      field: 'legal-name',
      title: 'Legal name',
      fields: [
        _EditField(
          label: 'LEGAL NAME',
          hint: 'Optional',
          fieldKey: const Key('org-settings-legal-name'),
          initial: details?.legalName ?? '',
        ),
        _EditField(
          label: 'CONTACT NAME',
          hint: 'Primary contact',
          fieldKey: const Key('org-settings-contact-name'),
          initial: details?.contactName ?? '',
        ),
      ],
      onSave: (values) =>
          _savePrivateDetails(legalName: values[0], contactName: values[1]),
    );
  }

  void _editContactEmail() {
    final details = _dashboard!.privateDetails;
    _openEditSheet(
      field: 'contact-email',
      title: 'Contact email',
      fields: [
        _EditField(
          label: 'CONTACT EMAIL',
          hint: 'name@example.com',
          fieldKey: const Key('org-settings-business-email'),
          initial: details?.businessEmail ?? '',
          keyboardType: TextInputType.emailAddress,
        ),
      ],
      onSave: (values) => _savePrivateDetails(businessEmail: values[0]),
    );
  }

  void _editPhone() {
    final details = _dashboard!.privateDetails;
    _openEditSheet(
      field: 'phone',
      title: 'Phone',
      fields: [
        _EditField(
          label: 'PHONE',
          hint: 'Optional',
          fieldKey: const Key('org-settings-phone'),
          initial: details?.phone ?? '',
          keyboardType: TextInputType.phone,
        ),
      ],
      onSave: (values) => _savePrivateDetails(phone: values[0]),
    );
  }

  // ------------------------------ photos ------------------------------

  int get _photoCount => _existingPhotoUrls.length + _sessionPhotos.length;

  void _openPhotosSheet({required bool canManage}) {
    showEpSheet(
      context,
      (_) => ListenableBuilder(
        listenable: _photosRevision,
        builder: (context, _) => _PhotosSheet(
          key: const Key('org-hub-sheet-photos'),
          existingUrls: _existingPhotoUrls,
          sessionPhotos: _sessionPhotos,
          adding: _addingPhoto,
          onAdd: canManage && !_addingPhoto && _photoCount < _maxPhotos
              ? _addPhoto
              : null,
        ),
      ),
    );
  }

  void _photosChanged(VoidCallback update) {
    setState(update);
    _photosRevision.value++;
  }

  Future<void> _addPhoto() async {
    if (_addingPhoto || _photoCount >= _maxPhotos) return;
    _photosChanged(() => _addingPhoto = true);
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
      _photosChanged(() => _sessionPhotos.add(media));
      app.say('Organization photo saved.');
    } catch (_) {
      if (mounted) app.say('Could not upload the photo. Please retry.');
    } finally {
      if (mounted) _photosChanged(() => _addingPhoto = false);
    }
  }

  // ------------------------------ finance ------------------------------

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

  void _confirmDeactivate() {
    final app = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (_) =>
          _DeactivateOrganizationDialog(organizationId: app.organizationId),
    );
  }

  // ------------------------------ build ------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dashboard = _dashboard;
    final organizationId = app.organizationId;
    final role = app.organizerRoleFor(organizationId) ?? dashboard?.role;
    final canManage =
        role == OrganizationRole.owner || role == OrganizationRole.manager;
    final isOwner = role == OrganizationRole.owner;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const EpDisplay('Organization', key: Key('org-hub-title'), size: 44),
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          _LoadError(onRetry: _load)
        else if (dashboard != null) ...[
          _buildProfileSection(dashboard.organization, canManage: canManage),
          const SizedBox(height: 32),
          const OrgTeamPanel(),
          if (app.canSeeFinance(organizationId)) ...[
            const SizedBox(height: 32),
            _buildFinanceSection(app),
          ],
          if (isOwner) ...[
            const SizedBox(height: 32),
            _buildPrivateSection(dashboard.privateDetails),
          ],
          if (canManage) ...[const SizedBox(height: 32), _buildDangerZone()],
        ],
      ],
    );
  }

  Widget _buildProfileSection(
    Organization organization, {
    required bool canManage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EpEyebrow('Profile — public'),
        const SizedBox(height: 8),
        const EpHairline(),
        _HubRow(
          key: const Key('org-hub-name'),
          label: 'Name',
          value: organization.name,
          onTap: canManage ? _editName : null,
        ),
        _HubRow(
          key: const Key('org-hub-about'),
          label: 'About',
          value: organization.description,
          onTap: canManage ? _editAbout : null,
        ),
        _HubRow(
          key: const Key('org-hub-website'),
          label: 'Website',
          value: organization.website,
          onTap: canManage ? _editWebsite : null,
        ),
        _HubRow(
          key: const Key('org-hub-photos'),
          label: 'Photos',
          value: '$_photoCount OF $_maxPhotos',
          onTap: () => _openPhotosSheet(canManage: canManage),
        ),
      ],
    );
  }

  Widget _buildFinanceSection(AppState app) {
    final status = app.organizationStripeStatusFor(app.organizationId);
    final (stripeLabel, stripeTone) = switch (status?.state) {
      StripeAccountState.enabled => ('Connected', EpStatusPillTone.success),
      StripeAccountState.onboarding || StripeAccountState.restricted => (
        'Setup in progress — finish in Stripe',
        EpStatusPillTone.attention,
      ),
      _ => ('Set up', EpStatusPillTone.attention),
    };
    final needsTaxInformation =
        status?.requirementsDue.any(
          RegExp(r'tax|ssn|id_number|verification\.document').hasMatch,
        ) ??
        false;
    final detailsSubmitted = status?.detailsSubmitted == true;
    final taxCollected = detailsSubmitted && !needsTaxInformation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EpEyebrow('Finance'),
        const SizedBox(height: 8),
        const EpHairline(),
        EpMenuRow(
          key: const Key('org-hub-stripe'),
          icon: Icons.account_balance_outlined,
          label: 'Stripe',
          trailing: Flexible(
            child: StatusPill(label: stripeLabel, tone: stripeTone),
          ),
          onTap: app.openFinance,
        ),
        EpMenuRow(
          key: const Key('org-hub-tax'),
          icon: Icons.receipt_long_outlined,
          label: 'Tax details',
          trailing: Flexible(
            child: StatusPill(
              label: taxCollected ? '✓ Collected via Stripe' : 'Action needed',
              tone: taxCollected
                  ? EpStatusPillTone.success
                  : EpStatusPillTone.attention,
            ),
          ),
          // Stripe collects tax details during onboarding; until details are
          // submitted the fix is finishing setup, which lives in Finance.
          onTap: detailsSubmitted
              ? () => _runStripeAction(app.openOrganizationExpressDashboard)
              : app.openFinance,
        ),
        if (_stripeError != null) ...[
          const SizedBox(height: 8),
          InlineFormFeedback(
            error: _stripeError,
            errorKey: const Key('org-settings-stripe-error'),
          ),
        ],
      ],
    );
  }

  Widget _buildPrivateSection(OrganizationPrivateDetails? details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EpEyebrow('Private details'),
        const SizedBox(height: 8),
        const EpHairline(),
        _HubRow(
          key: const Key('org-hub-legal-name'),
          label: 'Legal name',
          value: details?.legalName,
          action: 'Edit',
          onTap: _editLegalName,
        ),
        _HubRow(
          key: const Key('org-hub-contact-email'),
          label: 'Contact email',
          value: details?.businessEmail,
          action: 'Edit',
          onTap: _editContactEmail,
        ),
        _HubRow(
          key: const Key('org-hub-phone'),
          label: 'Phone',
          value: details?.phone,
          action: 'Edit',
          onTap: _editPhone,
        ),
      ],
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EpEyebrow('Danger zone'),
        const SizedBox(height: 8),
        const EpHairline(),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            key: const Key('org-settings-deactivate'),
            onPressed: _confirmDeactivate,
            style: TextButton.styleFrom(
              foregroundColor: context.epColors.destructive,
              textStyle: Theme.of(context).textTheme.epChipLabel,
            ),
            child: const Text(
              'DEACTIVATE ORGANIZATION',
              semanticsLabel: 'Deactivate organization',
            ),
          ),
        ),
      ],
    );
  }
}

/// Label left, value right; the row itself opens the field's sheet.
class _HubRow extends StatelessWidget {
  const _HubRow({
    super.key,
    required this.label,
    required this.value,
    this.action,
    this.onTap,
  });

  final String label;
  final String? value;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final text = value?.trim() ?? '';
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Flexible(child: EpDisplay(label, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: EpMonoText(
                      text.isEmpty ? 'Not set' : text,
                      keepCase: text.isNotEmpty,
                      color: text.isEmpty ? palette.muted : palette.ink,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (action != null && onTap != null) ...[
                  const SizedBox(width: 12),
                  EpMonoText(action!, weight: FontWeight.w500),
                ],
              ],
            ),
          ),
        ),
        const EpHairline(),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _EditField {
  const _EditField({
    required this.label,
    required this.hint,
    required this.fieldKey,
    required this.initial,
    this.required = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final Key fieldKey;
  final String initial;
  final bool required;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
}

/// One focused sheet per hub row: its fields, a Save pill, and the save error
/// kept inside the sheet so the user can retry without losing the draft.
class _EditSheet extends StatefulWidget {
  const _EditSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
  });

  final String title;
  final List<_EditField> fields;
  final Future<void> Function(List<String> values) onSave;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final List<TextEditingController> _controllers = [
    for (final field in widget.fields)
      TextEditingController(text: field.initial),
  ];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _complete {
    for (var index = 0; index < widget.fields.length; index++) {
      if (widget.fields[index].required &&
          _controllers[index].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving || !_complete) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave([
        for (final controller in _controllers) controller.text.trim(),
      ]);
      if (!mounted) return;
      Navigator.pop(context);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Changes could not be saved. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < widget.fields.length; index++) ...[
            if (index > 0) const SizedBox(height: EpLayout.fieldGap),
            EpLabeledField(
              label: widget.fields[index].label,
              hint: widget.fields[index].hint,
              fieldKey: widget.fields[index].fieldKey,
              controller: _controllers[index],
              required: widget.fields[index].required,
              enabled: !_saving,
              minLines: widget.fields[index].minLines,
              maxLines: widget.fields[index].maxLines,
              maxLength: widget.fields[index].maxLength,
              keyboardType: widget.fields[index].keyboardType,
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineFormFeedback(
              error: _error,
              errorKey: const Key('org-settings-save-error'),
            ),
          ],
          const SizedBox(height: 24),
          EpPill(
            key: const Key('org-hub-sheet-save'),
            label: _saving ? 'Saving…' : 'Save',
            variant: EpPillVariant.primary,
            size: EpPillSize.regular,
            expand: true,
            onPressed: _saving || !_complete ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _PhotosSheet extends StatelessWidget {
  const _PhotosSheet({
    super.key,
    required this.existingUrls,
    required this.sessionPhotos,
    required this.adding,
    required this.onAdd,
  });

  final List<String> existingUrls;
  final List<PickedMedia> sessionPhotos;
  final bool adding;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final count = existingUrls.length + sessionPhotos.length;
    final full = count >= _maxPhotos;
    return EpFormSheet(
      title: 'Photos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add up to $_maxPhotos photos of your organization.',
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ),
              const SizedBox(width: 12),
              EpMonoText(
                '$count of $_maxPhotos',
                key: const Key('org-hub-photos-count'),
                color: context.epColors.muted,
              ),
            ],
          ),
          if (count > 0) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in existingUrls)
                  _PhotoTile(
                    child: EpNetworkImage(
                      url: url,
                      cacheWidth: 110,
                      cacheHeight: 90,
                      fallback: const Icon(Icons.photo_outlined),
                    ),
                  ),
                for (final photo in sessionPhotos)
                  _PhotoTile(
                    child: Image.memory(
                      photo.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SlotShell(
            key: const Key('org-settings-add-photo'),
            state: SlotState.needed,
            onTap: onAdd,
            child: Row(
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  color: full
                      ? context.epColors.contentDisabled
                      : context.epColors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    adding ? 'ADDING…' : 'ADD PHOTO',
                    style: Theme.of(context).textTheme.epLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(EpLayout.cardRadius),
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
          const SizedBox(height: EpLayout.fieldGap),
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
            foregroundColor: context.epColors.background,
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
          const Text('Could not load the organization.'),
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
