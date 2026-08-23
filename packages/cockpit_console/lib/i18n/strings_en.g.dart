///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$app$en app = Translations$app$en.internal(_root);
	late final Translations$common$en common = Translations$common$en.internal(_root);
	late final Translations$language$en language = Translations$language$en.internal(_root);
	late final Translations$nav$en nav = Translations$nav$en.internal(_root);
	late final Translations$shell$en shell = Translations$shell$en.internal(_root);
	late final Translations$dashboard$en dashboard = Translations$dashboard$en.internal(_root);
	late final Translations$statusBar$en statusBar = Translations$statusBar$en.internal(_root);
	late final Translations$projects$en projects = Translations$projects$en.internal(_root);
	late final Translations$targets$en targets = Translations$targets$en.internal(_root);
	late final Translations$tests$en tests = Translations$tests$en.internal(_root);
	late final Translations$runs$en runs = Translations$runs$en.internal(_root);
	late final Translations$actions$en actions = Translations$actions$en.internal(_root);
	late final Translations$ai$en ai = Translations$ai$en.internal(_root);
	late final Translations$sessions$en sessions = Translations$sessions$en.internal(_root);
}

// Path: app
class Translations$app$en {
	Translations$app$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cockpit Console'
	String get title => 'Cockpit Console';

	/// en: 'Connecting to Cockpit'
	String get connecting => 'Connecting to Cockpit';

	/// en: 'Checking daemon health and Supervisor capabilities.'
	String get checking => 'Checking daemon health and Supervisor capabilities.';
}

// Path: common
class Translations$common$en {
	Translations$common$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Could not copy'
	String get copyFailed => 'Could not copy';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Unknown'
	String get unknown => 'Unknown';

	/// en: 'Not set'
	String get notSet => 'Not set';

	/// en: 'Previous page'
	String get previousPage => 'Previous page';

	/// en: 'Next page'
	String get nextPage => 'Next page';

	/// en: '{{start}}–{{end}} of {{total}}'
	String pageRange({required Object start, required Object end, required Object total}) => '${start}–${end} of ${total}';
}

// Path: language
class Translations$language$en {
	Translations$language$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Language'
	String get title => 'Language';

	/// en: 'Follow system'
	String get system => 'Follow system';

	/// en: 'English'
	String get english => 'English';

	/// en: '简体中文'
	String get simplifiedChinese => '简体中文';
}

// Path: nav
class Translations$nav$en {
	Translations$nav$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Dashboard'
	String get dashboard => 'Dashboard';

	/// en: 'Projects'
	String get projects => 'Projects';

	/// en: 'Apps & devices'
	String get appsDevices => 'Apps & devices';

	/// en: 'Live sessions'
	String get liveSessions => 'Live sessions';

	/// en: 'Tests'
	String get tests => 'Tests';

	/// en: 'Test runs'
	String get testRuns => 'Test runs';

	/// en: 'Actions'
	String get actions => 'Actions';

	/// en: 'AI Assistant'
	String get aiAssistant => 'AI Assistant';
}

// Path: shell
class Translations$shell$en {
	Translations$shell$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Offline'
	String get offline => 'Offline';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Degraded'
	String get degraded => 'Degraded';

	/// en: 'Toggle theme'
	String get toggleTheme => 'Toggle theme';

	/// en: 'Close navigation'
	String get closeNavigation => 'Close navigation';

	/// en: 'Open navigation'
	String get openNavigation => 'Open navigation';

	/// en: 'Expand navigation'
	String get expandNavigation => 'Expand navigation';

	/// en: 'Collapse navigation'
	String get collapseNavigation => 'Collapse navigation';
}

// Path: dashboard
class Translations$dashboard$en {
	Translations$dashboard$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Dashboard'
	String get title => 'Dashboard';

	/// en: 'Supervisor status and system overview'
	String get subtitle => 'Supervisor status and system overview';

	/// en: 'Start daemon'
	String get startDaemon => 'Start daemon';

	/// en: 'Restart daemon'
	String get restartDaemon => 'Restart daemon';

	/// en: 'System operational'
	String get systemOperational => 'System operational';

	/// en: 'Daemon running, API disconnected'
	String get daemonApiDisconnected => 'Daemon running, API disconnected';

	/// en: 'Daemon offline'
	String get daemonOffline => 'Daemon offline';

	/// en: 'API version'
	String get apiVersion => 'API version';

	/// en: 'Engine'
	String get engine => 'Engine';

	/// en: 'Started'
	String get started => 'Started';

	/// en: 'Operations'
	String get operations => 'Operations';

	/// en: '{{count}}d ago'
	String daysAgo({required Object count}) => '${count}d ago';

	/// en: '{{count}}h ago'
	String hoursAgo({required Object count}) => '${count}h ago';

	/// en: '{{count}}m ago'
	String minutesAgo({required Object count}) => '${count}m ago';

	/// en: 'Just now'
	String get justNow => 'Just now';

	/// en: 'Server information'
	String get serverInformation => 'Server information';

	/// en: 'Instance ID'
	String get instanceId => 'Instance ID';

	/// en: 'Engine version'
	String get engineVersion => 'Engine version';

	/// en: 'Started at'
	String get startedAt => 'Started at';

	/// en: 'Connecting to Supervisor'
	String get connectingTitle => 'Connecting to Supervisor';

	/// en: 'Establishing daemon connection and reading capabilities.'
	String get connectingDescription => 'Establishing daemon connection and reading capabilities.';

	/// en: 'Cannot connect to Supervisor'
	String get disconnectedTitle => 'Cannot connect to Supervisor';

	/// en: 'Retry connection'
	String get retryConnection => 'Retry connection';
}

// Path: statusBar
class Translations$statusBar$en {
	Translations$statusBar$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Daemon healthy'
	String get daemonHealthy => 'Daemon healthy';

	/// en: 'Daemon degraded'
	String get daemonDegraded => 'Daemon degraded';

	/// en: 'Daemon offline'
	String get daemonOffline => 'Daemon offline';

	/// en: 'API v{{version}}'
	String apiVersion({required Object version}) => 'API v${version}';
}

// Path: projects
class Translations$projects$en {
	Translations$projects$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Projects'
	String get title => 'Projects';

	/// en: 'Choose which local folders and projects Cockpit can use'
	String get subtitle => 'Choose which local folders and projects Cockpit can use';

	/// en: 'Add project'
	String get addProject => 'Add project';

	/// en: 'Allowed folders'
	String get allowedFolders => 'Allowed folders';

	/// en: 'Add folder'
	String get addFolder => 'Add folder';

	/// en: 'Hide removed history'
	String get hideRemovedHistory => 'Hide removed history';

	/// en: 'Show removed history ({{count}})'
	String showRemovedHistory({required Object count}) => 'Show removed history (${count})';

	/// en: 'Removed folders'
	String get removedFolders => 'Removed folders';

	/// en: 'Removed projects'
	String get removedProjects => 'Removed projects';

	/// en: 'No allowed folders'
	String get noAllowedFolders => 'No allowed folders';

	/// en: 'Add a local folder before adding projects inside it.'
	String get noAllowedFoldersDescription => 'Add a local folder before adding projects inside it.';

	/// en: 'Remove folder from Cockpit'
	String get removeFolderTooltip => 'Remove folder from Cockpit';

	/// en: 'Remove allowed folder?'
	String get removeFolderTitle => 'Remove allowed folder?';

	/// en: 'Cockpit will stop using {{path}} and remove its registered projects. Project files stay on disk. Removing now may interrupt active Cockpit sessions.'
	String removeFolderDescription({required Object path}) => 'Cockpit will stop using ${path} and remove its registered projects. Project files stay on disk. Removing now may interrupt active Cockpit sessions.';

	/// en: 'Removed folder from Cockpit'
	String get folderRemoved => 'Removed folder from Cockpit';

	/// en: 'Could not remove folder from Cockpit'
	String get folderRemoveFailed => 'Could not remove folder from Cockpit';

	/// en: 'Finish work and remove'
	String get finishWorkRemove => 'Finish work and remove';

	/// en: 'Remove now'
	String get removeNow => 'Remove now';

	/// en: 'Ready'
	String get stateReady => 'Ready';

	/// en: 'Removing'
	String get stateRemoving => 'Removing';

	/// en: 'Removed'
	String get stateRemoved => 'Removed';

	/// en: 'No projects added'
	String get noProjects => 'No projects added';

	/// en: 'Add a project directory to connect apps and run tests.'
	String get noProjectsDescription => 'Add a project directory to connect apps and run tests.';

	/// en: 'Removed project {{name}}'
	String removedProjectSemantics({required Object name}) => 'Removed project ${name}';

	/// en: 'Select project {{name}}'
	String selectProjectSemantics({required Object name}) => 'Select project ${name}';

	/// en: '{{workspace}} · root {{root}}'
	String workspaceIdentity({required Object workspace, required Object root}) => '${workspace} · root ${root}';

	/// en: 'Update project location'
	String get updateLocationTooltip => 'Update project location';

	/// en: 'Current'
	String get current => 'Current';

	/// en: 'Remove project from Cockpit'
	String get removeProjectTooltip => 'Remove project from Cockpit';

	/// en: 'Remove project?'
	String get removeProjectTitle => 'Remove project?';

	/// en: 'Cockpit will stop using {{path}}. Project files stay on disk. Removing now may interrupt active Cockpit sessions.'
	String removeProjectDescription({required Object path}) => 'Cockpit will stop using ${path}. Project files stay on disk. Removing now may interrupt active Cockpit sessions.';

	/// en: 'Removed project from Cockpit'
	String get projectRemoved => 'Removed project from Cockpit';

	/// en: 'Could not remove project'
	String get projectRemoveFailed => 'Could not remove project';

	/// en: 'Choose an absolute folder path.'
	String get absoluteFolderError => 'Choose an absolute folder path.';

	/// en: 'Could not add the folder.'
	String get addFolderFailed => 'Could not add the folder.';

	/// en: 'Add allowed folder'
	String get addFolderTitle => 'Add allowed folder';

	/// en: 'Cockpit can only use projects inside folders you add here. Nothing is uploaded.'
	String get addFolderDescription => 'Cockpit can only use projects inside folders you add here. Nothing is uploaded.';

	/// en: 'Folder path'
	String get folderPath => 'Folder path';

	/// en: '/absolute/path/to/project'
	String get folderPathHint => '/absolute/path/to/project';

	/// en: 'Name (optional)'
	String get optionalName => 'Name (optional)';

	/// en: 'My Project'
	String get projectNameHint => 'My Project';

	/// en: 'Add an allowed folder first.'
	String get allowedFolderRequired => 'Add an allowed folder first.';

	/// en: 'Choose an absolute project directory.'
	String get absoluteProjectError => 'Choose an absolute project directory.';

	/// en: 'Could not add the project.'
	String get addProjectFailed => 'Could not add the project.';

	/// en: 'Allowed folder'
	String get allowedFolder => 'Allowed folder';

	/// en: 'Project directory'
	String get projectDirectory => 'Project directory';

	/// en: 'No allowed folders are available.'
	String get noAllowedFoldersAvailable => 'No allowed folders are available.';

	/// en: 'Choose the project’s new absolute directory.'
	String get newAbsoluteProjectError => 'Choose the project’s new absolute directory.';

	/// en: 'Could not update the project location.'
	String get updateLocationFailed => 'Could not update the project location.';

	/// en: 'Update project location'
	String get updateLocationTitle => 'Update project location';

	/// en: 'Current directory'
	String get currentDirectory => 'Current directory';

	/// en: 'New project directory'
	String get newProjectDirectory => 'New project directory';

	/// en: 'Update location'
	String get updateLocation => 'Update location';
}

// Path: targets
class Translations$targets$en {
	Translations$targets$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Apps and devices'
	String get title => 'Apps and devices';

	/// en: 'Find and connect the apps and devices used by this project'
	String get subtitle => 'Find and connect the apps and devices used by this project';

	/// en: 'Select a project'
	String get selectProject => 'Select a project';

	/// en: 'Choose a project from the Projects page to view its apps and devices.'
	String get selectProjectDescription => 'Choose a project from the Projects page to view its apps and devices.';

	/// en: 'Choose project'
	String get chooseProject => 'Choose project';

	/// en: 'Could not find apps and devices: {{error}}'
	String discoverFailed({required Object error}) => 'Could not find apps and devices: ${error}';

	/// en: 'Find apps and devices'
	String get find => 'Find apps and devices';

	/// en: 'Ready to use'
	String get readyToUse => 'Ready to use';

	/// en: 'No apps or devices added'
	String get noneAdded => 'No apps or devices added';

	/// en: 'Find available apps and devices, then add the one you need.'
	String get noneAddedDescription => 'Find available apps and devices, then add the one you need.';

	/// en: 'Available to add'
	String get availableToAdd => 'Available to add';

	/// en: 'No apps or devices found'
	String get noneFound => 'No apps or devices found';

	/// en: 'Connect or start a device, then try finding again.'
	String get noneFoundDescription => 'Connect or start a device, then try finding again.';

	/// en: 'Could not load apps and devices'
	String get loadFailed => 'Could not load apps and devices';

	/// en: 'Running'
	String get running => 'Running';

	/// en: 'Ready'
	String get ready => 'Ready';

	/// en: 'App {{name}}'
	String appSemantics({required Object name}) => 'App ${name}';

	/// en: 'The app is running, but its Cockpit session is not available yet.'
	String get sessionUnavailable => 'The app is running, but its Cockpit session is not available yet.';

	/// en: 'Monitor live session'
	String get monitorSession => 'Monitor live session';

	/// en: 'Start app or device'
	String get start => 'Start app or device';

	/// en: 'Add {{name}}'
	String addNamed({required Object name}) => 'Add ${name}';

	late final Translations$targets$kind$en kind = Translations$targets$kind$en.internal(_root);
	late final Translations$targets$mode$en mode = Translations$targets$mode$en.internal(_root);
	late final Translations$targets$environment$en environment = Translations$targets$environment$en.internal(_root);

	/// en: 'Entries must use KEY=VALUE syntax: “{{line}}”.'
	String keyValueSyntaxError({required Object line}) => 'Entries must use KEY=VALUE syntax: “${line}”.';

	/// en: '{{kind}} targets require an app ID.'
	String appIdRequired({required Object kind}) => '${kind} targets require an app ID.';

	/// en: 'Added {{name}}'
	String added({required Object name}) => 'Added ${name}';

	/// en: 'Add app or device'
	String get addTitle => 'Add app or device';

	/// en: 'Device'
	String get device => 'Device';

	/// en: 'Platform'
	String get platform => 'Platform';

	/// en: 'Device ID'
	String get deviceId => 'Device ID';

	/// en: 'Type'
	String get type => 'Type';

	/// en: 'Launch file'
	String get launchFile => 'Launch file';

	/// en: 'Optional'
	String get optional => 'Optional';

	/// en: 'None'
	String get none => 'None';

	/// en: 'App identifier'
	String get appIdentifier => 'App identifier';

	/// en: 'Required'
	String get required => 'Required';

	/// en: 'Flavor'
	String get flavor => 'Flavor';

