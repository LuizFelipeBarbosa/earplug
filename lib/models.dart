import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'app_links.dart';
import 'date_names.dart';

String _marketplaceString(Object? value) => value is String ? value : '';

String? _marketplaceOptionalString(Object? value) =>
    value is String ? value : null;

int _marketplaceInt(Object? value) => value is num ? value.toInt() : 0;

int? _marketplaceOptionalInt(Object? value) =>
    value is num ? value.toInt() : null;

DateTime _marketplaceDate(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(value is num ? value.toInt() : 0);

DateTime? _marketplaceOptionalDate(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

Map<String, dynamic> _marketplaceMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

List<Map<String, dynamic>> _marketplaceMapList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) _marketplaceMap(item),
];

List<String> _marketplaceStringList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is String) item,
];

LatLng _marketplacePoint(
  Map<String, dynamic> json, {
  LatLng fallback = const LatLng(0, 0),
}) => LatLng(
  json['lat'] is num ? (json['lat'] as num).toDouble() : fallback.latitude,
  json['lng'] is num ? (json['lng'] as num).toDouble() : fallback.longitude,
);

enum AddressDisclosure {
  onTicket('onTicket'),
  public('public');

  const AddressDisclosure(this.wireValue);

  final String wireValue;

  static AddressDisclosure fromWire(Object? value) => value == 'onTicket'
      ? AddressDisclosure.onTicket
      : AddressDisclosure.public;
}

enum LocationPrecision { exact, approximate }

enum VenueType {
  bar('bar'),
  club('club'),
  hall('hall'),
  house('house'),
  outdoor('outdoor'),
  other('other');

  const VenueType(this.wireValue);

  final String wireValue;

  static VenueType fromWire(Object? value) => switch (value) {
    'bar' => VenueType.bar,
    'club' => VenueType.club,
    'hall' => VenueType.hall,
    'house' => VenueType.house,
    'outdoor' => VenueType.outdoor,
    _ => VenueType.other,
  };
}

class ApproxLocation {
  const ApproxLocation({required this.centroid, required this.label});

  final LatLng centroid;
  final String label;

  factory ApproxLocation.fromJson(
    Map<String, dynamic> json, {
    LatLng fallbackPoint = const LatLng(0, 0),
    String fallbackLabel = '',
  }) => ApproxLocation(
    centroid: _marketplacePoint(json, fallback: fallbackPoint),
    label: json['label'] is String ? json['label'] as String : fallbackLabel,
  );
}

class Venue {
  final String id;
  final String name;
  final String area;
  final String addr;
  final LatLng point;
  final String? slug;
  final String? description;
  final VenueType? venueType;
  final int? capacityPublic;
  final ApproxLocation? _approx;
  final String? neighborhood;
  final String? city;
  final AddressDisclosure disclosure;
  final bool verified;
  final String? managedByOrganizationId;
  final String? exactAddress;
  final bool supportsApproxLocation;

  const Venue({
    required this.id,
    required this.name,
    required this.area,
    required this.addr,
    required this.point,
    this.slug,
    this.description,
    this.venueType,
    this.capacityPublic,
    ApproxLocation? approx,
    this.neighborhood,
    this.city,
    this.disclosure = AddressDisclosure.public,
    this.verified = false,
    this.managedByOrganizationId,
    String? exactAddress,
    this.supportsApproxLocation = false,
  }) : // `approx` is the public constructor argument for the private override.
       // ignore: prefer_initializing_formals
       _approx = approx,
       exactAddress = exactAddress ?? (supportsApproxLocation ? null : addr);

  ApproxLocation get approx =>
      _approx ?? ApproxLocation(centroid: point, label: area);

  LocationPrecision get precision => exactAddress != null
      ? LocationPrecision.exact
      : LocationPrecision.approximate;

  LatLng? get exactPoint => exactAddress != null ? point : null;

  factory Venue.fromJson(Map<String, dynamic> json) {
    final area = _marketplaceString(json['area']);
    final addr = _marketplaceString(json['addr']);
    final disclosedPoint = _marketplacePoint(json);
    final description = _marketplaceOptionalString(json['description']);
    final venueType = json['venueType'] is String
        ? VenueType.fromWire(json['venueType'])
        : null;
    final capacityPublic = _marketplaceOptionalInt(json['capacityPublic']);
    if (!json.containsKey('approxLocation')) {
      return Venue(
        id: _marketplaceString(json['_id']),
        name: _marketplaceString(json['name']),
        area: area,
        addr: addr,
        point: disclosedPoint,
        description: description,
        venueType: venueType,
        capacityPublic: capacityPublic,
      );
    }

    final approx = ApproxLocation.fromJson(
      _marketplaceMap(json['approxLocation']),
      fallbackPoint: disclosedPoint,
      fallbackLabel: area,
    );
    final exactAddress = _marketplaceOptionalString(json['exactAddr']);
    return Venue(
      id: _marketplaceString(json['_id']),
      name: _marketplaceString(json['name']),
      area: area,
      addr: addr.isEmpty ? exactAddress ?? approx.label : addr,
      point: exactAddress == null ? approx.centroid : disclosedPoint,
      slug: _marketplaceOptionalString(json['slug']),
      description: description,
      venueType: venueType,
      capacityPublic: capacityPublic,
      approx: approx,
      neighborhood: _marketplaceOptionalString(json['neighborhood']),
      city: _marketplaceOptionalString(json['city']),
      disclosure: AddressDisclosure.fromWire(json['addressDisclosure']),
      verified: json['verified'] == true,
      managedByOrganizationId: _marketplaceOptionalString(
        json['managedByOrganizationId'],
      ),
      exactAddress: exactAddress,
      supportsApproxLocation: true,
    );
  }

  static const _unchanged = Object();

  Venue copyWith({
    String? id,
    String? name,
    String? area,
    String? addr,
    LatLng? point,
    Object? slug = _unchanged,
    Object? description = _unchanged,
    Object? venueType = _unchanged,
    Object? capacityPublic = _unchanged,
    Object? approx = _unchanged,
    Object? neighborhood = _unchanged,
    Object? city = _unchanged,
    AddressDisclosure? disclosure,
    bool? verified,
    Object? managedByOrganizationId = _unchanged,
    Object? exactAddress = _unchanged,
    bool? supportsApproxLocation,
  }) => Venue(
    id: id ?? this.id,
    name: name ?? this.name,
    area: area ?? this.area,
    addr: addr ?? this.addr,
    point: point ?? this.point,
    slug: identical(slug, _unchanged) ? this.slug : slug as String?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    venueType: identical(venueType, _unchanged)
        ? this.venueType
        : venueType as VenueType?,
    capacityPublic: identical(capacityPublic, _unchanged)
        ? this.capacityPublic
        : capacityPublic as int?,
    approx: identical(approx, _unchanged) ? _approx : approx as ApproxLocation?,
    neighborhood: identical(neighborhood, _unchanged)
        ? this.neighborhood
        : neighborhood as String?,
    city: identical(city, _unchanged) ? this.city : city as String?,
    disclosure: disclosure ?? this.disclosure,
    verified: verified ?? this.verified,
    managedByOrganizationId: identical(managedByOrganizationId, _unchanged)
        ? this.managedByOrganizationId
        : managedByOrganizationId as String?,
    exactAddress: identical(exactAddress, _unchanged)
        ? this.exactAddress
        : exactAddress as String?,
    supportsApproxLocation:
        supportsApproxLocation ?? this.supportsApproxLocation,
  );
}

class VenuePrivateDetails {
  const VenuePrivateDetails({
    required this.venueId,
    required this.addr,
    required this.point,
    this.loadInNotes,
    this.capacity,
  });

  final String venueId;
  final String addr;
  final LatLng point;
  final String? loadInNotes;
  final int? capacity;

  factory VenuePrivateDetails.fromJson(Map<String, dynamic> json) =>
      VenuePrivateDetails(
        venueId: _marketplaceString(json['venueId']),
        addr: _marketplaceString(json['addr']),
        point: _marketplacePoint(json),
        loadInNotes: _marketplaceOptionalString(json['loadInNotes']),
        capacity: _marketplaceOptionalInt(json['capacity']),
      );
}

enum OrganizationRole {
  owner('owner'),
  manager('manager'),
  finance('finance'),
  door('door');

  const OrganizationRole(this.wireValue);

  final String wireValue;

  static OrganizationRole fromWire(Object? value) => switch (value) {
    'owner' => OrganizationRole.owner,
    'manager' => OrganizationRole.manager,
    'finance' => OrganizationRole.finance,
    _ => OrganizationRole.door,
  };
}

enum OrganizationType {
  venueOperator('venueOperator'),
  promoter('promoter'),
  studentOrg('studentOrg'),
  other('other');

  const OrganizationType(this.wireValue);

  final String wireValue;

  static OrganizationType fromWire(Object? value) => switch (value) {
    'venueOperator' => OrganizationType.venueOperator,
    'promoter' => OrganizationType.promoter,
    'studentOrg' => OrganizationType.studentOrg,
    _ => OrganizationType.other,
  };
}

enum OrganizationStatus {
  pending('pending'),
  verified('verified'),
  suspended('suspended');

  const OrganizationStatus(this.wireValue);

  final String wireValue;

  static OrganizationStatus fromWire(Object? value) => switch (value) {
    'verified' => OrganizationStatus.verified,
    'suspended' => OrganizationStatus.suspended,
    _ => OrganizationStatus.pending,
  };
}

class Organization {
  const Organization({
    required this.id,
    required this.slug,
    required this.name,
    required this.orgType,
    required this.status,
    required this.verified,
    this.description,
    this.website,
    required this.photoUrls,
    required this.createdAt,
  });

  final String id;
  final String slug;
  final String name;
  final OrganizationType orgType;
  final OrganizationStatus status;
  final bool verified;
  final String? description;
  final String? website;
  final List<String> photoUrls;
  final DateTime createdAt;

