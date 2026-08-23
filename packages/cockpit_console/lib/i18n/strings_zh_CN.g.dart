///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsZhCn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsZhCn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zhCn,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh-CN>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsZhCn _root = this; // ignore: unused_field

	@override
	TranslationsZhCn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsZhCn(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$app$zh_CN app = _Translations$app$zh_CN._(_root);
	@override late final _Translations$common$zh_CN common = _Translations$common$zh_CN._(_root);
	@override late final _Translations$language$zh_CN language = _Translations$language$zh_CN._(_root);
	@override late final _Translations$nav$zh_CN nav = _Translations$nav$zh_CN._(_root);
	@override late final _Translations$shell$zh_CN shell = _Translations$shell$zh_CN._(_root);
	@override late final _Translations$dashboard$zh_CN dashboard = _Translations$dashboard$zh_CN._(_root);
	@override late final _Translations$statusBar$zh_CN statusBar = _Translations$statusBar$zh_CN._(_root);
	@override late final _Translations$projects$zh_CN projects = _Translations$projects$zh_CN._(_root);
	@override late final _Translations$targets$zh_CN targets = _Translations$targets$zh_CN._(_root);
	@override late final _Translations$tests$zh_CN tests = _Translations$tests$zh_CN._(_root);
	@override late final _Translations$runs$zh_CN runs = _Translations$runs$zh_CN._(_root);
	@override late final _Translations$actions$zh_CN actions = _Translations$actions$zh_CN._(_root);
	@override late final _Translations$ai$zh_CN ai = _Translations$ai$zh_CN._(_root);
	@override late final _Translations$sessions$zh_CN sessions = _Translations$sessions$zh_CN._(_root);
}

// Path: app
class _Translations$app$zh_CN extends Translations$app$en {
	_Translations$app$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cockpit Console';
	@override String get connecting => '正在连接 Cockpit';
	@override String get checking => '正在检查守护进程状态和 Supervisor 能力。';
}

// Path: common
class _Translations$common$zh_CN extends Translations$common$en {
	_Translations$common$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get refresh => '刷新';
	@override String get retry => '重试';
	@override String get cancel => '取消';
	@override String get copy => '复制';
	@override String get close => '关闭';
	@override String get unknown => '未知';
	@override String get notSet => '未设置';
	@override String get previousPage => '上一页';
	@override String get nextPage => '下一页';
	@override String pageRange({required Object start, required Object end, required Object total}) => '第 ${start}–${end} 项，共 ${total} 项';
}

// Path: language
class _Translations$language$zh_CN extends Translations$language$en {
	_Translations$language$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '语言';
	@override String get system => '跟随系统';
	@override String get english => 'English';
	@override String get simplifiedChinese => '简体中文';
}

// Path: nav
class _Translations$nav$zh_CN extends Translations$nav$en {
	_Translations$nav$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get dashboard => '概览';
	@override String get projects => '项目';
	@override String get appsDevices => '应用与设备';
	@override String get liveSessions => '实时会话';
	@override String get tests => '测试';
	@override String get testRuns => '测试运行';
	@override String get actions => '操作';
	@override String get aiAssistant => 'AI 助手';
}

// Path: shell
class _Translations$shell$zh_CN extends Translations$shell$en {
	_Translations$shell$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get offline => '离线';
	@override String get connected => '已连接';
	@override String get degraded => '连接异常';
	@override String get toggleTheme => '切换主题';
	@override String get closeNavigation => '关闭导航';
	@override String get openNavigation => '打开导航';
	@override String get expandNavigation => '展开导航';
	@override String get collapseNavigation => '收起导航';
}

// Path: dashboard
class _Translations$dashboard$zh_CN extends Translations$dashboard$en {
	_Translations$dashboard$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '概览';
	@override String get subtitle => 'Supervisor 状态和系统概况';
	@override String get startDaemon => '启动守护进程';
	@override String get restartDaemon => '重启守护进程';
	@override String get systemOperational => '系统运行正常';
	@override String get daemonApiDisconnected => '守护进程运行中，API 未连接';
	@override String get daemonOffline => '守护进程离线';
	@override String get apiVersion => 'API 版本';
	@override String get engine => '引擎';
	@override String get started => '启动时间';
	@override String get operations => '操作';
	@override String daysAgo({required Object count}) => '${count} 天前';
	@override String hoursAgo({required Object count}) => '${count} 小时前';
	@override String minutesAgo({required Object count}) => '${count} 分钟前';
	@override String get justNow => '刚刚';
	@override String get serverInformation => '服务器信息';
	@override String get instanceId => '实例 ID';
	@override String get engineVersion => '引擎版本';
	@override String get startedAt => '启动于';
	@override String get connectingTitle => '正在连接 Supervisor';
	@override String get connectingDescription => '正在连接守护进程并读取可用能力。';
	@override String get disconnectedTitle => '无法连接 Supervisor';
	@override String get retryConnection => '重新连接';
}

// Path: statusBar
class _Translations$statusBar$zh_CN extends Translations$statusBar$en {
	_Translations$statusBar$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get daemonHealthy => '守护进程正常';
	@override String get daemonDegraded => '守护进程异常';
	@override String get daemonOffline => '守护进程离线';
	@override String apiVersion({required Object version}) => 'API v${version}';
}

// Path: projects
class _Translations$projects$zh_CN extends Translations$projects$en {
	_Translations$projects$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '项目';
	@override String get subtitle => '选择 Cockpit 可以使用的本地文件夹和项目';
	@override String get addProject => '添加项目';
	@override String get allowedFolders => '允许的文件夹';
	@override String get addFolder => '添加文件夹';
	@override String get hideRemovedHistory => '隐藏移除记录';
	@override String showRemovedHistory({required Object count}) => '显示移除记录（${count}）';
	@override String get removedFolders => '已移除文件夹';
	@override String get removedProjects => '已移除项目';
	@override String get noAllowedFolders => '尚未添加允许的文件夹';
	@override String get noAllowedFoldersDescription => '请先添加本地文件夹，再添加其中的项目。';
	@override String get removeFolderTooltip => '从 Cockpit 移除文件夹';
	@override String get removeFolderTitle => '移除允许的文件夹？';
	@override String removeFolderDescription({required Object path}) => 'Cockpit 将停止使用 ${path}，并移除其中已注册的项目。项目文件仍会保留在磁盘上。立即移除可能会中断正在运行的 Cockpit 会话。';
	@override String get folderRemoved => '已从 Cockpit 移除文件夹';
	@override String get folderRemoveFailed => '无法从 Cockpit 移除文件夹';
	@override String get finishWorkRemove => '完成当前工作后移除';
	@override String get removeNow => '立即移除';
	@override String get stateReady => '可用';
	@override String get stateRemoving => '正在移除';
	@override String get stateRemoved => '已移除';
	@override String get noProjects => '尚未添加项目';
	@override String get noProjectsDescription => '添加项目目录后即可连接应用并运行测试。';
	@override String removedProjectSemantics({required Object name}) => '已移除项目 ${name}';
	@override String selectProjectSemantics({required Object name}) => '选择项目 ${name}';
	@override String workspaceIdentity({required Object workspace, required Object root}) => '${workspace} · 根目录 ${root}';
	@override String get updateLocationTooltip => '更新项目位置';
	@override String get current => '当前';
	@override String get removeProjectTooltip => '从 Cockpit 移除项目';
	@override String get removeProjectTitle => '移除项目？';
	@override String removeProjectDescription({required Object path}) => 'Cockpit 将停止使用 ${path}。项目文件仍会保留在磁盘上。立即移除可能会中断正在运行的 Cockpit 会话。';
	@override String get projectRemoved => '已从 Cockpit 移除项目';
	@override String get projectRemoveFailed => '无法移除项目';
	@override String get absoluteFolderError => '请选择绝对文件夹路径。';
	@override String get addFolderFailed => '无法添加文件夹。';
	@override String get addFolderTitle => '添加允许的文件夹';
	@override String get addFolderDescription => 'Cockpit 只能使用你在此添加的文件夹内的项目，不会上传任何内容。';
	@override String get folderPath => '文件夹路径';
	@override String get folderPathHint => '/绝对路径/项目目录';
	@override String get optionalName => '名称（可选）';
	@override String get projectNameHint => '我的项目';
	@override String get allowedFolderRequired => '请先添加允许的文件夹。';
	@override String get absoluteProjectError => '请选择项目的绝对目录。';
	@override String get addProjectFailed => '无法添加项目。';
	@override String get allowedFolder => '允许的文件夹';
	@override String get projectDirectory => '项目目录';
	@override String get noAllowedFoldersAvailable => '没有可用的允许文件夹。';
	@override String get newAbsoluteProjectError => '请选择项目的新绝对目录。';
	@override String get updateLocationFailed => '无法更新项目位置。';
	@override String get updateLocationTitle => '更新项目位置';
	@override String get currentDirectory => '当前目录';
	@override String get newProjectDirectory => '新项目目录';
	@override String get updateLocation => '更新位置';
}

// Path: targets
class _Translations$targets$zh_CN extends Translations$targets$en {
	_Translations$targets$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '应用与设备';
	@override String get subtitle => '查找并连接此项目使用的应用和设备';
	@override String get selectProject => '选择项目';
	@override String get selectProjectDescription => '请先在“项目”页面选择一个项目，再查看其应用和设备。';
	@override String get chooseProject => '选择项目';
	@override String discoverFailed({required Object error}) => '无法查找应用和设备：${error}';
	@override String get find => '查找应用和设备';
	@override String get readyToUse => '可直接使用';
	@override String get noneAdded => '尚未添加应用或设备';
	@override String get noneAddedDescription => '查找可用的应用和设备，然后添加需要使用的目标。';
	@override String get availableToAdd => '可添加';
	@override String get noneFound => '未找到应用或设备';
	@override String get noneFoundDescription => '连接或启动设备后重新查找。';
	@override String get loadFailed => '无法加载应用和设备';
	@override String get running => '运行中';
	@override String get ready => '可用';
	@override String appSemantics({required Object name}) => '应用 ${name}';
	@override String get sessionUnavailable => '应用正在运行，但其 Cockpit 会话暂时不可用。';
	@override String get monitorSession => '监听实时会话';
	@override String get start => '启动应用或设备';
	@override String addNamed({required Object name}) => '添加 ${name}';
	@override late final _Translations$targets$kind$zh_CN kind = _Translations$targets$kind$zh_CN._(_root);
	@override late final _Translations$targets$mode$zh_CN mode = _Translations$targets$mode$zh_CN._(_root);
	@override late final _Translations$targets$environment$zh_CN environment = _Translations$targets$environment$zh_CN._(_root);
	@override String keyValueSyntaxError({required Object line}) => '每一项都必须使用 KEY=VALUE 格式：“${line}”。';
	@override String appIdRequired({required Object kind}) => '${kind}目标必须提供应用 ID。';
	@override String added({required Object name}) => '已添加 ${name}';
	@override String get addTitle => '添加应用或设备';
	@override String get device => '设备';
	@override String get platform => '平台';
	@override String get deviceId => '设备 ID';
	@override String get type => '类型';
	@override String get launchFile => '启动文件';
	@override String get optional => '可选';
	@override String get none => '无';
	@override String get appIdentifier => '应用标识符';
	@override String get required => '必填';
	@override String get flavor => 'Flavor';
	@override String get optionalIos => '可选（iOS）';
	@override String get environmentLabel => '环境';
	@override String get modeLabel => '模式';
	@override String get add => '添加';
	@override String get timeoutIntegerError => '启动超时必须是整数毫秒数。';
	@override String get timeoutRangeError => '启动超时必须在 1,000 至 1,800,000 毫秒之间。';
	@override String launched({required Object target}) => '已启动 ${target}';
	@override String launchTitle({required Object kind}) => '启动${kind}';
	@override String get target => '目标';
	@override String get systemControlNote => '此目标通过系统控制启动，不接受启动模式和 Flutter 配置。';
	@override String get launchTimeout => '启动超时（毫秒）';
	@override String get launchTimeoutDefault => '默认（600,000）';
	@override String get launchConfiguration => '启动配置';
	@override String get dartDefines => 'Dart 定义';
	@override String get keyValueLines => '每行一个 KEY=VALUE';
	@override String get dartDefineFiles => 'Dart 定义文件';
	@override String get fileLines => '每行一个 config/*.json';
	@override String get flutterArgs => 'Flutter 参数';
	@override String get flutterArgsLines => '每行一个参数，例如 --verbose';
	@override String get launch => '启动';
}