	/// en: 'Optional (iOS)'
	String get optionalIos => 'Optional (iOS)';

	/// en: 'Environment'
	String get environmentLabel => 'Environment';

	/// en: 'Mode'
	String get modeLabel => 'Mode';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Launch timeout must be an integer number of milliseconds.'
	String get timeoutIntegerError => 'Launch timeout must be an integer number of milliseconds.';

	/// en: 'Launch timeout must be between 1,000 and 1,800,000 ms.'
	String get timeoutRangeError => 'Launch timeout must be between 1,000 and 1,800,000 ms.';

	/// en: 'Launched {{target}}'
	String launched({required Object target}) => 'Launched ${target}';

	/// en: 'Launch {{kind}}'
	String launchTitle({required Object kind}) => 'Launch ${kind}';

	/// en: 'Target'
	String get target => 'Target';

	/// en: 'This target is activated through system control. Launch mode and Flutter configuration are not accepted.'
	String get systemControlNote => 'This target is activated through system control. Launch mode and Flutter configuration are not accepted.';

	/// en: 'Launch timeout (ms)'
	String get launchTimeout => 'Launch timeout (ms)';

	/// en: 'Default (600,000)'
	String get launchTimeoutDefault => 'Default (600,000)';

	/// en: 'Launch configuration'
	String get launchConfiguration => 'Launch configuration';

	/// en: 'Dart defines'
	String get dartDefines => 'Dart defines';

	/// en: 'KEY=VALUE, one per line'
	String get keyValueLines => 'KEY=VALUE, one per line';

	/// en: 'Dart define files'
	String get dartDefineFiles => 'Dart define files';

	/// en: 'config/*.json, one per line'
	String get fileLines => 'config/*.json, one per line';

	/// en: 'Flutter arguments'
	String get flutterArgs => 'Flutter arguments';

	/// en: '--verbose, one per line'
	String get flutterArgsLines => '--verbose, one per line';

	/// en: 'Launch'
	String get launch => 'Launch';
}

// Path: tests
class Translations$tests$en {
	Translations$tests$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Tests'
	String get title => 'Tests';

	/// en: 'Create and check case or suite files in LON, JSON, or YAML'
	String get subtitle => 'Create and check case or suite files in LON, JSON, or YAML';

	/// en: 'Select a project'
	String get selectProject => 'Select a project';

	/// en: 'Choose a project from the Projects page to view its test files.'
	String get selectProjectDescription => 'Choose a project from the Projects page to view its test files.';

	/// en: 'Choose project'
	String get chooseProject => 'Choose project';

	/// en: 'Could not load test files'
	String get loadFailed => 'Could not load test files';

	/// en: 'Could not read {{path}}: {{error}}'
	String readFailed({required Object path, required Object error}) => 'Could not read ${path}: ${error}';

	/// en: 'Discard unsaved changes?'
	String get discardTitle => 'Discard unsaved changes?';

	/// en: 'The editor contains changes that have not been saved.'
	String get discardDescription => 'The editor contains changes that have not been saved.';

	/// en: 'Keep editing'
	String get keepEditing => 'Keep editing';

	/// en: 'Discard changes'
	String get discardChanges => 'Discard changes';

	/// en: 'Test files'
	String get files => 'Test files';

	/// en: 'New test'
	String get newTest => 'New test';

	/// en: 'No test files yet'
	String get emptyTitle => 'No test files yet';

	/// en: 'Create a test, save it, then check it before running.'
	String get emptyDescription => 'Create a test, save it, then check it before running.';

	/// en: 'Test suite'
	String get suite => 'Test suite';

	/// en: '(one) {Test suite · {{n}} case} (other) {Test suite · {{n}} cases}'
	String suiteCases({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Test suite · ${n} case',
		other: 'Test suite · ${n} cases',
	);

	/// en: 'Test case'
	String get testCase => 'Test case';

	/// en: 'Test file path'
	String get filePath => 'Test file path';

	/// en: 'Relative to project, for example cockpit/e2e/case.yaml'
	String get filePathHint => 'Relative to project, for example cockpit/e2e/case.yaml';

	/// en: 'Saving'
	String get saving => 'Saving';

	/// en: 'Unsaved'
	String get unsaved => 'Unsaved';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'Format'
	String get format => 'Format';

	/// en: 'Save test'
	String get save => 'Save test';

	/// en: 'Check test'
	String get check => 'Check test';

	/// en: 'The selected project changed before saving started.'
	String get saveWorkspaceChanged => 'The selected project changed before saving started.';

	/// en: 'A test save is already in progress.'
	String get saveBusy => 'A test save is already in progress.';

	/// en: 'Test content cannot be empty.'
	String get saveEmpty => 'Test content cannot be empty.';

	/// en: 'The test path must be relative to the project.'
	String get saveRelativePath => 'The test path must be relative to the project.';

	/// en: 'LON tests must use a .lon path.'
	String get saveExtensionLon => 'LON tests must use a .lon path.';

	/// en: 'JSON tests must use a .json path.'
	String get saveExtensionJson => 'JSON tests must use a .json path.';

	/// en: 'YAML tests must use a .yaml or .yml path.'
	String get saveExtensionYaml => 'YAML tests must use a .yaml or .yml path.';

	/// en: 'The test changed while it was being checked. Save it again.'
	String get saveDocumentChanged => 'The test changed while it was being checked. Save it again.';

	/// en: 'Could not save the test.'
	String get saveFailed => 'Could not save the test.';

	/// en: 'Saved and indexed {{path}}'
	String indexed({required Object path}) => 'Saved and indexed ${path}';

	/// en: 'Saved and indexed {{path}}, but the previous backup could not be removed: {{error}}'
	String indexedCleanupWarning({required Object path, required Object error}) => 'Saved and indexed ${path}, but the previous backup could not be removed: ${error}';

	/// en: 'The test is invalid, but no diagnostic was returned.'
	String get validationNoDiagnostic => 'The test is invalid, but no diagnostic was returned.';

	/// en: 'Valid document'
	String get valid => 'Valid document';

	/// en: 'Validation failed'
	String get invalid => 'Validation failed';

	/// en: 'Errors: {{count}}'
	String errors({required Object count}) => 'Errors: ${count}';

	/// en: 'Warnings: {{count}}'
	String warnings({required Object count}) => 'Warnings: ${count}';
}

// Path: runs
class Translations$runs$en {
	Translations$runs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Test runs'
	String get title => 'Test runs';

	/// en: 'Run a test case or suite and follow its result'
	String get subtitle => 'Run a test case or suite and follow its result';

	/// en: 'Select a project'
	String get selectProject => 'Select a project';

	/// en: 'Choose a project from the Projects page to start a test run.'
	String get selectProjectDescription => 'Choose a project from the Projects page to start a test run.';

	/// en: 'Choose project'
	String get chooseProject => 'Choose project';

	/// en: 'Run inputs must be a LON, JSON, or YAML object.'
	String get inputsObjectError => 'Run inputs must be a LON, JSON, or YAML object.';

	/// en: 'Use a duration such as 30s, 5m, or 1h.'
	String get durationError => 'Use a duration such as 30s, 5m, or 1h.';

	/// en: 'Unsupported timeout unit.'
	String get timeoutUnitError => 'Unsupported timeout unit.';

	/// en: 'Timeout must be between 1ms and {{maximum}}.'
	String timeoutRangeError({required Object maximum}) => 'Timeout must be between 1ms and ${maximum}.';

	/// en: 'Suite'
	String get suite => 'Suite';

	/// en: 'Case'
	String get caseLabel => 'Case';

	/// en: 'Could not restore run status: {{error}}'
	String restoreFailed({required Object error}) => 'Could not restore run status: ${error}';

	/// en: 'The selected test file changed or was removed. Choose it again.'
	String get selectedFileChanged => 'The selected test file changed or was removed. Choose it again.';

	/// en: 'Could not refresh test files: {{error}}'
	String refreshTestsFailed({required Object error}) => 'Could not refresh test files: ${error}';

	/// en: 'Cancellation requested'
	String get cancellationRequested => 'Cancellation requested';

	/// en: 'Could not cancel the run: {{error}}'
	String cancelFailed({required Object error}) => 'Could not cancel the run: ${error}';

	/// en: 'Could not refresh the run: {{error}}'
	String refreshFailed({required Object error}) => 'Could not refresh the run: ${error}';

	/// en: 'Retry recent runs'
	String get retryRecent => 'Retry recent runs';

	/// en: 'Refresh recent runs'
	String get refreshRecent => 'Refresh recent runs';

	/// en: 'Save artifact'
	String get saveArtifact => 'Save artifact';

	/// en: 'Saved verified artifact to {{path}}'
	String artifactSaved({required Object path}) => 'Saved verified artifact to ${path}';

	/// en: 'Download failed: {{error}}'
	String downloadFailed({required Object error}) => 'Download failed: ${error}';

	/// en: 'Could not observe the run: {{error}}'
	String observeFailed({required Object error}) => 'Could not observe the run: ${error}';

	/// en: 'Expected a JSON object event.'
	String get jsonEventError => 'Expected a JSON object event.';

	/// en: 'Run completed'
	String get completed => 'Run completed';

	/// en: 'Stream {{kind}}'
	String streamEvent({required Object kind}) => 'Stream ${kind}';

	/// en: 'Malformed event: {{error}}'
	String malformedEvent({required Object error}) => 'Malformed event: ${error}';

	/// en: 'Could not load run status: {{error}}'
	String statusLoadFailed({required Object error}) => 'Could not load run status: ${error}';

	/// en: 'Event stream ended before the terminal state'
	String get streamEnded => 'Event stream ended before the terminal state';

	/// en: 'Loading test files…'
	String get loadingTests => 'Loading test files…';

	/// en: 'Test files are temporarily unavailable.'
	String get testsUnavailable => 'Test files are temporarily unavailable.';

	/// en: 'Create a test file before starting a run.'
	String get createTestFirst => 'Create a test file before starting a run.';

	/// en: 'Select a test file to continue.'
	String get selectFile => 'Select a test file to continue.';

	/// en: 'Select a test case to continue.'
	String get selectCase => 'Select a test case to continue.';

	/// en: 'Ready to run in the current project.'
	String get ready => 'Ready to run in the current project.';

	/// en: 'Start a test run'
	String get startTitle => 'Start a test run';

	/// en: 'Choose a case or suite. Override the app only when the test file default is not the intended target.'
	String get startDescription => 'Choose a case or suite. Override the app only when the test file default is not the intended target.';

	/// en: '1. Test file'
	String get testFileStep => '1. Test file';

	/// en: 'Choose a test file'
	String get chooseTestFile => 'Choose a test file';

	/// en: '2. Test case'
	String get testCaseStep => '2. Test case';

	/// en: 'Choose a test case'
	String get chooseTestCase => 'Choose a test case';

	/// en: '2. Suite contents'
	String get suiteContentsStep => '2. Suite contents';

	/// en: 'All cases in this suite'
	String get allSuiteCases => 'All cases in this suite';

	/// en: '3. App or device'
	String get targetStep => '3. App or device';

	/// en: 'Use test file default'
	String get useFileDefault => 'Use test file default';

	/// en: 'Retry tests'
	String get retryTests => 'Retry tests';

	/// en: 'Open tests'
	String get openTests => 'Open tests';

	/// en: 'Cockpit could not load the current test index. Retry when the project worker is available.'
	String get indexLoadFailed => 'Cockpit could not load the current test index. Retry when the project worker is available.';

	/// en: 'Cockpit could not refresh the test index. Existing choices remain available.'
	String get indexRefreshFailed => 'Cockpit could not refresh the test index. Existing choices remain available.';

	/// en: 'Run suite'
	String get runSuite => 'Run suite';

	/// en: 'Run test'
	String get runTest => 'Run test';

	/// en: 'Run options'
	String get options => 'Run options';

	/// en: 'Inputs (optional)'
	String get inputsOptional => 'Inputs (optional)';

	/// en: 'LON, JSON, or YAML object'
	String get inputsHint => 'LON, JSON, or YAML object';

	/// en: 'Timeout (optional)'
	String get timeoutOptional => 'Timeout (optional)';

	/// en: 'Use the default, for example 30s or 5m'
	String get timeoutHint => 'Use the default, for example 30s or 5m';

	/// en: 'Recent runs are temporarily unavailable'
	String get recentUnavailable => 'Recent runs are temporarily unavailable';

	/// en: 'Loading run'
	String get loadingRun => 'Loading run';

	/// en: '(one) {{{n}} event} (other) {{{n}} events}'
	String events({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} event',
		other: '${n} events',
	);

	/// en: 'New run'
	String get newRun => 'New run';

	/// en: 'Cancel run'
	String get cancelRun => 'Cancel run';

	/// en: 'Recent runs'
	String get recentRuns => 'Recent runs';

	/// en: 'Why this run failed'
	String get failureTitle => 'Why this run failed';

	/// en: 'Files and evidence ({{count}})'
	String filesEvidence({required Object count}) => 'Files and evidence (${count})';

	/// en: 'Save file'
	String get saveFile => 'Save file';

	late final Translations$runs$state$en state = Translations$runs$state$en.internal(_root);
}

// Path: actions
class Translations$actions$en {
	Translations$actions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Actions'
	String get title => 'Actions';

	/// en: 'Inspect and run the actions available in Cockpit'
	String get subtitle => 'Inspect and run the actions available in Cockpit';

	/// en: 'Select an action'
	String get select => 'Select an action';

	/// en: 'Choose an available action to review its inputs and run it with a LON, JSON, or YAML object.'
	String get selectDescription => 'Choose an available action to review its inputs and run it with a LON, JSON, or YAML object.';

	/// en: 'Select a project to run this project-scoped action.'
	String get selectProjectReason => 'Select a project to run this project-scoped action.';

	/// en: 'Select an allowed folder to run this folder-scoped action.'
	String get selectFolderReason => 'Select an allowed folder to run this folder-scoped action.';

	/// en: 'No allowed folder is available. Add one under Projects to run folder-scoped actions.'
	String get noFolderReason => 'No allowed folder is available. Add one under Projects to run folder-scoped actions.';

	/// en: 'Filter actions'
	String get filter => 'Filter actions';

	/// en: 'Global actions'
	String get global => 'Global actions';

	/// en: 'Project actions'
	String get project => 'Project actions';

	/// en: 'Could not load actions: {{error}}'
	String loadFailed({required Object error}) => 'Could not load actions: ${error}';

	/// en: 'No actions are advertised.'
	String get none => 'No actions are advertised.';

	/// en: 'No actions match “{{query}}”.'
	String noMatch({required Object query}) => 'No actions match “${query}”.';

	late final Translations$actions$scopeBadge$en scopeBadge = Translations$actions$scopeBadge$en.internal(_root);

	/// en: 'Input'
	String get input => 'Input';

	/// en: 'A LON, JSON, or YAML object. The idempotency key belongs to the invocation envelope, not this object.'
	String get inputDescription => 'A LON, JSON, or YAML object. The idempotency key belongs to the invocation envelope, not this object.';

	/// en: 'Scope'
	String get scope => 'Scope';

	/// en: 'Mutation'
	String get mutation => 'Mutation';

