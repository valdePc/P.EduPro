/// Recognizes reserved document prefixes without changing the Firestore ID.
bool isInternalSchoolDocumentId(String id) {
  final normalized = id.toLowerCase();
  return normalized.startsWith('valmichapp_admin_') ||
      normalized.startsWith('eduproapp_admin_');
}
