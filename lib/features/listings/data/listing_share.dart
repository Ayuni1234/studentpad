/// Set STUDENTPAD_PUBLIC_WEB_ORIGIN for release builds to make shared links
/// use the deployed, canonical StudentPad domain.
const studentPadPublicWebOrigin =
    String.fromEnvironment('STUDENTPAD_PUBLIC_WEB_ORIGIN');

Uri listingShareUri(String listingId) {
  final origin = studentPadPublicWebOrigin.trim().isEmpty
      ? Uri.base.origin
      : studentPadPublicWebOrigin.trim();
  return Uri.parse(origin).replace(
    path: '/listing/${Uri.encodeComponent(listingId)}',
    query: null,
    fragment: null,
  );
}