	/// en: 'Idempotency'
	String get idempotency => 'Idempotency';

	/// en: 'Execution'
	String get execution => 'Execution';

	/// en: 'Timeout'
	String get timeout => 'Timeout';

	/// en: '{{defaultValue}} (maximum {{maximum}})'
	String timeoutValue({required Object defaultValue, required Object maximum}) => '${defaultValue} (maximum ${maximum})';

	/// en: 'Effects'
	String get effects => 'Effects';

	/// en: 'Features'
	String get features => 'Features';

	/// en: 'Input schema'
	String get inputSchema => 'Input schema';

	/// en: 'Output schema'
	String get outputSchema => 'Output schema';

	/// en: 'Idempotency key'
	String get idempotencyKey => 'Idempotency key';

	/// en: 'Generated when run'
	String get generatedWhenRun => 'Generated when run';

	/// en: 'Optional'
	String get optional => 'Optional';

	/// en: 'Generate a new key'
	String get generateKey => 'Generate a new key';

	/// en: 'Required because this action can change state.'
	String get keyRequiredDescription => 'Required because this action can change state.';

	/// en: 'Optional and omitted when blank.'
	String get keyOptionalDescription => 'Optional and omitted when blank.';

	/// en: 'No active project roots are registered.'
	String get noRoots => 'No active project roots are registered.';

	/// en: 'Project root'
	String get projectRoot => 'Project root';

	/// en: 'Select an active root'
	String get selectRoot => 'Select an active root';

	/// en: 'This action cannot be run here.'
	String get unavailable => 'This action cannot be run here.';

	/// en: 'Add allowed folder'
	String get addFolder => 'Add allowed folder';

	/// en: 'Running…'
	String get running => 'Running…';

	/// en: 'Run action'
	String get run => 'Run action';

	/// en: 'This action can change state.'
	String get mutationWarning => 'This action can change state.';

	/// en: 'Runs for the selected allowed folder.'
	String get scopeRootDescription => 'Runs for the selected allowed folder.';

	/// en: 'Runs for the selected project.'
	String get scopeProjectDescription => 'Runs for the selected project.';

	/// en: 'Runs in Supervisor scope; no project required.'
	String get scopeGlobalDescription => 'Runs in Supervisor scope; no project required.';

	/// en: 'Action did not succeed'
	String get failed => 'Action did not succeed';

	/// en: 'Result'
	String get result => 'Result';

	/// en: 'Submitted'
	String get submitted => 'Submitted';

	/// en: 'Submitted · {{state}}'
	String submittedState({required Object state}) => 'Submitted · ${state}';

	/// en: 'Copied'
	String get copied => 'Copied';

	/// en: 'Copy'
	String get copy => 'Copy';

	late final Translations$actions$scopeValue$en scopeValue = Translations$actions$scopeValue$en.internal(_root);
	late final Translations$actions$mutationValue$en mutationValue = Translations$actions$mutationValue$en.internal(_root);
	late final Translations$actions$idempotencyValue$en idempotencyValue = Translations$actions$idempotencyValue$en.internal(_root);
	late final Translations$actions$executionValue$en executionValue = Translations$actions$executionValue$en.internal(_root);
}

// Path: ai
class Translations$ai$en {
	Translations$ai$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'AI Assistant'
	String get title => 'AI Assistant';

	/// en: 'Agent settings'
	String get settings => 'Agent settings';

	/// en: 'Connect an AI agent to start'
	String get connectToStart => 'Connect an AI agent to start';

	/// en: 'Connecting…'
	String get connecting => 'Connecting…';

	/// en: 'Connecting to agent'
	String get connectingToAgent => 'Connecting to agent';

	/// en: 'Start a conversation'
	String get startConversation => 'Start a conversation';

	/// en: 'Connect an ACP-compatible agent, then ask questions or run development tasks here.'
	String get connectDescription => 'Connect an ACP-compatible agent, then ask questions or run development tasks here.';

	/// en: 'Connect agent'
	String get connectAgent => 'Connect agent';

	/// en: 'Connect an agent to start chatting'
	String get connectChatHint => 'Connect an agent to start chatting';

	/// en: 'Connect AI agent'
	String get connectTitle => 'Connect AI agent';

	/// en: 'Choose an agent and its working directory.'
	String get connectSubtitle => 'Choose an agent and its working directory.';

	/// en: 'Close connection setup'
	String get closeConnectionSetup => 'Close connection setup';

	/// en: 'Close settings'
	String get closeSettings => 'Close settings';

	/// en: 'The agent is no longer connected.'
	String get disconnected => 'The agent is no longer connected.';

	/// en: 'Clear chat view'
	String get clearChat => 'Clear chat view';

	/// en: 'Disconnect agent'
	String get disconnect => 'Disconnect agent';

	/// en: 'Custom'
	String get custom => 'Custom';

	/// en: 'Any ACP executable'
	String get customDescription => 'Any ACP executable';

	/// en: 'Agent'
	String get agent => 'Agent';

	/// en: 'Choose an AI agent'
	String get chooseAgent => 'Choose an AI agent';

	/// en: '{{name}} ACP agent'
	String presetDescription({required Object name}) => '${name} ACP agent';

	/// en: 'Select working directory'
	String get selectWorkingDirectory => 'Select working directory';

	/// en: 'Start session'
	String get startSession => 'Start session';

	/// en: 'Executable'
	String get executable => 'Executable';

	/// en: 'Arguments (one per line)'
	String get arguments => 'Arguments (one per line)';

	/// en: 'Passed directly to the executable without a shell.'
	String get argumentsDescription => 'Passed directly to the executable without a shell.';

	/// en: 'Working directory'
	String get workingDirectory => 'Working directory';

	/// en: '/absolute/path/to/project'
	String get workingDirectoryHint => '/absolute/path/to/project';

	/// en: 'Browse directories'
	String get browseDirectories => 'Browse directories';

	/// en: 'Select a project before editing.'
	String get selectProjectBeforeEditing => 'Select a project before editing.';

	/// en: 'Latest'
	String get latest => 'Latest';

	/// en: 'Dismiss error'
	String get dismissError => 'Dismiss error';

	/// en: 'Permission required to continue'
	String get permissionRequired => 'Permission required to continue';

	/// en: 'Input'
	String get input => 'Input';

	/// en: 'Location'
	String get location => 'Location';

	/// en: 'Locations'
	String get locations => 'Locations';

	/// en: 'Cancel request'
	String get cancelRequest => 'Cancel request';

	/// en: 'Sign in to continue'
	String get signInTitle => 'Sign in to continue';

	/// en: 'Choose an authentication method in agent settings, then finish the sign-in flow.'
	String get signInDescription => 'Choose an authentication method in agent settings, then finish the sign-in flow.';

	/// en: 'Open sign-in'
	String get openSignIn => 'Open sign-in';

	/// en: 'Create or open a session'
	String get sessionTitle => 'Create or open a session';

	/// en: 'Use agent settings to start a new session or resume recent work.'
	String get sessionDescription => 'Use agent settings to start a new session or resume recent work.';

	/// en: 'Open session setup'
	String get openSessionSetup => 'Open session setup';

	/// en: 'Ask about your workspace, request a change, or describe a test scenario.'
	String get conversationDescription => 'Ask about your workspace, request a change, or describe a test scenario.';

	/// en: 'Send to editor'
	String get sendToEditor => 'Send to editor';

	late final Translations$ai$composer$en composer = Translations$ai$composer$en.internal(_root);
	late final Translations$ai$connection$en connection = Translations$ai$connection$en.internal(_root);
	late final Translations$ai$mcp$en mcp = Translations$ai$mcp$en.internal(_root);
	late final Translations$ai$session$en session = Translations$ai$session$en.internal(_root);
	late final Translations$ai$tool$en tool = Translations$ai$tool$en.internal(_root);
}

// Path: sessions
class Translations$sessions$en {
	Translations$sessions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Live sessions'
	String get title => 'Live sessions';

	/// en: 'Observe running apps without changing or restarting them'
	String get subtitle => 'Observe running apps without changing or restarting them';

	/// en: 'Finding running sessions'
	String get findingTitle => 'Finding running sessions';

	/// en: 'Cockpit is checking every active project for running apps.'
	String get findingDescription => 'Cockpit is checking every active project for running apps.';

	/// en: 'No sessions to monitor'
	String get emptyTitle => 'No sessions to monitor';

	/// en: 'Start an app with Cockpit. Running sessions appear here automatically and remain available after they stop.'
	String get emptyDescription => 'Start an app with Cockpit. Running sessions appear here automatically and remain available after they stop.';

	/// en: 'Check again'
	String get checkAgain => 'Check again';

	/// en: '{{live}} live · {{total}} total'
	String liveCount({required Object live, required Object total}) => '${live} live · ${total} total';

	/// en: '{{live}} live sessions, {{total}} total sessions'
	String liveCountSemantics({required Object live, required Object total}) => '${live} live sessions, ${total} total sessions';

	/// en: 'Sessions'
	String get listTitle => 'Sessions';

	/// en: '{{project}}, {{platform}}, session {{session}}'
	String selectSemantics({required Object project, required Object platform, required Object session}) => '${project}, ${platform}, session ${session}';

	/// en: '(one) {Could not refresh {{n}} project.} (other) {Could not refresh {{n}} projects.}'
	String refreshFailed({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Could not refresh ${n} project.',
		other: 'Could not refresh ${n} projects.',
	);

	/// en: 'Project refresh failed.'
	String get refreshProjectFailed => 'Project refresh failed.';

	/// en: 'This session is no longer active.'
	String get stoppedMessage => 'This session is no longer active.';

	/// en: 'The app bridge is reconnecting.'
	String get bridgeReconnectingMessage => 'The app bridge is reconnecting.';

	/// en: 'Select a session to inspect its live state.'
	String get selectPrompt => 'Select a session to inspect its live state.';

	/// en: 'Session {{session}}'
	String sessionId({required Object session}) => 'Session ${session}';

	/// en: 'App'
	String get contextApp => 'App';

	/// en: 'Open this project in Apps & devices'
	String get contextAppTip => 'Open this project in Apps & devices';

	/// en: 'Actions'
	String get contextActions => 'Actions';

	/// en: 'Open actions for this project'
	String get contextActionsTip => 'Open actions for this project';

	/// en: 'Tests'
	String get contextTests => 'Tests';

	/// en: 'Open tests for this project'
	String get contextTestsTip => 'Open tests for this project';

	/// en: 'Runs'
	String get contextRuns => 'Runs';

	/// en: 'Open test runs for this project'
	String get contextRunsTip => 'Open test runs for this project';

	/// en: 'Refresh {{section}}'
	String refreshSection({required Object section}) => 'Refresh ${section}';

	late final Translations$sessions$status$en status = Translations$sessions$status$en.internal(_root);
	late final Translations$sessions$sections$en sections = Translations$sessions$sections$en.internal(_root);
	late final Translations$sessions$data$en data = Translations$sessions$data$en.internal(_root);
	late final Translations$sessions$overview$en overview = Translations$sessions$overview$en.internal(_root);
	late final Translations$sessions$ui$en ui = Translations$sessions$ui$en.internal(_root);
	late final Translations$sessions$logs$en logs = Translations$sessions$logs$en.internal(_root);

	/// en: 'Connection, route, runtime error, and network changes appear here as Cockpit observes them.'
	String get activityEmpty => 'Connection, route, runtime error, and network changes appear here as Cockpit observes them.';

	late final Translations$sessions$activity$en activity = Translations$sessions$activity$en.internal(_root);
	late final Translations$sessions$timeline$en timeline = Translations$sessions$timeline$en.internal(_root);
	late final Translations$sessions$diagnostics$en diagnostics = Translations$sessions$diagnostics$en.internal(_root);
	late final Translations$sessions$network$en network = Translations$sessions$network$en.internal(_root);
}

// Path: targets.kind
class Translations$targets$kind$en {
	Translations$targets$kind$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Flutter app'
	String get flutterApp => 'Flutter app';

	/// en: 'Native app'
	String get nativeApp => 'Native app';

	/// en: 'Desktop app'
	String get desktopApp => 'Desktop app';

	/// en: 'Browser page'
	String get browserPage => 'Browser page';

	/// en: 'System surface'
	String get systemSurface => 'System surface';

	/// en: 'Device'
	String get device => 'Device';

	/// en: 'Host workspace'
	String get hostWorkspace => 'Host workspace';
}

// Path: targets.mode
class Translations$targets$mode$en {
	Translations$targets$mode$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Development'
	String get development => 'Development';

	/// en: 'Automation'
	String get automation => 'Automation';
}

// Path: targets.environment
class Translations$targets$environment$en {
	Translations$targets$environment$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Development'
	String get development => 'Development';

	/// en: 'Test'
	String get test => 'Test';

	/// en: 'Staging'
	String get staging => 'Staging';

	/// en: 'Production'
	String get production => 'Production';

	/// en: 'Unknown'
	String get unknown => 'Unknown';
}

// Path: runs.state
class Translations$runs$state$en {
	Translations$runs$state$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Queued'
	String get queued => 'Queued';

	/// en: 'Running'
	String get running => 'Running';

	/// en: 'Finalizing'
	String get finalizing => 'Finalizing';

	/// en: 'Completed'
	String get completed => 'Completed';

	/// en: 'Passed'
	String get passed => 'Passed';

	/// en: 'Failed'
	String get failed => 'Failed';

	/// en: 'Blocked'
	String get blocked => 'Blocked';

	/// en: 'Skipped'
	String get skipped => 'Skipped';

	/// en: 'Cancelled'
	String get cancelled => 'Cancelled';

	/// en: 'Interrupted'
	String get interrupted => 'Interrupted';

	/// en: 'Error'
	String get internalError => 'Error';
}

// Path: actions.scopeBadge
class Translations$actions$scopeBadge$en {
	Translations$actions$scopeBadge$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'global'
	String get global => 'global';

	/// en: 'workspace'
	String get workspace => 'workspace';

	/// en: 'root'
	String get root => 'root';
}

// Path: actions.scopeValue
class Translations$actions$scopeValue$en {
	Translations$actions$scopeValue$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Supervisor (global)'
	String get supervisor => 'Supervisor (global)';

	/// en: 'Root'
	String get root => 'Root';

	/// en: 'Workspace'
	String get workspace => 'Workspace';
}

// Path: actions.mutationValue
class Translations$actions$mutationValue$en {
	Translations$actions$mutationValue$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Read-only'
	String get readOnly => 'Read-only';

	/// en: 'Mutating'
	String get mutating => 'Mutating';
}

// Path: actions.idempotencyValue
class Translations$actions$idempotencyValue$en {
	Translations$actions$idempotencyValue$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Required'
	String get required => 'Required';

	/// en: 'Optional'
	String get optional => 'Optional';

	/// en: 'Prohibited'
	String get prohibited => 'Prohibited';
}

// Path: actions.executionValue
class Translations$actions$executionValue$en {
	Translations$actions$executionValue$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Synchronous'
	String get synchronous => 'Synchronous';

