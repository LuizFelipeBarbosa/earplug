const publicWebOrigin = 'https://earplug.app';
const publicWebHost = 'earplug.app';
const organizerApplyPath = '/org/apply';

const legalTermsUrl = '$publicWebOrigin/legal/terms';
const legalPrivacyUrl = '$publicWebOrigin/legal/privacy';
const legalOrganizerAgreementUrl = '$publicWebOrigin/legal/organizer-agreement';
const legalArtistAgreementUrl = '$publicWebOrigin/legal/artist-agreement';
const legalHostAgreementUrl = '$publicWebOrigin/legal/host-agreement';

/// Flip to true when counsel's legal text is live at the URLs above.
const bool legalEffective = false;

String publicWebUrl(String path) =>
    '$publicWebOrigin/${_trimLeadingSlash(path)}';

String publicWebDisplayUrl(String path) =>
    '$publicWebHost/${_trimLeadingSlash(path)}';

String _trimLeadingSlash(String path) =>
    path.startsWith('/') ? path.substring(1) : path;