// Path: tests
class _Translations$tests$zh_CN extends Translations$tests$en {
	_Translations$tests$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '测试';
	@override String get subtitle => '使用 LON、JSON 或 YAML 创建并检查测试用例和套件文件';
	@override String get selectProject => '选择项目';
	@override String get selectProjectDescription => '请先在“项目”页面选择一个项目，再查看其测试文件。';
	@override String get chooseProject => '选择项目';
	@override String get loadFailed => '无法加载测试文件';
	@override String readFailed({required Object path, required Object error}) => '无法读取 ${path}：${error}';
	@override String get discardTitle => '放弃未保存的更改？';
	@override String get discardDescription => '编辑器中还有尚未保存的更改。';
	@override String get keepEditing => '继续编辑';
	@override String get discardChanges => '放弃更改';
	@override String get files => '测试文件';
	@override String get newTest => '新建测试';
	@override String get emptyTitle => '尚无测试文件';
	@override String get emptyDescription => '创建并保存测试，然后在运行前完成检查。';
	@override String get suite => '测试套件';
	@override String suiteCases({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '测试套件 · ${n} 个用例',
		other: '测试套件 · ${n} 个用例',
	);
	@override String get testCase => '测试用例';
	@override String get filePath => '测试文件路径';
	@override String get filePathHint => '相对于项目，例如 cockpit/e2e/case.yaml';
	@override String get saving => '正在保存';
	@override String get unsaved => '未保存';
	@override String get saved => '已保存';
	@override String get format => '格式';
	@override String get save => '保存测试';
	@override String get check => '检查测试';
	@override String get saveWorkspaceChanged => '保存开始前，所选项目已发生变化。';
	@override String get saveBusy => '已有测试正在保存。';
	@override String get saveEmpty => '测试内容不能为空。';
	@override String get saveRelativePath => '测试路径必须是相对于项目的路径。';
	@override String get saveExtensionLon => 'LON 测试必须使用 .lon 路径。';
	@override String get saveExtensionJson => 'JSON 测试必须使用 .json 路径。';
	@override String get saveExtensionYaml => 'YAML 测试必须使用 .yaml 或 .yml 路径。';
	@override String get saveDocumentChanged => '检查期间测试内容发生了变化，请重新保存。';
	@override String get saveFailed => '无法保存测试。';
	@override String indexed({required Object path}) => '已保存并索引 ${path}';
	@override String indexedCleanupWarning({required Object path, required Object error}) => '已保存并索引 ${path}，但无法删除先前的备份：${error}';
	@override String get validationNoDiagnostic => '测试无效，但服务未返回诊断信息。';
	@override String get valid => '文档有效';
	@override String get invalid => '检查失败';
	@override String errors({required Object count}) => '错误：${count}';
	@override String warnings({required Object count}) => '警告：${count}';
}

// Path: runs
class _Translations$runs$zh_CN extends Translations$runs$en {
	_Translations$runs$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '测试运行';
	@override String get subtitle => '运行测试用例或套件并跟踪结果';
	@override String get selectProject => '选择项目';
	@override String get selectProjectDescription => '请先在“项目”页面选择一个项目，再开始测试运行。';
	@override String get chooseProject => '选择项目';
	@override String get inputsObjectError => '运行输入必须是 LON、JSON 或 YAML 对象。';
	@override String get durationError => '请使用 30s、5m 或 1h 这样的时长。';
	@override String get timeoutUnitError => '不支持此超时单位。';
	@override String timeoutRangeError({required Object maximum}) => '超时时间必须在 1ms 至 ${maximum} 之间。';
	@override String get suite => '套件';
	@override String get caseLabel => '用例';
	@override String restoreFailed({required Object error}) => '无法恢复运行状态：${error}';
	@override String get selectedFileChanged => '所选测试文件已变更或被移除，请重新选择。';
	@override String refreshTestsFailed({required Object error}) => '无法刷新测试文件：${error}';
	@override String get cancellationRequested => '已请求取消';
	@override String cancelFailed({required Object error}) => '无法取消运行：${error}';
	@override String refreshFailed({required Object error}) => '无法刷新运行：${error}';
	@override String get retryRecent => '重试最近运行';
	@override String get refreshRecent => '刷新最近运行';
	@override String get saveArtifact => '保存产物';
	@override String artifactSaved({required Object path}) => '已将验证后的产物保存到 ${path}';
	@override String downloadFailed({required Object error}) => '下载失败：${error}';
	@override String observeFailed({required Object error}) => '无法监听运行：${error}';
	@override String get jsonEventError => '事件必须是 JSON 对象。';
	@override String get completed => '运行已完成';
	@override String streamEvent({required Object kind}) => '事件流 ${kind}';
	@override String malformedEvent({required Object error}) => '事件格式错误：${error}';
	@override String statusLoadFailed({required Object error}) => '无法加载运行状态：${error}';
	@override String get streamEnded => '事件流在终态前结束';
	@override String get loadingTests => '正在加载测试文件…';
	@override String get testsUnavailable => '测试文件暂时不可用。';
	@override String get createTestFirst => '请先创建测试文件，再开始运行。';
	@override String get selectFile => '选择测试文件后继续。';
	@override String get selectCase => '选择测试用例后继续。';
	@override String get ready => '可以在当前项目中运行。';
	@override String get startTitle => '开始测试运行';
	@override String get startDescription => '选择用例或套件。仅当测试文件的默认目标不是预期应用时，才覆盖应用或设备。';
	@override String get testFileStep => '1. 测试文件';
	@override String get chooseTestFile => '选择测试文件';
	@override String get testCaseStep => '2. 测试用例';
	@override String get chooseTestCase => '选择测试用例';
	@override String get suiteContentsStep => '2. 套件内容';
	@override String get allSuiteCases => '运行此套件中的所有用例';
	@override String get targetStep => '3. 应用或设备';
	@override String get useFileDefault => '使用测试文件默认目标';
	@override String get retryTests => '重试加载测试';
	@override String get openTests => '打开测试';
	@override String get indexLoadFailed => 'Cockpit 无法加载当前测试索引，请在项目 Worker 可用后重试。';
	@override String get indexRefreshFailed => 'Cockpit 无法刷新测试索引，现有选项仍可继续使用。';
	@override String get runSuite => '运行套件';
	@override String get runTest => '运行测试';
	@override String get options => '运行选项';
	@override String get inputsOptional => '输入（可选）';
	@override String get inputsHint => 'LON、JSON 或 YAML 对象';
	@override String get timeoutOptional => '超时（可选）';
	@override String get timeoutHint => '使用默认值，例如 30s 或 5m';
	@override String get recentUnavailable => '最近运行暂时不可用';
	@override String get loadingRun => '正在加载运行';
	@override String events({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '${n} 个事件',
		other: '${n} 个事件',
	);
	@override String get newRun => '新建运行';
	@override String get cancelRun => '取消运行';
	@override String get recentRuns => '最近运行';
	@override String get failureTitle => '此运行失败的原因';
	@override String filesEvidence({required Object count}) => '文件与证据（${count}）';
	@override String get saveFile => '保存文件';
	@override late final _Translations$runs$state$zh_CN state = _Translations$runs$state$zh_CN._(_root);
}

// Path: actions
class _Translations$actions$zh_CN extends Translations$actions$en {
	_Translations$actions$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '操作';
	@override String get subtitle => '查看并运行 Cockpit 当前提供的操作';
	@override String get select => '选择操作';
	@override String get selectDescription => '选择一个可用操作，查看输入要求，并使用 LON、JSON 或 YAML 对象运行。';
	@override String get selectProjectReason => '请选择项目后运行此项目级操作。';
	@override String get selectFolderReason => '请选择允许的文件夹后运行此文件夹级操作。';
	@override String get noFolderReason => '没有可用的允许文件夹。请先在“项目”中添加文件夹，再运行文件夹级操作。';
	@override String get filter => '筛选操作';
	@override String get global => '全局操作';
	@override String get project => '项目操作';
	@override String loadFailed({required Object error}) => '无法加载操作：${error}';
	@override String get none => '当前没有可用操作。';
	@override String noMatch({required Object query}) => '没有与“${query}”匹配的操作。';
	@override late final _Translations$actions$scopeBadge$zh_CN scopeBadge = _Translations$actions$scopeBadge$zh_CN._(_root);
	@override String get input => '输入';
	@override String get inputDescription => '使用 LON、JSON 或 YAML 对象。幂等键属于调用信封，不应放在此对象中。';
	@override String get scope => '作用域';
	@override String get mutation => '变更类型';
	@override String get idempotency => '幂等性';
	@override String get execution => '执行方式';
	@override String get timeout => '超时';
	@override String timeoutValue({required Object defaultValue, required Object maximum}) => '${defaultValue}（最大 ${maximum}）';
	@override String get effects => '影响';
	@override String get features => '所需能力';
	@override String get inputSchema => '输入 Schema';
	@override String get outputSchema => '输出 Schema';
	@override String get idempotencyKey => '幂等键';
	@override String get generatedWhenRun => '运行时生成';
	@override String get optional => '可选';
	@override String get generateKey => '生成新键';
	@override String get keyRequiredDescription => '此操作可能改变状态，因此必须提供。';
	@override String get keyOptionalDescription => '可选，留空时不会发送。';
	@override String get noRoots => '尚未注册活动项目根目录。';
	@override String get projectRoot => '项目根目录';
	@override String get selectRoot => '选择活动根目录';
	@override String get unavailable => '无法在此处运行该操作。';
	@override String get addFolder => '添加允许的文件夹';
	@override String get running => '正在运行…';
	@override String get run => '运行操作';
	@override String get mutationWarning => '此操作可能改变状态。';
	@override String get scopeRootDescription => '针对所选允许文件夹运行。';
	@override String get scopeProjectDescription => '针对所选项目运行。';
	@override String get scopeGlobalDescription => '在 Supervisor 作用域中运行，不需要选择项目。';
	@override String get failed => '操作未成功';
	@override String get result => '结果';
	@override String get submitted => '已提交';
	@override String submittedState({required Object state}) => '已提交 · ${state}';
	@override String get copied => '已复制';
	@override String get copy => '复制';
	@override late final _Translations$actions$scopeValue$zh_CN scopeValue = _Translations$actions$scopeValue$zh_CN._(_root);
	@override late final _Translations$actions$mutationValue$zh_CN mutationValue = _Translations$actions$mutationValue$zh_CN._(_root);
	@override late final _Translations$actions$idempotencyValue$zh_CN idempotencyValue = _Translations$actions$idempotencyValue$zh_CN._(_root);
	@override late final _Translations$actions$executionValue$zh_CN executionValue = _Translations$actions$executionValue$zh_CN._(_root);
}

// Path: ai
class _Translations$ai$zh_CN extends Translations$ai$en {
	_Translations$ai$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AI 助手';
	@override String get settings => 'Agent 设置';
	@override String get connectToStart => '连接 AI Agent 后开始使用';
	@override String get connecting => '正在连接…';
	@override String get connectingToAgent => '正在连接 Agent';
	@override String get startConversation => '开始对话';
	@override String get connectDescription => '连接兼容 ACP 的 Agent 后，即可在这里提问或执行开发任务。';
	@override String get connectAgent => '连接 Agent';
	@override String get connectChatHint => '连接 Agent 后开始对话';
	@override String get connectTitle => '连接 AI Agent';
	@override String get connectSubtitle => '选择 Agent 及其工作目录。';
	@override String get closeConnectionSetup => '关闭连接设置';
	@override String get closeSettings => '关闭设置';
	@override String get disconnected => 'Agent 已断开连接。';
	@override String get clearChat => '清空对话视图';
	@override String get disconnect => '断开 Agent';
	@override String get custom => '自定义';
	@override String get customDescription => '任意 ACP 可执行文件';
	@override String get agent => 'Agent';
	@override String get chooseAgent => '选择 AI Agent';
	@override String presetDescription({required Object name}) => '${name} ACP Agent';
	@override String get selectWorkingDirectory => '选择工作目录';
	@override String get startSession => '开始会话';
	@override String get executable => '可执行文件';
	@override String get arguments => '参数（每行一个）';
	@override String get argumentsDescription => '参数会直接传给可执行文件，不经过 Shell。';
	@override String get workingDirectory => '工作目录';
	@override String get workingDirectoryHint => '/项目的绝对路径';
	@override String get browseDirectories => '浏览目录';
	@override String get selectProjectBeforeEditing => '请先选择项目，再发送到编辑器。';
	@override String get latest => '最新消息';
	@override String get dismissError => '关闭错误';
	@override String get permissionRequired => '继续操作需要授权';
	@override String get input => '输入';
	@override String get location => '位置';
	@override String get locations => '位置';
	@override String get cancelRequest => '取消请求';
	@override String get signInTitle => '登录后继续';
	@override String get signInDescription => '在 Agent 设置中选择登录方式，然后完成登录流程。';
	@override String get openSignIn => '打开登录';
	@override String get sessionTitle => '创建或打开会话';
	@override String get sessionDescription => '使用 Agent 设置创建新会话或恢复最近工作。';
	@override String get openSessionSetup => '打开会话设置';
	@override String get conversationDescription => '询问工作区内容、请求代码修改或描述测试场景。';
	@override String get sendToEditor => '发送到编辑器';
	@override late final _Translations$ai$composer$zh_CN composer = _Translations$ai$composer$zh_CN._(_root);
	@override late final _Translations$ai$connection$zh_CN connection = _Translations$ai$connection$zh_CN._(_root);
	@override late final _Translations$ai$mcp$zh_CN mcp = _Translations$ai$mcp$zh_CN._(_root);
	@override late final _Translations$ai$session$zh_CN session = _Translations$ai$session$zh_CN._(_root);
	@override late final _Translations$ai$tool$zh_CN tool = _Translations$ai$tool$zh_CN._(_root);
}

// Path: sessions
class _Translations$sessions$zh_CN extends Translations$sessions$en {
	_Translations$sessions$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => '实时会话';
	@override String get subtitle => '查看正在运行的应用，不会修改或重启应用';
	@override String get findingTitle => '正在查找运行中的会话';
	@override String get findingDescription => 'Cockpit 正在检查所有活动项目中的运行应用。';
	@override String get emptyTitle => '暂无可监听会话';
	@override String get emptyDescription => '使用 Cockpit 启动应用后，会话会自动显示在这里，并在停止后保留记录。';
	@override String get checkAgain => '重新检查';
	@override String liveCount({required Object live, required Object total}) => '${live} 个运行中 · 共 ${total} 个';
	@override String liveCountSemantics({required Object live, required Object total}) => '${live} 个运行中的会话，共 ${total} 个会话';
	@override String get listTitle => '会话';
	@override String selectSemantics({required Object project, required Object platform, required Object session}) => '${project}，${platform}，会话 ${session}';
	@override String refreshFailed({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '${n} 个项目刷新失败。',
		other: '${n} 个项目刷新失败。',
	);
	@override String get refreshProjectFailed => '项目刷新失败。';
	@override String get stoppedMessage => '此会话已不再活动。';
	@override String get bridgeReconnectingMessage => '应用桥接正在重新连接。';
	@override String get selectPrompt => '选择一个会话以查看其实时状态。';
	@override String sessionId({required Object session}) => '会话 ${session}';
	@override String get contextApp => '应用';
	@override String get contextAppTip => '在“应用与设备”中打开此项目';
	@override String get contextActions => '操作';
	@override String get contextActionsTip => '打开此项目的操作';
	@override String get contextTests => '测试';
	@override String get contextTestsTip => '打开此项目的测试';
	@override String get contextRuns => '运行';
	@override String get contextRunsTip => '打开此项目的测试运行';
	@override String refreshSection({required Object section}) => '刷新${section}';
	@override late final _Translations$sessions$status$zh_CN status = _Translations$sessions$status$zh_CN._(_root);
	@override late final _Translations$sessions$sections$zh_CN sections = _Translations$sessions$sections$zh_CN._(_root);
	@override late final _Translations$sessions$data$zh_CN data = _Translations$sessions$data$zh_CN._(_root);
	@override late final _Translations$sessions$overview$zh_CN overview = _Translations$sessions$overview$zh_CN._(_root);
	@override late final _Translations$sessions$ui$zh_CN ui = _Translations$sessions$ui$zh_CN._(_root);
	@override late final _Translations$sessions$logs$zh_CN logs = _Translations$sessions$logs$zh_CN._(_root);
	@override String get activityEmpty => 'Cockpit 监听到的连接、路由、运行时错误和网络变化会显示在这里。';
	@override late final _Translations$sessions$activity$zh_CN activity = _Translations$sessions$activity$zh_CN._(_root);
	@override late final _Translations$sessions$timeline$zh_CN timeline = _Translations$sessions$timeline$zh_CN._(_root);
	@override late final _Translations$sessions$diagnostics$zh_CN diagnostics = _Translations$sessions$diagnostics$zh_CN._(_root);
	@override late final _Translations$sessions$network$zh_CN network = _Translations$sessions$network$zh_CN._(_root);
}

// Path: targets.kind
class _Translations$targets$kind$zh_CN extends Translations$targets$kind$en {
	_Translations$targets$kind$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get flutterApp => 'Flutter 应用';
	@override String get nativeApp => '原生应用';
	@override String get desktopApp => '桌面应用';
	@override String get browserPage => '浏览器页面';
	@override String get systemSurface => '系统界面';
	@override String get device => '设备';
	@override String get hostWorkspace => '主机工作区';
}

// Path: targets.mode
class _Translations$targets$mode$zh_CN extends Translations$targets$mode$en {
	_Translations$targets$mode$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get development => '开发';
	@override String get automation => '自动化';
}

// Path: targets.environment
class _Translations$targets$environment$zh_CN extends Translations$targets$environment$en {
	_Translations$targets$environment$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get development => '开发';
	@override String get test => '测试';
	@override String get staging => '预发布';
	@override String get production => '生产';
	@override String get unknown => '未知';
}

// Path: runs.state
class _Translations$runs$state$zh_CN extends Translations$runs$state$en {
	_Translations$runs$state$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get queued => '排队中';
	@override String get running => '运行中';
	@override String get finalizing => '正在收尾';
	@override String get completed => '已完成';
	@override String get passed => '通过';
	@override String get failed => '失败';
	@override String get blocked => '已阻塞';
	@override String get skipped => '已跳过';
	@override String get cancelled => '已取消';
	@override String get interrupted => '已中断';
	@override String get internalError => '内部错误';
}

// Path: actions.scopeBadge
class _Translations$actions$scopeBadge$zh_CN extends Translations$actions$scopeBadge$en {
	_Translations$actions$scopeBadge$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get global => '全局';
	@override String get workspace => '项目';
	@override String get root => '根目录';
}

// Path: actions.scopeValue
class _Translations$actions$scopeValue$zh_CN extends Translations$actions$scopeValue$en {
	_Translations$actions$scopeValue$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get supervisor => 'Supervisor（全局）';
	@override String get root => '根目录';
	@override String get workspace => '工作区';
}

// Path: actions.mutationValue
class _Translations$actions$mutationValue$zh_CN extends Translations$actions$mutationValue$en {
	_Translations$actions$mutationValue$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get readOnly => '只读';
	@override String get mutating => '会修改状态';
}

// Path: actions.idempotencyValue
class _Translations$actions$idempotencyValue$zh_CN extends Translations$actions$idempotencyValue$en {
	_Translations$actions$idempotencyValue$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get required => '必需';
	@override String get optional => '可选';
	@override String get prohibited => '禁止';
}

// Path: actions.executionValue
class _Translations$actions$executionValue$zh_CN extends Translations$actions$executionValue$en {
	_Translations$actions$executionValue$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get synchronous => '同步';
	@override String get job => '任务';
}

// Path: ai.composer
class _Translations$ai$composer$zh_CN extends Translations$ai$composer$en {
	_Translations$ai$composer$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get duplicateAttachment => '该附件已经添加。';
	@override String get messageHint => '输入消息…';
	@override String get sessionRequiredHint => '创建会话或登录后开始对话';
	@override String get stopResponse => '停止响应';
	@override String get sendMessage => '发送消息（Enter）';
	@override String get addMessage => '输入消息或添加附件';
	@override String inlineLimit({required Object size, required Object limit}) => '内联 ${size} · 上限 ${limit}';
	@override String get availableCommands => '可用命令';
	@override String get addContext => '添加上下文';
	@override String get attachImage => '附加图片';
	@override String get attachImageDescription => '以内联数据发送图片';
	@override String get attachAudio => '附加音频';
	@override String get attachAudioDescription => '以内联数据发送音频';
	@override String get embedContext => '嵌入上下文文件';
	@override String get embedContextDescription => '包含完整文件内容';
	@override String get linkFile => '链接本地文件';
	@override String get linkFileDescription => '引用文件但不复制内容';
	@override String get linkResource => '链接资源 URI';
	@override String get linkResourceDescription => '引用 Agent 可访问的任意资源';
	@override String removeAttachment({required Object name}) => '移除 ${name}';
	@override String get name => '名称';
	@override String get nameHint => 'API 规范';
	@override String get absoluteUri => '绝对 URI';
	@override String get mimeOptional => 'MIME 类型（可选）';
	@override String get descriptionOptional => '描述（可选）';
	@override String get resourceError => '请输入名称和带有 Scheme 的绝对 URI。';
	@override String get addResource => '添加资源';
	@override String get linked => '已链接';
	@override String get embedded => '已嵌入';
	@override String get pathUnavailable => '所选文件没有可用的本地路径。';
	@override String get notRegularFile => '所选路径不是普通文件。';
	@override String get resourceRequirements => '资源链接必须包含名称和绝对 URI。';
	@override String promptLimit({required Object size, required Object limit}) => '内联附件已使用 ${size}，提示上限为 ${limit}。';
	@override String unsupportedImage({required Object name}) => '“${name}”不是支持的图片文件。';
	@override String unsupportedAudio({required Object name}) => '“${name}”不是支持的音频文件。';
	@override String get emptyFile => '所选文件为空。';
	@override String fileTooLarge({required Object size, required Object limit}) => '所选文件大小为 ${size}，内联附件上限为 ${limit}。';
}

// Path: ai.connection
class _Translations$ai$connection$zh_CN extends Translations$ai$connection$en {
	_Translations$ai$connection$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get createSession => '创建会话';
	@override String get workingDirectory => '工作目录';
	@override String get selectSessionDirectory => '选择会话工作目录';
	@override String get sessionContext => '会话上下文';
	@override String get optionalContext => '可选目录和 MCP 服务器';
	@override String configuredItems({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '已配置 ${n} 项',
		other: '已配置 ${n} 项',
	);
	@override String get additionalDirectories => '附加目录';
	@override String get additionalDirectoriesDescription => '允许 Agent 访问工作目录之外的其他工作区根目录。';
	@override String get addDirectory => '添加目录';
	@override String get mcpServers => 'MCP 服务器';
	@override String get mcpServersDescription => '为此 Agent 连接附加工具和资源，这些值不会被存储。';
	@override String get addServer => '添加服务器';
	@override String get addSessionDirectory => '添加会话目录';
	@override String get duplicateDirectory => '该目录已经添加。';
	@override String get duplicateServer => 'MCP 服务器名称必须唯一。';
	@override String remove({required Object name}) => '移除 ${name}';
}

// Path: ai.mcp
class _Translations$ai$mcp$zh_CN extends Translations$ai$mcp$en {
	_Translations$ai$mcp$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get addTitle => '添加 MCP 服务器';
	@override String get editTitle => '编辑 MCP 服务器';
	@override String get transport => '传输方式';
	@override String get name => '名称';
	@override String get executablePath => '可执行文件绝对路径';
	@override String get serverUrl => '服务器 URL';
	@override String get arguments => '参数（每行一个）';
	@override String get environment => '环境变量（NAME=value）';
	@override String get headers => '请求头（Name: value）';
	@override String get valuesDescription => '这些值仅用于当前连接，Cockpit Console 不会存储。';
	@override String get addServer => '添加服务器';
	@override String get saveServer => '保存服务器';
	@override String get nameRequired => '请输入服务器名称。';
	@override String get executableRequired => '请输入可执行文件路径。';
	@override String get urlRequired => '请输入服务器 URL。';
	@override String get absoluteExecutable => 'stdio 可执行文件必须使用绝对路径。';
	@override String get absoluteUrl => '服务器 URL 必须是绝对 HTTP(S) URL。';
	@override String environmentSyntax({required Object line}) => '环境变量第 ${line} 行必须使用 NAME=value 格式。';
	@override String environmentName({required Object line}) => '环境变量第 ${line} 行的变量名无效。';
	@override String environmentDuplicate({required Object name}) => '环境变量“${name}”重复。';
	@override String headerSyntax({required Object line}) => '请求头第 ${line} 行必须使用 Name: value 格式。';
	@override String headerName({required Object line}) => '请求头第 ${line} 行的名称无效。';
	@override String headerDuplicate({required Object name}) => '请求头“${name}”重复。';
	@override String get stdioDescription => '所有 ACP Agent 均支持。';
	@override String get httpDescription => '需要 Agent 支持 HTTP MCP。';
	@override String get sseDescription => '需要 Agent 支持 SSE MCP。';
}

// Path: ai.session
class _Translations$ai$session$zh_CN extends Translations$ai$session$en {
	_Translations$ai$session$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get authentication => '身份验证';
	@override String get signIn => '登录';
	@override String get signOut => '退出登录';
	@override String get section => '会话';
	@override String get refreshRecent => '刷新最近会话';
	@override String get signInFirst => '请先登录，再创建会话。';
	@override String get noneOpen => '当前没有打开的会话，创建会话后即可开始对话。';
	@override String get newSession => '新建会话';
	@override String get close => '关闭会话';
	@override String get recent => '最近会话';
	@override String get loading => '正在加载会话…';
	@override String get noneSaved => '此 Agent 没有返回已保存的会话。';
	@override String get loadMore => '加载更多';
	@override String get activeSession => '当前会话';
	@override String additionalDirectories({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '${n} 个附加目录',
		other: '${n} 个附加目录',
	);
	@override String mcpServers({required Object names}) => 'MCP：${names}';
	@override String get active => '当前';
	@override String get actions => '会话操作';
	@override String get resume => '恢复';
	@override String get load => '加载';
	@override String get loadHistory => '从历史记录加载';
	@override String get delete => '删除会话';
	@override String get settings => 'Agent 设置';
	@override String get mode => '模式';
	@override String get noSettings => '此 Agent 没有提供会话设置。';
	@override String get currentContext => '当前上下文';
	@override String get usage => '用量';
	@override String tokensUsed({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '已使用 ${n} 个 Token',
		other: '已使用 ${n} 个 Token',
	);
	@override String tokenContext({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '上下文容量 ${n} 个 Token',
		other: '上下文容量 ${n} 个 Token',
	);
	@override String get plan => '计划';
	@override String get availableCommands => '可用命令';
	@override String get authNotRequired => '无需身份验证';
	@override String get authAvailable => '可以登录';
	@override String get authRequired => '必须登录';
	@override String get authWaiting => '正在等待登录完成…';
	@override String get authenticated => '已登录';
	@override String get signingOut => '正在退出登录…';
	@override String get capImages => '图片';
	@override String get capAudio => '音频';
	@override String get capContext => '上下文文件';
	@override String get capLoad => '加载会话';
	@override String get capResume => '恢复会话';
	@override String get capHistory => '历史记录';
	@override String get deleteTitle => '删除会话？';
	@override String deleteDescription({required Object name}) => '从 Agent 删除“${name}”。此操作无法撤销。';
	@override String get keep => '保留会话';
}

// Path: ai.tool
class _Translations$ai$tool$zh_CN extends Translations$ai$tool$en {
	_Translations$ai$tool$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get rawInput => '原始输入';
	@override String get rawOutput => '原始输出';
	@override String get terminal => '终端';
	@override String get audio => '音频';
	@override String invalidImage({required Object mime}) => 'Agent 返回了无效的 ${mime} 图片数据。';
	@override String get malformedImage => 'Agent 返回的 base64 图片数据格式错误。';
	@override String get textResource => '文本资源';
	@override String get binaryResource => '二进制资源';
	@override String get diff => '差异';
	@override String get before => '修改前';
	@override String get after => '修改后';
	@override String get location => '位置';
	@override late final _Translations$ai$tool$status$zh_CN status = _Translations$ai$tool$status$zh_CN._(_root);
}

// Path: sessions.status
class _Translations$sessions$status$zh_CN extends Translations$sessions$status$en {
	_Translations$sessions$status$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get reconnecting => '正在重连';
	@override String get live => '运行中';
	@override String get starting => '正在启动';
	@override String get reloading => '正在热重载';
	@override String get restarting => '正在重启';
	@override String get checking => '正在检查';
	@override String get failed => '失败';
	@override String get unavailable => '不可用';
	@override String get stopped => '已停止';
}

// Path: sessions.sections
class _Translations$sessions$sections$zh_CN extends Translations$sessions$sections$en {
	_Translations$sessions$sections$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get overview => '概览';
	@override String get ui => '界面';
	@override String get logs => '日志';
	@override String get network => '网络';
	@override String get activity => '活动';
	@override String get diagnostics => '诊断';
}

// Path: sessions.data
class _Translations$sessions$data$zh_CN extends Translations$sessions$data$en {
	_Translations$sessions$data$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get structured => '结构化数据';
	@override String get empty => '此会话暂时没有可用数据。';
	@override String get copy => '复制数据';
	@override String get copied => '数据已复制';
	@override String get notSet => '未设置';
	@override String copyLabel({required Object label}) => '复制${label}';
	@override String labelCopied({required Object label}) => '${label}已复制';
	@override String fields({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '${n} 个字段',
		other: '${n} 个字段',
	);
	@override String items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '${n} 项',
		other: '${n} 项',
	);
}

// Path: sessions.overview
class _Translations$sessions$overview$zh_CN extends Translations$sessions$overview$en {
	_Translations$sessions$overview$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get appProcess => '应用进程';
	@override String get reachable => '可访问';
	@override String get unavailable => '不可用';
	@override String get checking => '正在检查';
	@override String get bridge => 'Cockpit 桥接';
	@override String get connected => '已连接';
	@override String get disconnected => '未连接';
	@override String get runtimeErrors => '运行时错误';
	@override String get networkFailures => '网络失败';
	@override String get currentState => '当前状态';
	@override String get currentStateDescription => 'Cockpit 当前监听到的应用和桥接身份。';
	@override String get route => '路由';
	@override String get lifecycle => '生命周期';
	@override String get reloadGeneration => '热重载代次';
	@override String get lastRuntimeStatus => '最近运行状态';
	@override String get nextStep => '下一步';
	@override String get lastError => '最近错误';
	@override String get noActionNeeded => '无需操作';
	@override String get launchIdentity => '启动身份';
	@override String get launchIdentityDescription => '使用这些信息确认应用是否运行在预期项目中。';
	@override String get project => '项目';
	@override String get workspace => '工作区';
	@override String get session => '会话';
	@override String get target => '目标';
	@override String get device => '设备';
	@override String get entrypoint => '入口文件';
	@override String get flavor => '构建环境';
	@override String get appId => '应用 ID';
	@override String get vmService => 'VM 服务';
}

// Path: sessions.ui
class _Translations$sessions$ui$zh_CN extends Translations$sessions$ui$en {
	_Translations$sessions$ui$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get open => '打开此分区以加载完整的 Flutter 界面快照。';
	@override String get current => '当前界面';
	@override String get description => '完整展示已挂载目标、诊断、无障碍信息和 Element 结构。';
	@override String get snapshotFile => '快照文件';
	@override String get treeFile => 'Widget 树文件';
	@override String get targets => '目标';
	@override String get elements => 'Element 数量';
	@override String get snapshotTruncated => '快照已截断';
	@override String get treeTruncated => '树已截断';
	@override String get completeSnapshot => '完整快照';
	@override String get snapshotUnavailable => '无法加载完整界面快照。';
	@override String get copySnapshot => '复制快照数据';
	@override String get fullTree => '完整 Widget 树';
	@override String get treeUnavailable => '无法加载完整的已挂载 Element 树。';
	@override String get copyTree => '复制 Widget 树数据';
	@override String get metadata => '检查元数据';
	@override String get metadataEmpty => '暂无检查元数据。';
	@override String get copyMetadata => '复制检查元数据';
}

// Path: sessions.logs
class _Translations$sessions$logs$zh_CN extends Translations$sessions$logs$en {
	_Translations$sessions$logs$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get open => '打开此分区以实时查看启动日志和应用日志。';
	@override String get live => '每 2 秒自动刷新';
	@override String get latestBelow => '最新输出在底部';
	@override String get startupTitle => '启动与 Flutter 工具日志';
	@override String get startupNone => '暂无启动或 Flutter 工具日志。';
	@override String startupRecent({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '最近 ${n} 行启动日志',
		other: '最近 ${n} 行启动日志',
	);
	@override String get startupRunningEmpty => 'Cockpit 正在等待 Flutter 工具输出。';
	@override String get title => '应用日志';
	@override String get none => '未捕获到应用日志。';
	@override String recent({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '最近 ${n} 行日志',
		other: '最近 ${n} 行日志',
	);
	@override String get olderHidden => '，更早日志已隐藏';
	@override String get runningEmpty => '应用正在运行，但尚未捕获到日志输出。';
}

// Path: sessions.activity
class _Translations$sessions$activity$zh_CN extends Translations$sessions$activity$en {
	_Translations$sessions$activity$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get discovered => '发现会话';
	@override String discoveredDetail({required Object platform, required Object device}) => '${platform} · ${device}';
	@override String get connected => '会话已连接';
	@override String get changed => '会话状态变化';
	@override String stateDetail({required Object from, required Object to}) => '${from} → ${to}';
	@override String get appUnavailable => '应用进程不可用';
	@override String get appReachable => '应用进程可访问';
	@override String get bridgeConnected => 'Cockpit 桥接已连接';
	@override String get bridgeDisconnected => 'Cockpit 桥接已断开';
	@override String sessionDetail({required Object session}) => '会话 ${session}';
	@override String get routeChanged => '路由变化';
	@override String routeDetail({required Object from, required Object to}) => '${from} → ${to}';
	@override String get unknownRoute => '未知';
	@override String get runtimeError => '捕获到运行时错误';
	@override String runtimeErrorDetail({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '当前快照中有 ${n} 个错误',
		other: '当前快照中有 ${n} 个错误',
	);
	@override String get networkFailure => '捕获到网络失败';
	@override String networkFailureDetail({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '已捕获 ${n} 个失败请求',
		other: '已捕获 ${n} 个失败请求',
	);
}

// Path: sessions.timeline
class _Translations$sessions$timeline$zh_CN extends Translations$sessions$timeline$en {
	_Translations$sessions$timeline$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get newestFirst => '最新在前';
	@override String showing({required Object visible, required Object total}) => '${visible} / ${total}';
	@override String get all => '全部';
	@override String get lifecycle => '生命周期';
	@override String get routes => '路由';
	@override String get runtime => '运行时';
	@override String get network => '网络';
	@override String get noMatch => '没有符合当前筛选条件的事件。';
	@override String get expand => '展开事件详情';
	@override String get collapse => '收起事件详情';
	@override String discarded({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '为保持内存稳定，已丢弃较早的 ${n} 个事件。',
		other: '为保持内存稳定，已丢弃较早的 ${n} 个事件。',
	);
	@override late final _Translations$sessions$timeline$severity$zh_CN severity = _Translations$sessions$timeline$severity$zh_CN._(_root);
}

// Path: sessions.diagnostics
class _Translations$sessions$diagnostics$zh_CN extends Translations$sessions$diagnostics$en {
	_Translations$sessions$diagnostics$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get open => '打开此分区以加载运行时错误和会话日志。';
	@override String get runtimeErrors => '运行时错误';
	@override String get noRuntimeErrors => '未捕获到运行时错误。';
	@override String capturedErrors({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '已捕获 ${n} 个运行时错误。',
		other: '已捕获 ${n} 个运行时错误。',
	);
	@override String get sessionLogs => '会话日志';
	@override String get noSessionLines => '未捕获到会话生命周期日志。';
	@override String recentSessionLines({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '最近 ${n} 行生命周期日志。',
		other: '最近 ${n} 行生命周期日志。',
	);
	@override String get sessionLogsUnavailable => '暂无会话生命周期日志。';
	@override String get runtimeError => '运行时错误';
}

// Path: sessions.network
class _Translations$sessions$network$zh_CN extends Translations$sessions$network$en {
	_Translations$sessions$network$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get open => '打开此分区以加载最新网络请求。';
	@override String loadOlder({required Object loaded, required Object total}) => '加载更早请求（已加载 ${loaded} / ${total}）';
	@override String get selectRequest => '选择一个请求以查看详情。';
	@override String get total => '总数';
	@override String get loaded => '已加载';
	@override String get failures => '失败';
	@override String get inFlight => '进行中';
	@override String get source => '来源';
	@override String get exportTooltip => '导出请求或响应正文';
	@override String get safeResponse => '安全导出响应';
	@override String get safeRequest => '安全导出请求';
	@override String get safeBoth => '安全导出请求和响应';
	@override String get rawBoth => '导出未脱敏正文…';
	@override String get unknownRequestUri => '未知请求地址';
	@override String get metadataEmpty => '暂无请求元数据。';
	@override String get copyMetadata => '复制请求元数据';
	@override String get unmaskedFiles => '未脱敏正文文件';
	@override String get bodyFiles => '正文文件';
	@override String get bodyDescription => 'Cockpit 会将请求和响应正文分别写入已验证文件。';
	@override String get copyPaths => '复制正文文件路径';
	@override String get confirmRawTitle => '导出未脱敏网络正文？';
	@override String get confirmRawDescription => '导出的文件可能包含凭据、Cookie、个人数据或二进制内容。Cockpit 只会返回文件路径。';
	@override String get exportUnmasked => '导出未脱敏内容';
	@override String get empty => '尚未捕获到网络请求。操作应用后刷新此分区。';
	@override String get unknownUri => '未知地址';
	@override String get unknownSource => '未知';
}

// Path: ai.tool.status
class _Translations$ai$tool$status$zh_CN extends Translations$ai$tool$status$en {
	_Translations$ai$tool$status$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get completed => '已完成';
	@override String get failed => '失败';
	@override String get inProgress => '进行中';
}

// Path: sessions.timeline.severity
class _Translations$sessions$timeline$severity$zh_CN extends Translations$sessions$timeline$severity$en {
	_Translations$sessions$timeline$severity$zh_CN._(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get info => '信息';
	@override String get success => '成功';
	@override String get warning => '警告';
	@override String get error => '错误';
}

/// The flat map containing all translations for locale <zh-CN>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsZhCn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'app.title' => 'Cockpit Console',
			'app.connecting' => '正在连接 Cockpit',
			'app.checking' => '正在检查守护进程状态和 Supervisor 能力。',
			'common.refresh' => '刷新',
			'common.retry' => '重试',
			'common.cancel' => '取消',
			'common.copy' => '复制',
			'common.close' => '关闭',
			'common.unknown' => '未知',
			'common.notSet' => '未设置',
			'common.previousPage' => '上一页',
			'common.nextPage' => '下一页',
			'common.pageRange' => ({required Object start, required Object end, required Object total}) => '第 ${start}–${end} 项，共 ${total} 项',
			'language.title' => '语言',
			'language.system' => '跟随系统',
			'language.english' => 'English',
			'language.simplifiedChinese' => '简体中文',
			'nav.dashboard' => '概览',
			'nav.projects' => '项目',
			'nav.appsDevices' => '应用与设备',
			'nav.liveSessions' => '实时会话',
			'nav.tests' => '测试',
			'nav.testRuns' => '测试运行',
			'nav.actions' => '操作',
			'nav.aiAssistant' => 'AI 助手',
			'shell.offline' => '离线',
			'shell.connected' => '已连接',
			'shell.degraded' => '连接异常',
			'shell.toggleTheme' => '切换主题',
			'shell.closeNavigation' => '关闭导航',
			'shell.openNavigation' => '打开导航',
			'shell.expandNavigation' => '展开导航',
			'shell.collapseNavigation' => '收起导航',
			'dashboard.title' => '概览',
			'dashboard.subtitle' => 'Supervisor 状态和系统概况',
			'dashboard.startDaemon' => '启动守护进程',
			'dashboard.restartDaemon' => '重启守护进程',
			'dashboard.systemOperational' => '系统运行正常',
			'dashboard.daemonApiDisconnected' => '守护进程运行中，API 未连接',
			'dashboard.daemonOffline' => '守护进程离线',
			'dashboard.apiVersion' => 'API 版本',
			'dashboard.engine' => '引擎',
			'dashboard.started' => '启动时间',
			'dashboard.operations' => '操作',
			'dashboard.daysAgo' => ({required Object count}) => '${count} 天前',
			'dashboard.hoursAgo' => ({required Object count}) => '${count} 小时前',
			'dashboard.minutesAgo' => ({required Object count}) => '${count} 分钟前',
			'dashboard.justNow' => '刚刚',
			'dashboard.serverInformation' => '服务器信息',
			'dashboard.instanceId' => '实例 ID',
			'dashboard.engineVersion' => '引擎版本',
			'dashboard.startedAt' => '启动于',
			'dashboard.connectingTitle' => '正在连接 Supervisor',
			'dashboard.connectingDescription' => '正在连接守护进程并读取可用能力。',
			'dashboard.disconnectedTitle' => '无法连接 Supervisor',
			'dashboard.retryConnection' => '重新连接',
			'statusBar.daemonHealthy' => '守护进程正常',
			'statusBar.daemonDegraded' => '守护进程异常',
			'statusBar.daemonOffline' => '守护进程离线',
			'statusBar.apiVersion' => ({required Object version}) => 'API v${version}',
			'projects.title' => '项目',
			'projects.subtitle' => '选择 Cockpit 可以使用的本地文件夹和项目',
			'projects.addProject' => '添加项目',
			'projects.allowedFolders' => '允许的文件夹',
			'projects.addFolder' => '添加文件夹',
			'projects.hideRemovedHistory' => '隐藏移除记录',
			'projects.showRemovedHistory' => ({required Object count}) => '显示移除记录（${count}）',
			'projects.removedFolders' => '已移除文件夹',
			'projects.removedProjects' => '已移除项目',
			'projects.noAllowedFolders' => '尚未添加允许的文件夹',
			'projects.noAllowedFoldersDescription' => '请先添加本地文件夹，再添加其中的项目。',
			'projects.removeFolderTooltip' => '从 Cockpit 移除文件夹',
			'projects.removeFolderTitle' => '移除允许的文件夹？',
			'projects.removeFolderDescription' => ({required Object path}) => 'Cockpit 将停止使用 ${path}，并移除其中已注册的项目。项目文件仍会保留在磁盘上。立即移除可能会中断正在运行的 Cockpit 会话。',
			'projects.folderRemoved' => '已从 Cockpit 移除文件夹',
			'projects.folderRemoveFailed' => '无法从 Cockpit 移除文件夹',
			'projects.finishWorkRemove' => '完成当前工作后移除',
			'projects.removeNow' => '立即移除',
			'projects.stateReady' => '可用',
			'projects.stateRemoving' => '正在移除',
			'projects.stateRemoved' => '已移除',
			'projects.noProjects' => '尚未添加项目',
			'projects.noProjectsDescription' => '添加项目目录后即可连接应用并运行测试。',
			'projects.removedProjectSemantics' => ({required Object name}) => '已移除项目 ${name}',
			'projects.selectProjectSemantics' => ({required Object name}) => '选择项目 ${name}',
			'projects.workspaceIdentity' => ({required Object workspace, required Object root}) => '${workspace} · 根目录 ${root}',
			'projects.updateLocationTooltip' => '更新项目位置',
			'projects.current' => '当前',
			'projects.removeProjectTooltip' => '从 Cockpit 移除项目',
			'projects.removeProjectTitle' => '移除项目？',
			'projects.removeProjectDescription' => ({required Object path}) => 'Cockpit 将停止使用 ${path}。项目文件仍会保留在磁盘上。立即移除可能会中断正在运行的 Cockpit 会话。',
			'projects.projectRemoved' => '已从 Cockpit 移除项目',
			'projects.projectRemoveFailed' => '无法移除项目',
			'projects.absoluteFolderError' => '请选择绝对文件夹路径。',
			'projects.addFolderFailed' => '无法添加文件夹。',
			'projects.addFolderTitle' => '添加允许的文件夹',
			'projects.addFolderDescription' => 'Cockpit 只能使用你在此添加的文件夹内的项目，不会上传任何内容。',
			'projects.folderPath' => '文件夹路径',
			'projects.folderPathHint' => '/绝对路径/项目目录',
			'projects.optionalName' => '名称（可选）',
			'projects.projectNameHint' => '我的项目',
			'projects.allowedFolderRequired' => '请先添加允许的文件夹。',
			'projects.absoluteProjectError' => '请选择项目的绝对目录。',
			'projects.addProjectFailed' => '无法添加项目。',
			'projects.allowedFolder' => '允许的文件夹',
			'projects.projectDirectory' => '项目目录',
			'projects.noAllowedFoldersAvailable' => '没有可用的允许文件夹。',
			'projects.newAbsoluteProjectError' => '请选择项目的新绝对目录。',
			'projects.updateLocationFailed' => '无法更新项目位置。',
			'projects.updateLocationTitle' => '更新项目位置',
			'projects.currentDirectory' => '当前目录',
			'projects.newProjectDirectory' => '新项目目录',
			'projects.updateLocation' => '更新位置',
			'targets.title' => '应用与设备',
			'targets.subtitle' => '查找并连接此项目使用的应用和设备',
			'targets.selectProject' => '选择项目',
			'targets.selectProjectDescription' => '请先在“项目”页面选择一个项目，再查看其应用和设备。',
			'targets.chooseProject' => '选择项目',
			'targets.discoverFailed' => ({required Object error}) => '无法查找应用和设备：${error}',
			'targets.find' => '查找应用和设备',
			'targets.readyToUse' => '可直接使用',
			'targets.noneAdded' => '尚未添加应用或设备',
			'targets.noneAddedDescription' => '查找可用的应用和设备，然后添加需要使用的目标。',
			'targets.availableToAdd' => '可添加',
			'targets.noneFound' => '未找到应用或设备',
			'targets.noneFoundDescription' => '连接或启动设备后重新查找。',
			'targets.loadFailed' => '无法加载应用和设备',
			'targets.running' => '运行中',
			'targets.ready' => '可用',
			'targets.appSemantics' => ({required Object name}) => '应用 ${name}',
			'targets.sessionUnavailable' => '应用正在运行，但其 Cockpit 会话暂时不可用。',
			'targets.monitorSession' => '监听实时会话',
			'targets.start' => '启动应用或设备',
			'targets.addNamed' => ({required Object name}) => '添加 ${name}',
			'targets.kind.flutterApp' => 'Flutter 应用',
			'targets.kind.nativeApp' => '原生应用',
			'targets.kind.desktopApp' => '桌面应用',
			'targets.kind.browserPage' => '浏览器页面',
			'targets.kind.systemSurface' => '系统界面',
			'targets.kind.device' => '设备',
			'targets.kind.hostWorkspace' => '主机工作区',
			'targets.mode.development' => '开发',
			'targets.mode.automation' => '自动化',
			'targets.environment.development' => '开发',
			'targets.environment.test' => '测试',
			'targets.environment.staging' => '预发布',
			'targets.environment.production' => '生产',
			'targets.environment.unknown' => '未知',
			'targets.keyValueSyntaxError' => ({required Object line}) => '每一项都必须使用 KEY=VALUE 格式：“${line}”。',
			'targets.appIdRequired' => ({required Object kind}) => '${kind}目标必须提供应用 ID。',
			'targets.added' => ({required Object name}) => '已添加 ${name}',
			'targets.addTitle' => '添加应用或设备',
			'targets.device' => '设备',
			'targets.platform' => '平台',
			'targets.deviceId' => '设备 ID',
			'targets.type' => '类型',
			'targets.launchFile' => '启动文件',
			'targets.optional' => '可选',
			'targets.none' => '无',
			'targets.appIdentifier' => '应用标识符',
			'targets.required' => '必填',
			'targets.flavor' => 'Flavor',
			'targets.optionalIos' => '可选（iOS）',
			'targets.environmentLabel' => '环境',
			'targets.modeLabel' => '模式',
			'targets.add' => '添加',
			'targets.timeoutIntegerError' => '启动超时必须是整数毫秒数。',
			'targets.timeoutRangeError' => '启动超时必须在 1,000 至 1,800,000 毫秒之间。',
			'targets.launched' => ({required Object target}) => '已启动 ${target}',
			'targets.launchTitle' => ({required Object kind}) => '启动${kind}',
			'targets.target' => '目标',
			'targets.systemControlNote' => '此目标通过系统控制启动，不接受启动模式和 Flutter 配置。',
			'targets.launchTimeout' => '启动超时（毫秒）',
			'targets.launchTimeoutDefault' => '默认（600,000）',
			'targets.launchConfiguration' => '启动配置',
			'targets.dartDefines' => 'Dart 定义',
			'targets.keyValueLines' => '每行一个 KEY=VALUE',
			'targets.dartDefineFiles' => 'Dart 定义文件',
			'targets.fileLines' => '每行一个 config/*.json',
			'targets.flutterArgs' => 'Flutter 参数',
			'targets.flutterArgsLines' => '每行一个参数，例如 --verbose',
			'targets.launch' => '启动',
			'tests.title' => '测试',
			'tests.subtitle' => '使用 LON、JSON 或 YAML 创建并检查测试用例和套件文件',
			'tests.selectProject' => '选择项目',
			'tests.selectProjectDescription' => '请先在“项目”页面选择一个项目，再查看其测试文件。',
			'tests.chooseProject' => '选择项目',
			'tests.loadFailed' => '无法加载测试文件',
			'tests.readFailed' => ({required Object path, required Object error}) => '无法读取 ${path}：${error}',
			'tests.discardTitle' => '放弃未保存的更改？',
			'tests.discardDescription' => '编辑器中还有尚未保存的更改。',
			'tests.keepEditing' => '继续编辑',
			'tests.discardChanges' => '放弃更改',
			'tests.files' => '测试文件',
			'tests.newTest' => '新建测试',
			'tests.emptyTitle' => '尚无测试文件',
			'tests.emptyDescription' => '创建并保存测试，然后在运行前完成检查。',
			'tests.suite' => '测试套件',
			'tests.suiteCases' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '测试套件 · ${n} 个用例', other: '测试套件 · ${n} 个用例', ),
			'tests.testCase' => '测试用例',
			'tests.filePath' => '测试文件路径',
			'tests.filePathHint' => '相对于项目，例如 cockpit/e2e/case.yaml',
			'tests.saving' => '正在保存',
			'tests.unsaved' => '未保存',
			'tests.saved' => '已保存',
			'tests.format' => '格式',
			'tests.save' => '保存测试',
			'tests.check' => '检查测试',
			'tests.saveWorkspaceChanged' => '保存开始前，所选项目已发生变化。',
			'tests.saveBusy' => '已有测试正在保存。',
			'tests.saveEmpty' => '测试内容不能为空。',
			'tests.saveRelativePath' => '测试路径必须是相对于项目的路径。',
			'tests.saveExtensionLon' => 'LON 测试必须使用 .lon 路径。',
			'tests.saveExtensionJson' => 'JSON 测试必须使用 .json 路径。',
			'tests.saveExtensionYaml' => 'YAML 测试必须使用 .yaml 或 .yml 路径。',
			'tests.saveDocumentChanged' => '检查期间测试内容发生了变化，请重新保存。',
			'tests.saveFailed' => '无法保存测试。',
			'tests.indexed' => ({required Object path}) => '已保存并索引 ${path}',
			'tests.indexedCleanupWarning' => ({required Object path, required Object error}) => '已保存并索引 ${path}，但无法删除先前的备份：${error}',
			'tests.validationNoDiagnostic' => '测试无效，但服务未返回诊断信息。',
			'tests.valid' => '文档有效',
			'tests.invalid' => '检查失败',
			'tests.errors' => ({required Object count}) => '错误：${count}',
			'tests.warnings' => ({required Object count}) => '警告：${count}',
			'runs.title' => '测试运行',
			'runs.subtitle' => '运行测试用例或套件并跟踪结果',
			'runs.selectProject' => '选择项目',
			'runs.selectProjectDescription' => '请先在“项目”页面选择一个项目，再开始测试运行。',
			'runs.chooseProject' => '选择项目',
			'runs.inputsObjectError' => '运行输入必须是 LON、JSON 或 YAML 对象。',
			'runs.durationError' => '请使用 30s、5m 或 1h 这样的时长。',
			'runs.timeoutUnitError' => '不支持此超时单位。',
			'runs.timeoutRangeError' => ({required Object maximum}) => '超时时间必须在 1ms 至 ${maximum} 之间。',
			'runs.suite' => '套件',
			'runs.caseLabel' => '用例',
			'runs.restoreFailed' => ({required Object error}) => '无法恢复运行状态：${error}',
			'runs.selectedFileChanged' => '所选测试文件已变更或被移除，请重新选择。',
			'runs.refreshTestsFailed' => ({required Object error}) => '无法刷新测试文件：${error}',
			'runs.cancellationRequested' => '已请求取消',
			'runs.cancelFailed' => ({required Object error}) => '无法取消运行：${error}',
			'runs.refreshFailed' => ({required Object error}) => '无法刷新运行：${error}',
			'runs.retryRecent' => '重试最近运行',
			'runs.refreshRecent' => '刷新最近运行',
			'runs.saveArtifact' => '保存产物',
			'runs.artifactSaved' => ({required Object path}) => '已将验证后的产物保存到 ${path}',
			'runs.downloadFailed' => ({required Object error}) => '下载失败：${error}',
			'runs.observeFailed' => ({required Object error}) => '无法监听运行：${error}',
			'runs.jsonEventError' => '事件必须是 JSON 对象。',
			'runs.completed' => '运行已完成',
			'runs.streamEvent' => ({required Object kind}) => '事件流 ${kind}',
			'runs.malformedEvent' => ({required Object error}) => '事件格式错误：${error}',
			'runs.statusLoadFailed' => ({required Object error}) => '无法加载运行状态：${error}',
			'runs.streamEnded' => '事件流在终态前结束',
			'runs.loadingTests' => '正在加载测试文件…',
			'runs.testsUnavailable' => '测试文件暂时不可用。',
			'runs.createTestFirst' => '请先创建测试文件，再开始运行。',
			'runs.selectFile' => '选择测试文件后继续。',
			'runs.selectCase' => '选择测试用例后继续。',
			'runs.ready' => '可以在当前项目中运行。',
			'runs.startTitle' => '开始测试运行',
			'runs.startDescription' => '选择用例或套件。仅当测试文件的默认目标不是预期应用时，才覆盖应用或设备。',
			'runs.testFileStep' => '1. 测试文件',
			'runs.chooseTestFile' => '选择测试文件',
			'runs.testCaseStep' => '2. 测试用例',
			'runs.chooseTestCase' => '选择测试用例',
			'runs.suiteContentsStep' => '2. 套件内容',
			'runs.allSuiteCases' => '运行此套件中的所有用例',
			'runs.targetStep' => '3. 应用或设备',
			'runs.useFileDefault' => '使用测试文件默认目标',
			'runs.retryTests' => '重试加载测试',
			'runs.openTests' => '打开测试',
			'runs.indexLoadFailed' => 'Cockpit 无法加载当前测试索引，请在项目 Worker 可用后重试。',
			'runs.indexRefreshFailed' => 'Cockpit 无法刷新测试索引，现有选项仍可继续使用。',
			'runs.runSuite' => '运行套件',
			'runs.runTest' => '运行测试',
			'runs.options' => '运行选项',
			'runs.inputsOptional' => '输入（可选）',
			'runs.inputsHint' => 'LON、JSON 或 YAML 对象',
			'runs.timeoutOptional' => '超时（可选）',
			'runs.timeoutHint' => '使用默认值，例如 30s 或 5m',
			'runs.recentUnavailable' => '最近运行暂时不可用',
			'runs.loadingRun' => '正在加载运行',
			'runs.events' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '${n} 个事件', other: '${n} 个事件', ),
			'runs.newRun' => '新建运行',
			'runs.cancelRun' => '取消运行',
			'runs.recentRuns' => '最近运行',
			'runs.failureTitle' => '此运行失败的原因',
			'runs.filesEvidence' => ({required Object count}) => '文件与证据（${count}）',
			'runs.saveFile' => '保存文件',
			'runs.state.queued' => '排队中',
			'runs.state.running' => '运行中',
			'runs.state.finalizing' => '正在收尾',
			'runs.state.completed' => '已完成',
			'runs.state.passed' => '通过',
			'runs.state.failed' => '失败',
			'runs.state.blocked' => '已阻塞',
			'runs.state.skipped' => '已跳过',
			'runs.state.cancelled' => '已取消',
			'runs.state.interrupted' => '已中断',
			'runs.state.internalError' => '内部错误',
			'actions.title' => '操作',
			'actions.subtitle' => '查看并运行 Cockpit 当前提供的操作',
			'actions.select' => '选择操作',
			'actions.selectDescription' => '选择一个可用操作，查看输入要求，并使用 LON、JSON 或 YAML 对象运行。',
			'actions.selectProjectReason' => '请选择项目后运行此项目级操作。',
			'actions.selectFolderReason' => '请选择允许的文件夹后运行此文件夹级操作。',
			'actions.noFolderReason' => '没有可用的允许文件夹。请先在“项目”中添加文件夹，再运行文件夹级操作。',
			'actions.filter' => '筛选操作',
			'actions.global' => '全局操作',
			'actions.project' => '项目操作',
			'actions.loadFailed' => ({required Object error}) => '无法加载操作：${error}',
			'actions.none' => '当前没有可用操作。',
			'actions.noMatch' => ({required Object query}) => '没有与“${query}”匹配的操作。',
			'actions.scopeBadge.global' => '全局',
			'actions.scopeBadge.workspace' => '项目',
			'actions.scopeBadge.root' => '根目录',
			'actions.input' => '输入',
			'actions.inputDescription' => '使用 LON、JSON 或 YAML 对象。幂等键属于调用信封，不应放在此对象中。',
			'actions.scope' => '作用域',
			'actions.mutation' => '变更类型',
			'actions.idempotency' => '幂等性',
			'actions.execution' => '执行方式',
			'actions.timeout' => '超时',
			'actions.timeoutValue' => ({required Object defaultValue, required Object maximum}) => '${defaultValue}（最大 ${maximum}）',
			'actions.effects' => '影响',
			'actions.features' => '所需能力',
			'actions.inputSchema' => '输入 Schema',
			'actions.outputSchema' => '输出 Schema',
			'actions.idempotencyKey' => '幂等键',
			'actions.generatedWhenRun' => '运行时生成',
			'actions.optional' => '可选',
			'actions.generateKey' => '生成新键',
			'actions.keyRequiredDescription' => '此操作可能改变状态，因此必须提供。',
			'actions.keyOptionalDescription' => '可选，留空时不会发送。',
			'actions.noRoots' => '尚未注册活动项目根目录。',
			'actions.projectRoot' => '项目根目录',
			'actions.selectRoot' => '选择活动根目录',
			'actions.unavailable' => '无法在此处运行该操作。',
			'actions.addFolder' => '添加允许的文件夹',
			'actions.running' => '正在运行…',
			'actions.run' => '运行操作',
			'actions.mutationWarning' => '此操作可能改变状态。',
			'actions.scopeRootDescription' => '针对所选允许文件夹运行。',
			'actions.scopeProjectDescription' => '针对所选项目运行。',
			'actions.scopeGlobalDescription' => '在 Supervisor 作用域中运行，不需要选择项目。',
			'actions.failed' => '操作未成功',
			'actions.result' => '结果',
			'actions.submitted' => '已提交',
			'actions.submittedState' => ({required Object state}) => '已提交 · ${state}',
			'actions.copied' => '已复制',
			'actions.copy' => '复制',
			'actions.scopeValue.supervisor' => 'Supervisor（全局）',
			'actions.scopeValue.root' => '根目录',
			'actions.scopeValue.workspace' => '工作区',
			'actions.mutationValue.readOnly' => '只读',
			'actions.mutationValue.mutating' => '会修改状态',
			'actions.idempotencyValue.required' => '必需',
			'actions.idempotencyValue.optional' => '可选',
			'actions.idempotencyValue.prohibited' => '禁止',
			'actions.executionValue.synchronous' => '同步',
			'actions.executionValue.job' => '任务',
			'ai.title' => 'AI 助手',
			'ai.settings' => 'Agent 设置',
			'ai.connectToStart' => '连接 AI Agent 后开始使用',
			'ai.connecting' => '正在连接…',
			'ai.connectingToAgent' => '正在连接 Agent',
			'ai.startConversation' => '开始对话',
			'ai.connectDescription' => '连接兼容 ACP 的 Agent 后，即可在这里提问或执行开发任务。',
			'ai.connectAgent' => '连接 Agent',
			'ai.connectChatHint' => '连接 Agent 后开始对话',
			'ai.connectTitle' => '连接 AI Agent',
			'ai.connectSubtitle' => '选择 Agent 及其工作目录。',
			'ai.closeConnectionSetup' => '关闭连接设置',
			'ai.closeSettings' => '关闭设置',
			'ai.disconnected' => 'Agent 已断开连接。',
			'ai.clearChat' => '清空对话视图',
			'ai.disconnect' => '断开 Agent',
			'ai.custom' => '自定义',
			'ai.customDescription' => '任意 ACP 可执行文件',
			'ai.agent' => 'Agent',
			'ai.chooseAgent' => '选择 AI Agent',
			'ai.presetDescription' => ({required Object name}) => '${name} ACP Agent',
			'ai.selectWorkingDirectory' => '选择工作目录',
			'ai.startSession' => '开始会话',
			'ai.executable' => '可执行文件',
			'ai.arguments' => '参数（每行一个）',
			'ai.argumentsDescription' => '参数会直接传给可执行文件，不经过 Shell。',
			'ai.workingDirectory' => '工作目录',
			'ai.workingDirectoryHint' => '/项目的绝对路径',
			'ai.browseDirectories' => '浏览目录',
			'ai.selectProjectBeforeEditing' => '请先选择项目，再发送到编辑器。',
			'ai.latest' => '最新消息',
			'ai.dismissError' => '关闭错误',
			'ai.permissionRequired' => '继续操作需要授权',
			'ai.input' => '输入',
			'ai.location' => '位置',
			'ai.locations' => '位置',
			'ai.cancelRequest' => '取消请求',
			'ai.signInTitle' => '登录后继续',
			'ai.signInDescription' => '在 Agent 设置中选择登录方式，然后完成登录流程。',
			'ai.openSignIn' => '打开登录',
			'ai.sessionTitle' => '创建或打开会话',
			'ai.sessionDescription' => '使用 Agent 设置创建新会话或恢复最近工作。',
			'ai.openSessionSetup' => '打开会话设置',
			'ai.conversationDescription' => '询问工作区内容、请求代码修改或描述测试场景。',
			'ai.sendToEditor' => '发送到编辑器',
			'ai.composer.duplicateAttachment' => '该附件已经添加。',
			'ai.composer.messageHint' => '输入消息…',
			'ai.composer.sessionRequiredHint' => '创建会话或登录后开始对话',
			'ai.composer.stopResponse' => '停止响应',
			'ai.composer.sendMessage' => '发送消息（Enter）',
			'ai.composer.addMessage' => '输入消息或添加附件',
			'ai.composer.inlineLimit' => ({required Object size, required Object limit}) => '内联 ${size} · 上限 ${limit}',
			'ai.composer.availableCommands' => '可用命令',
			'ai.composer.addContext' => '添加上下文',
			'ai.composer.attachImage' => '附加图片',
			'ai.composer.attachImageDescription' => '以内联数据发送图片',
			'ai.composer.attachAudio' => '附加音频',
			'ai.composer.attachAudioDescription' => '以内联数据发送音频',
			'ai.composer.embedContext' => '嵌入上下文文件',
			'ai.composer.embedContextDescription' => '包含完整文件内容',
			'ai.composer.linkFile' => '链接本地文件',
			'ai.composer.linkFileDescription' => '引用文件但不复制内容',
			'ai.composer.linkResource' => '链接资源 URI',
			'ai.composer.linkResourceDescription' => '引用 Agent 可访问的任意资源',
			'ai.composer.removeAttachment' => ({required Object name}) => '移除 ${name}',
			'ai.composer.name' => '名称',
			'ai.composer.nameHint' => 'API 规范',
			'ai.composer.absoluteUri' => '绝对 URI',
			'ai.composer.mimeOptional' => 'MIME 类型（可选）',
			'ai.composer.descriptionOptional' => '描述（可选）',
			'ai.composer.resourceError' => '请输入名称和带有 Scheme 的绝对 URI。',
			'ai.composer.addResource' => '添加资源',
			'ai.composer.linked' => '已链接',
			'ai.composer.embedded' => '已嵌入',
			'ai.composer.pathUnavailable' => '所选文件没有可用的本地路径。',
			'ai.composer.notRegularFile' => '所选路径不是普通文件。',
			'ai.composer.resourceRequirements' => '资源链接必须包含名称和绝对 URI。',
			'ai.composer.promptLimit' => ({required Object size, required Object limit}) => '内联附件已使用 ${size}，提示上限为 ${limit}。',
			'ai.composer.unsupportedImage' => ({required Object name}) => '“${name}”不是支持的图片文件。',
			'ai.composer.unsupportedAudio' => ({required Object name}) => '“${name}”不是支持的音频文件。',
			'ai.composer.emptyFile' => '所选文件为空。',
			'ai.composer.fileTooLarge' => ({required Object size, required Object limit}) => '所选文件大小为 ${size}，内联附件上限为 ${limit}。',
			'ai.connection.createSession' => '创建会话',
			'ai.connection.workingDirectory' => '工作目录',
			'ai.connection.selectSessionDirectory' => '选择会话工作目录',
			'ai.connection.sessionContext' => '会话上下文',
			'ai.connection.optionalContext' => '可选目录和 MCP 服务器',
			'ai.connection.configuredItems' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '已配置 ${n} 项', other: '已配置 ${n} 项', ),
			'ai.connection.additionalDirectories' => '附加目录',
			'ai.connection.additionalDirectoriesDescription' => '允许 Agent 访问工作目录之外的其他工作区根目录。',
			'ai.connection.addDirectory' => '添加目录',
			'ai.connection.mcpServers' => 'MCP 服务器',
			'ai.connection.mcpServersDescription' => '为此 Agent 连接附加工具和资源，这些值不会被存储。',
			'ai.connection.addServer' => '添加服务器',
			'ai.connection.addSessionDirectory' => '添加会话目录',
			'ai.connection.duplicateDirectory' => '该目录已经添加。',
			'ai.connection.duplicateServer' => 'MCP 服务器名称必须唯一。',
			'ai.connection.remove' => ({required Object name}) => '移除 ${name}',
			'ai.mcp.addTitle' => '添加 MCP 服务器',
			'ai.mcp.editTitle' => '编辑 MCP 服务器',
			'ai.mcp.transport' => '传输方式',
			'ai.mcp.name' => '名称',
			'ai.mcp.executablePath' => '可执行文件绝对路径',
			'ai.mcp.serverUrl' => '服务器 URL',
			'ai.mcp.arguments' => '参数（每行一个）',
			'ai.mcp.environment' => '环境变量（NAME=value）',
			'ai.mcp.headers' => '请求头（Name: value）',
			'ai.mcp.valuesDescription' => '这些值仅用于当前连接，Cockpit Console 不会存储。',
			'ai.mcp.addServer' => '添加服务器',
			'ai.mcp.saveServer' => '保存服务器',
			'ai.mcp.nameRequired' => '请输入服务器名称。',
			'ai.mcp.executableRequired' => '请输入可执行文件路径。',
			'ai.mcp.urlRequired' => '请输入服务器 URL。',
			'ai.mcp.absoluteExecutable' => 'stdio 可执行文件必须使用绝对路径。',
			'ai.mcp.absoluteUrl' => '服务器 URL 必须是绝对 HTTP(S) URL。',
			'ai.mcp.environmentSyntax' => ({required Object line}) => '环境变量第 ${line} 行必须使用 NAME=value 格式。',
			'ai.mcp.environmentName' => ({required Object line}) => '环境变量第 ${line} 行的变量名无效。',
			'ai.mcp.environmentDuplicate' => ({required Object name}) => '环境变量“${name}”重复。',
			'ai.mcp.headerSyntax' => ({required Object line}) => '请求头第 ${line} 行必须使用 Name: value 格式。',
			'ai.mcp.headerName' => ({required Object line}) => '请求头第 ${line} 行的名称无效。',
			'ai.mcp.headerDuplicate' => ({required Object name}) => '请求头“${name}”重复。',
			'ai.mcp.stdioDescription' => '所有 ACP Agent 均支持。',
			'ai.mcp.httpDescription' => '需要 Agent 支持 HTTP MCP。',
			'ai.mcp.sseDescription' => '需要 Agent 支持 SSE MCP。',
			'ai.session.authentication' => '身份验证',
			'ai.session.signIn' => '登录',
			'ai.session.signOut' => '退出登录',
			'ai.session.section' => '会话',
			'ai.session.refreshRecent' => '刷新最近会话',
			'ai.session.signInFirst' => '请先登录，再创建会话。',
			'ai.session.noneOpen' => '当前没有打开的会话，创建会话后即可开始对话。',
			'ai.session.newSession' => '新建会话',
			'ai.session.close' => '关闭会话',
			'ai.session.recent' => '最近会话',
			'ai.session.loading' => '正在加载会话…',
			'ai.session.noneSaved' => '此 Agent 没有返回已保存的会话。',
			'ai.session.loadMore' => '加载更多',
			'ai.session.activeSession' => '当前会话',
			'ai.session.additionalDirectories' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '${n} 个附加目录', other: '${n} 个附加目录', ),
			'ai.session.mcpServers' => ({required Object names}) => 'MCP：${names}',
			'ai.session.active' => '当前',
			'ai.session.actions' => '会话操作',
			'ai.session.resume' => '恢复',
			'ai.session.load' => '加载',
			'ai.session.loadHistory' => '从历史记录加载',
			'ai.session.delete' => '删除会话',
			'ai.session.settings' => 'Agent 设置',
			'ai.session.mode' => '模式',
			'ai.session.noSettings' => '此 Agent 没有提供会话设置。',
			'ai.session.currentContext' => '当前上下文',
			'ai.session.usage' => '用量',
			_ => null,
		} ?? switch (path) {
			'ai.session.tokensUsed' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '已使用 ${n} 个 Token', other: '已使用 ${n} 个 Token', ),
			'ai.session.tokenContext' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '上下文容量 ${n} 个 Token', other: '上下文容量 ${n} 个 Token', ),
			'ai.session.plan' => '计划',
			'ai.session.availableCommands' => '可用命令',
			'ai.session.authNotRequired' => '无需身份验证',
			'ai.session.authAvailable' => '可以登录',
			'ai.session.authRequired' => '必须登录',
			'ai.session.authWaiting' => '正在等待登录完成…',
			'ai.session.authenticated' => '已登录',
			'ai.session.signingOut' => '正在退出登录…',
			'ai.session.capImages' => '图片',
			'ai.session.capAudio' => '音频',
			'ai.session.capContext' => '上下文文件',
			'ai.session.capLoad' => '加载会话',
			'ai.session.capResume' => '恢复会话',
			'ai.session.capHistory' => '历史记录',
			'ai.session.deleteTitle' => '删除会话？',
			'ai.session.deleteDescription' => ({required Object name}) => '从 Agent 删除“${name}”。此操作无法撤销。',
			'ai.session.keep' => '保留会话',
			'ai.tool.rawInput' => '原始输入',
			'ai.tool.rawOutput' => '原始输出',
			'ai.tool.terminal' => '终端',
			'ai.tool.audio' => '音频',
			'ai.tool.invalidImage' => ({required Object mime}) => 'Agent 返回了无效的 ${mime} 图片数据。',
			'ai.tool.malformedImage' => 'Agent 返回的 base64 图片数据格式错误。',
			'ai.tool.textResource' => '文本资源',
			'ai.tool.binaryResource' => '二进制资源',
			'ai.tool.diff' => '差异',
			'ai.tool.before' => '修改前',
			'ai.tool.after' => '修改后',
			'ai.tool.location' => '位置',
			'ai.tool.status.completed' => '已完成',
			'ai.tool.status.failed' => '失败',
			'ai.tool.status.inProgress' => '进行中',
			'sessions.title' => '实时会话',
			'sessions.subtitle' => '查看正在运行的应用，不会修改或重启应用',
			'sessions.findingTitle' => '正在查找运行中的会话',
			'sessions.findingDescription' => 'Cockpit 正在检查所有活动项目中的运行应用。',
			'sessions.emptyTitle' => '暂无可监听会话',
			'sessions.emptyDescription' => '使用 Cockpit 启动应用后，会话会自动显示在这里，并在停止后保留记录。',
			'sessions.checkAgain' => '重新检查',
			'sessions.liveCount' => ({required Object live, required Object total}) => '${live} 个运行中 · 共 ${total} 个',
			'sessions.liveCountSemantics' => ({required Object live, required Object total}) => '${live} 个运行中的会话，共 ${total} 个会话',
			'sessions.listTitle' => '会话',
			'sessions.selectSemantics' => ({required Object project, required Object platform, required Object session}) => '${project}，${platform}，会话 ${session}',
			'sessions.refreshFailed' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '${n} 个项目刷新失败。', other: '${n} 个项目刷新失败。', ),
			'sessions.refreshProjectFailed' => '项目刷新失败。',
			'sessions.stoppedMessage' => '此会话已不再活动。',
			'sessions.bridgeReconnectingMessage' => '应用桥接正在重新连接。',
			'sessions.selectPrompt' => '选择一个会话以查看其实时状态。',
			'sessions.sessionId' => ({required Object session}) => '会话 ${session}',
			'sessions.contextApp' => '应用',
			'sessions.contextAppTip' => '在“应用与设备”中打开此项目',
			'sessions.contextActions' => '操作',
			'sessions.contextActionsTip' => '打开此项目的操作',
			'sessions.contextTests' => '测试',
			'sessions.contextTestsTip' => '打开此项目的测试',
			'sessions.contextRuns' => '运行',
			'sessions.contextRunsTip' => '打开此项目的测试运行',
			'sessions.refreshSection' => ({required Object section}) => '刷新${section}',
			'sessions.status.reconnecting' => '正在重连',
			'sessions.status.live' => '运行中',
			'sessions.status.starting' => '正在启动',
			'sessions.status.reloading' => '正在热重载',
			'sessions.status.restarting' => '正在重启',
			'sessions.status.checking' => '正在检查',
			'sessions.status.failed' => '失败',
			'sessions.status.unavailable' => '不可用',
			'sessions.status.stopped' => '已停止',
			'sessions.sections.overview' => '概览',
			'sessions.sections.ui' => '界面',
			'sessions.sections.logs' => '日志',
			'sessions.sections.network' => '网络',
			'sessions.sections.activity' => '活动',
			'sessions.sections.diagnostics' => '诊断',
			'sessions.data.structured' => '结构化数据',
			'sessions.data.empty' => '此会话暂时没有可用数据。',
			'sessions.data.copy' => '复制数据',
			'sessions.data.copied' => '数据已复制',
			'sessions.data.notSet' => '未设置',
			'sessions.data.copyLabel' => ({required Object label}) => '复制${label}',
			'sessions.data.labelCopied' => ({required Object label}) => '${label}已复制',
			'sessions.data.fields' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '${n} 个字段', other: '${n} 个字段', ),
			'sessions.data.items' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '${n} 项', other: '${n} 项', ),
			'sessions.overview.appProcess' => '应用进程',
			'sessions.overview.reachable' => '可访问',
			'sessions.overview.unavailable' => '不可用',
			'sessions.overview.checking' => '正在检查',
			'sessions.overview.bridge' => 'Cockpit 桥接',
			'sessions.overview.connected' => '已连接',
			'sessions.overview.disconnected' => '未连接',
			'sessions.overview.runtimeErrors' => '运行时错误',
			'sessions.overview.networkFailures' => '网络失败',
			'sessions.overview.currentState' => '当前状态',
			'sessions.overview.currentStateDescription' => 'Cockpit 当前监听到的应用和桥接身份。',
			'sessions.overview.route' => '路由',
			'sessions.overview.lifecycle' => '生命周期',
			'sessions.overview.reloadGeneration' => '热重载代次',
			'sessions.overview.lastRuntimeStatus' => '最近运行状态',
			'sessions.overview.nextStep' => '下一步',
			'sessions.overview.lastError' => '最近错误',
			'sessions.overview.noActionNeeded' => '无需操作',
			'sessions.overview.launchIdentity' => '启动身份',
			'sessions.overview.launchIdentityDescription' => '使用这些信息确认应用是否运行在预期项目中。',
			'sessions.overview.project' => '项目',
			'sessions.overview.workspace' => '工作区',
			'sessions.overview.session' => '会话',
			'sessions.overview.target' => '目标',
			'sessions.overview.device' => '设备',
			'sessions.overview.entrypoint' => '入口文件',
			'sessions.overview.flavor' => '构建环境',
			'sessions.overview.appId' => '应用 ID',
			'sessions.overview.vmService' => 'VM 服务',
			'sessions.ui.open' => '打开此分区以加载完整的 Flutter 界面快照。',
			'sessions.ui.current' => '当前界面',
			'sessions.ui.description' => '完整展示已挂载目标、诊断、无障碍信息和 Element 结构。',
			'sessions.ui.snapshotFile' => '快照文件',
			'sessions.ui.treeFile' => 'Widget 树文件',
			'sessions.ui.targets' => '目标',
			'sessions.ui.elements' => 'Element 数量',
			'sessions.ui.snapshotTruncated' => '快照已截断',
			'sessions.ui.treeTruncated' => '树已截断',
			'sessions.ui.completeSnapshot' => '完整快照',
			'sessions.ui.snapshotUnavailable' => '无法加载完整界面快照。',
			'sessions.ui.copySnapshot' => '复制快照数据',
			'sessions.ui.fullTree' => '完整 Widget 树',
			'sessions.ui.treeUnavailable' => '无法加载完整的已挂载 Element 树。',
			'sessions.ui.copyTree' => '复制 Widget 树数据',
			'sessions.ui.metadata' => '检查元数据',
			'sessions.ui.metadataEmpty' => '暂无检查元数据。',
			'sessions.ui.copyMetadata' => '复制检查元数据',
			'sessions.logs.open' => '打开此分区以实时查看启动日志和应用日志。',
			'sessions.logs.live' => '每 2 秒自动刷新',
			'sessions.logs.latestBelow' => '最新输出在底部',
			'sessions.logs.startupTitle' => '启动与 Flutter 工具日志',
			'sessions.logs.startupNone' => '暂无启动或 Flutter 工具日志。',
			'sessions.logs.startupRecent' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '最近 ${n} 行启动日志', other: '最近 ${n} 行启动日志', ),
			'sessions.logs.startupRunningEmpty' => 'Cockpit 正在等待 Flutter 工具输出。',
			'sessions.logs.title' => '应用日志',
			'sessions.logs.none' => '未捕获到应用日志。',
			'sessions.logs.recent' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '最近 ${n} 行日志', other: '最近 ${n} 行日志', ),
			'sessions.logs.olderHidden' => '，更早日志已隐藏',
			'sessions.logs.runningEmpty' => '应用正在运行，但尚未捕获到日志输出。',
			'sessions.activityEmpty' => 'Cockpit 监听到的连接、路由、运行时错误和网络变化会显示在这里。',
			'sessions.activity.discovered' => '发现会话',
			'sessions.activity.discoveredDetail' => ({required Object platform, required Object device}) => '${platform} · ${device}',
			'sessions.activity.connected' => '会话已连接',
			'sessions.activity.changed' => '会话状态变化',
			'sessions.activity.stateDetail' => ({required Object from, required Object to}) => '${from} → ${to}',
			'sessions.activity.appUnavailable' => '应用进程不可用',
			'sessions.activity.appReachable' => '应用进程可访问',
			'sessions.activity.bridgeConnected' => 'Cockpit 桥接已连接',
			'sessions.activity.bridgeDisconnected' => 'Cockpit 桥接已断开',
			'sessions.activity.sessionDetail' => ({required Object session}) => '会话 ${session}',
			'sessions.activity.routeChanged' => '路由变化',
			'sessions.activity.routeDetail' => ({required Object from, required Object to}) => '${from} → ${to}',
			'sessions.activity.unknownRoute' => '未知',
			'sessions.activity.runtimeError' => '捕获到运行时错误',
			'sessions.activity.runtimeErrorDetail' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '当前快照中有 ${n} 个错误', other: '当前快照中有 ${n} 个错误', ),
			'sessions.activity.networkFailure' => '捕获到网络失败',
			'sessions.activity.networkFailureDetail' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '已捕获 ${n} 个失败请求', other: '已捕获 ${n} 个失败请求', ),
			'sessions.timeline.newestFirst' => '最新在前',
			'sessions.timeline.showing' => ({required Object visible, required Object total}) => '${visible} / ${total}',
			'sessions.timeline.all' => '全部',
			'sessions.timeline.lifecycle' => '生命周期',
			'sessions.timeline.routes' => '路由',
			'sessions.timeline.runtime' => '运行时',
			'sessions.timeline.network' => '网络',
			'sessions.timeline.noMatch' => '没有符合当前筛选条件的事件。',
			'sessions.timeline.expand' => '展开事件详情',
			'sessions.timeline.collapse' => '收起事件详情',
			'sessions.timeline.discarded' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '为保持内存稳定，已丢弃较早的 ${n} 个事件。', other: '为保持内存稳定，已丢弃较早的 ${n} 个事件。', ),
			'sessions.timeline.severity.info' => '信息',
			'sessions.timeline.severity.success' => '成功',
			'sessions.timeline.severity.warning' => '警告',
			'sessions.timeline.severity.error' => '错误',
			'sessions.diagnostics.open' => '打开此分区以加载运行时错误和会话日志。',
			'sessions.diagnostics.runtimeErrors' => '运行时错误',
			'sessions.diagnostics.noRuntimeErrors' => '未捕获到运行时错误。',
			'sessions.diagnostics.capturedErrors' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '已捕获 ${n} 个运行时错误。', other: '已捕获 ${n} 个运行时错误。', ),
			'sessions.diagnostics.sessionLogs' => '会话日志',
			'sessions.diagnostics.noSessionLines' => '未捕获到会话生命周期日志。',
			'sessions.diagnostics.recentSessionLines' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '最近 ${n} 行生命周期日志。', other: '最近 ${n} 行生命周期日志。', ),
			'sessions.diagnostics.sessionLogsUnavailable' => '暂无会话生命周期日志。',
			'sessions.diagnostics.runtimeError' => '运行时错误',
			'sessions.network.open' => '打开此分区以加载最新网络请求。',
			'sessions.network.loadOlder' => ({required Object loaded, required Object total}) => '加载更早请求（已加载 ${loaded} / ${total}）',
			'sessions.network.selectRequest' => '选择一个请求以查看详情。',
			'sessions.network.total' => '总数',
			'sessions.network.loaded' => '已加载',
			'sessions.network.failures' => '失败',
			'sessions.network.inFlight' => '进行中',
			'sessions.network.source' => '来源',
			'sessions.network.exportTooltip' => '导出请求或响应正文',
			'sessions.network.safeResponse' => '安全导出响应',
			'sessions.network.safeRequest' => '安全导出请求',
			'sessions.network.safeBoth' => '安全导出请求和响应',
			'sessions.network.rawBoth' => '导出未脱敏正文…',
			'sessions.network.unknownRequestUri' => '未知请求地址',
			'sessions.network.metadataEmpty' => '暂无请求元数据。',
			'sessions.network.copyMetadata' => '复制请求元数据',
			'sessions.network.unmaskedFiles' => '未脱敏正文文件',
			'sessions.network.bodyFiles' => '正文文件',
			'sessions.network.bodyDescription' => 'Cockpit 会将请求和响应正文分别写入已验证文件。',
			'sessions.network.copyPaths' => '复制正文文件路径',
			'sessions.network.confirmRawTitle' => '导出未脱敏网络正文？',
			'sessions.network.confirmRawDescription' => '导出的文件可能包含凭据、Cookie、个人数据或二进制内容。Cockpit 只会返回文件路径。',
			'sessions.network.exportUnmasked' => '导出未脱敏内容',
			'sessions.network.empty' => '尚未捕获到网络请求。操作应用后刷新此分区。',
			'sessions.network.unknownUri' => '未知地址',
			'sessions.network.unknownSource' => '未知',
			_ => null,
		};
	}
}