	/// en: 'Job'
	String get job => 'Job';
}

// Path: ai.composer
class Translations$ai$composer$en {
	Translations$ai$composer$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'That attachment is already included.'
	String get duplicateAttachment => 'That attachment is already included.';

	/// en: 'Send a message…'
	String get messageHint => 'Send a message…';

	/// en: 'Create a session or sign in to start chatting'
	String get sessionRequiredHint => 'Create a session or sign in to start chatting';

	/// en: 'Stop response'
	String get stopResponse => 'Stop response';

	/// en: 'Send message (Enter)'
	String get sendMessage => 'Send message (Enter)';

	/// en: 'Write a message or add an attachment'
	String get addMessage => 'Write a message or add an attachment';

	/// en: '{{size}} inline · {{limit}} limit'
	String inlineLimit({required Object size, required Object limit}) => '${size} inline · ${limit} limit';

	/// en: 'Available commands'
	String get availableCommands => 'Available commands';

	/// en: 'Add context'
	String get addContext => 'Add context';

	/// en: 'Attach image'
	String get attachImage => 'Attach image';

	/// en: 'Send image data inline'
	String get attachImageDescription => 'Send image data inline';

	/// en: 'Attach audio'
	String get attachAudio => 'Attach audio';

	/// en: 'Send audio data inline'
	String get attachAudioDescription => 'Send audio data inline';

	/// en: 'Embed context file'
	String get embedContext => 'Embed context file';

	/// en: 'Include complete file contents'
	String get embedContextDescription => 'Include complete file contents';

	/// en: 'Link local file'
	String get linkFile => 'Link local file';

	/// en: 'Reference a file without copying it'
	String get linkFileDescription => 'Reference a file without copying it';

	/// en: 'Link resource URI'
	String get linkResource => 'Link resource URI';

	/// en: 'Reference any agent-accessible resource'
	String get linkResourceDescription => 'Reference any agent-accessible resource';

	/// en: 'Remove {{name}}'
	String removeAttachment({required Object name}) => 'Remove ${name}';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'API specification'
	String get nameHint => 'API specification';

	/// en: 'Absolute URI'
	String get absoluteUri => 'Absolute URI';

	/// en: 'MIME type (optional)'
	String get mimeOptional => 'MIME type (optional)';

	/// en: 'Description (optional)'
	String get descriptionOptional => 'Description (optional)';

	/// en: 'Enter a name and an absolute URI with a scheme.'
	String get resourceError => 'Enter a name and an absolute URI with a scheme.';

	/// en: 'Add resource'
	String get addResource => 'Add resource';

	/// en: 'linked'
	String get linked => 'linked';

	/// en: 'embedded'
	String get embedded => 'embedded';

	/// en: 'The selected file does not expose a local path.'
	String get pathUnavailable => 'The selected file does not expose a local path.';

	/// en: 'The selected path is not a regular file.'
	String get notRegularFile => 'The selected path is not a regular file.';

	/// en: 'Resource links require a name and an absolute URI.'
	String get resourceRequirements => 'Resource links require a name and an absolute URI.';

	/// en: 'Inline attachments use {{size}}. The prompt limit is {{limit}}.'
	String promptLimit({required Object size, required Object limit}) => 'Inline attachments use ${size}. The prompt limit is ${limit}.';

	/// en: '“{{name}}” is not a supported image file.'
	String unsupportedImage({required Object name}) => '“${name}” is not a supported image file.';

	/// en: '“{{name}}” is not a supported audio file.'
	String unsupportedAudio({required Object name}) => '“${name}” is not a supported audio file.';

	/// en: 'The selected file is empty.'
	String get emptyFile => 'The selected file is empty.';

	/// en: 'The selected file is {{size}}. Inline attachments are limited to {{limit}}.'
	String fileTooLarge({required Object size, required Object limit}) => 'The selected file is ${size}. Inline attachments are limited to ${limit}.';
}

// Path: ai.connection
class Translations$ai$connection$en {
	Translations$ai$connection$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Create session'
	String get createSession => 'Create session';

	/// en: 'Working directory'
	String get workingDirectory => 'Working directory';

	/// en: 'Select session working directory'
	String get selectSessionDirectory => 'Select session working directory';

	/// en: 'Session context'
	String get sessionContext => 'Session context';

	/// en: 'Optional directories and MCP servers'
	String get optionalContext => 'Optional directories and MCP servers';

	/// en: '(one) {{{n}} configured item} (other) {{{n}} configured items}'
	String configuredItems({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} configured item',
		other: '${n} configured items',
	);

	/// en: 'Additional directories'
	String get additionalDirectories => 'Additional directories';

	/// en: 'Grant the agent access to workspace roots beyond the working directory.'
	String get additionalDirectoriesDescription => 'Grant the agent access to workspace roots beyond the working directory.';

	/// en: 'Add directory'
	String get addDirectory => 'Add directory';

	/// en: 'MCP servers'
	String get mcpServers => 'MCP servers';

	/// en: 'Attach tools and resources for this Agent connection. Values are not stored.'
	String get mcpServersDescription => 'Attach tools and resources for this Agent connection. Values are not stored.';

	/// en: 'Add server'
	String get addServer => 'Add server';

	/// en: 'Add session directory'
	String get addSessionDirectory => 'Add session directory';

	/// en: 'That directory is already included.'
	String get duplicateDirectory => 'That directory is already included.';

	/// en: 'MCP server names must be unique.'
	String get duplicateServer => 'MCP server names must be unique.';

	/// en: 'Remove {{name}}'
	String remove({required Object name}) => 'Remove ${name}';
}

// Path: ai.mcp
class Translations$ai$mcp$en {
	Translations$ai$mcp$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add MCP server'
	String get addTitle => 'Add MCP server';

	/// en: 'Edit MCP server'
	String get editTitle => 'Edit MCP server';

	/// en: 'Transport'
	String get transport => 'Transport';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Absolute executable path'
	String get executablePath => 'Absolute executable path';

	/// en: 'Server URL'
	String get serverUrl => 'Server URL';

	/// en: 'Arguments (one per line)'
	String get arguments => 'Arguments (one per line)';

	/// en: 'Environment (NAME=value)'
	String get environment => 'Environment (NAME=value)';

	/// en: 'Headers (Name: value)'
	String get headers => 'Headers (Name: value)';

	/// en: 'Connection-only values. Cockpit Console does not store them.'
	String get valuesDescription => 'Connection-only values. Cockpit Console does not store them.';

	/// en: 'Add server'
	String get addServer => 'Add server';

	/// en: 'Save server'
	String get saveServer => 'Save server';

	/// en: 'Enter a server name.'
	String get nameRequired => 'Enter a server name.';

	/// en: 'Enter an executable path.'
	String get executableRequired => 'Enter an executable path.';

	/// en: 'Enter a server URL.'
	String get urlRequired => 'Enter a server URL.';

	/// en: 'The stdio executable must use an absolute path.'
	String get absoluteExecutable => 'The stdio executable must use an absolute path.';

	/// en: 'The server URL must be an absolute HTTP(S) URL.'
	String get absoluteUrl => 'The server URL must be an absolute HTTP(S) URL.';

	/// en: 'Environment line {{line}} must use NAME=value.'
	String environmentSyntax({required Object line}) => 'Environment line ${line} must use NAME=value.';

	/// en: 'Environment line {{line}} has an invalid variable name.'
	String environmentName({required Object line}) => 'Environment line ${line} has an invalid variable name.';

	/// en: 'Environment variable “{{name}}” is duplicated.'
	String environmentDuplicate({required Object name}) => 'Environment variable “${name}” is duplicated.';

	/// en: 'Header line {{line}} must use Name: value.'
	String headerSyntax({required Object line}) => 'Header line ${line} must use Name: value.';

	/// en: 'Header line {{line}} has an invalid name.'
	String headerName({required Object line}) => 'Header line ${line} has an invalid name.';

	/// en: 'Header “{{name}}” is duplicated.'
	String headerDuplicate({required Object name}) => 'Header “${name}” is duplicated.';

	/// en: 'Supported by every ACP agent.'
	String get stdioDescription => 'Supported by every ACP agent.';

	/// en: 'Requires the agent HTTP MCP capability.'
	String get httpDescription => 'Requires the agent HTTP MCP capability.';

	/// en: 'Requires the agent SSE MCP capability.'
	String get sseDescription => 'Requires the agent SSE MCP capability.';
}

// Path: ai.session
class Translations$ai$session$en {
	Translations$ai$session$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Authentication'
	String get authentication => 'Authentication';

	/// en: 'Sign in'
	String get signIn => 'Sign in';

	/// en: 'Sign out'
	String get signOut => 'Sign out';

	/// en: 'Session'
	String get section => 'Session';

	/// en: 'Refresh recent sessions'
	String get refreshRecent => 'Refresh recent sessions';

	/// en: 'Sign in before creating a session.'
	String get signInFirst => 'Sign in before creating a session.';

	/// en: 'No session is open. Create one to start chatting.'
	String get noneOpen => 'No session is open. Create one to start chatting.';

	/// en: 'New session'
	String get newSession => 'New session';

	/// en: 'Close session'
	String get close => 'Close session';

	/// en: 'Recent sessions'
	String get recent => 'Recent sessions';

	/// en: 'Loading sessions…'
	String get loading => 'Loading sessions…';

	/// en: 'No saved sessions were returned by this agent.'
	String get noneSaved => 'No saved sessions were returned by this agent.';

	/// en: 'Load more'
	String get loadMore => 'Load more';

	/// en: 'Active session'
	String get activeSession => 'Active session';

	/// en: '(one) {{{n}} additional directory} (other) {{{n}} additional directories}'
	String additionalDirectories({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} additional directory',
		other: '${n} additional directories',
	);

	/// en: 'MCP: {{names}}'
	String mcpServers({required Object names}) => 'MCP: ${names}';

	/// en: 'Active'
	String get active => 'Active';

	/// en: 'Session actions'
	String get actions => 'Session actions';

	/// en: 'Resume'
	String get resume => 'Resume';

	/// en: 'Load'
	String get load => 'Load';

	/// en: 'Load from history'
	String get loadHistory => 'Load from history';

	/// en: 'Delete session'
	String get delete => 'Delete session';

	/// en: 'Agent settings'
	String get settings => 'Agent settings';

	/// en: 'Mode'
	String get mode => 'Mode';

	/// en: 'This agent did not advertise session settings.'
	String get noSettings => 'This agent did not advertise session settings.';

	/// en: 'Current context'
	String get currentContext => 'Current context';

	/// en: 'Usage'
	String get usage => 'Usage';

	/// en: '(one) {{{n}} token used} (other) {{{n}} tokens used}'
	String tokensUsed({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} token used',
		other: '${n} tokens used',
	);

	/// en: '(one) {{{n}}-token context} (other) {{{n}}-token context}'
	String tokenContext({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n}-token context',
		other: '${n}-token context',
	);

	/// en: 'Plan'
	String get plan => 'Plan';

	/// en: 'Available commands'
	String get availableCommands => 'Available commands';

	/// en: 'Authentication is not required'
	String get authNotRequired => 'Authentication is not required';

	/// en: 'Sign-in is available'
	String get authAvailable => 'Sign-in is available';

	/// en: 'Sign-in is required'
	String get authRequired => 'Sign-in is required';

	/// en: 'Waiting for sign-in to finish…'
	String get authWaiting => 'Waiting for sign-in to finish…';

	/// en: 'Signed in'
	String get authenticated => 'Signed in';

	/// en: 'Signing out…'
	String get signingOut => 'Signing out…';

	/// en: 'Images'
	String get capImages => 'Images';

	/// en: 'Audio'
	String get capAudio => 'Audio';

	/// en: 'Context files'
	String get capContext => 'Context files';

	/// en: 'Load sessions'
	String get capLoad => 'Load sessions';

	/// en: 'Resume'
	String get capResume => 'Resume';

	/// en: 'History'
	String get capHistory => 'History';

	/// en: 'Delete session?'
	String get deleteTitle => 'Delete session?';

	/// en: 'Delete “{{name}}” from the agent. This cannot be undone.'
	String deleteDescription({required Object name}) => 'Delete “${name}” from the agent. This cannot be undone.';

	/// en: 'Keep session'
	String get keep => 'Keep session';
}

// Path: ai.tool
class Translations$ai$tool$en {
	Translations$ai$tool$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Raw input'
	String get rawInput => 'Raw input';

	/// en: 'Raw output'
	String get rawOutput => 'Raw output';

	/// en: 'Terminal'
	String get terminal => 'Terminal';

	/// en: 'Audio'
	String get audio => 'Audio';

	/// en: 'The agent returned invalid {{mime}} image data.'
	String invalidImage({required Object mime}) => 'The agent returned invalid ${mime} image data.';

	/// en: 'The agent returned malformed base64 image data.'
	String get malformedImage => 'The agent returned malformed base64 image data.';

	/// en: 'Text resource'
	String get textResource => 'Text resource';

	/// en: 'Binary resource'
	String get binaryResource => 'Binary resource';

	/// en: 'Diff'
	String get diff => 'Diff';

	/// en: 'Before'
	String get before => 'Before';

	/// en: 'After'
	String get after => 'After';

	/// en: 'Location'
	String get location => 'Location';

	late final Translations$ai$tool$status$en status = Translations$ai$tool$status$en.internal(_root);
}

// Path: sessions.status
class Translations$sessions$status$en {
	Translations$sessions$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Reconnecting'
	String get reconnecting => 'Reconnecting';

	/// en: 'Live'
	String get live => 'Live';

	/// en: 'Starting'
	String get starting => 'Starting';

	/// en: 'Reloading'
	String get reloading => 'Reloading';

	/// en: 'Restarting'
	String get restarting => 'Restarting';

	/// en: 'Checking'
	String get checking => 'Checking';

	/// en: 'Failed'
	String get failed => 'Failed';

	/// en: 'Unavailable'
	String get unavailable => 'Unavailable';

	/// en: 'Stopped'
	String get stopped => 'Stopped';
}

// Path: sessions.sections
class Translations$sessions$sections$en {
	Translations$sessions$sections$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Overview'
	String get overview => 'Overview';

	/// en: 'UI'
	String get ui => 'UI';

	/// en: 'Logs'
	String get logs => 'Logs';

	/// en: 'Network'
	String get network => 'Network';

	/// en: 'Activity'
	String get activity => 'Activity';

	/// en: 'Diagnostics'
	String get diagnostics => 'Diagnostics';
}

// Path: sessions.data
class Translations$sessions$data$en {
	Translations$sessions$data$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Structured data'
	String get structured => 'Structured data';

	/// en: 'No data is available for this session yet.'
	String get empty => 'No data is available for this session yet.';

	/// en: 'Copy data'
	String get copy => 'Copy data';

	/// en: 'Data copied'
	String get copied => 'Data copied';

	/// en: 'Not set'
	String get notSet => 'Not set';

	/// en: 'Copy {{label}}'
	String copyLabel({required Object label}) => 'Copy ${label}';

	/// en: '{{label}} copied'
	String labelCopied({required Object label}) => '${label} copied';

	/// en: '(one) {{{n}} field} (other) {{{n}} fields}'
	String fields({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} field',
		other: '${n} fields',
	);

