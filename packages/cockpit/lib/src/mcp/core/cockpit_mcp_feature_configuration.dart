import 'cockpit_mcp_feature_category.dart';
import 'cockpit_mcp_feature_descriptor.dart';

enum CockpitMcpProfile {
  core,
  dart,
  flutter,
  app,
  e2e,
  all;

  static CockpitMcpProfile parse(String value) {
    for (final profile in values) {
      if (profile.name == value) return profile;
    }
    throw FormatException('Unknown MCP profile $value.');
  }
}

final class CockpitMcpFeatureConfiguration {
  const CockpitMcpFeatureConfiguration({
    this.enabledNames = const <String>{},
    this.disabledNames = const <String>{},
  });

  factory CockpitMcpFeatureConfiguration.forProfile(
    CockpitMcpProfile profile, {
    Set<String> enabledNames = const <String>{},
    Set<String> disabledNames = const <String>{},
  }) {
    final profileNames = switch (profile) {
      CockpitMcpProfile.core => const <String>{},
      CockpitMcpProfile.dart => const <String>{'dart'},
      CockpitMcpProfile.flutter => const <String>{'dart', 'flutter'},
      CockpitMcpProfile.app => const <String>{'app'},
      CockpitMcpProfile.e2e => const <String>{'app', 'e2e'},
      CockpitMcpProfile.all => const <String>{'all'},
    };
    return CockpitMcpFeatureConfiguration(
      enabledNames: <String>{...profileNames, ...enabledNames},
      disabledNames: disabledNames,
    );
  }

  final Set<String> enabledNames;
  final Set<String> disabledNames;

  bool isEnabled(CockpitMcpFeatureDescriptor definition) {
    if (disabledNames.contains(definition.name)) {
      return false;
    }
    if (enabledNames.contains(definition.name)) {
      return true;
    }

    for (final category in _categoriesInPrecedenceOrder(
      definition.categories,
    )) {
      final categoryName = category.serializedName;
      if (disabledNames.contains(categoryName)) {
        return false;
      }
      if (enabledNames.contains(categoryName)) {
        return true;
      }
    }

    return definition.enabledByDefault;
  }

  Iterable<CockpitMcpFeatureCategory> _categoriesInPrecedenceOrder(
    List<CockpitMcpFeatureCategory> categories,
  ) sync* {
    final seen = <CockpitMcpFeatureCategory>{...categories};
    final queue = <CockpitMcpFeatureCategory>[];

    void insert(CockpitMcpFeatureCategory category) {
      final priority = _distanceToTop(category);
      for (var index = 0; index < queue.length; index++) {
        final item = queue[index];
        if (_distanceToTop(item) < priority) {
          queue.insert(index, category);
          return;
        }
      }
      queue.add(category);
    }

    categories.forEach(insert);
    while (queue.isNotEmpty) {
      final category = queue.removeAt(0);
      yield category;
      final parent = category.parent;
      if (parent != null && seen.add(parent)) {
        insert(parent);
      }
    }
  }

  int _distanceToTop(CockpitMcpFeatureCategory category) {
    var result = 0;
    var parent = category.parent;
    while (parent != null) {
      result++;
      parent = parent.parent;
    }
    return result;
  }
}
