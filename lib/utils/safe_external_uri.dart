/// Validates document and attachment links before handing them to the platform.
/// This does not establish that an HTTPS website is trustworthy.
Uri? safeExternalDocumentUri(String raw) {
  final value = raw.trim();
  if (value.isEmpty || RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
