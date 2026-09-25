const meowWatchThemeIds = <String>['cozy', 'cinemaNoir', 'glassAurora'];

String normalizeMeowWatchTheme(String theme) =>
    meowWatchThemeIds.contains(theme) ? theme : 'cozy';