	/// en: '(one) {{{n}} item} (other) {{{n}} items}'
	String items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} item',
		other: '${n} items',
	);
}

// Path: sessions.overview
class Translations$sessions$overview$en {
	Translations$sessions$overview$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'App process'
	String get appProcess => 'App process';

	/// en: 'Reachable'
	String get reachable => 'Reachable';

	/// en: 'Unavailable'
	String get unavailable => 'Unavailable';

	/// en: 'Checking'
	String get checking => 'Checking';

	/// en: 'Cockpit bridge'
	String get bridge => 'Cockpit bridge';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Disconnected'
	String get disconnected => 'Disconnected';

	/// en: 'Runtime errors'
	String get runtimeErrors => 'Runtime errors';

	/// en: 'Network failures'
	String get networkFailures => 'Network failures';

	/// en: 'Current state'
	String get currentState => 'Current state';

	/// en: 'The exact app and bridge identity Cockpit is observing.'
	String get currentStateDescription => 'The exact app and bridge identity Cockpit is observing.';

	/// en: 'Route'
	String get route => 'Route';

	/// en: 'Lifecycle'
	String get lifecycle => 'Lifecycle';

	/// en: 'Reload generation'
	String get reloadGeneration => 'Reload generation';

	/// en: 'Last runtime status'
	String get lastRuntimeStatus => 'Last runtime status';

	/// en: 'Next step'
	String get nextStep => 'Next step';

	/// en: 'Last error'
	String get lastError => 'Last error';

	/// en: 'No action needed'
	String get noActionNeeded => 'No action needed';

	/// en: 'Launch identity'
	String get launchIdentity => 'Launch identity';

	/// en: 'Use these values to confirm the app is running in the intended project.'
	String get launchIdentityDescription => 'Use these values to confirm the app is running in the intended project.';

	/// en: 'Project'
	String get project => 'Project';

	/// en: 'Workspace'
	String get workspace => 'Workspace';

	/// en: 'Session'
	String get session => 'Session';

	/// en: 'Target'
	String get target => 'Target';

	/// en: 'Device'
	String get device => 'Device';

	/// en: 'Entrypoint'
	String get entrypoint => 'Entrypoint';

	/// en: 'Flavor'
	String get flavor => 'Flavor';

	/// en: 'App ID'
	String get appId => 'App ID';

	/// en: 'VM service'
	String get vmService => 'VM service';
}

// Path: sessions.ui
class Translations$sessions$ui$en {
	Translations$sessions$ui$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open this section to load the complete Flutter UI snapshot.'
	String get open => 'Open this section to load the complete Flutter UI snapshot.';

	/// en: 'Current UI'
	String get current => 'Current UI';

	/// en: 'Complete mounted targets, diagnostics, accessibility, and Element structure.'
	String get description => 'Complete mounted targets, diagnostics, accessibility, and Element structure.';

	/// en: 'Snapshot file'
	String get snapshotFile => 'Snapshot file';

	/// en: 'Widget tree file'
	String get treeFile => 'Widget tree file';

	/// en: 'Targets'
	String get targets => 'Targets';

	/// en: 'Elements'
	String get elements => 'Elements';

	/// en: 'Snapshot truncated'
	String get snapshotTruncated => 'Snapshot truncated';

	/// en: 'Tree truncated'
	String get treeTruncated => 'Tree truncated';

	/// en: 'Complete snapshot'
	String get completeSnapshot => 'Complete snapshot';

	/// en: 'The complete UI snapshot could not be loaded.'
	String get snapshotUnavailable => 'The complete UI snapshot could not be loaded.';

	/// en: 'Copy snapshot data'
	String get copySnapshot => 'Copy snapshot data';

	/// en: 'Full widget tree'
	String get fullTree => 'Full widget tree';

	/// en: 'The full mounted Element tree could not be loaded.'
	String get treeUnavailable => 'The full mounted Element tree could not be loaded.';

	/// en: 'Copy widget tree data'
	String get copyTree => 'Copy widget tree data';

	/// en: 'Inspection metadata'
	String get metadata => 'Inspection metadata';

	/// en: 'No inspection metadata is available.'
	String get metadataEmpty => 'No inspection metadata is available.';

	/// en: 'Copy inspection metadata'
	String get copyMetadata => 'Copy inspection metadata';
}

// Path: sessions.logs
class Translations$sessions$logs$en {
	Translations$sessions$logs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open this section to follow startup and application logs live.'
	String get open => 'Open this section to follow startup and application logs live.';

	/// en: 'Refreshes every 2 seconds'
	String get live => 'Refreshes every 2 seconds';

	/// en: 'Latest output below'
	String get latestBelow => 'Latest output below';

	/// en: 'Show log output'
	String get expand => 'Show log output';

	/// en: 'Hide log output'
	String get collapse => 'Hide log output';

	/// en: 'Copy log lines'
	String get copyLines => 'Copy log lines';

	/// en: 'Log lines copied'
	String get linesCopied => 'Log lines copied';

	/// en: 'Copy log file path'
	String get copyPath => 'Copy log file path';

	/// en: 'Log file path copied'
	String get pathCopied => 'Log file path copied';

	/// en: 'Startup and Flutter tool logs'
	String get startupTitle => 'Startup and Flutter tool logs';

	/// en: 'No startup or Flutter tool log lines were captured.'
	String get startupNone => 'No startup or Flutter tool log lines were captured.';

	/// en: '(one) {{{n}} recent startup log line} (other) {{{n}} recent startup log lines}'
	String startupRecent({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} recent startup log line',
		other: '${n} recent startup log lines',
	);

	/// en: 'Cockpit is waiting for Flutter tool output.'
	String get startupRunningEmpty => 'Cockpit is waiting for Flutter tool output.';

	/// en: 'Application logs'
	String get title => 'Application logs';

	/// en: 'No application log lines were captured.'
	String get none => 'No application log lines were captured.';

	/// en: '(one) {{{n}} recent log line} (other) {{{n}} recent log lines}'
	String recent({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} recent log line',
		other: '${n} recent log lines',
	);

	/// en: ', older lines hidden'
	String get olderHidden => ', older lines hidden';

	/// en: 'The app is running without captured log output.'
	String get runningEmpty => 'The app is running without captured log output.';
}

// Path: sessions.activity
class Translations$sessions$activity$en {
	Translations$sessions$activity$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Session discovered'
	String get discovered => 'Session discovered';

	/// en: '{{platform}} · {{device}}'
	String discoveredDetail({required Object platform, required Object device}) => '${platform} · ${device}';

	/// en: 'Session connected'
	String get connected => 'Session connected';

	/// en: 'Session changed'
	String get changed => 'Session changed';

	/// en: '{{from}} → {{to}}'
	String stateDetail({required Object from, required Object to}) => '${from} → ${to}';

	/// en: 'App process unavailable'
	String get appUnavailable => 'App process unavailable';

	/// en: 'App process reachable'
	String get appReachable => 'App process reachable';

	/// en: 'Cockpit bridge connected'
	String get bridgeConnected => 'Cockpit bridge connected';

	/// en: 'Cockpit bridge disconnected'
	String get bridgeDisconnected => 'Cockpit bridge disconnected';

	/// en: 'Session {{session}}'
	String sessionDetail({required Object session}) => 'Session ${session}';

	/// en: 'Route changed'
	String get routeChanged => 'Route changed';

	/// en: '{{from}} → {{to}}'
	String routeDetail({required Object from, required Object to}) => '${from} → ${to}';

	/// en: 'unknown'
	String get unknownRoute => 'unknown';

	/// en: 'Runtime error captured'
	String get runtimeError => 'Runtime error captured';

	/// en: '(one) {{{n}} error in the current snapshot} (other) {{{n}} errors in the current snapshot}'
	String runtimeErrorDetail({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} error in the current snapshot',
		other: '${n} errors in the current snapshot',
	);

	/// en: 'Network failure captured'
	String get networkFailure => 'Network failure captured';

	/// en: '(one) {{{n}} failed request captured} (other) {{{n}} failed requests captured}'
	String networkFailureDetail({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} failed request captured',
		other: '${n} failed requests captured',
	);
}

// Path: sessions.timeline
class Translations$sessions$timeline$en {
	Translations$sessions$timeline$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Newest first'
	String get newestFirst => 'Newest first';

	/// en: '{{visible}} / {{total}}'
	String showing({required Object visible, required Object total}) => '${visible} / ${total}';

	/// en: 'All'
	String get all => 'All';

	/// en: 'Lifecycle'
	String get lifecycle => 'Lifecycle';

	/// en: 'Routes'
	String get routes => 'Routes';

	/// en: 'Runtime'
	String get runtime => 'Runtime';

	/// en: 'Network'
	String get network => 'Network';

	/// en: 'No events match this filter.'
	String get noMatch => 'No events match this filter.';

	/// en: 'Show event details'
	String get expand => 'Show event details';

	/// en: 'Hide event details'
	String get collapse => 'Hide event details';

	/// en: '(one) {{{n}} older event was discarded to keep memory stable.} (other) {{{n}} older events were discarded to keep memory stable.}'
	String discarded({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} older event was discarded to keep memory stable.',
		other: '${n} older events were discarded to keep memory stable.',
	);

	late final Translations$sessions$timeline$severity$en severity = Translations$sessions$timeline$severity$en.internal(_root);
}

// Path: sessions.diagnostics
class Translations$sessions$diagnostics$en {
	Translations$sessions$diagnostics$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open this section to load runtime errors and session logs.'
	String get open => 'Open this section to load runtime errors and session logs.';

	/// en: 'Runtime errors'
	String get runtimeErrors => 'Runtime errors';

	/// en: 'No runtime errors were captured.'
	String get noRuntimeErrors => 'No runtime errors were captured.';

	/// en: '(one) {{{n}} captured runtime error.} (other) {{{n}} captured runtime errors.}'
	String capturedErrors({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} captured runtime error.',
		other: '${n} captured runtime errors.',
	);

	/// en: 'Session logs'
	String get sessionLogs => 'Session logs';

	/// en: 'No session lifecycle log lines were captured.'
	String get noSessionLines => 'No session lifecycle log lines were captured.';

	/// en: '(one) {{{n}} recent lifecycle log line.} (other) {{{n}} recent lifecycle log lines.}'
	String recentSessionLines({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} recent lifecycle log line.',
		other: '${n} recent lifecycle log lines.',
	);

	/// en: 'No session lifecycle logs are available.'
	String get sessionLogsUnavailable => 'No session lifecycle logs are available.';

	/// en: 'Runtime error'
	String get runtimeError => 'Runtime error';
}

// Path: sessions.network
class Translations$sessions$network$en {
	Translations$sessions$network$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open this section to load the latest network requests.'
	String get open => 'Open this section to load the latest network requests.';

	/// en: 'Load older requests ({{loaded}} of {{total}})'
	String loadOlder({required Object loaded, required Object total}) => 'Load older requests (${loaded} of ${total})';

	/// en: 'Select a request to inspect it.'
	String get selectRequest => 'Select a request to inspect it.';

	/// en: 'Total'
	String get total => 'Total';

	/// en: 'Loaded'
	String get loaded => 'Loaded';

	/// en: 'Failures'
	String get failures => 'Failures';

	/// en: 'In flight'
	String get inFlight => 'In flight';

	/// en: 'Source'
	String get source => 'Source';

	/// en: 'Export request or response body'
	String get exportTooltip => 'Export request or response body';

	/// en: 'Export safe response'
	String get safeResponse => 'Export safe response';

	/// en: 'Export safe request'
	String get safeRequest => 'Export safe request';

	/// en: 'Export both safely'
	String get safeBoth => 'Export both safely';

	/// en: 'Export unmasked bodies…'
	String get rawBoth => 'Export unmasked bodies…';

	/// en: 'Unknown request URI'
	String get unknownRequestUri => 'Unknown request URI';

	/// en: 'No request metadata is available.'
	String get metadataEmpty => 'No request metadata is available.';

	/// en: 'Copy request metadata'
	String get copyMetadata => 'Copy request metadata';

	/// en: 'Unmasked body files'
	String get unmaskedFiles => 'Unmasked body files';

	/// en: 'Body files'
	String get bodyFiles => 'Body files';

	/// en: 'Cockpit writes request and response bodies to separate verified files.'
	String get bodyDescription => 'Cockpit writes request and response bodies to separate verified files.';

	/// en: 'Copy body file paths'
	String get copyPaths => 'Copy body file paths';

	/// en: 'Export unmasked network bodies?'
	String get confirmRawTitle => 'Export unmasked network bodies?';

	/// en: 'The exported files may contain credentials, cookies, personal data, or binary payloads. Cockpit will return file paths only.'
	String get confirmRawDescription => 'The exported files may contain credentials, cookies, personal data, or binary payloads. Cockpit will return file paths only.';

	/// en: 'Export unmasked'
	String get exportUnmasked => 'Export unmasked';

	/// en: 'No network requests were captured. Use the app, then refresh this section.'
	String get empty => 'No network requests were captured. Use the app, then refresh this section.';

	/// en: 'Unknown URI'
	String get unknownUri => 'Unknown URI';

	/// en: 'Unknown'
	String get unknownSource => 'Unknown';
}

// Path: ai.tool.status
class Translations$ai$tool$status$en {
	Translations$ai$tool$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Completed'
	String get completed => 'Completed';

	/// en: 'Failed'
	String get failed => 'Failed';

	/// en: 'In progress'
	String get inProgress => 'In progress';
}

// Path: sessions.timeline.severity
class Translations$sessions$timeline$severity$en {
	Translations$sessions$timeline$severity$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Info'
	String get info => 'Info';

	/// en: 'Success'
	String get success => 'Success';

	/// en: 'Warning'
	String get warning => 'Warning';