  factory Organization.fromJson(Map<String, dynamic> json) {
    final status = OrganizationStatus.fromWire(json['status']);
    return Organization(
      id: _marketplaceString(json['_id']),
      slug: _marketplaceString(json['slug']),
      name: _marketplaceString(json['name']),
      orgType: OrganizationType.fromWire(json['orgType']),
      status: status,
      verified: json['verified'] is bool
          ? json['verified'] as bool
          : status == OrganizationStatus.verified,
      description: _marketplaceOptionalString(json['description']),
      website: _marketplaceOptionalString(json['website']),
      photoUrls: _marketplaceStringList(json['photoUrls']),
      createdAt: _marketplaceDate(json['createdAt']),
    );
  }
}

class OrganizationMembership {
  const OrganizationMembership({
    required this.organization,
    required this.role,
  });

  final Organization organization;
  final OrganizationRole role;

  factory OrganizationMembership.fromJson(Map<String, dynamic> json) =>
      OrganizationMembership(
        organization: Organization.fromJson(
          _marketplaceMap(json['organization']),
        ),
        role: OrganizationRole.fromWire(json['role']),
      );
}

class OrganizationVerification {
  const OrganizationVerification({
    required this.verified,
    required this.stripeDetailsSubmitted,
    required this.stripeChargesEnabled,
    required this.stripePayoutsEnabled,
    required this.profileComplete,
    required this.teamInvited,
  });

  final bool verified;
  final bool stripeDetailsSubmitted;
  final bool stripeChargesEnabled;
  final bool stripePayoutsEnabled;
  final bool profileComplete;
  final bool teamInvited;

  factory OrganizationVerification.fromJson(Map<String, dynamic> json) =>
      OrganizationVerification(
        verified: json['verified'] == true,
        stripeDetailsSubmitted: json['stripeDetailsSubmitted'] == true,
        stripeChargesEnabled: json['stripeChargesEnabled'] == true,
        stripePayoutsEnabled: json['stripePayoutsEnabled'] == true,
        profileComplete: json['profileComplete'] == true,
        teamInvited: json['teamInvited'] == true,
      );
}

class OrganizationPrivateDetails {
  const OrganizationPrivateDetails({
    this.legalName,
    required this.businessEmail,
    required this.contactName,
    this.phone,
  });

  final String? legalName;
  final String businessEmail;
  final String contactName;
  final String? phone;

  factory OrganizationPrivateDetails.fromJson(Map<String, dynamic> json) =>
      OrganizationPrivateDetails(
        legalName: _marketplaceOptionalString(json['legalName']),
        businessEmail: _marketplaceString(json['businessEmail']),
        contactName: _marketplaceString(json['contactName']),
        phone: _marketplaceOptionalString(json['phone']),
      );
}

class OrganizationDashboard {
  const OrganizationDashboard({
    required this.organization,
    required this.role,
    required this.viaPlatformAdmin,
    required this.verification,
    required this.venues,
    required this.memberCount,
    required this.privateDetails,
  });

  final Organization organization;
  final OrganizationRole? role;
  final bool viaPlatformAdmin;
  final OrganizationVerification verification;
  final List<Venue> venues;
  final int memberCount;
  final OrganizationPrivateDetails? privateDetails;

  factory OrganizationDashboard.fromJson(Map<String, dynamic> json) =>
      OrganizationDashboard(
        organization: Organization.fromJson(
          _marketplaceMap(json['organization']),
        ),
        role: json['role'] is String
            ? OrganizationRole.fromWire(json['role'])
            : null,
        viaPlatformAdmin: json['viaPlatformAdmin'] == true,
        verification: OrganizationVerification.fromJson(
          _marketplaceMap(json['verification']),
        ),
        venues: [
          for (final venue in _marketplaceMapList(json['venues']))
            Venue.fromJson(venue),
        ],
        memberCount: _marketplaceInt(json['memberCount']),
        privateDetails: json['privateDetails'] is Map
            ? OrganizationPrivateDetails.fromJson(
                _marketplaceMap(json['privateDetails']),
              )
            : null,
      );
}

class OrganizationMember {
  const OrganizationMember({
    required this.userId,
    required this.name,
    this.email,
    required this.role,
    required this.createdAt,
  });

  final String userId;
  final String name;
  final String? email;
  final OrganizationRole role;
  final DateTime createdAt;

  factory OrganizationMember.fromJson(Map<String, dynamic> json) =>
      OrganizationMember(
        userId: _marketplaceString(json['userId']),
        name: _marketplaceString(json['name']),
        email: _marketplaceOptionalString(json['email']),
        role: OrganizationRole.fromWire(json['role']),
        createdAt: _marketplaceDate(json['createdAt']),
      );
}

class OrganizationInvite {
  const OrganizationInvite({
    required this.organizationId,
    required this.token,
    required this.role,
    required this.expiresAt,
    required this.revoked,
    required this.expired,
  });

  final String organizationId;
  final String token;
  final OrganizationRole role;
  final DateTime expiresAt;
  final bool revoked;
  final bool expired;

  factory OrganizationInvite.fromJson(Map<String, dynamic> json) =>
      OrganizationInvite(
        organizationId: _marketplaceString(json['organizationId']),
        token: _marketplaceString(json['token']),
        role: OrganizationRole.fromWire(json['role']),
        expiresAt: _marketplaceDate(json['expiresAt']),
        revoked: json['revoked'] == true,
        expired: json['expired'] == true,
      );
}

