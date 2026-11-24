/// Product scope switches for the GHST app.
///
/// The project topic is GPS real-time delivery: customer shipping orders,
/// driver dispatch / tracking, and operator administration. Commerce modules
/// (food & shopping marketplace, merchant storefronts, cart, flash sale,
/// lucky wheel / blind box) are kept in the codebase but hidden from the UI.
///
/// Re-enable at build time with `--dart-define=GHST_COMMERCE=true`.
class GhstFeatures {
  GhstFeatures._();

  /// Whether marketplace / merchant / promo-game surfaces are visible.
  ///
  /// Mutable only so widget tests that cover the legacy commerce flows can
  /// opt back in; production code must treat it as read-only.
  static bool commerceEnabled = const bool.fromEnvironment('GHST_COMMERCE');
}