	/// en: 'Error'
	String get error => 'Error';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'app.title' => 'Cockpit Console',
			'app.connecting' => 'Connecting to Cockpit',
			'app.checking' => 'Checking daemon health and Supervisor capabilities.',
			'common.refresh' => 'Refresh',
			'common.retry' => 'Retry',
			'common.cancel' => 'Cancel',
			'common.copy' => 'Copy',
			'common.copyFailed' => 'Could not copy',
			'common.close' => 'Close',
			'common.unknown' => 'Unknown',
			'common.notSet' => 'Not set',
			'common.previousPage' => 'Previous page',
			'common.nextPage' => 'Next page',
			'common.pageRange' => ({required Object start, required Object end, required Object total}) => '${start}–${end} of ${total}',
			'language.title' => 'Language',
			'language.system' => 'Follow system',
			'language.english' => 'English',
			'language.simplifiedChinese' => '简体中文',
			'nav.dashboard' => 'Dashboard',
			'nav.projects' => 'Projects',
			'nav.appsDevices' => 'Apps & devices',
			'nav.liveSessions' => 'Live sessions',
			'nav.tests' => 'Tests',
			'nav.testRuns' => 'Test runs',
			'nav.actions' => 'Actions',
			'nav.aiAssistant' => 'AI Assistant',
			'shell.offline' => 'Offline',
			'shell.connected' => 'Connected',
			'shell.degraded' => 'Degraded',
			'shell.toggleTheme' => 'Toggle theme',
			'shell.closeNavigation' => 'Close navigation',
			'shell.openNavigation' => 'Open navigation',
			'shell.expandNavigation' => 'Expand navigation',
			'shell.collapseNavigation' => 'Collapse navigation',
			'dashboard.title' => 'Dashboard',
			'dashboard.subtitle' => 'Supervisor status and system overview',
			'dashboard.startDaemon' => 'Start daemon',
			'dashboard.restartDaemon' => 'Restart daemon',
			'dashboard.systemOperational' => 'System operational',
			'dashboard.daemonApiDisconnected' => 'Daemon running, API disconnected',
			'dashboard.daemonOffline' => 'Daemon offline',
			'dashboard.apiVersion' => 'API version',
			'dashboard.engine' => 'Engine',
			'dashboard.started' => 'Started',
			'dashboard.operations' => 'Operations',
			'dashboard.daysAgo' => ({required Object count}) => '${count}d ago',
			'dashboard.hoursAgo' => ({required Object count}) => '${count}h ago',
			'dashboard.minutesAgo' => ({required Object count}) => '${count}m ago',
			'dashboard.justNow' => 'Just now',
			'dashboard.serverInformation' => 'Server information',
			'dashboard.instanceId' => 'Instance ID',
			'dashboard.engineVersion' => 'Engine version',
			'dashboard.startedAt' => 'Started at',
			'dashboard.connectingTitle' => 'Connecting to Supervisor',
			'dashboard.connectingDescription' => 'Establishing daemon connection and reading capabilities.',
			'dashboard.disconnectedTitle' => 'Cannot connect to Supervisor',
			'dashboard.retryConnection' => 'Retry connection',
			'statusBar.daemonHealthy' => 'Daemon healthy',
			'statusBar.daemonDegraded' => 'Daemon degraded',
			'statusBar.daemonOffline' => 'Daemon offline',
			'statusBar.apiVersion' => ({required Object version}) => 'API v${version}',
			'projects.title' => 'Projects',
			'projects.subtitle' => 'Choose which local folders and projects Cockpit can use',
			'projects.addProject' => 'Add project',
			'projects.allowedFolders' => 'Allowed folders',
			'projects.addFolder' => 'Add folder',
			'projects.hideRemovedHistory' => 'Hide removed history',
			'projects.showRemovedHistory' => ({required Object count}) => 'Show removed history (${count})',
			'projects.removedFolders' => 'Removed folders',
			'projects.removedProjects' => 'Removed projects',
			'projects.noAllowedFolders' => 'No allowed folders',
			'projects.noAllowedFoldersDescription' => 'Add a local folder before adding projects inside it.',
			'projects.removeFolderTooltip' => 'Remove folder from Cockpit',
			'projects.removeFolderTitle' => 'Remove allowed folder?',
			'projects.removeFolderDescription' => ({required Object path}) => 'Cockpit will stop using ${path} and remove its registered projects. Project files stay on disk. Removing now may interrupt active Cockpit sessions.',
			'projects.folderRemoved' => 'Removed folder from Cockpit',
			'projects.folderRemoveFailed' => 'Could not remove folder from Cockpit',
			'projects.finishWorkRemove' => 'Finish work and remove',
			'projects.removeNow' => 'Remove now',
			'projects.stateReady' => 'Ready',
			'projects.stateRemoving' => 'Removing',
			'projects.stateRemoved' => 'Removed',
			'projects.noProjects' => 'No projects added',
			'projects.noProjectsDescription' => 'Add a project directory to connect apps and run tests.',
			'projects.removedProjectSemantics' => ({required Object name}) => 'Removed project ${name}',
			'projects.selectProjectSemantics' => ({required Object name}) => 'Select project ${name}',
			'projects.workspaceIdentity' => ({required Object workspace, required Object root}) => '${workspace} · root ${root}',
			'projects.updateLocationTooltip' => 'Update project location',
			'projects.current' => 'Current',
			'projects.removeProjectTooltip' => 'Remove project from Cockpit',
			'projects.removeProjectTitle' => 'Remove project?',
			'projects.removeProjectDescription' => ({required Object path}) => 'Cockpit will stop using ${path}. Project files stay on disk. Removing now may interrupt active Cockpit sessions.',
			'projects.projectRemoved' => 'Removed project from Cockpit',
			'projects.projectRemoveFailed' => 'Could not remove project',
			'projects.absoluteFolderError' => 'Choose an absolute folder path.',
			'projects.addFolderFailed' => 'Could not add the folder.',
			'projects.addFolderTitle' => 'Add allowed folder',
			'projects.addFolderDescription' => 'Cockpit can only use projects inside folders you add here. Nothing is uploaded.',
			'projects.folderPath' => 'Folder path',
			'projects.folderPathHint' => '/absolute/path/to/project',
			'projects.optionalName' => 'Name (optional)',
			'projects.projectNameHint' => 'My Project',
			'projects.allowedFolderRequired' => 'Add an allowed folder first.',
			'projects.absoluteProjectError' => 'Choose an absolute project directory.',
			'projects.addProjectFailed' => 'Could not add the project.',
			'projects.allowedFolder' => 'Allowed folder',
			'projects.projectDirectory' => 'Project directory',
			'projects.noAllowedFoldersAvailable' => 'No allowed folders are available.',
			'projects.newAbsoluteProjectError' => 'Choose the project’s new absolute directory.',
			'projects.updateLocationFailed' => 'Could not update the project location.',
			'projects.updateLocationTitle' => 'Update project location',
			'projects.currentDirectory' => 'Current directory',
			'projects.newProjectDirectory' => 'New project directory',
			'projects.updateLocation' => 'Update location',
			'targets.title' => 'Apps and devices',
			'targets.subtitle' => 'Find and connect the apps and devices used by this project',
			'targets.selectProject' => 'Select a project',
			'targets.selectProjectDescription' => 'Choose a project from the Projects page to view its apps and devices.',
			'targets.chooseProject' => 'Choose project',
			'targets.discoverFailed' => ({required Object error}) => 'Could not find apps and devices: ${error}',
			'targets.find' => 'Find apps and devices',
			'targets.readyToUse' => 'Ready to use',
			'targets.noneAdded' => 'No apps or devices added',
			'targets.noneAddedDescription' => 'Find available apps and devices, then add the one you need.',
			'targets.availableToAdd' => 'Available to add',
			'targets.noneFound' => 'No apps or devices found',
			'targets.noneFoundDescription' => 'Connect or start a device, then try finding again.',
			'targets.loadFailed' => 'Could not load apps and devices',
			'targets.running' => 'Running',
			'targets.ready' => 'Ready',
			'targets.appSemantics' => ({required Object name}) => 'App ${name}',
			'targets.sessionUnavailable' => 'The app is running, but its Cockpit session is not available yet.',
			'targets.monitorSession' => 'Monitor live session',
			'targets.start' => 'Start app or device',
			'targets.addNamed' => ({required Object name}) => 'Add ${name}',
			'targets.kind.flutterApp' => 'Flutter app',
			'targets.kind.nativeApp' => 'Native app',
			'targets.kind.desktopApp' => 'Desktop app',
			'targets.kind.browserPage' => 'Browser page',
			'targets.kind.systemSurface' => 'System surface',
			'targets.kind.device' => 'Device',
			'targets.kind.hostWorkspace' => 'Host workspace',
			'targets.mode.development' => 'Development',
			'targets.mode.automation' => 'Automation',
			'targets.environment.development' => 'Development',
			'targets.environment.test' => 'Test',
			'targets.environment.staging' => 'Staging',
			'targets.environment.production' => 'Production',
			'targets.environment.unknown' => 'Unknown',
			'targets.keyValueSyntaxError' => ({required Object line}) => 'Entries must use KEY=VALUE syntax: “${line}”.',
			'targets.appIdRequired' => ({required Object kind}) => '${kind} targets require an app ID.',
			'targets.added' => ({required Object name}) => 'Added ${name}',
			'targets.addTitle' => 'Add app or device',
			'targets.device' => 'Device',
			'targets.platform' => 'Platform',
			'targets.deviceId' => 'Device ID',
			'targets.type' => 'Type',
			'targets.launchFile' => 'Launch file',
			'targets.optional' => 'Optional',
			'targets.none' => 'None',
			'targets.appIdentifier' => 'App identifier',
			'targets.required' => 'Required',
			'targets.flavor' => 'Flavor',
			'targets.optionalIos' => 'Optional (iOS)',
			'targets.environmentLabel' => 'Environment',
			'targets.modeLabel' => 'Mode',
			'targets.add' => 'Add',
			'targets.timeoutIntegerError' => 'Launch timeout must be an integer number of milliseconds.',
			'targets.timeoutRangeError' => 'Launch timeout must be between 1,000 and 1,800,000 ms.',
			'targets.launched' => ({required Object target}) => 'Launched ${target}',
			'targets.launchTitle' => ({required Object kind}) => 'Launch ${kind}',
			'targets.target' => 'Target',
			'targets.systemControlNote' => 'This target is activated through system control. Launch mode and Flutter configuration are not accepted.',
			'targets.launchTimeout' => 'Launch timeout (ms)',
			'targets.launchTimeoutDefault' => 'Default (600,000)',
			'targets.launchConfiguration' => 'Launch configuration',
			'targets.dartDefines' => 'Dart defines',
			'targets.keyValueLines' => 'KEY=VALUE, one per line',
			'targets.dartDefineFiles' => 'Dart define files',
			'targets.fileLines' => 'config/*.json, one per line',
			'targets.flutterArgs' => 'Flutter arguments',
			'targets.flutterArgsLines' => '--verbose, one per line',
			'targets.launch' => 'Launch',
			'tests.title' => 'Tests',
			'tests.subtitle' => 'Create and check case or suite files in LON, JSON, or YAML',
			'tests.selectProject' => 'Select a project',
			'tests.selectProjectDescription' => 'Choose a project from the Projects page to view its test files.',
			'tests.chooseProject' => 'Choose project',
			'tests.loadFailed' => 'Could not load test files',
			'tests.readFailed' => ({required Object path, required Object error}) => 'Could not read ${path}: ${error}',
			'tests.discardTitle' => 'Discard unsaved changes?',
			'tests.discardDescription' => 'The editor contains changes that have not been saved.',
			'tests.keepEditing' => 'Keep editing',
			'tests.discardChanges' => 'Discard changes',
			'tests.files' => 'Test files',
			'tests.newTest' => 'New test',
			'tests.emptyTitle' => 'No test files yet',
			'tests.emptyDescription' => 'Create a test, save it, then check it before running.',
			'tests.suite' => 'Test suite',
			'tests.suiteCases' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Test suite · ${n} case', other: 'Test suite · ${n} cases', ),
			'tests.testCase' => 'Test case',
			'tests.filePath' => 'Test file path',
			'tests.filePathHint' => 'Relative to project, for example cockpit/e2e/case.yaml',
			'tests.saving' => 'Saving',
			'tests.unsaved' => 'Unsaved',
			'tests.saved' => 'Saved',
			'tests.format' => 'Format',
			'tests.save' => 'Save test',
			'tests.check' => 'Check test',
			'tests.saveWorkspaceChanged' => 'The selected project changed before saving started.',
			'tests.saveBusy' => 'A test save is already in progress.',
			'tests.saveEmpty' => 'Test content cannot be empty.',
			'tests.saveRelativePath' => 'The test path must be relative to the project.',
			'tests.saveExtensionLon' => 'LON tests must use a .lon path.',
			'tests.saveExtensionJson' => 'JSON tests must use a .json path.',
			'tests.saveExtensionYaml' => 'YAML tests must use a .yaml or .yml path.',
			'tests.saveDocumentChanged' => 'The test changed while it was being checked. Save it again.',
			'tests.saveFailed' => 'Could not save the test.',
			'tests.indexed' => ({required Object path}) => 'Saved and indexed ${path}',
			'tests.indexedCleanupWarning' => ({required Object path, required Object error}) => 'Saved and indexed ${path}, but the previous backup could not be removed: ${error}',
			'tests.validationNoDiagnostic' => 'The test is invalid, but no diagnostic was returned.',
			'tests.valid' => 'Valid document',
			'tests.invalid' => 'Validation failed',
			'tests.errors' => ({required Object count}) => 'Errors: ${count}',
			'tests.warnings' => ({required Object count}) => 'Warnings: ${count}',
			'runs.title' => 'Test runs',
			'runs.subtitle' => 'Run a test case or suite and follow its result',
			'runs.selectProject' => 'Select a project',
			'runs.selectProjectDescription' => 'Choose a project from the Projects page to start a test run.',
			'runs.chooseProject' => 'Choose project',
			'runs.inputsObjectError' => 'Run inputs must be a LON, JSON, or YAML object.',
			'runs.durationError' => 'Use a duration such as 30s, 5m, or 1h.',
			'runs.timeoutUnitError' => 'Unsupported timeout unit.',
			'runs.timeoutRangeError' => ({required Object maximum}) => 'Timeout must be between 1ms and ${maximum}.',
			'runs.suite' => 'Suite',
			'runs.caseLabel' => 'Case',
			'runs.restoreFailed' => ({required Object error}) => 'Could not restore run status: ${error}',
			'runs.selectedFileChanged' => 'The selected test file changed or was removed. Choose it again.',
			'runs.refreshTestsFailed' => ({required Object error}) => 'Could not refresh test files: ${error}',
			'runs.cancellationRequested' => 'Cancellation requested',
			'runs.cancelFailed' => ({required Object error}) => 'Could not cancel the run: ${error}',
			'runs.refreshFailed' => ({required Object error}) => 'Could not refresh the run: ${error}',
			'runs.retryRecent' => 'Retry recent runs',
			'runs.refreshRecent' => 'Refresh recent runs',
			'runs.saveArtifact' => 'Save artifact',
			'runs.artifactSaved' => ({required Object path}) => 'Saved verified artifact to ${path}',
			'runs.downloadFailed' => ({required Object error}) => 'Download failed: ${error}',
			'runs.observeFailed' => ({required Object error}) => 'Could not observe the run: ${error}',
			'runs.jsonEventError' => 'Expected a JSON object event.',
			'runs.completed' => 'Run completed',
			'runs.streamEvent' => ({required Object kind}) => 'Stream ${kind}',
			'runs.malformedEvent' => ({required Object error}) => 'Malformed event: ${error}',
			'runs.statusLoadFailed' => ({required Object error}) => 'Could not load run status: ${error}',
			'runs.streamEnded' => 'Event stream ended before the terminal state',
			'runs.loadingTests' => 'Loading test files…',
			'runs.testsUnavailable' => 'Test files are temporarily unavailable.',
			'runs.createTestFirst' => 'Create a test file before starting a run.',
			'runs.selectFile' => 'Select a test file to continue.',
			'runs.selectCase' => 'Select a test case to continue.',
			'runs.ready' => 'Ready to run in the current project.',
			'runs.startTitle' => 'Start a test run',
			'runs.startDescription' => 'Choose a case or suite. Override the app only when the test file default is not the intended target.',
			'runs.testFileStep' => '1. Test file',
			'runs.chooseTestFile' => 'Choose a test file',
			'runs.testCaseStep' => '2. Test case',
			'runs.chooseTestCase' => 'Choose a test case',
			'runs.suiteContentsStep' => '2. Suite contents',
			'runs.allSuiteCases' => 'All cases in this suite',
			'runs.targetStep' => '3. App or device',
			'runs.useFileDefault' => 'Use test file default',
			'runs.retryTests' => 'Retry tests',
			'runs.openTests' => 'Open tests',
			'runs.indexLoadFailed' => 'Cockpit could not load the current test index. Retry when the project worker is available.',
			'runs.indexRefreshFailed' => 'Cockpit could not refresh the test index. Existing choices remain available.',
			'runs.runSuite' => 'Run suite',
			'runs.runTest' => 'Run test',
			'runs.options' => 'Run options',
			'runs.inputsOptional' => 'Inputs (optional)',
			'runs.inputsHint' => 'LON, JSON, or YAML object',
			'runs.timeoutOptional' => 'Timeout (optional)',
			'runs.timeoutHint' => 'Use the default, for example 30s or 5m',
			'runs.recentUnavailable' => 'Recent runs are temporarily unavailable',
			'runs.loadingRun' => 'Loading run',
			'runs.events' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} event', other: '${n} events', ),
			'runs.newRun' => 'New run',
			'runs.cancelRun' => 'Cancel run',
			'runs.recentRuns' => 'Recent runs',
			'runs.failureTitle' => 'Why this run failed',
			'runs.filesEvidence' => ({required Object count}) => 'Files and evidence (${count})',
			'runs.saveFile' => 'Save file',
			'runs.state.queued' => 'Queued',
			'runs.state.running' => 'Running',
			'runs.state.finalizing' => 'Finalizing',
			'runs.state.completed' => 'Completed',
			'runs.state.passed' => 'Passed',
			'runs.state.failed' => 'Failed',
			'runs.state.blocked' => 'Blocked',
			'runs.state.skipped' => 'Skipped',
			'runs.state.cancelled' => 'Cancelled',
			'runs.state.interrupted' => 'Interrupted',
			'runs.state.internalError' => 'Error',
			'actions.title' => 'Actions',
			'actions.subtitle' => 'Inspect and run the actions available in Cockpit',
			'actions.select' => 'Select an action',
			'actions.selectDescription' => 'Choose an available action to review its inputs and run it with a LON, JSON, or YAML object.',
			'actions.selectProjectReason' => 'Select a project to run this project-scoped action.',
			'actions.selectFolderReason' => 'Select an allowed folder to run this folder-scoped action.',
			'actions.noFolderReason' => 'No allowed folder is available. Add one under Projects to run folder-scoped actions.',
			'actions.filter' => 'Filter actions',
			'actions.global' => 'Global actions',
			'actions.project' => 'Project actions',
			'actions.loadFailed' => ({required Object error}) => 'Could not load actions: ${error}',
			'actions.none' => 'No actions are advertised.',
			'actions.noMatch' => ({required Object query}) => 'No actions match “${query}”.',
			'actions.scopeBadge.global' => 'global',
			'actions.scopeBadge.workspace' => 'workspace',
			'actions.scopeBadge.root' => 'root',
			'actions.input' => 'Input',
			'actions.inputDescription' => 'A LON, JSON, or YAML object. The idempotency key belongs to the invocation envelope, not this object.',
			'actions.scope' => 'Scope',
			'actions.mutation' => 'Mutation',
			'actions.idempotency' => 'Idempotency',
			'actions.execution' => 'Execution',
			'actions.timeout' => 'Timeout',
			'actions.timeoutValue' => ({required Object defaultValue, required Object maximum}) => '${defaultValue} (maximum ${maximum})',
			'actions.effects' => 'Effects',
			'actions.features' => 'Features',
			'actions.inputSchema' => 'Input schema',
			'actions.outputSchema' => 'Output schema',
			'actions.idempotencyKey' => 'Idempotency key',
			'actions.generatedWhenRun' => 'Generated when run',
			'actions.optional' => 'Optional',
			'actions.generateKey' => 'Generate a new key',
			'actions.keyRequiredDescription' => 'Required because this action can change state.',
			'actions.keyOptionalDescription' => 'Optional and omitted when blank.',
			'actions.noRoots' => 'No active project roots are registered.',
			'actions.projectRoot' => 'Project root',
			'actions.selectRoot' => 'Select an active root',
			'actions.unavailable' => 'This action cannot be run here.',
			'actions.addFolder' => 'Add allowed folder',
			'actions.running' => 'Running…',
			'actions.run' => 'Run action',
			'actions.mutationWarning' => 'This action can change state.',
			'actions.scopeRootDescription' => 'Runs for the selected allowed folder.',
			'actions.scopeProjectDescription' => 'Runs for the selected project.',
			'actions.scopeGlobalDescription' => 'Runs in Supervisor scope; no project required.',
			'actions.failed' => 'Action did not succeed',
			'actions.result' => 'Result',
			'actions.submitted' => 'Submitted',
			'actions.submittedState' => ({required Object state}) => 'Submitted · ${state}',
			'actions.copied' => 'Copied',
			'actions.copy' => 'Copy',
			'actions.scopeValue.supervisor' => 'Supervisor (global)',
			'actions.scopeValue.root' => 'Root',
			'actions.scopeValue.workspace' => 'Workspace',
			'actions.mutationValue.readOnly' => 'Read-only',
			'actions.mutationValue.mutating' => 'Mutating',
			'actions.idempotencyValue.required' => 'Required',
			'actions.idempotencyValue.optional' => 'Optional',
			'actions.idempotencyValue.prohibited' => 'Prohibited',
			'actions.executionValue.synchronous' => 'Synchronous',
			'actions.executionValue.job' => 'Job',
			'ai.title' => 'AI Assistant',
			'ai.settings' => 'Agent settings',
			'ai.connectToStart' => 'Connect an AI agent to start',
			'ai.connecting' => 'Connecting…',
			'ai.connectingToAgent' => 'Connecting to agent',
			'ai.startConversation' => 'Start a conversation',
			'ai.connectDescription' => 'Connect an ACP-compatible agent, then ask questions or run development tasks here.',
			'ai.connectAgent' => 'Connect agent',
			'ai.connectChatHint' => 'Connect an agent to start chatting',
			'ai.connectTitle' => 'Connect AI agent',
			'ai.connectSubtitle' => 'Choose an agent and its working directory.',
			'ai.closeConnectionSetup' => 'Close connection setup',
			'ai.closeSettings' => 'Close settings',
			'ai.disconnected' => 'The agent is no longer connected.',
			'ai.clearChat' => 'Clear chat view',
			'ai.disconnect' => 'Disconnect agent',
			'ai.custom' => 'Custom',
			'ai.customDescription' => 'Any ACP executable',
			'ai.agent' => 'Agent',
			'ai.chooseAgent' => 'Choose an AI agent',
			'ai.presetDescription' => ({required Object name}) => '${name} ACP agent',
			'ai.selectWorkingDirectory' => 'Select working directory',
			'ai.startSession' => 'Start session',
			'ai.executable' => 'Executable',
			'ai.arguments' => 'Arguments (one per line)',
			'ai.argumentsDescription' => 'Passed directly to the executable without a shell.',
			'ai.workingDirectory' => 'Working directory',
			'ai.workingDirectoryHint' => '/absolute/path/to/project',
			'ai.browseDirectories' => 'Browse directories',
			'ai.selectProjectBeforeEditing' => 'Select a project before editing.',
			'ai.latest' => 'Latest',
			'ai.dismissError' => 'Dismiss error',
			'ai.permissionRequired' => 'Permission required to continue',
			'ai.input' => 'Input',
			'ai.location' => 'Location',
			'ai.locations' => 'Locations',
			'ai.cancelRequest' => 'Cancel request',
			'ai.signInTitle' => 'Sign in to continue',
			'ai.signInDescription' => 'Choose an authentication method in agent settings, then finish the sign-in flow.',
			'ai.openSignIn' => 'Open sign-in',
			'ai.sessionTitle' => 'Create or open a session',
			'ai.sessionDescription' => 'Use agent settings to start a new session or resume recent work.',
			'ai.openSessionSetup' => 'Open session setup',
			'ai.conversationDescription' => 'Ask about your workspace, request a change, or describe a test scenario.',
			'ai.sendToEditor' => 'Send to editor',
			'ai.composer.duplicateAttachment' => 'That attachment is already included.',
			'ai.composer.messageHint' => 'Send a message…',
			'ai.composer.sessionRequiredHint' => 'Create a session or sign in to start chatting',
			'ai.composer.stopResponse' => 'Stop response',
			'ai.composer.sendMessage' => 'Send message (Enter)',
			'ai.composer.addMessage' => 'Write a message or add an attachment',
			'ai.composer.inlineLimit' => ({required Object size, required Object limit}) => '${size} inline · ${limit} limit',
			'ai.composer.availableCommands' => 'Available commands',
			'ai.composer.addContext' => 'Add context',
			'ai.composer.attachImage' => 'Attach image',
			'ai.composer.attachImageDescription' => 'Send image data inline',
			'ai.composer.attachAudio' => 'Attach audio',
			'ai.composer.attachAudioDescription' => 'Send audio data inline',
			'ai.composer.embedContext' => 'Embed context file',
			'ai.composer.embedContextDescription' => 'Include complete file contents',
			'ai.composer.linkFile' => 'Link local file',
			'ai.composer.linkFileDescription' => 'Reference a file without copying it',
			'ai.composer.linkResource' => 'Link resource URI',
			'ai.composer.linkResourceDescription' => 'Reference any agent-accessible resource',
			'ai.composer.removeAttachment' => ({required Object name}) => 'Remove ${name}',
			'ai.composer.name' => 'Name',
			'ai.composer.nameHint' => 'API specification',
			'ai.composer.absoluteUri' => 'Absolute URI',
			'ai.composer.mimeOptional' => 'MIME type (optional)',
			'ai.composer.descriptionOptional' => 'Description (optional)',
			'ai.composer.resourceError' => 'Enter a name and an absolute URI with a scheme.',
			'ai.composer.addResource' => 'Add resource',
			'ai.composer.linked' => 'linked',
			'ai.composer.embedded' => 'embedded',
			'ai.composer.pathUnavailable' => 'The selected file does not expose a local path.',
			'ai.composer.notRegularFile' => 'The selected path is not a regular file.',
			'ai.composer.resourceRequirements' => 'Resource links require a name and an absolute URI.',
			'ai.composer.promptLimit' => ({required Object size, required Object limit}) => 'Inline attachments use ${size}. The prompt limit is ${limit}.',
			'ai.composer.unsupportedImage' => ({required Object name}) => '“${name}” is not a supported image file.',
			'ai.composer.unsupportedAudio' => ({required Object name}) => '“${name}” is not a supported audio file.',
			'ai.composer.emptyFile' => 'The selected file is empty.',
			'ai.composer.fileTooLarge' => ({required Object size, required Object limit}) => 'The selected file is ${size}. Inline attachments are limited to ${limit}.',
			'ai.connection.createSession' => 'Create session',
			'ai.connection.workingDirectory' => 'Working directory',
			'ai.connection.selectSessionDirectory' => 'Select session working directory',
			'ai.connection.sessionContext' => 'Session context',
			'ai.connection.optionalContext' => 'Optional directories and MCP servers',
			'ai.connection.configuredItems' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} configured item', other: '${n} configured items', ),
			'ai.connection.additionalDirectories' => 'Additional directories',
			'ai.connection.additionalDirectoriesDescription' => 'Grant the agent access to workspace roots beyond the working directory.',
			'ai.connection.addDirectory' => 'Add directory',
			'ai.connection.mcpServers' => 'MCP servers',
			'ai.connection.mcpServersDescription' => 'Attach tools and resources for this Agent connection. Values are not stored.',
			'ai.connection.addServer' => 'Add server',
			'ai.connection.addSessionDirectory' => 'Add session directory',
			'ai.connection.duplicateDirectory' => 'That directory is already included.',
			'ai.connection.duplicateServer' => 'MCP server names must be unique.',
			'ai.connection.remove' => ({required Object name}) => 'Remove ${name}',
			'ai.mcp.addTitle' => 'Add MCP server',
			'ai.mcp.editTitle' => 'Edit MCP server',
			'ai.mcp.transport' => 'Transport',
			'ai.mcp.name' => 'Name',
			'ai.mcp.executablePath' => 'Absolute executable path',
			'ai.mcp.serverUrl' => 'Server URL',
			'ai.mcp.arguments' => 'Arguments (one per line)',
			'ai.mcp.environment' => 'Environment (NAME=value)',
			'ai.mcp.headers' => 'Headers (Name: value)',
			'ai.mcp.valuesDescription' => 'Connection-only values. Cockpit Console does not store them.',
			'ai.mcp.addServer' => 'Add server',
			'ai.mcp.saveServer' => 'Save server',
			'ai.mcp.nameRequired' => 'Enter a server name.',
			'ai.mcp.executableRequired' => 'Enter an executable path.',
			'ai.mcp.urlRequired' => 'Enter a server URL.',
			'ai.mcp.absoluteExecutable' => 'The stdio executable must use an absolute path.',
			'ai.mcp.absoluteUrl' => 'The server URL must be an absolute HTTP(S) URL.',
			'ai.mcp.environmentSyntax' => ({required Object line}) => 'Environment line ${line} must use NAME=value.',
			'ai.mcp.environmentName' => ({required Object line}) => 'Environment line ${line} has an invalid variable name.',
			'ai.mcp.environmentDuplicate' => ({required Object name}) => 'Environment variable “${name}” is duplicated.',
			'ai.mcp.headerSyntax' => ({required Object line}) => 'Header line ${line} must use Name: value.',
			'ai.mcp.headerName' => ({required Object line}) => 'Header line ${line} has an invalid name.',
			'ai.mcp.headerDuplicate' => ({required Object name}) => 'Header “${name}” is duplicated.',
			'ai.mcp.stdioDescription' => 'Supported by every ACP agent.',
			'ai.mcp.httpDescription' => 'Requires the agent HTTP MCP capability.',
			'ai.mcp.sseDescription' => 'Requires the agent SSE MCP capability.',
			'ai.session.authentication' => 'Authentication',
			'ai.session.signIn' => 'Sign in',
			'ai.session.signOut' => 'Sign out',
			'ai.session.section' => 'Session',
			'ai.session.refreshRecent' => 'Refresh recent sessions',
			'ai.session.signInFirst' => 'Sign in before creating a session.',
			'ai.session.noneOpen' => 'No session is open. Create one to start chatting.',
			'ai.session.newSession' => 'New session',
			'ai.session.close' => 'Close session',
			'ai.session.recent' => 'Recent sessions',
			'ai.session.loading' => 'Loading sessions…',
			'ai.session.noneSaved' => 'No saved sessions were returned by this agent.',
			'ai.session.loadMore' => 'Load more',
			'ai.session.activeSession' => 'Active session',
			'ai.session.additionalDirectories' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} additional directory', other: '${n} additional directories', ),
			'ai.session.mcpServers' => ({required Object names}) => 'MCP: ${names}',
			'ai.session.active' => 'Active',
			'ai.session.actions' => 'Session actions',
			'ai.session.resume' => 'Resume',
			'ai.session.load' => 'Load',
			'ai.session.loadHistory' => 'Load from history',
			'ai.session.delete' => 'Delete session',
			'ai.session.settings' => 'Agent settings',
			'ai.session.mode' => 'Mode',
			'ai.session.noSettings' => 'This agent did not advertise session settings.',
			'ai.session.currentContext' => 'Current context',
			_ => null,
		} ?? switch (path) {
			'ai.session.usage' => 'Usage',
			'ai.session.tokensUsed' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} token used', other: '${n} tokens used', ),
			'ai.session.tokenContext' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n}-token context', other: '${n}-token context', ),
			'ai.session.plan' => 'Plan',
			'ai.session.availableCommands' => 'Available commands',
			'ai.session.authNotRequired' => 'Authentication is not required',
			'ai.session.authAvailable' => 'Sign-in is available',
			'ai.session.authRequired' => 'Sign-in is required',
			'ai.session.authWaiting' => 'Waiting for sign-in to finish…',
			'ai.session.authenticated' => 'Signed in',
			'ai.session.signingOut' => 'Signing out…',
			'ai.session.capImages' => 'Images',
			'ai.session.capAudio' => 'Audio',
			'ai.session.capContext' => 'Context files',
			'ai.session.capLoad' => 'Load sessions',
			'ai.session.capResume' => 'Resume',
			'ai.session.capHistory' => 'History',
			'ai.session.deleteTitle' => 'Delete session?',
			'ai.session.deleteDescription' => ({required Object name}) => 'Delete “${name}” from the agent. This cannot be undone.',
			'ai.session.keep' => 'Keep session',
			'ai.tool.rawInput' => 'Raw input',
			'ai.tool.rawOutput' => 'Raw output',
			'ai.tool.terminal' => 'Terminal',
			'ai.tool.audio' => 'Audio',
			'ai.tool.invalidImage' => ({required Object mime}) => 'The agent returned invalid ${mime} image data.',
			'ai.tool.malformedImage' => 'The agent returned malformed base64 image data.',
			'ai.tool.textResource' => 'Text resource',
			'ai.tool.binaryResource' => 'Binary resource',
			'ai.tool.diff' => 'Diff',
			'ai.tool.before' => 'Before',
			'ai.tool.after' => 'After',
			'ai.tool.location' => 'Location',
			'ai.tool.status.completed' => 'Completed',
			'ai.tool.status.failed' => 'Failed',
			'ai.tool.status.inProgress' => 'In progress',
			'sessions.title' => 'Live sessions',
			'sessions.subtitle' => 'Observe running apps without changing or restarting them',
			'sessions.findingTitle' => 'Finding running sessions',
			'sessions.findingDescription' => 'Cockpit is checking every active project for running apps.',
			'sessions.emptyTitle' => 'No sessions to monitor',
			'sessions.emptyDescription' => 'Start an app with Cockpit. Running sessions appear here automatically and remain available after they stop.',
			'sessions.checkAgain' => 'Check again',
			'sessions.liveCount' => ({required Object live, required Object total}) => '${live} live · ${total} total',
			'sessions.liveCountSemantics' => ({required Object live, required Object total}) => '${live} live sessions, ${total} total sessions',
			'sessions.listTitle' => 'Sessions',
			'sessions.selectSemantics' => ({required Object project, required Object platform, required Object session}) => '${project}, ${platform}, session ${session}',
			'sessions.refreshFailed' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Could not refresh ${n} project.', other: 'Could not refresh ${n} projects.', ),
			'sessions.refreshProjectFailed' => 'Project refresh failed.',
			'sessions.stoppedMessage' => 'This session is no longer active.',
			'sessions.bridgeReconnectingMessage' => 'The app bridge is reconnecting.',
			'sessions.selectPrompt' => 'Select a session to inspect its live state.',
			'sessions.sessionId' => ({required Object session}) => 'Session ${session}',
			'sessions.contextApp' => 'App',
			'sessions.contextAppTip' => 'Open this project in Apps & devices',
			'sessions.contextActions' => 'Actions',
			'sessions.contextActionsTip' => 'Open actions for this project',
			'sessions.contextTests' => 'Tests',
			'sessions.contextTestsTip' => 'Open tests for this project',
			'sessions.contextRuns' => 'Runs',
			'sessions.contextRunsTip' => 'Open test runs for this project',
			'sessions.refreshSection' => ({required Object section}) => 'Refresh ${section}',
			'sessions.status.reconnecting' => 'Reconnecting',
			'sessions.status.live' => 'Live',
			'sessions.status.starting' => 'Starting',
			'sessions.status.reloading' => 'Reloading',
			'sessions.status.restarting' => 'Restarting',
			'sessions.status.checking' => 'Checking',
			'sessions.status.failed' => 'Failed',
			'sessions.status.unavailable' => 'Unavailable',
			'sessions.status.stopped' => 'Stopped',
			'sessions.sections.overview' => 'Overview',
			'sessions.sections.ui' => 'UI',
			'sessions.sections.logs' => 'Logs',
			'sessions.sections.network' => 'Network',
			'sessions.sections.activity' => 'Activity',
			'sessions.sections.diagnostics' => 'Diagnostics',
			'sessions.data.structured' => 'Structured data',
			'sessions.data.empty' => 'No data is available for this session yet.',
			'sessions.data.copy' => 'Copy data',
			'sessions.data.copied' => 'Data copied',
			'sessions.data.notSet' => 'Not set',
			'sessions.data.copyLabel' => ({required Object label}) => 'Copy ${label}',
			'sessions.data.labelCopied' => ({required Object label}) => '${label} copied',
			'sessions.data.fields' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} field', other: '${n} fields', ),
			'sessions.data.items' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} item', other: '${n} items', ),
			'sessions.overview.appProcess' => 'App process',
			'sessions.overview.reachable' => 'Reachable',
			'sessions.overview.unavailable' => 'Unavailable',
			'sessions.overview.checking' => 'Checking',
			'sessions.overview.bridge' => 'Cockpit bridge',
			'sessions.overview.connected' => 'Connected',
			'sessions.overview.disconnected' => 'Disconnected',
			'sessions.overview.runtimeErrors' => 'Runtime errors',
			'sessions.overview.networkFailures' => 'Network failures',
			'sessions.overview.currentState' => 'Current state',
			'sessions.overview.currentStateDescription' => 'The exact app and bridge identity Cockpit is observing.',
			'sessions.overview.route' => 'Route',
			'sessions.overview.lifecycle' => 'Lifecycle',
			'sessions.overview.reloadGeneration' => 'Reload generation',
			'sessions.overview.lastRuntimeStatus' => 'Last runtime status',
			'sessions.overview.nextStep' => 'Next step',
			'sessions.overview.lastError' => 'Last error',
			'sessions.overview.noActionNeeded' => 'No action needed',
			'sessions.overview.launchIdentity' => 'Launch identity',
			'sessions.overview.launchIdentityDescription' => 'Use these values to confirm the app is running in the intended project.',
			'sessions.overview.project' => 'Project',
			'sessions.overview.workspace' => 'Workspace',
			'sessions.overview.session' => 'Session',
			'sessions.overview.target' => 'Target',
			'sessions.overview.device' => 'Device',
			'sessions.overview.entrypoint' => 'Entrypoint',
			'sessions.overview.flavor' => 'Flavor',
			'sessions.overview.appId' => 'App ID',
			'sessions.overview.vmService' => 'VM service',
			'sessions.ui.open' => 'Open this section to load the complete Flutter UI snapshot.',
			'sessions.ui.current' => 'Current UI',
			'sessions.ui.description' => 'Complete mounted targets, diagnostics, accessibility, and Element structure.',
			'sessions.ui.snapshotFile' => 'Snapshot file',
			'sessions.ui.treeFile' => 'Widget tree file',
			'sessions.ui.targets' => 'Targets',
			'sessions.ui.elements' => 'Elements',
			'sessions.ui.snapshotTruncated' => 'Snapshot truncated',
			'sessions.ui.treeTruncated' => 'Tree truncated',
			'sessions.ui.completeSnapshot' => 'Complete snapshot',
			'sessions.ui.snapshotUnavailable' => 'The complete UI snapshot could not be loaded.',
			'sessions.ui.copySnapshot' => 'Copy snapshot data',
			'sessions.ui.fullTree' => 'Full widget tree',
			'sessions.ui.treeUnavailable' => 'The full mounted Element tree could not be loaded.',
			'sessions.ui.copyTree' => 'Copy widget tree data',
			'sessions.ui.metadata' => 'Inspection metadata',
			'sessions.ui.metadataEmpty' => 'No inspection metadata is available.',
			'sessions.ui.copyMetadata' => 'Copy inspection metadata',
			'sessions.logs.open' => 'Open this section to follow startup and application logs live.',
			'sessions.logs.live' => 'Refreshes every 2 seconds',
			'sessions.logs.latestBelow' => 'Latest output below',
			'sessions.logs.expand' => 'Show log output',
			'sessions.logs.collapse' => 'Hide log output',
			'sessions.logs.copyLines' => 'Copy log lines',
			'sessions.logs.linesCopied' => 'Log lines copied',
			'sessions.logs.copyPath' => 'Copy log file path',
			'sessions.logs.pathCopied' => 'Log file path copied',
			'sessions.logs.startupTitle' => 'Startup and Flutter tool logs',
			'sessions.logs.startupNone' => 'No startup or Flutter tool log lines were captured.',
			'sessions.logs.startupRecent' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} recent startup log line', other: '${n} recent startup log lines', ),
			'sessions.logs.startupRunningEmpty' => 'Cockpit is waiting for Flutter tool output.',
			'sessions.logs.title' => 'Application logs',
			'sessions.logs.none' => 'No application log lines were captured.',
			'sessions.logs.recent' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} recent log line', other: '${n} recent log lines', ),
			'sessions.logs.olderHidden' => ', older lines hidden',
			'sessions.logs.runningEmpty' => 'The app is running without captured log output.',
			'sessions.activityEmpty' => 'Connection, route, runtime error, and network changes appear here as Cockpit observes them.',
			'sessions.activity.discovered' => 'Session discovered',
			'sessions.activity.discoveredDetail' => ({required Object platform, required Object device}) => '${platform} · ${device}',
			'sessions.activity.connected' => 'Session connected',
			'sessions.activity.changed' => 'Session changed',
			'sessions.activity.stateDetail' => ({required Object from, required Object to}) => '${from} → ${to}',
			'sessions.activity.appUnavailable' => 'App process unavailable',
			'sessions.activity.appReachable' => 'App process reachable',
			'sessions.activity.bridgeConnected' => 'Cockpit bridge connected',
			'sessions.activity.bridgeDisconnected' => 'Cockpit bridge disconnected',
			'sessions.activity.sessionDetail' => ({required Object session}) => 'Session ${session}',
			'sessions.activity.routeChanged' => 'Route changed',
			'sessions.activity.routeDetail' => ({required Object from, required Object to}) => '${from} → ${to}',
			'sessions.activity.unknownRoute' => 'unknown',
			'sessions.activity.runtimeError' => 'Runtime error captured',
			'sessions.activity.runtimeErrorDetail' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} error in the current snapshot', other: '${n} errors in the current snapshot', ),
			'sessions.activity.networkFailure' => 'Network failure captured',
			'sessions.activity.networkFailureDetail' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} failed request captured', other: '${n} failed requests captured', ),
			'sessions.timeline.newestFirst' => 'Newest first',
			'sessions.timeline.showing' => ({required Object visible, required Object total}) => '${visible} / ${total}',
			'sessions.timeline.all' => 'All',
			'sessions.timeline.lifecycle' => 'Lifecycle',
			'sessions.timeline.routes' => 'Routes',
			'sessions.timeline.runtime' => 'Runtime',
			'sessions.timeline.network' => 'Network',
			'sessions.timeline.noMatch' => 'No events match this filter.',
			'sessions.timeline.expand' => 'Show event details',
			'sessions.timeline.collapse' => 'Hide event details',
			'sessions.timeline.discarded' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} older event was discarded to keep memory stable.', other: '${n} older events were discarded to keep memory stable.', ),
			'sessions.timeline.severity.info' => 'Info',
			'sessions.timeline.severity.success' => 'Success',
			'sessions.timeline.severity.warning' => 'Warning',
			'sessions.timeline.severity.error' => 'Error',
			'sessions.diagnostics.open' => 'Open this section to load runtime errors and session logs.',
			'sessions.diagnostics.runtimeErrors' => 'Runtime errors',
			'sessions.diagnostics.noRuntimeErrors' => 'No runtime errors were captured.',
			'sessions.diagnostics.capturedErrors' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} captured runtime error.', other: '${n} captured runtime errors.', ),
			'sessions.diagnostics.sessionLogs' => 'Session logs',
			'sessions.diagnostics.noSessionLines' => 'No session lifecycle log lines were captured.',
			'sessions.diagnostics.recentSessionLines' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} recent lifecycle log line.', other: '${n} recent lifecycle log lines.', ),
			'sessions.diagnostics.sessionLogsUnavailable' => 'No session lifecycle logs are available.',
			'sessions.diagnostics.runtimeError' => 'Runtime error',
			'sessions.network.open' => 'Open this section to load the latest network requests.',
			'sessions.network.loadOlder' => ({required Object loaded, required Object total}) => 'Load older requests (${loaded} of ${total})',
			'sessions.network.selectRequest' => 'Select a request to inspect it.',
			'sessions.network.total' => 'Total',
			'sessions.network.loaded' => 'Loaded',
			'sessions.network.failures' => 'Failures',
			'sessions.network.inFlight' => 'In flight',
			'sessions.network.source' => 'Source',
			'sessions.network.exportTooltip' => 'Export request or response body',
			'sessions.network.safeResponse' => 'Export safe response',
			'sessions.network.safeRequest' => 'Export safe request',
			'sessions.network.safeBoth' => 'Export both safely',
			'sessions.network.rawBoth' => 'Export unmasked bodies…',
			'sessions.network.unknownRequestUri' => 'Unknown request URI',
			'sessions.network.metadataEmpty' => 'No request metadata is available.',
			'sessions.network.copyMetadata' => 'Copy request metadata',
			'sessions.network.unmaskedFiles' => 'Unmasked body files',
			'sessions.network.bodyFiles' => 'Body files',
			'sessions.network.bodyDescription' => 'Cockpit writes request and response bodies to separate verified files.',
			'sessions.network.copyPaths' => 'Copy body file paths',
			'sessions.network.confirmRawTitle' => 'Export unmasked network bodies?',
			'sessions.network.confirmRawDescription' => 'The exported files may contain credentials, cookies, personal data, or binary payloads. Cockpit will return file paths only.',
			'sessions.network.exportUnmasked' => 'Export unmasked',
			'sessions.network.empty' => 'No network requests were captured. Use the app, then refresh this section.',
			'sessions.network.unknownUri' => 'Unknown URI',
			'sessions.network.unknownSource' => 'Unknown',
			_ => null,
		};
	}
}
