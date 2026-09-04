import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/approx_area_map.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/map_view.dart';
import '../widgets/sheets.dart';
import 'admin_queue.dart' show organizationTypeLabel;

String venueTypeLabel(VenueType type) => switch (type) {
  VenueType.bar => 'Bar',
  VenueType.club => 'Club',
  VenueType.hall => 'Hall',
  VenueType.house => 'House',
  VenueType.outdoor => 'Outdoor',
  VenueType.other => 'Other',
};

class AdminApplicationScreen extends StatefulWidget {
  const AdminApplicationScreen({super.key, required this.applicationId});

  final String applicationId;

  @override
  State<AdminApplicationScreen> createState() => _AdminApplicationScreenState();
}

class _AdminApplicationScreenState extends State<AdminApplicationScreen> {
  OrganizationApplication? _application;
  Organization? _resultingOrganization;
  Object? _loadToken;
  bool _loadScheduled = false;
  bool _loaded = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _decisionInFlight = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    if (!app.isPlatformAdmin || _loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AppState>().isPlatformAdmin) {
        _refresh();
      } else {
        _loadScheduled = false;
      }
    });
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    final token = Object();
    _loadToken = token;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final application = await app.repository.organizationApplication(
        widget.applicationId,
      );
      Organization? resultingOrganization;
      final organizationId = application?.resultingOrganizationId;
      if (application?.status == OrganizationApplicationStatus.approved &&
          organizationId != null) {
        resultingOrganization = await app.repository.organization(
          organizationId,
        );
      }
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _application = application;
        _resultingOrganization = resultingOrganization;
        _loaded = true;
        _loading = false;
      });
    } catch (error) {
      logError('adminApplication', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loaded = true;
        _loading = false;
        _loadFailed = true;
      });
      app.say(genericErrorMessage);
    }
  }

  Future<bool> _performDecision(
    ApplicationDecision decision, {
    String? note,
  }) async {
    if (_decisionInFlight) return false;
    final app = context.read<AppState>();
    setState(() => _decisionInFlight = true);
    try {
      await app.repository.decideOrganizationApplication(
        applicationId: widget.applicationId,
        decision: decision,
        note: note,
      );
      return true;
    } catch (error) {
      logError('adminDecision', error);
      app.say(genericErrorMessage);
      return false;
    } finally {
      if (mounted) setState(() => _decisionInFlight = false);
    }
  }

  Future<void> _startReview() async {
    final succeeded = await _performDecision(ApplicationDecision.underReview);
    if (!succeeded || !mounted) return;
    context.read<AppState>().say('Application moved to review.');
    await _refresh();
  }

  Future<void> _showNoteDecision({
    required ApplicationDecision decision,
    required String title,
    required String successMessage,
  }) async {
    var confirmed = false;
    await showEpSheet(
      context,
      (_) => _DecisionNoteSheet(
        title: title,
        onConfirm: (note) async {
          final succeeded = await _performDecision(decision, note: note);
          if (succeeded) confirmed = true;
          return succeeded;
        },
      ),
    );
    if (!confirmed || !mounted) return;
    context.read<AppState>().say(successMessage);
    await _refresh();
  }

  Future<void> _showApproval() async {
    var confirmed = false;
    await showEpSheet(
      context,
      (_) => _ApprovalSheet(
        onConfirm: () async {
          final succeeded = await _performDecision(
            ApplicationDecision.approved,
          );
          if (succeeded) confirmed = true;
          return succeeded;
        },
      ),
    );
    if (!confirmed || !mounted) return;
    context.read<AppState>().say('Organization created.');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isPlatformAdmin) {
      return _NotAuthorized(onBack: app.toFanView);
    }

    final application = _application;
    return Material(
      color: context.epColors.background,
      child: Column(
        children: [
          ScreenHeader(
            child: Row(
              children: [
                CircleIconButton(onTap: app.back),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    application?.orgName ?? 'APPLICATION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epPageHeading,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(application)),
          if (application != null && _isActionable(application.status))
            _AdminReviewActionBar(
              status: application.status,
              enabled: !_decisionInFlight && !_loading,
              onStart: _startReview,
              onRequestInfo: () => _showNoteDecision(
                decision: ApplicationDecision.needsInfo,
                title: 'REQUEST INFO',
                successMessage: 'Requested more information.',
              ),
              onApprove: _showApproval,
              onReject: () => _showNoteDecision(
                decision: ApplicationDecision.rejected,
                title: 'REJECT APPLICATION',
                successMessage: 'Application rejected.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(OrganizationApplication? application) {
    if (application == null && (!_loaded || _loading)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (application == null && _loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load this application."),
              const SizedBox(height: 12),
              EpButton(
                'RETRY',
                kind: EpButtonKind.outline,
                onTap: _loading ? null : _refresh,
              ),
            ],
          ),
        ),
      );
    }
    if (application == null) {
      return const Center(child: Text('Application not found.'));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        if (_loading) const LinearProgressIndicator(),
        _OrganizationSection(application: application),
        _ContactSection(application: application),
        _VenueSection(venue: application.venue),
        _DocumentsSection(documents: application.documents),
        _ReviewSection(
          application: application,
          resultingOrganization: _resultingOrganization,
        ),
      ],
    );
  }
}

class _OrganizationSection extends StatelessWidget {
  const _OrganizationSection({required this.application});

  final OrganizationApplication application;

  @override
  Widget build(BuildContext context) {
    final website = application.website?.trim();
    return _DetailSection(
      label: 'ORGANIZATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailValue(label: 'Name', value: application.orgName),
          _DetailValue(
            label: 'Type',
            value: organizationTypeLabel(application.orgType),
          ),
          if (website != null && website.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openExternalForUser(context, website),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: Text(website),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.application});

  final OrganizationApplication application;

  @override
  Widget build(BuildContext context) {
    return _DetailSection(
      label: 'CONTACT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailValue(label: 'Name', value: application.contactName),
          _DetailValue(label: 'Email', value: application.businessEmail),
          if (application.phone case final phone?)
            _DetailValue(label: 'Phone', value: phone),
        ],
      ),
    );
  }
}

class _VenueSection extends StatelessWidget {
  const _VenueSection({required this.venue});

  final ApplicationVenueDraft? venue;

  @override
  Widget build(BuildContext context) {
    final draft = venue;
    if (draft == null) {
      return const _DetailSection(
        label: 'VENUE',
        child: Text('No venue provided.'),
      );
    }
    final exactVenue = Venue(
      id: '',
      name: draft.name,
      area: draft.area,
      addr: draft.addr,
      point: draft.point,
    );
    return _DetailSection(
      label: 'VENUE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailValue(label: 'Name', value: draft.name),
          _DetailValue(label: 'Exact address', value: draft.addr),
          if (draft.capacity case final capacity?)
            _DetailValue(label: 'Capacity', value: '$capacity'),
          if (draft.venueType case final type?)
            _DetailValue(label: 'Venue type', value: venueTypeLabel(type)),
          const SizedBox(height: 12),
          const _MapCaption(text: 'Exact address — admin only'),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: VenueMiniMap(venue: exactVenue, approximate: false),
          ),
          const SizedBox(height: 16),
          const _MapCaption(text: 'What fans will see'),
          const SizedBox(height: 7),
          ApproxAreaMap(centroid: draft.point, label: draft.area),
        ],
      ),
    );
  }
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.documents});

  final List<ApplicationDocument> documents;

  @override
  Widget build(BuildContext context) {
    return _DetailSection(
      label: 'DOCUMENTS',
      child: documents.isEmpty
          ? const DashedBox(
              child: Text('No documents.', textAlign: TextAlign.center),
            )
          : Column(
              children: [
                for (var index = 0; index < documents.length; index++) ...[
                  _DocumentRow(document: documents[index], index: index),
                  if (index < documents.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.index});

  final ApplicationDocument document;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isImage = document.contentType?.startsWith('image/') == true;
    final url = document.url;
    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: EpNetworkImage(
            url: url,
            cacheWidth: 360,
            cacheHeight: 150,
            fallback: const ColoredBox(
              color: Colors.black12,
              child: Center(child: Icon(Icons.image_not_supported_outlined)),
            ),
          ),
        ),
      );
    }

    return EpCard(
      child: Row(
        children: [
          const Icon(Icons.description_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              document.contentType ?? 'Document ${index + 1}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (url != null && url.isNotEmpty)
            TextButton(
              onPressed: () => openExternalForUser(context, url),
              child: const Text('OPEN'),
            ),
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.application,
    required this.resultingOrganization,
  });

  final OrganizationApplication application;
  final Organization? resultingOrganization;

  @override
  Widget build(BuildContext context) {
    final note = application.reviewNote?.trim();
    final decidedAt = application.decidedAt;
    final organization = resultingOrganization;
    return _DetailSection(
      label: 'REVIEW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(
            label: _statusLabel(application.status),
            tone: _statusTone(application.status),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Note: $note'),
          ],
          if (decidedAt != null) ...[
            const SizedBox(height: 8),
            Text('Decided ${dateLabel(decidedAt)}'),
          ],
          if (application.status == OrganizationApplicationStatus.approved &&
              application.resultingOrganizationId != null &&
              organization != null) ...[
            const SizedBox(height: 12),
            Text(
              'Organization created — ${organization.name} '
              '(${organization.slug})',
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: label),
        EpCard(child: child),
      ],
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.epCaption.copyWith(
                color: context.epColors.contentSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MapCaption extends StatelessWidget {
  const _MapCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.epCaption.copyWith(color: context.epColors.contentSecondary),
    );
  }
}

class _AdminReviewActionBar extends StatelessWidget {
  const _AdminReviewActionBar({
    required this.status,
    required this.enabled,
    required this.onStart,
    required this.onRequestInfo,
    required this.onApprove,
    required this.onReject,
  });

  final OrganizationApplicationStatus status;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onRequestInfo;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.epColors.tabBarBackground,
          border: Border(top: BorderSide(color: context.epColors.border)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status == OrganizationApplicationStatus.submitted) ...[
                EpButton(
                  'START REVIEW',
                  key: const Key('admin-review-start'),
                  onTap: enabled ? onStart : null,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: EpButton(
                      'REQUEST INFO',
                      key: const Key('admin-review-request-info'),
                      kind: EpButtonKind.outline,
                      fontSize: 10,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onTap: enabled ? onRequestInfo : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: EpButton(
                      'APPROVE',
                      key: const Key('admin-review-approve'),
                      kind: EpButtonKind.outline,
                      fontSize: 10,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onTap: enabled ? onApprove : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: EpButton(
                      'REJECT',
                      key: const Key('admin-review-reject'),
                      kind: EpButtonKind.outline,
                      fontSize: 10,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onTap: enabled ? onReject : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionNoteSheet extends StatefulWidget {
  const _DecisionNoteSheet({required this.title, required this.onConfirm});

  final String title;
  final Future<bool> Function(String? note) onConfirm;

  @override
  State<_DecisionNoteSheet> createState() => _DecisionNoteSheetState();
}

class _DecisionNoteSheetState extends State<_DecisionNoteSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final trimmed = _controller.text.trim();
    final succeeded = await widget.onConfirm(trimmed.isEmpty ? null : trimmed);
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EpLabeledField(
            label: 'NOTE',
            hint: 'Add a note (optional)',
            controller: _controller,
            fieldKey: const Key('admin-review-note'),
            minLines: 3,
            maxLines: 5,
          ),
          const SizedBox(height: 14),
          EpButton(
            'CONFIRM',
            key: const Key('admin-review-confirm'),
            onTap: _submitting ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

class _ApprovalSheet extends StatefulWidget {
  const _ApprovalSheet({required this.onConfirm});

  final Future<bool> Function() onConfirm;

  @override
  State<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends State<_ApprovalSheet> {
  bool _submitting = false;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final succeeded = await widget.onConfirm();
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: 'APPROVE APPLICATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('This creates the organization and its venue.'),
          const SizedBox(height: 14),
          EpButton(
            'CONFIRM',
            key: const Key('admin-review-confirm'),
            onTap: _submitting ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('admin-not-authorized'),
      child: Material(
        color: context.epColors.background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Only platform admins can review organizer applications.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epBody,
              ),
              const SizedBox(height: 16),
              EpButton(
                'BACK TO FAN VIEW',
                kind: EpButtonKind.outline,
                onTap: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isActionable(OrganizationApplicationStatus status) =>
    status == OrganizationApplicationStatus.submitted ||
    status == OrganizationApplicationStatus.underReview;

String _statusLabel(OrganizationApplicationStatus status) => status.wireValue
    .replaceAll('_', ' ')
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

EpStatusPillTone _statusTone(OrganizationApplicationStatus status) =>
    switch (status) {
      OrganizationApplicationStatus.approved => EpStatusPillTone.success,
      OrganizationApplicationStatus.submitted => EpStatusPillTone.selected,
      OrganizationApplicationStatus.underReview ||
      OrganizationApplicationStatus.needsInfo => EpStatusPillTone.warning,
      OrganizationApplicationStatus.draft ||
      OrganizationApplicationStatus.rejected ||
      OrganizationApplicationStatus.withdrawn => EpStatusPillTone.neutral,
    };
