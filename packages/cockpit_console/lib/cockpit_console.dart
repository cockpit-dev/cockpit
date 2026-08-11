/// Cockpit Console - desktop GUI client for Cockpit E2E automation.
///
/// Provides a Linear / Vercel inspired interface for managing workspaces,
/// targets, test documents (YAML / JSON), run execution, live event streams,
/// and AI-assisted test authoring. Uses hooks_riverpod for state management,
/// hive_ce for persistent preferences, and kache_hive_ce for API response
/// caching.
library;

export 'src/cockpit_console_app.dart';
export 'src/providers/core_providers.dart';
export 'src/providers/data_providers.dart';
export 'src/providers/preferences_store.dart';
export 'src/providers/response_cache.dart';
export 'src/theme/console_colors.dart';
export 'src/theme/console_palette.dart';
export 'src/theme/console_theme.dart';
export 'src/ui/navigation/console_nav.dart';