class OrganizationInviteResolution {
  const OrganizationInviteResolution({
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  final String organizationId;
  final String organizationName;
  final OrganizationRole role;

  factory OrganizationInviteResolution.fromJson(Map<String, dynamic> json) =>
      OrganizationInviteResolution(
        organizationId: _marketplaceString(json['organizationId']),
        organizationName: _marketplaceString(json['organizationName']),
        role: OrganizationRole.fromWire(json['role']),
      );
}

class OrganizationInviteAcceptance {
  const OrganizationInviteAcceptance({
    required this.organizationId,
    required this.membershipCreated,
  });

  final String organizationId;
  final bool membershipCreated;

  factory OrganizationInviteAcceptance.fromJson(Map<String, dynamic> json) =>
      OrganizationInviteAcceptance(
        organizationId: _marketplaceString(json['organizationId']),
        membershipCreated: json['membershipCreated'] == true,
      );
}

enum OrganizationApplicationStatus {
  draft('draft'),
  submitted('submitted'),
  underReview('under_review'),
  needsInfo('needs_info'),
  approved('approved'),
  rejected('rejected'),
  withdrawn('withdrawn');

  const OrganizationApplicationStatus(this.wireValue);

  final String wireValue;

  static OrganizationApplicationStatus fromWire(Object? value) =>
      switch (value) {
        'submitted' => OrganizationApplicationStatus.submitted,
        'under_review' => OrganizationApplicationStatus.underReview,
        'needs_info' => OrganizationApplicationStatus.needsInfo,
        'approved' => OrganizationApplicationStatus.approved,
        'rejected' => OrganizationApplicationStatus.rejected,
        'withdrawn' => OrganizationApplicationStatus.withdrawn,
        _ => OrganizationApplicationStatus.draft,
      };
}

enum ApplicationDecision {
  underReview('under_review'),
  needsInfo('needs_info'),
  approved('approved'),
  rejected('rejected');

  const ApplicationDecision(this.wireValue);

  final String wireValue;

  static ApplicationDecision fromWire(Object? value) => switch (value) {
    'needs_info' => ApplicationDecision.needsInfo,
    'approved' => ApplicationDecision.approved,
    'rejected' => ApplicationDecision.rejected,
    _ => ApplicationDecision.underReview,
  };
}

class ApplicationVenueDraft {
  const ApplicationVenueDraft({
    required this.name,
    required this.addr,
    required this.point,
    required this.area,
    this.neighborhood,
    this.city,
    this.capacity,
    this.venueType,
  });

  final String name;
  final String addr;
  final LatLng point;
  final String area;
  final String? neighborhood;
  final String? city;
  final int? capacity;
  final VenueType? venueType;

  factory ApplicationVenueDraft.fromJson(Map<String, dynamic> json) =>
      ApplicationVenueDraft(
        name: _marketplaceString(json['name']),
        addr: _marketplaceString(json['addr']),
        point: _marketplacePoint(json),
        area: _marketplaceString(json['area']),
        neighborhood: _marketplaceOptionalString(json['neighborhood']),
        city: _marketplaceOptionalString(json['city']),
        capacity: _marketplaceOptionalInt(json['capacity']),
        venueType: json['venueType'] is String
            ? VenueType.fromWire(json['venueType'])
            : null,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'addr': addr,
    'lat': point.latitude,
    'lng': point.longitude,
    'area': area,
    if (neighborhood != null) 'neighborhood': neighborhood,
    if (city != null) 'city': city,
    if (capacity != null) 'capacity': capacity,
    if (venueType != null) 'venueType': venueType!.wireValue,
  };
}

class ApplicationDocument {
  const ApplicationDocument({
    required this.storageId,
    this.url,
    this.contentType,
    this.sizeBytes,
  });

  final String storageId;
  final String? url;
  final String? contentType;
  final int? sizeBytes;

  factory ApplicationDocument.fromJson(Map<String, dynamic> json) =>
      ApplicationDocument(
        storageId: _marketplaceString(json['storageId']),
        url: _marketplaceOptionalString(json['url']),
        contentType: _marketplaceOptionalString(json['contentType']),
        sizeBytes: _marketplaceOptionalInt(json['sizeBytes']),
      );
}

class OrganizationApplication {
  const OrganizationApplication({
    required this.id,
    required this.status,
    required this.orgName,
    required this.orgType,
    this.website,
    required this.contactName,
    required this.businessEmail,
    this.phone,
    this.venue,
    required this.documents,
    this.reviewNote,
    this.decidedAt,
    this.resultingOrganizationId,
    this.resultingVenueId,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final OrganizationApplicationStatus status;
  final String orgName;
  final OrganizationType orgType;
  final String? website;
  final String contactName;
  final String businessEmail;
  final String? phone;
  final ApplicationVenueDraft? venue;
  final List<ApplicationDocument> documents;
  final String? reviewNote;
  final DateTime? decidedAt;
  final String? resultingOrganizationId;
  final String? resultingVenueId;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory OrganizationApplication.fromJson(Map<String, dynamic> json) {
    final documentJson = json['documents'] ?? json['verificationDocuments'];
    return OrganizationApplication(
      id: _marketplaceString(json['_id']),
      status: OrganizationApplicationStatus.fromWire(json['status']),
      orgName: _marketplaceString(json['orgName']),
      orgType: OrganizationType.fromWire(json['orgType']),
      website: _marketplaceOptionalString(json['website']),
      contactName: _marketplaceString(json['contactName']),
      businessEmail: _marketplaceString(json['businessEmail']),
      phone: _marketplaceOptionalString(json['phone']),
      venue: json['venue'] is Map
          ? ApplicationVenueDraft.fromJson(_marketplaceMap(json['venue']))
          : null,
      documents: [
        for (final document in _marketplaceMapList(documentJson))
          ApplicationDocument.fromJson(document),
      ],
      reviewNote: _marketplaceOptionalString(json['reviewNote']),
      decidedAt: _marketplaceOptionalDate(json['decidedAt']),
      resultingOrganizationId: _marketplaceOptionalString(
        json['resultingOrganizationId'],
      ),
      resultingVenueId: _marketplaceOptionalString(json['resultingVenueId']),
      revision: _marketplaceInt(json['revision']),
      createdAt: _marketplaceDate(json['createdAt']),
      updatedAt: _marketplaceDate(json['updatedAt']),
    );
  }

  bool get editable =>
      status == OrganizationApplicationStatus.draft ||
      status == OrganizationApplicationStatus.needsInfo;
}

class AdminApplicationRow {
  const AdminApplicationRow({
    required this.application,
    required this.applicantUserId,
    required this.applicantName,
    required this.applicantEmail,
  });

  final OrganizationApplication application;
  final String applicantUserId;
  final String applicantName;
  final String applicantEmail;

  factory AdminApplicationRow.fromJson(Map<String, dynamic> json) {
    final applicant = _marketplaceMap(json['applicant']);
    return AdminApplicationRow(
      application: OrganizationApplication.fromJson(
        _marketplaceMap(json['application']),
      ),
      applicantUserId: _marketplaceString(
        json['applicantUserId'] ?? applicant['userId'],
      ),
      applicantName: _marketplaceString(
        json['applicantName'] ?? applicant['name'],
      ),
      applicantEmail: _marketplaceString(
        json['applicantEmail'] ?? applicant['email'],
      ),
    );
  }
}

class AdminApplicationPage {
  const AdminApplicationPage({
    required this.items,
    required this.continueCursor,
    required this.isDone,
  });

  final List<AdminApplicationRow> items;
  final String? continueCursor;
  final bool isDone;

  factory AdminApplicationPage.fromJson(Map<String, dynamic> json) =>
      AdminApplicationPage(
        items: [
          for (final row in _marketplaceMapList(json['page'] ?? json['items']))
            AdminApplicationRow.fromJson(row),
        ],
        continueCursor: _marketplaceOptionalString(json['continueCursor']),
        isDone: json['isDone'] == true,
      );
}

class AdminOverview {
  const AdminOverview({
    required this.submitted,
    required this.underReview,
    required this.needsInfo,
    required this.verifiedOrganizations,
    required this.suspendedOrganizations,
    required this.capped,
  });

  final int submitted;
  final int underReview;
  final int needsInfo;
  final int verifiedOrganizations;
  final int suspendedOrganizations;
  final bool capped;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final counts = _marketplaceMap(json['counts']);
    return AdminOverview(
      submitted: _marketplaceInt(counts['submittedApplications']),
      underReview: _marketplaceInt(counts['underReviewApplications']),
      needsInfo: _marketplaceInt(counts['needsInfoApplications']),
      verifiedOrganizations: _marketplaceInt(counts['verifiedOrganizations']),
      suspendedOrganizations: _marketplaceInt(counts['suspendedOrganizations']),
      capped: json['capped'] == true,
    );
  }
}

class VenueCreationResult {
  const VenueCreationResult({required this.venue, required this.created});

  final Venue venue;
  final bool created;
}

class RsvpTicket {
  const RsvpTicket({required this.payload, this.checkedInAt});

  final String payload;
  final DateTime? checkedInAt;

  factory RsvpTicket.fromJson(Map<String, dynamic> json) => RsvpTicket(
    payload: json['payload'] as String,
    checkedInAt: _optionalDate(json['checkedInAt']),
  );
}

class DoorRoster {
  const DoorRoster({
    required this.total,
    required this.checkedIn,
    required this.truncated,
  });

  final int total;
  final int checkedIn;
  final bool truncated;

  factory DoorRoster.fromJson(Map<String, dynamic> json) => DoorRoster(
    total: (json['total'] as num).toInt(),
    checkedIn: (json['checkedIn'] as num).toInt(),
    truncated: json['truncated'] as bool,
  );
}

enum DoorCheckInStatus { invalid, wrongGig, checkedIn, alreadyCheckedIn }

class DoorCheckInResult {
  const DoorCheckInResult({
    required this.status,
    this.fanName,
    this.checkedInAt,
  });

  final DoorCheckInStatus status;
  final String? fanName;
  final DateTime? checkedInAt;

  factory DoorCheckInResult.fromJson(Map<String, dynamic> json) =>
      DoorCheckInResult(
        status: DoorCheckInStatus.values.byName(json['status'] as String),
        fanName: json['fanName'] as String?,
        checkedInAt: _optionalDate(json['checkedInAt']),
      );
}

enum FanCity {
  sf,
  oak,
  berkeley,
  alameda,
  emeryville,
  richmond,
  dalyCity,
  sanMateo,
  paloAlto,
  sanJose,
  hayward,
  fremont,
  walnutCreek,
  sanRafael,
}

extension FanCityDetails on FanCity {
  String get label => switch (this) {
    FanCity.sf => 'San Francisco',
    FanCity.oak => 'Oakland',
    FanCity.berkeley => 'Berkeley',
    FanCity.alameda => 'Alameda',
    FanCity.emeryville => 'Emeryville',
    FanCity.richmond => 'Richmond',
    FanCity.dalyCity => 'Daly City',
    FanCity.sanMateo => 'San Mateo',
    FanCity.paloAlto => 'Palo Alto',
    FanCity.sanJose => 'San Jose',
    FanCity.hayward => 'Hayward',
    FanCity.fremont => 'Fremont',
    FanCity.walnutCreek => 'Walnut Creek',
    FanCity.sanRafael => 'San Rafael',
  };

  LatLng get center => switch (this) {
    FanCity.sf => const LatLng(37.7749, -122.4194),
    FanCity.oak => const LatLng(37.8044, -122.2712),
    FanCity.berkeley => const LatLng(37.8715, -122.2730),
    FanCity.alameda => const LatLng(37.7652, -122.2416),
    FanCity.emeryville => const LatLng(37.8313, -122.2852),
    FanCity.richmond => const LatLng(37.9358, -122.3477),
    FanCity.dalyCity => const LatLng(37.6879, -122.4702),
    FanCity.sanMateo => const LatLng(37.5630, -122.3255),
    FanCity.paloAlto => const LatLng(37.4419, -122.1430),
    FanCity.sanJose => const LatLng(37.3382, -121.8863),
    FanCity.hayward => const LatLng(37.6688, -122.0808),
    FanCity.fremont => const LatLng(37.5485, -121.9886),
    FanCity.walnutCreek => const LatLng(37.9101, -122.0652),
    FanCity.sanRafael => const LatLng(37.9735, -122.5311),
  };

  String get autocompleteLabel => '$label, CA';

  Iterable<String> get _locationSearchValues => [
    label,
    '$label, CA',
    '$label, California',
    ...switch (this) {
      FanCity.sf => const ['SF', 'San Fran'],
      FanCity.sanJose => const ['SJ'],
      _ => const <String>[],
    },
  ];

  bool matchesLocationQuery(String query) {
    final normalizedQuery = _normalizeLocationInput(query);
    if (normalizedQuery.isEmpty) return false;
    final queryTerms = normalizedQuery.split(' ');
    return _locationSearchValues.any((value) {
      final normalizedValue = _normalizeLocationInput(value);
      return queryTerms.every(normalizedValue.contains);
    });
  }

  bool matchesExactLocation(String input) {
    final normalizedInput = _normalizeLocationInput(input);
    return normalizedInput.isNotEmpty &&
        _locationSearchValues.any(
          (value) => _normalizeLocationInput(value) == normalizedInput,
        );
  }
}

String _normalizeLocationInput(String input) => input
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

FanCity? fanCityFromLocationInput(String input) {
  for (final city in FanCity.values) {
    if (city.matchesExactLocation(input)) return city;
  }
  return null;
}

Iterable<FanCity> fanCitySuggestions(String query) sync* {
  if (query.trim().isEmpty) return;
  for (final city in FanCity.values) {
    if (city.matchesLocationQuery(query)) yield city;
  }
}

FanCity? _fanCityFromWire(Object? value) {
  if (value is! String) return null;
  for (final city in FanCity.values) {
    if (city.name == value) return city;
  }
  return null;
}

enum FanGenreChoice { pending, selected, open }

class FanOnboarding {
  final FanCity? preferredCity;
  final FanGenreChoice genreChoice;
  final bool collapsed;

  const FanOnboarding({
    this.preferredCity,
    required this.genreChoice,
    required this.collapsed,
  });

  factory FanOnboarding.fromJson(Map<String, dynamic> json) => FanOnboarding(
    preferredCity: _fanCityFromWire(json['preferredCity']),
    genreChoice: FanGenreChoice.values.byName(json['genreChoice'] as String),
    collapsed: json['collapsed'] as bool,
  );
}

class UserProfile {
  final String name;
  final String email;
  final List<String> genres;
  final int attendedCount;
  final DateTime createdAt;
  final String? avatarUrl;
  final String? bio;
  final FanCity? homeLocation;
  final bool locationPersonalizationEnabled;
  final bool followedBandUpdatesEnabled;
  final bool profileTutorialAvailable;
  final bool profileTutorialCompleted;
  final FanOnboarding? fanOnboarding;

  const UserProfile({
    required this.name,
    required this.email,
    required this.genres,
    required this.attendedCount,
    required this.createdAt,
    this.avatarUrl,
    this.bio,
    this.homeLocation,
    this.locationPersonalizationEnabled = false,
    this.followedBandUpdatesEnabled = true,
    this.profileTutorialAvailable = true,
    this.profileTutorialCompleted = false,
    this.fanOnboarding,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    email: json['email'] as String,
    genres: List<String>.from(json['genres'] as List),
    attendedCount: (json['attendedCount'] as num).toInt(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num).toInt(),
    ),
    avatarUrl: json['avatarUrl'] is String ? json['avatarUrl'] as String : null,
    bio: json['bio'] is String ? json['bio'] as String : null,
    homeLocation: _fanCityFromWire(json['homeLocation']),
    locationPersonalizationEnabled:
        json['locationPersonalizationEnabled'] is bool
        ? json['locationPersonalizationEnabled'] as bool
        : false,
    followedBandUpdatesEnabled: json['followedBandUpdatesEnabled'] is bool
        ? json['followedBandUpdatesEnabled'] as bool
        : true,
    // Presence is a compatibility capability. Backends released before the
    // tutorial mutation omit this key; showing its controls against those
    // deployments guarantees a function-not-found error on completion.
    profileTutorialAvailable: json['profileTutorialCompleted'] is bool,
    profileTutorialCompleted: json['profileTutorialCompleted'] is bool
        ? json['profileTutorialCompleted'] as bool
        : false,
    fanOnboarding: switch (json['fanOnboarding']) {
      final Map<Object?, Object?> value => FanOnboarding.fromJson(
        Map<String, dynamic>.from(value),
      ),
      _ => null,
    },
  );

  static const _unchanged = Object();

  UserProfile copyWith({
    String? name,
    String? email,
    List<String>? genres,
    int? attendedCount,
    DateTime? createdAt,
    Object? avatarUrl = _unchanged,
    Object? bio = _unchanged,
    Object? homeLocation = _unchanged,
    bool? locationPersonalizationEnabled,
    bool? followedBandUpdatesEnabled,
    bool? profileTutorialAvailable,
    bool? profileTutorialCompleted,
    Object? fanOnboarding = _unchanged,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      genres: genres ?? this.genres,
      attendedCount: attendedCount ?? this.attendedCount,
      createdAt: createdAt ?? this.createdAt,
      avatarUrl: identical(avatarUrl, _unchanged)
          ? this.avatarUrl
          : avatarUrl as String?,
      bio: identical(bio, _unchanged) ? this.bio : bio as String?,
      homeLocation: identical(homeLocation, _unchanged)
          ? this.homeLocation
          : homeLocation as FanCity?,
      locationPersonalizationEnabled:
          locationPersonalizationEnabled ?? this.locationPersonalizationEnabled,
      followedBandUpdatesEnabled:
          followedBandUpdatesEnabled ?? this.followedBandUpdatesEnabled,
      profileTutorialAvailable:
          profileTutorialAvailable ?? this.profileTutorialAvailable,
      profileTutorialCompleted:
          profileTutorialCompleted ?? this.profileTutorialCompleted,
      fanOnboarding: identical(fanOnboarding, _unchanged)
          ? this.fanOnboarding
          : fanOnboarding as FanOnboarding?,
    );
  }
}

/// Print texture laid over a flyer's base color.
enum FlyerPattern {
  /// Photocopier scan lines: 2px bars every [FlyerStyle.pitch].
  scan,

  /// Riso dot grid: one dot per [FlyerStyle.pitch] square.
  dots,

  /// Blueprint hatching: 45° bars, half of [FlyerStyle.pitch] wide.
  hatch,

  /// Sunburst rays: alternating wedges [FlyerStyle.pitch] degrees apart.
  rays,
}

/// Xeroxed-flyer treatment: base color, a print texture over it, and the ink
/// colour text on the flyer is set in.
class FlyerStyle {
  final Color base;
  final Color patternColor;
  final Color fg;
  final FlyerPattern pattern;

  /// Texture spacing — pixels for [FlyerPattern.scan], [FlyerPattern.dots] and
  /// [FlyerPattern.hatch], degrees per wedge pair for [FlyerPattern.rays].
  final double pitch;

  const FlyerStyle({
    required this.base,
    required this.patternColor,
    required this.fg,
    this.pattern = FlyerPattern.scan,
    this.pitch = 5,
  });
}

enum GigWhen { tonight, week, later }

enum OpportunityMode {
  publicEvent('publicEvent'),
  privateBooking('privateBooking');

  const OpportunityMode(this.wireValue);

  final String wireValue;

  static OpportunityMode fromWire(Object? value) => switch (value) {
    'privateBooking' => OpportunityMode.privateBooking,
    _ => OpportunityMode.publicEvent,
  };
}

enum OpportunityVisibility {
  publicListing('public'),
  inviteOnly('inviteOnly');

  const OpportunityVisibility(this.wireValue);

  final String wireValue;

  static OpportunityVisibility fromWire(Object? value) => switch (value) {
    'inviteOnly' => OpportunityVisibility.inviteOnly,
    _ => OpportunityVisibility.publicListing,
  };
}

enum OpportunityTicketing {
  none('none'),
  rsvp('rsvp'),
  external('external'),
  paid('paid');

  const OpportunityTicketing(this.wireValue);

  final String wireValue;

  static OpportunityTicketing fromWire(Object? value) => switch (value) {
    'rsvp' => OpportunityTicketing.rsvp,
    'external' => OpportunityTicketing.external,
    'paid' => OpportunityTicketing.paid,
    _ => OpportunityTicketing.none,
  };
}

enum OpportunityStatus {
  draft('draft'),
  open('open'),
  applicationsClosed('applications_closed'),
  booking('booking'),
  confirmed('confirmed'),
  completed('completed'),
  cancelled('cancelled');

  const OpportunityStatus(this.wireValue);

  final String wireValue;

  static OpportunityStatus fromWire(Object? value) => switch (value) {
    'open' => OpportunityStatus.open,
    'applications_closed' => OpportunityStatus.applicationsClosed,
    'booking' => OpportunityStatus.booking,
    'confirmed' => OpportunityStatus.confirmed,
    'completed' => OpportunityStatus.completed,
    'cancelled' => OpportunityStatus.cancelled,
    _ => OpportunityStatus.draft,
  };
}

enum SlotRole {
  headliner('headliner'),
  support('support'),
  opener('opener');

  const SlotRole(this.wireValue);

  final String wireValue;

  static SlotRole fromWire(Object? value) => switch (value) {
    'headliner' => SlotRole.headliner,
    'opener' => SlotRole.opener,
    _ => SlotRole.support,
  };
}

enum SlotStatus {
  open('open'),
  booked('booked'),
  cancelled('cancelled');

  const SlotStatus(this.wireValue);

  final String wireValue;

  static SlotStatus fromWire(Object? value) => switch (value) {
    'booked' => SlotStatus.booked,
    'cancelled' => SlotStatus.cancelled,
    _ => SlotStatus.open,
  };
}

enum ArtistApplicationStatus {
  submitted('submitted'),
  underReview('under_review'),
  shortlisted('shortlisted'),
  offered('offered'),
  booked('booked'),
  declined('declined'),
  withdrawn('withdrawn'),
  expired('expired');

  const ArtistApplicationStatus(this.wireValue);

  final String wireValue;

  static ArtistApplicationStatus fromWire(Object? value) => switch (value) {
    'under_review' => ArtistApplicationStatus.underReview,
    'shortlisted' => ArtistApplicationStatus.shortlisted,
    'offered' => ArtistApplicationStatus.offered,
    'booked' => ArtistApplicationStatus.booked,
    'declined' => ArtistApplicationStatus.declined,
    'withdrawn' => ArtistApplicationStatus.withdrawn,
    'expired' => ArtistApplicationStatus.expired,
    _ => ArtistApplicationStatus.submitted,
  };

  bool get isActive =>
      this == ArtistApplicationStatus.submitted ||
      this == ArtistApplicationStatus.underReview ||
      this == ArtistApplicationStatus.shortlisted ||
      this == ArtistApplicationStatus.offered;
}

enum ArtistApplicationReviewAction {
  underReview('under_review'),
  shortlisted('shortlisted'),
  declined('declined');

  const ArtistApplicationReviewAction(this.wireValue);

  final String wireValue;

  static ArtistApplicationReviewAction fromWire(Object? value) =>
      switch (value) {
        'shortlisted' => ArtistApplicationReviewAction.shortlisted,
        'declined' => ArtistApplicationReviewAction.declined,
        _ => ArtistApplicationReviewAction.underReview,
      };
}

class OpportunitySlot {
  const OpportunitySlot({
    required this.id,
    required this.order,
    required this.role,
    this.setLengthMin,
    required this.guaranteeMinor,
    required this.required,
    required this.status,
    this.bandId,
  });

  final String id;
  final int order;
  final SlotRole role;
  final int? setLengthMin;
  final int guaranteeMinor;
  final bool required;
  final SlotStatus status;
  final String? bandId;

  factory OpportunitySlot.fromJson(Map<String, dynamic> json) =>
      OpportunitySlot(
        id: _marketplaceString(json['_id']),
        order: _marketplaceInt(json['order']),
        role: SlotRole.fromWire(json['role']),
        setLengthMin: _marketplaceOptionalInt(json['setLengthMin']),
        guaranteeMinor: _marketplaceInt(json['guaranteeMinor']),
        required: json['required'] == true,
        status: SlotStatus.fromWire(json['status']),
        bandId: _marketplaceOptionalString(json['bandId']),
      );
}

class Opportunity {
  const Opportunity({
    required this.id,
    required this.organizationId,
    required this.mode,
    this.venueId,
    this.venue,
    required this.title,
    required this.desc,
    this.eventType,
    this.expectedAttendance,
    required this.genres,
    required this.startsAt,
    this.doorsAt,
    this.endsAt,
    required this.ageRequirement,
    this.equipment,
    this.requirements,
    required this.flyKey,
    this.flyerUrl,
    required this.applicationsCloseAt,
    required this.visibility,
    required this.ticketing,
    this.externalUrl,
    required this.status,
    required this.slug,
    required this.revision,
    required this.applicationCount,
    required this.slots,
    required this.invitedBandIds,
    required this.createdAt,
    required this.updatedAt,
    required this.area,
    this.venueType,
    required this.currency,
  });

  final String id;
  final String organizationId;
  final OpportunityMode mode;
  final String? venueId;
  final Venue? venue;
  final String title;
  final String desc;
  final String? eventType;
  final int? expectedAttendance;
  final List<String> genres;
  final DateTime startsAt;
  final DateTime? doorsAt;
  final DateTime? endsAt;
  final AgeRequirement ageRequirement;
  final String? equipment;
  final String? requirements;
  final String flyKey;
  final String? flyerUrl;
  final DateTime applicationsCloseAt;
  final OpportunityVisibility visibility;
  final OpportunityTicketing ticketing;
  final String? externalUrl;
  final OpportunityStatus status;
  final String slug;
  final int revision;
  final int applicationCount;
  final List<OpportunitySlot> slots;
  final List<String> invitedBandIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String area;
  final VenueType? venueType;
  final String currency;

  factory Opportunity.fromJson(Map<String, dynamic> json) => Opportunity(
    id: _marketplaceString(json['_id']),
    organizationId: _marketplaceString(json['organizationId']),
    mode: OpportunityMode.fromWire(json['mode']),
    venueId: _marketplaceOptionalString(json['venueId']),
    venue: json['venue'] is Map
        ? Venue.fromJson(_marketplaceMap(json['venue']))
        : null,
    title: _marketplaceString(json['title']),
    desc: _marketplaceString(json['desc']),
    eventType: _marketplaceOptionalString(json['eventType']),
    expectedAttendance: _marketplaceOptionalInt(json['expectedAttendance']),
    genres: _marketplaceStringList(json['genres']),
    startsAt: _marketplaceDate(json['startsAt']),
    doorsAt: _marketplaceOptionalDate(json['doorsAt']),
    endsAt: _marketplaceOptionalDate(json['endsAt']),
    ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
    equipment: _marketplaceOptionalString(json['equipment']),
    requirements: _marketplaceOptionalString(json['requirements']),
    flyKey: _marketplaceString(json['flyKey']),
    flyerUrl: _marketplaceOptionalString(json['flyerUrl']),
    applicationsCloseAt: _marketplaceDate(json['applicationsCloseAt']),
    visibility: OpportunityVisibility.fromWire(json['visibility']),
    ticketing: OpportunityTicketing.fromWire(json['ticketing']),
    externalUrl: _marketplaceOptionalString(json['externalUrl']),
    status: OpportunityStatus.fromWire(json['status']),
    slug: _marketplaceString(json['slug']),
    revision: _marketplaceInt(json['revision']),
    applicationCount: _marketplaceInt(json['applicationCount']),
    slots: [
      for (final slot in _marketplaceMapList(json['slots']))
        OpportunitySlot.fromJson(slot),
    ],
    invitedBandIds: _marketplaceStringList(json['invitedBandIds']),
    createdAt: _marketplaceDate(json['createdAt']),
    updatedAt: _marketplaceDate(json['updatedAt']),
    area: _marketplaceString(json['area']),
    venueType: json['venueType'] is String
        ? VenueType.fromWire(json['venueType'])
        : null,
    currency: _marketplaceString(json['currency']),
  );
}

class SlotInput {
  const SlotInput({
    required this.role,
    this.setLengthMin,
    required this.guaranteeMinor,
    required this.required,
  });

  final SlotRole role;
  final int? setLengthMin;
  final int guaranteeMinor;
  final bool required;

  Map<String, dynamic> toJson() => {
    'role': role.wireValue,
    'setLengthMin': ?setLengthMin,
    'guaranteeMinor': guaranteeMinor,
    'required': required,
  };
}

class ArtistApplication {
  const ArtistApplication({
    required this.id,
    required this.opportunityId,
    required this.slotId,
    required this.bandId,
    required this.status,
    required this.message,
    this.askMinor,
    this.availabilityNote,
    this.lineupNote,
    this.decidedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String opportunityId;
  final String slotId;
  final String bandId;
  final ArtistApplicationStatus status;
  final String message;
  final int? askMinor;
  final String? availabilityNote;
  final String? lineupNote;
  final DateTime? decidedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ArtistApplication.fromJson(Map<String, dynamic> json) =>
      ArtistApplication(
        id: _marketplaceString(json['_id']),
        opportunityId: _marketplaceString(json['opportunityId']),
        slotId: _marketplaceString(json['slotId']),
        bandId: _marketplaceString(json['bandId']),
        status: ArtistApplicationStatus.fromWire(json['status']),
        message: _marketplaceString(json['message']),
        askMinor: _marketplaceOptionalInt(json['askMinor']),
        availabilityNote: _marketplaceOptionalString(json['availabilityNote']),
        lineupNote: _marketplaceOptionalString(json['lineupNote']),
        decidedAt: _marketplaceOptionalDate(json['decidedAt']),
        createdAt: _marketplaceDate(json['createdAt']),
        updatedAt: _marketplaceDate(json['updatedAt']),
      );
}

class ApplicantRow {
  const ApplicantRow({
    required this.application,
    required this.band,
    this.contactEmail,
  });

  final ArtistApplication application;
  final Band band;
  final String? contactEmail;

  factory ApplicantRow.fromJson(Map<String, dynamic> json) => ApplicantRow(
    application: ArtistApplication.fromJson(
      _marketplaceMap(json['application']),
    ),
    band: _bandFromJson(_marketplaceMap(json['band'])),
    contactEmail: _marketplaceOptionalString(json['contactEmail']),
  );

  // Band's legacy parser expects complete payloads. Normalize this nested
  // payload so marketplace rows keep the same tolerant parsing contract.
  static Band _bandFromJson(Map<String, dynamic> json) {
    final colorHex = _marketplaceString(json['colorHex']);
    final hex = colorHex.startsWith('#') ? colorHex.substring(1) : colorHex;
    return Band.fromJson({
      ...json,
      '_id': _marketplaceString(json['_id']),
      'slug': _marketplaceString(json['slug']),
      'name': _marketplaceString(json['name']),
      'genres': _marketplaceStringList(json['genres']),
      'area': _marketplaceString(json['area']),
      'colorHex': int.tryParse(hex, radix: 16) == null ? '000000' : hex,
      'initials': _marketplaceString(json['initials']),
      'followerCount': _marketplaceInt(json['followerCount']),
      if (json.containsKey('bio')) 'bio': _marketplaceString(json['bio']),
      'linkIg': _marketplaceOptionalString(json['linkIg']),
      'linkBc': _marketplaceOptionalString(json['linkBc']),
      'linkYt': _marketplaceOptionalString(json['linkYt']),
      'credits': _marketplaceOptionalString(json['credits']),
      if (json.containsKey('avatarUrl'))
        'avatarUrl': _marketplaceOptionalString(json['avatarUrl']),
      if (json.containsKey('bannerUrl'))
        'bannerUrl': _marketplaceOptionalString(json['bannerUrl']),
      'heroUrl': _marketplaceOptionalString(json['heroUrl']),
      'pastShows': [
        for (final show in _marketplaceMapList(json['pastShows']))
          {
            'title': _marketplaceString(show['title']),
            'meta': _marketplaceString(show['meta']),
          },
      ],
    });
  }
}

class BandApplication {
  const BandApplication({required this.application, required this.opportunity});

  final ArtistApplication application;
  final Opportunity opportunity;

  factory BandApplication.fromJson(Map<String, dynamic> json) =>
      BandApplication(
        application: ArtistApplication.fromJson(
          _marketplaceMap(json['application']),
        ),
        opportunity: Opportunity.fromJson(_marketplaceMap(json['opportunity'])),
      );
}

class BrowseItem {
  const BrowseItem({
    required this.opportunity,
    required this.invited,
    this.myApplicationStatus,
  });

  final Opportunity opportunity;
  final bool invited;
  final ArtistApplicationStatus? myApplicationStatus;

  factory BrowseItem.fromJson(Map<String, dynamic> json) => BrowseItem(
    opportunity: Opportunity.fromJson(_marketplaceMap(json['opportunity'])),
    invited: json['invited'] == true,
    myApplicationStatus: json['myApplicationStatus'] == null
        ? null
        : ArtistApplicationStatus.fromWire(json['myApplicationStatus']),
  );
}

class OpportunityPage {
  const OpportunityPage({
    required this.items,
    required this.continueCursor,
    required this.isDone,
  });

  final List<BrowseItem> items;
  final String? continueCursor;
  final bool isDone;

  factory OpportunityPage.fromJson(Map<String, dynamic> json) =>
      OpportunityPage(
        items: [
          for (final row in _marketplaceMapList(json['page'] ?? json['items']))
            BrowseItem.fromJson(row),
        ],
        continueCursor: _marketplaceOptionalString(json['continueCursor']),
        isDone: json['isDone'] == true,
      );
}

class OpportunityFilters {
  const OpportunityFilters({
    this.area,
    this.genre,
    this.venueType,
    this.minGuaranteeMinor,
  });

  final String? area;
  final String? genre;
  final VenueType? venueType;
  final int? minGuaranteeMinor;

  Map<String, dynamic> toJson() => {
    'area': ?area,
    'genre': ?genre,
    'venueType': ?venueType?.wireValue,
    'minGuaranteeMinor': ?minGuaranteeMinor,
  };
}

class GigWritePolicy {
  const GigWritePolicy({required this.bandGigWrites});

  final bool bandGigWrites;

  factory GigWritePolicy.fromJson(Map<String, dynamic> json) =>
      GigWritePolicy(bandGigWrites: json['bandGigWrites'] == true);
}

enum Ticketing { rsvp, external }

enum GigLifecycle { published, cancelled, unpublished, deleted }

enum GigProjectStatus { draft, published, cancelled, deleted }

enum GigPerformerKind { band, invited, text }

enum GigPerformerRole { headliner, support, opener }

class GigPerformer {
  final String id;
  final GigPerformerKind kind;
  final String name;
  final GigPerformerRole role;
  final String? bandId;
  final String? inviteUrl;

  const GigPerformer({
    required this.id,
    required this.kind,
    required this.name,
    required this.role,
    this.bandId,
    this.inviteUrl,
  });

  factory GigPerformer.fromJson(Map<String, dynamic> json) => GigPerformer(
    id: json['_id'] as String,
    kind: GigPerformerKind.values.byName(json['kind'] as String),
    name: json['name'] as String,
    role: GigPerformerRole.values.byName(json['role'] as String),
    bandId: json['bandId'] as String?,
    inviteUrl: json['inviteUrl'] as String?,
  );
}

class GigProject {
  final String id;
  final String bandId;
  final String? publicGigId;
  final String? publicSlug;
  final GigProjectStatus status;
  final int revision;
  final int? publishedRevision;
  final String? title;
  final DateTime? doorsAt;
  final DateTime? startsAt;
  final String? venueId;
  final int price;
  final String flyKey;
  final String? flyStorageId;
  final String? flyerUrl;
  final bool overlay;
  final String desc;
  final Ticketing ticketing;
  final AgeRequirement ageRequirement;
  final String? externalUrl;
  final String cap;
  final DateTime updatedAt;
  final List<GigPerformer> performers;

  const GigProject({
    required this.id,
    required this.bandId,
    required this.status,
    required this.revision,
    required this.price,
    required this.flyKey,
    required this.overlay,
    required this.desc,
    required this.ticketing,
    required this.ageRequirement,
    required this.cap,
    required this.updatedAt,
    required this.performers,
    this.publicGigId,
    this.publicSlug,
    this.publishedRevision,
    this.title,
    this.doorsAt,
    this.startsAt,
    this.venueId,
    this.flyStorageId,
    this.flyerUrl,
    this.externalUrl,
  });

  factory GigProject.fromJson(Map<String, dynamic> json) => GigProject(
    id: json['_id'] as String,
    bandId: json['bandId'] as String,
    publicGigId: json['publicGigId'] as String?,
    publicSlug: json['publicSlug'] as String?,
    status: GigProjectStatus.values.byName(json['status'] as String),
    revision: (json['revision'] as num).toInt(),
    publishedRevision: (json['publishedRevision'] as num?)?.toInt(),
    title: json['title'] as String?,
    doorsAt: _optionalDate(json['doorsAt']),
    startsAt: _optionalDate(json['startsAt']),
    venueId: json['venueId'] as String?,
    price: (json['price'] as num).toInt(),
    flyKey: json['flyKey'] as String,
    flyStorageId: json['flyStorageId'] as String?,
    flyerUrl: json['flyerUrl'] as String?,
    overlay: json['overlay'] as bool,
    desc: json['desc'] as String,
    ticketing: Ticketing.values.byName(json['ticketing'] as String),
    ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
    externalUrl: json['externalUrl'] as String?,
    cap: json['cap'] as String,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['updatedAt'] as num).toInt(),
    ),
    performers: [
      for (final item in json['performers'] as List)
        GigPerformer.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
  );

  bool get hasUnpublishedChanges =>
      status == GigProjectStatus.published && publishedRevision != revision;
}

DateTime? _optionalDate(Object? milliseconds) => milliseconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch((milliseconds as num).toInt());

enum AgeRequirement {
  allAges('allAges', 'All ages'),
  eighteenPlus('18Plus', '18+'),
  twentyOnePlus('21Plus', '21+');

  const AgeRequirement(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Legacy gigs did not store an age requirement. They remain visible as
  /// all-ages shows until the backend data is optionally backfilled.
  static AgeRequirement fromJson(Object? value) => switch (value) {
    '18Plus' => AgeRequirement.eighteenPlus,
    '21Plus' => AgeRequirement.twentyOnePlus,
    _ => AgeRequirement.allAges,
  };
}

class Gig {
  final String id;
  final String slug;
  final String title;
  final String venueId;
  final int price; // dollars; 0 == free
  final DateTime startsAt;
  final DateTime? doorsAt;
  final String dateShort; // "TUE JUL 28"
  final String dateLine; // "TONIGHT · DOORS 8PM"
  final String time; // "8PM / 9PM"
  final GigWhen when;
  final String flyKey;
  final List<String> lineup; // band ids
  final List<GigPerformer> performers;
  final int going;
  final List<String> genres;
  final String desc;
  final Ticketing tix;
  final String? externalUrl;
  final String? flyerUrl;
  final String cap;
  final AgeRequirement ageRequirement;
  final GigLifecycle lifecycle;
  final String? createdByBand;
  final bool discoveryListingReady;

  const Gig({
    required this.id,
    this.slug = '',
    required this.title,
    required this.venueId,
    required this.price,
    required this.startsAt,
    this.doorsAt,
    required this.dateShort,
    required this.dateLine,
    required this.time,
    required this.when,
    required this.flyKey,
    required this.lineup,
    this.performers = const [],
    required this.going,
    required this.genres,
    required this.desc,
    required this.tix,
    this.externalUrl,
    this.flyerUrl,
    this.cap = 'No cap',
    this.ageRequirement = AgeRequirement.allAges,
    this.lifecycle = GigLifecycle.published,
    this.createdByBand,
    this.discoveryListingReady = false,
  });

  /// The stable public slug when one is available, otherwise the legacy ID.
  /// Keeping the fallback here prevents older/demo records from producing an
  /// empty `/g/` link during the slug rollout.
  String get publicRef => slug.isEmpty ? id : slug;

  factory Gig.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    now ??= DateTime.now();
    final startsAtMs = (json['startsAt'] as num).toInt();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    final doorsAtMs = json['doorsAt'] as num?;
    final doorsTime = json['doorsTime'] as String;

    return Gig(
      id: json['_id'] as String,
      slug: (json['slug'] as String?) ?? json['_id'] as String,
      title: json['title'] as String,
      venueId: json['venueId'] as String,
      price: (json['price'] as num).toInt(),
      startsAt: startsAt,
      doorsAt: doorsAtMs == null
          ? startsAt
          : DateTime.fromMillisecondsSinceEpoch(doorsAtMs.toInt()),
      dateShort: _dateShortForDate(startsAt),
      dateLine: _dateLineForDate(startsAt, doorsTime, now),
      time: doorsTime,
      when: _whenForDate(startsAt, now),
      flyKey: json['flyKey'] as String,
      lineup: List<String>.from(json['lineup'] as List),
      performers: [
        for (final item in (json['performers'] as List?) ?? const [])
          GigPerformer(
            id: '',
            kind: (item as Map)['bandId'] == null
                ? GigPerformerKind.text
                : GigPerformerKind.band,
            name: item['name'] as String,
            role: GigPerformerRole.values.byName(item['role'] as String),
            bandId: item['bandId'] as String?,
          ),
      ],
      going: (json['goingCount'] as num?)?.toInt() ?? 0,
      genres: List<String>.from(json['genres'] as List),
      desc: json['desc'] as String,
      tix: Ticketing.values.byName(json['ticketing'] as String),
      externalUrl: json['externalUrl'] as String?,
      flyerUrl: json['flyerUrl'] as String?,
      cap: json['cap'] as String,
      ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
      lifecycle: GigLifecycle.values.byName(
        (json['lifecycle'] as String?) ?? 'published',
      ),
      createdByBand: json['createdByBand'] as String?,
      discoveryListingReady: json['discoveryListingReady'] == true,
    );
  }

  static GigWhen whenFor(int startsAtMs, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _whenForDate(startsAt, current);
  }

  static GigWhen _whenForDate(DateTime startsAt, DateTime now) {
    final isTonight =
        startsAt.year == now.year &&
        startsAt.month == now.month &&
        startsAt.day == now.day;
    if (isTonight) return GigWhen.tonight;
    if (startsAt.difference(now) < const Duration(days: 7)) {
      return GigWhen.week;
    }
    return GigWhen.later;
  }

  /// "8PM" from "8PM / 9PM" — the doors half of [time].
  String get doorsLabel => doorsLabelFor(time);

  static String doorsLabelFor(String doorsTime) {
    final separator = doorsTime.indexOf(' / ');
    return separator == -1 ? doorsTime : doorsTime.substring(0, separator);
  }

  static String dateShortFor(int startsAtMs) {
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _dateShortForDate(startsAt);
  }

  static String _dateShortForDate(DateTime startsAt) {
    return '${weekdayNamesUpper[startsAt.weekday - 1]} '
        '${monthNamesUpper[startsAt.month - 1]} ${startsAt.day}';
  }

  static String dateLineFor(int startsAtMs, String doorsTime, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _dateLineForDate(startsAt, doorsTime, current);
  }

  static String _dateLineForDate(
    DateTime startsAt,
    String doorsTime,
    DateTime now,
  ) {
    final doors = doorsLabelFor(doorsTime);
    if (_whenForDate(startsAt, now) == GigWhen.tonight) {
      return 'TONIGHT · DOORS $doors';
    }

    return '${weekdayNamesUpper[startsAt.weekday - 1]} · DOORS $doors';
  }

  bool get free => price == 0;
  String get priceLabel => free ? 'FREE' : '\$$price';
  int? get numericCapacity {
    final value = int.tryParse(cap.trim());
    return value != null && value > 0 ? value : null;
  }

  /// Whether this gig has the same venue-facing listing content as [other].
  /// Live RSVP counts and clock-derived labels do not change the listing.
  bool sameListing(Gig other) {
    if (id != other.id ||
        slug != other.slug ||
        title != other.title ||
        venueId != other.venueId ||
        price != other.price ||
        startsAt != other.startsAt ||
        doorsAt != other.doorsAt ||
        time != other.time ||
        flyKey != other.flyKey ||
        !listEquals(lineup, other.lineup) ||
        performers.length != other.performers.length ||
        !listEquals(genres, other.genres) ||
        desc != other.desc ||
        tix != other.tix ||
        externalUrl != other.externalUrl ||
        flyerUrl != other.flyerUrl ||
        cap != other.cap ||
        ageRequirement != other.ageRequirement ||
        lifecycle != other.lifecycle ||
        createdByBand != other.createdByBand ||
        discoveryListingReady != other.discoveryListingReady) {
      return false;
    }
    for (var index = 0; index < performers.length; index++) {
      final performer = performers[index];
      final otherPerformer = other.performers[index];
      if (performer.name != otherPerformer.name ||
          performer.role != otherPerformer.role ||
          performer.bandId != otherPerformer.bandId ||
          performer.kind != otherPerformer.kind) {
        return false;
      }
    }
    return true;
  }

  /// Recomputes the labels that depend on the current local calendar day.
  Gig relabeled({required DateTime now}) {
    final updatedWhen = _whenForDate(startsAt, now);
    final updatedDateLine = _dateLineForDate(startsAt, time, now);
    if (updatedWhen == when && updatedDateLine == dateLine) return this;
    return copyWith(when: updatedWhen, dateLine: updatedDateLine);
  }

  Gig copyWith({
    String? slug,
    String? title,
    String? venueId,
    int? price,
    DateTime? startsAt,
    DateTime? doorsAt,
    String? dateShort,
    String? dateLine,
    String? time,
    GigWhen? when,
    String? flyKey,
    List<String>? lineup,
    List<GigPerformer>? performers,
    int? going,
    List<String>? genres,
    String? desc,
    Ticketing? tix,
    String? externalUrl,
    String? flyerUrl,
    String? cap,
    AgeRequirement? ageRequirement,
    GigLifecycle? lifecycle,
    String? createdByBand,
    bool? discoveryListingReady,
  }) => Gig(
    id: id,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    venueId: venueId ?? this.venueId,
    price: price ?? this.price,
    startsAt: startsAt ?? this.startsAt,
    doorsAt: doorsAt ?? this.doorsAt,
    dateShort: dateShort ?? this.dateShort,
    dateLine: dateLine ?? this.dateLine,
    time: time ?? this.time,
    when: when ?? this.when,
    flyKey: flyKey ?? this.flyKey,
    lineup: lineup ?? this.lineup,
    performers: performers ?? this.performers,
    going: going ?? this.going,
    genres: genres ?? this.genres,
    desc: desc ?? this.desc,
    tix: tix ?? this.tix,
    externalUrl: externalUrl ?? this.externalUrl,
    flyerUrl: flyerUrl ?? this.flyerUrl,
    cap: cap ?? this.cap,
    ageRequirement: ageRequirement ?? this.ageRequirement,
    lifecycle: lifecycle ?? this.lifecycle,
    createdByBand: createdByBand ?? this.createdByBand,
    discoveryListingReady: discoveryListingReady ?? this.discoveryListingReady,
  );
}

class PastGig {
  final String title;
  final String meta;

  const PastGig(this.title, this.meta);
}

enum FanHistoryStatus { rsvped }

/// A past RSVP shown on the signed-in fan's private profile.
///
/// This deliberately says only that the fan RSVPed. Earplug has no check-in
/// signal that would let the client claim verified attendance.
class FanHistoryItem {
  final String gigId;
  final String title;
  final DateTime startsAt;
  final String venueName;
  final List<String> bandNames;
  final String flyKey;
  final String? flyerUrl;
  final FanHistoryStatus status;

  const FanHistoryItem({
    required this.gigId,
    required this.title,
    required this.startsAt,
    required this.venueName,
    required this.bandNames,
    required this.flyKey,
    required this.flyerUrl,
    required this.status,
  });

  factory FanHistoryItem.fromJson(Map<String, dynamic> json) => FanHistoryItem(
    gigId: json['gigId'] as String,
    title: json['title'] as String,
    startsAt: DateTime.fromMillisecondsSinceEpoch(
      (json['startsAt'] as num).toInt(),
    ),
    venueName: json['venueName'] as String,
    bandNames: List<String>.from(json['bandNames'] as List),
    flyKey: json['flyKey'] as String,
    flyerUrl: json['flyerUrl'] as String?,
    status: FanHistoryStatus.values.byName(json['status'] as String),
  );

  /// Compatibility for the original compact history row while the richer
  /// profile presentation can use the structured fields directly.
  String get meta => Gig.dateShortFor(startsAt.millisecondsSinceEpoch);
}

class Band {
  final String id;
  final String slug;
  final String name;
  final List<String> genres;
  final String area;
  final Color color;
  final String initials;
  final int followers;
  final String bio;
  final String? linkIg;
  final String? linkBc;
  final String? linkYt;
  final String? credits;
  final String? avatarUrl;
  final String? bannerUrl;
  final bool _avatarUrlResolved;
  final bool _bannerUrlResolved;

  /// Legacy shared artwork URL retained for older/demo payloads.
  final String? heroUrl;
  final List<String> upcoming; // gig ids
  final List<PastGig> past;
  final bool profileComplete;
  final bool discoveryProfileReady;
  final bool isSummary;

  const Band({
    required this.id,
    this.slug = '',
    required this.name,
    required this.genres,
    required this.area,
    required this.color,
    required this.initials,
    required this.followers,
    required this.bio,
    this.linkIg,
    this.linkBc,
    this.linkYt,
    this.credits,
    this.avatarUrl,
    this.bannerUrl,
    this._avatarUrlResolved = false,
    this._bannerUrlResolved = false,
    this.heroUrl,
    this.upcoming = const [],
    this.past = const [],
    this.profileComplete = false,
    this.discoveryProfileReady = false,
    this.isSummary = false,
  });

  /// The public slug when available, with the internal ID as a rollout-safe
  /// fallback for legacy records.
  String get publicRef => slug.isEmpty ? id : slug;

  factory Band.fromJson(Map<String, dynamic> json) {
    final pastShows = json['pastShows'] as List? ?? const [];

    return Band(
      id: json['_id'] as String,
      slug: (json['slug'] as String?) ?? '',
      name: json['name'] as String,
      genres: List<String>.from(json['genres'] as List),
      area: json['area'] as String,
      color: _colorFromHex(json['colorHex'] as String),
      initials: json['initials'] as String,
      followers: (json['followerCount'] as num).toInt(),
      bio: (json['bio'] as String?) ?? '',
      linkIg: json['linkIg'] as String?,
      linkBc: json['linkBc'] as String?,
      linkYt: json['linkYt'] as String?,
      credits: json['credits'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      avatarUrlResolved: json.containsKey('avatarUrl'),
      bannerUrlResolved: json.containsKey('bannerUrl'),
      heroUrl: json['heroUrl'] as String?,
      profileComplete: json['profileComplete'] == true,
      discoveryProfileReady: json['discoveryProfileReady'] == true,
      isSummary: !json.containsKey('bio'),
      upcoming: const [],
      past: [
        for (final show in pastShows)
          PastGig((show as Map)['title'] as String, show['meta'] as String),
      ],
    );
  }

  String get genreLine => genres.join(' · ');
  String get followersLabel => _compactCount(followers);
  bool get avatarUrlResolved => _avatarUrlResolved;
  String? get profileImageUrl =>
      _avatarUrlResolved ? avatarUrl : avatarUrl ?? heroUrl;
  String? get headerImageUrl =>
      _bannerUrlResolved ? bannerUrl : bannerUrl ?? heroUrl;

  /// Refreshes feed-owned summary fields while retaining full profile data.
  Band mergeSummary(Band summary, {required List<String> upcoming}) {
    final summaryResolvesAvatar = summary.avatarUrlResolved;
    return Band(
      id: id,
      slug: summary.slug,
      name: summary.name,
      genres: summary.genres,
      area: summary.area,
      color: summary.color,
      initials: summary.initials,
      followers: summary.followers,
      bio: bio,
      linkIg: linkIg,
      linkBc: linkBc,
      linkYt: linkYt,
      credits: credits,
      avatarUrl: summaryResolvesAvatar ? summary.avatarUrl : avatarUrl,
      bannerUrl: bannerUrl,
      avatarUrlResolved: summaryResolvesAvatar
          ? summary.avatarUrlResolved
          : _avatarUrlResolved,
      bannerUrlResolved: _bannerUrlResolved,
      heroUrl: heroUrl,
      upcoming: upcoming,
      past: past,
      profileComplete: summary.profileComplete,
      discoveryProfileReady: summary.discoveryProfileReady,
      isSummary: false,
    );
  }

  Band copyWith({
    String? slug,
    String? name,
    List<String>? genres,
    String? area,
    Color? color,
    String? initials,
    int? followers,
    String? bio,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
    String? avatarUrl,
    String? bannerUrl,
    bool? avatarUrlResolved,
    bool? bannerUrlResolved,
    String? heroUrl,
    List<String>? upcoming,
    bool? profileComplete,
    bool? discoveryProfileReady,
    bool? isSummary,
  }) => Band(
    id: id,
    slug: slug ?? this.slug,
    name: name ?? this.name,
    genres: genres ?? this.genres,
    area: area ?? this.area,
    color: color ?? this.color,
    initials: initials ?? this.initials,
    followers: followers ?? this.followers,
    bio: bio ?? this.bio,
    linkIg: linkIg ?? this.linkIg,
    linkBc: linkBc ?? this.linkBc,
    linkYt: linkYt ?? this.linkYt,
    credits: credits ?? this.credits,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bannerUrl: bannerUrl ?? this.bannerUrl,
    avatarUrlResolved: avatarUrlResolved ?? _avatarUrlResolved,
    bannerUrlResolved: bannerUrlResolved ?? _bannerUrlResolved,
    heroUrl: heroUrl ?? this.heroUrl,
    upcoming: upcoming ?? this.upcoming,
    past: past,
    profileComplete: profileComplete ?? this.profileComplete,
    discoveryProfileReady: discoveryProfileReady ?? this.discoveryProfileReady,
    isSummary: isSummary ?? this.isSummary,
  );
}

/// Profile-only data that intentionally stays out of feed and search payloads.
class BandProfileDetails {
  final String? credits;
  final String? linkIg;
  final String? linkBc;
  final String? linkYt;
  final List<String> memberNames;

  const BandProfileDetails({
    this.credits,
    this.linkIg,
    this.linkBc,
    this.linkYt,
    required this.memberNames,
  });

  factory BandProfileDetails.fromJson(Map<String, dynamic> json) =>
      BandProfileDetails(
        credits: json['credits'] as String?,
        linkIg: json['linkIg'] as String?,
        linkBc: json['linkBc'] as String?,
        linkYt: json['linkYt'] as String?,
        memberNames: List<String>.from(
          json['memberNames'] as List? ?? const [],
        ),
      );

  static const empty = BandProfileDetails(memberNames: []);
}

/// The seven task-oriented steps shown only to a band's administrators.
class BandSetupStatus {
  final bool profileComplete;
  final bool profileImageAdded;
  final bool musicAdded;
  final bool socialLinksAdded;
  final bool firstGigCreated;
  final bool membersInvited;
  final bool publicProfilePreviewed;

  const BandSetupStatus({
    required this.profileComplete,
    required this.profileImageAdded,
    required this.musicAdded,
    required this.socialLinksAdded,
    required this.firstGigCreated,
    required this.membersInvited,
    required this.publicProfilePreviewed,
  });

  factory BandSetupStatus.fromJson(Map<String, dynamic> json) =>
      BandSetupStatus(
        profileComplete: json['profileComplete'] == true,
        profileImageAdded: json['profileImageAdded'] == true,
        musicAdded: json['musicAdded'] == true,
        socialLinksAdded: json['socialLinksAdded'] == true,
        firstGigCreated: json['firstGigCreated'] == true,
        membersInvited: json['membersInvited'] == true,
        publicProfilePreviewed: json['publicProfilePreviewed'] == true,
      );

  List<bool> get steps => [
    profileComplete,
    profileImageAdded,
    musicAdded,
    socialLinksAdded,
    firstGigCreated,
    membersInvited,
    publicProfilePreviewed,
  ];

  int get completedCount => steps.where((step) => step).length;
}

class BandDiscoveryShow {
  final String gigId;
  final String projectId;
  final String title;
  final DateTime startsAt;

  const BandDiscoveryShow({
    required this.gigId,
    required this.projectId,
    required this.title,
    required this.startsAt,
  });

  factory BandDiscoveryShow.fromJson(Map<String, dynamic> json) =>
      BandDiscoveryShow(
        gigId: json['gigId'] as String,
        projectId: json['projectId'] as String,
        title: json['title'] as String,
        startsAt: DateTime.fromMillisecondsSinceEpoch(
          (json['startsAt'] as num).toInt(),
        ),
      );
}

class DiscoveryBoostWindow {
  final DateTime opensAt;
  final DateTime closesAt;
  final bool active;

  const DiscoveryBoostWindow({
    required this.opensAt,
    required this.closesAt,
    required this.active,
  });

  factory DiscoveryBoostWindow.fromJson(Map<String, dynamic> json) =>
      DiscoveryBoostWindow(
        opensAt: DateTime.fromMillisecondsSinceEpoch(
          (json['opensAt'] as num).toInt(),
        ),
        closesAt: DateTime.fromMillisecondsSinceEpoch(
          (json['closesAt'] as num).toInt(),
        ),
        active: json['active'] == true,
      );
}

/// The six independent criteria behind organic discovery activation.
class BandDiscoveryReadiness {
  final bool profileComplete;
  final bool profileImageReady;
  final bool clipReady;
  final bool publishedShowReady;
  final bool venuePosterReady;
  final bool publishedRevisionCurrent;
  final BandDiscoveryShow? relevantShow;
  final BandDiscoveryShow? nextEligibleShow;
  final DiscoveryBoostWindow? boostWindow;

  const BandDiscoveryReadiness({
    required this.profileComplete,
    required this.profileImageReady,
    required this.clipReady,
    required this.publishedShowReady,
    required this.venuePosterReady,
    required this.publishedRevisionCurrent,
    this.relevantShow,
    this.nextEligibleShow,
    this.boostWindow,
  });

  factory BandDiscoveryReadiness.fromJson(Map<String, dynamic> json) =>
      BandDiscoveryReadiness(
        profileComplete: json['profileComplete'] == true,
        profileImageReady: json['profileImageReady'] == true,
        clipReady: json['clipReady'] == true,
        publishedShowReady: json['publishedShowReady'] == true,
        venuePosterReady: json['venuePosterReady'] == true,
        publishedRevisionCurrent: json['publishedRevisionCurrent'] == true,
        relevantShow: switch (json['relevantShow']) {
          final Map<Object?, Object?> value => BandDiscoveryShow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
        nextEligibleShow: switch (json['nextEligibleShow']) {
          final Map<Object?, Object?> value => BandDiscoveryShow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
        boostWindow: switch (json['boostWindow']) {
          final Map<Object?, Object?> value => DiscoveryBoostWindow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
      );

  List<bool> get steps => [
    profileComplete,
    profileImageReady,
    clipReady,
    publishedShowReady,
    venuePosterReady,
    publishedRevisionCurrent,
  ];

  int get completedCount => steps.where((step) => step).length;
}

/// Every editable band-profile field, submitted in one backend transaction.
class BandProfileUpdate {
  final String bandId;
  final String name;
  final List<String> genres;
  final String area;
  final String bio;
  final String linkIg;
  final String linkBc;
  final String linkYt;
  final String credits;

  const BandProfileUpdate({
    required this.bandId,
    required this.name,
    required this.genres,
    required this.area,
    required this.bio,
    required this.linkIg,
    required this.linkBc,
    required this.linkYt,
    required this.credits,
  });
}

class BandInvite {
  final String bandId;
  final String token;
  final DateTime expiresAt;
  final bool revoked;
  final bool expired;

  const BandInvite({
    required this.bandId,
    required this.token,
    required this.expiresAt,
    required this.revoked,
    required this.expired,
  });

  factory BandInvite.fromJson(Map<String, dynamic> json) => BandInvite(
    bandId: json['bandId'] as String,
    token: json['token'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['expiresAt'] as num).toInt(),
    ),
    revoked: json['revoked'] == true,
    expired: json['expired'] == true,
  );

  String get url => publicWebUrl('join/$token');
}

/// The deliberately small public payload used before a recipient confirms.
class BandInviteResolution {
  final String bandId;
  final String bandName;
  final String initials;
  final Color color;

  const BandInviteResolution({
    required this.bandId,
    required this.bandName,
    required this.initials,
    required this.color,
  });

  factory BandInviteResolution.fromJson(Map<String, dynamic> json) =>
      BandInviteResolution(
        bandId: json['bandId'] as String,
        bandName: json['bandName'] as String,
        initials: json['initials'] as String,
        color: _colorFromHex(json['colorHex'] as String),
      );
}

class BandInviteAcceptance {
  final String bandId;
  final bool membershipCreated;

  const BandInviteAcceptance({
    required this.bandId,
    required this.membershipCreated,
  });

  factory BandInviteAcceptance.fromJson(Map<String, dynamic> json) =>
      BandInviteAcceptance(
        bandId: json['bandId'] as String,
        membershipCreated: json['membershipCreated'] == true,
      );
}

/// The small public payload shown before a band claims a lineup invitation.
class PerformerInviteResolution {
  final String performerName;
  final String gigTitle;

  const PerformerInviteResolution({
    required this.performerName,
    required this.gigTitle,
  });

  factory PerformerInviteResolution.fromJson(Map<String, dynamic> json) =>
      PerformerInviteResolution(
        performerName: json['performerName'] as String,
        gigTitle: json['gigTitle'] as String,
      );
}

enum MediaKind { video, photo }

class BandArchiveResult {
  const BandArchiveResult({
    required this.bandId,
    required this.archivedAt,
    required this.alreadyArchived,
  });

  final String bandId;
  final DateTime archivedAt;
  final bool alreadyArchived;

  factory BandArchiveResult.fromJson(Map<String, dynamic> json) =>
      BandArchiveResult(
        bandId: json['bandId'] as String,
        archivedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['archivedAt'] as num).toInt(),
        ),
        alreadyArchived: json['alreadyArchived'] == true,
      );
}

class BandArchiveStatus {
  const BandArchiveStatus({required this.bandId, required this.archivedAt});

  final String bandId;
  final DateTime? archivedAt;

  bool get archived => archivedAt != null;

  factory BandArchiveStatus.fromJson(Map<String, dynamic> json) =>
      BandArchiveStatus(
        bandId: json['bandId'] as String,
        archivedAt: json['archivedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['archivedAt'] as num).toInt(),
              ),
      );
}

class BandMedia {
  final String id;
  final String bandId;
  final MediaKind kind;
  final String? url;
  final String? thumbnailUrl;
  final String title;
  final String? caption;
  final int? sizeBytes;
  final int? views;
  final int? lengthSec;
  final bool pinned;
  final int order;
  final bool isHero;
  final bool isAvatar;
  final bool isBanner;

  const BandMedia({
    required this.id,
    required this.bandId,
    required this.kind,
    required this.url,
    this.thumbnailUrl,
    required this.title,
    required this.caption,
    required this.sizeBytes,
    required this.views,
    required this.lengthSec,
    required this.pinned,
    required this.order,
    required this.isHero,
    this.isAvatar = false,
    this.isBanner = false,
  });

  factory BandMedia.fromJson(Map<String, dynamic> json) => BandMedia(
    id: json['_id'] as String,
    bandId: json['bandId'] as String,
    kind: MediaKind.values.byName(json['kind'] as String),
    url: json['url'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    title: json['title'] as String,
    caption: json['caption'] as String?,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    views: (json['views'] as num?)?.toInt(),
    lengthSec: (json['lengthSec'] as num?)?.toInt(),
    pinned: json['pinned'] as bool,
    order: (json['order'] as num).toInt(),
    isHero: json['isHero'] as bool,
    isAvatar: json['isAvatar'] as bool? ?? false,
    isBanner: json['isBanner'] as bool? ?? json['isHero'] as bool,
  );

  bool get isVideo => kind == MediaKind.video;

  String get lenLabel {
    if (lengthSec == null) return '';
    final seconds = (lengthSec! % 60).toString().padLeft(2, '0');
    return '${lengthSec! ~/ 60}:$seconds';
  }

  String get viewsLabel =>
      views == null ? '' : '${_compactCount(views!)} views';

  BandMedia copyWith({bool? pinned, int? order, String? title}) => BandMedia(
    id: id,
    bandId: bandId,
    kind: kind,
    url: url,
    thumbnailUrl: thumbnailUrl,
    title: title ?? this.title,
    caption: caption,
    sizeBytes: sizeBytes,
    views: views,
    lengthSec: lengthSec,
    pinned: pinned ?? this.pinned,
    order: order ?? this.order,
    isHero: isHero,
    isAvatar: isAvatar,
    isBanner: isBanner,
  );
}

Color _colorFromHex(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

String _compactCount(num count) {
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return count == count.roundToDouble() ? '${count.toInt()}' : '$count';
}
