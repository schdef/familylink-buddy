import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Extension on [BuildContext] for simple access to [AppStrings].
extension LocalizationExtension on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

/// Abstract base class defining all user-facing strings in the parent app.
abstract class AppStrings {
  const AppStrings();

  static Locale? _manualLocale;
  static Locale? get manualLocale => _manualLocale;
  static set manualLocale(Locale? locale) {
    _manualLocale = locale;
    notifyLocaleChanged();
  }

  static final List<VoidCallback> _listeners = [];
  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void notifyLocaleChanged() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  static const String _prefKey = 'app_language_override';

  /// Loads any previously saved language preference from SharedPreferences.
  static Future<void> loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code != null && code.isNotEmpty) {
        _manualLocale = Locale(code);
        notifyLocaleChanged();
      }
    } catch (_) {}
  }

  /// Sets a manual language preference and persists it.
  /// Pass null to revert to system default.
  static Future<void> setSavedLocale(String? languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (languageCode == null || languageCode.isEmpty) {
        await prefs.remove(_prefKey);
        _manualLocale = null;
      } else {
        await prefs.setString(_prefKey, languageCode);
        _manualLocale = Locale(languageCode);
      }
      notifyLocaleChanged();
    } catch (_) {}
  }

  /// Returns the appropriate [AppStrings] instance based on context, manual setting, or system locale.
  static AppStrings of(BuildContext? context) {
    if (_manualLocale != null) {
      return getStrings(_manualLocale!.languageCode);
    }
    if (context != null) {
      final locale = Localizations.maybeLocaleOf(context);
      if (locale != null) {
        return getStrings(locale.languageCode);
      }
    }
    return current;
  }

  /// Returns the currently active Locale (manual override or system locale).
  static Locale get currentLocale {
    if (_manualLocale != null) return _manualLocale!;
    return PlatformDispatcher.instance.locale;
  }

  /// Returns current strings based on manual override or system locale (defaults to English if not German).
  static AppStrings get current {
    if (_manualLocale != null) {
      return getStrings(_manualLocale!.languageCode);
    }
    final systemLang = PlatformDispatcher.instance.locale.languageCode;
    return getStrings(systemLang);
  }

  /// Resolves [AppStrings] by language code.
  static AppStrings getStrings(String languageCode) {
    if (languageCode.toLowerCase().startsWith('de')) {
      return const AppStringsDe();
    }
    return const AppStringsEn();
  }

  String get languageCode;

  // ===========================================================================
  // 1. GENERAL / COMMON
  // ===========================================================================
  String get appName;
  String get appEdition;
  String appVersion(String version);
  String get appArchitecture;
  String get appCloudNotice;
  String get language;
  String get systemDefault;
  String get english;
  String get german;
  String get cancel;
  String get delete;
  String get confirm;
  String get save;
  String get close;
  String get refresh;
  String get settings;
  String get lanLocal;
  String get lanDirect;
  String get cloudSync;
  String get connected;
  String get online;
  String get offline;
  String get checking;
  String get errorPrefix;
  String get unknown;

  // ===========================================================================
  // 2. DEVICE LIST SCREEN
  // ===========================================================================
  String get myChildren;
  String get refreshTooltip;
  String get settingsTooltip;
  String get unpairDeviceTitle;
  String unpairDeviceConfirm(String name);
  String get unpair;
  String deviceUnpaired(String name);
  String get appSettingsTitle;
  String get noChildrenPaired;
  String get noChildrenPairedDesc;
  String get pairDevice;
  String get localLan;
  String get timeBankButton;
  String get commsButton;
  String get unpairTooltip;
  String get addChild;

  // ===========================================================================
  // 3. PAIRING SCREEN
  // ===========================================================================
  String get pairDeviceTitle;
  String get scanQrCodeTitle;
  String get pairChildLocally;
  String get pairChildLocallyDesc;
  String get invalidQrCode;
  String connectionFailed(String ip, int port);
  String connectionFailedHint(String ip, int port);
  String deviceNotFoundOnLan(String code);
  String get successfullyPaired;
  String get fillAllFields;
  String pairingFailed(dynamic error);
  String get enterCodeOrIp;
  String get deviceNameLabel;
  String get defaultChildName;
  String get methodA;
  String get codeOrIpHint;
  String get connect;
  String get methodB;
  String get cameraUnavailableTitle;
  String get cameraUnavailableDesc;
  String get enterManually;
  String get webManualPairingHint;
  String get localEmulatorPairing;

  // ===========================================================================
  // 4. VOLUME CONTROL SCREEN & P2P UPDATE
  // ===========================================================================
  String get volumeControlTitle;
  String get statusUpdated;
  String get updateErrorNoResponse;
  String get audioPlayingSpotify;
  String get activeMediaPlayback;
  String get stopPlayback;
  String get playbackStopped;
  String get errorStoppingPlayback;
  String get quickAccess;
  String get quickActionAppLimits;
  String get quickActionBedtime;
  String get quickActionScreenshot;
  String get quickActionUpdate;
  String get quickActionCalls;
  String get quickActionChats;
  String get mediaVolume;
  String get ringtoneVolume;
  String get alarmVolume;
  String get muteAll;
  String get maxVolume;
  String get lastSeenNever;
  String get lastSeenJustNow;
  String lastSeenSecondsAgo(int s);
  String lastSeenMinutesAgo(int m);
  String lastSeenHoursAgo(int h);
  String lastSeenDaysAgo(int d);
  String get p2pUpdateTitle;
  String get p2pUpdateDesc;
  String get childIpLabel;
  String get childIpHint;
  String get apkFileLabel;
  String get apkFileHint;
  String get selectApkTooltip;
  String get selectingFile;
  String get selectApkButton;
  String get unknownSize;
  String apkSelected(String name, String size);
  String filePickError(dynamic error);
  String get enterChildIp;
  String get preparingTransfer;
  String get noValidApk;
  String sendingApkWifi(String ip);
  String wifiTransferProgress(int percent);
  String get updateSuccess;
  String get transferring;
  String get transferUpdate;
  String get updatesTitle;
  String get checkForUpdates;
  String updateAvailable(String version);
  String get upToDate;
  String get downloadAndInstall;
  String downloadingUpdate(int percent);
  String get updateParentApp;
  String get updateChildApp;
  String get updateError;
  String get checkingForUpdates;
  String get releaseNotes;
  String currentVersionLabel(String version);
  String latestVersionLabel(String version);
  String get pushedToChildSuccess;
  String get parentAppUpdated;
  String get installPermissionRequired;
  String get installFailed;
  String get webManualDownloadNotice;
  String get downloadFailed;
  String get p2pTransferFailed;
  String get triggerTabletDownload;
  String get tabletDownloadTriggered;

  // ===========================================================================
  // 5. SCREENSHOT SCREEN
  // ===========================================================================
  String get liveScreenTitle;
  String screenshotNotReceived(String error);
  String get screenshotDeleted;
  String errorDeletingScreenshot(String? error);
  String get screenshotNotDeleted;
  String get invalidImageFormat;
  String get imageLoadError;
  String get closeAppTitle;
  String closeAppConfirm(String app);
  String get closeAppButton;
  String appClosed(String app);
  String get appCloseFailed;
  String get lockTabletTitle;
  String get lockTabletConfirm;
  String get lockNow;
  String get tabletLocked;
  String get tabletLockFailed;
  String get deleteScreenshotTitle;
  String deleteScreenshotConfirm(String dt);
  String get deleteAllScreenshotsTitle;
  String deleteAllScreenshotsConfirm(int count);
  String get deleteAll;
  String get allScreenshotsDeleted;
  String errorDeletingAllScreenshots(String? error);
  String get cameraLabel;
  String get frontCamera;
  String get backCamera;
  String get frontCameraShort;
  String get backCameraShort;
  String get flashOff;
  String get screenshotSuccess;
  String get cameraSuccess;
  String get running;
  String get captureScreenshot;
  String get takeCameraPhoto;
  String get locking;
  String get lockScreen;
  String get firestorePermissionDenied;
  String get securityRulesUpdateRequired;
  String get firestorePermissionHelp;
  String get localFirstDiagnosisTitle;
  String get localFirstDiagnosisHelp;
  String get localFirstDiagnosisSteps;
  String get accessibilityServiceRequired;
  String get noScreenshotYet;
  String get noScreenshotDesc;
  String get cameraBackLabel;
  String get cameraFrontLabel;
  String get screenLabel;
  String get zoom;
  String activeApp(String app);
  String get closingApp;
  String get closeAppImmediate;
  String get lockingTablet;
  String get lockTablet;
  String historyCount(int count);
  String get deletingAll;
  String get newBadge;

  // ===========================================================================
  // 6. APP LIMITS SCREEN
  // ===========================================================================
  String get appLimitsTitle;
  String appBlockedInstant(String name);
  String appUnblocked(String name);
  String bonusAdded(int min, String category);
  String get bonusSyncFailed;
  String categorySaved(String name);
  String get categorySaveFailed;
  String get deleteCategoryTitle;
  String deleteCategoryConfirm(String name);
  String categoryDeleted(String name);
  String get categoryDeleteFailed;
  String tabBlacklist(int count);
  String tabCategories(int count);
  String get blacklistBanner;
  String blockedApps(int count);
  String get blockApp;
  String get noAppsBlocked;
  String get noAppsBlockedDesc;
  String get addAppToBlacklist;
  String get statusBlocked;
  String get unblock;
  String timeCategoriesHeader(int count);
  String get newCategory;
  String get noCategoriesYet;
  String get noCategoriesDesc;
  String get createFirstCategory;
  String get dailyLimit;
  String get bonusToday;
  String get assignedApps;
  String get noAppsInGroup;
  String get add15MinBonus;
  String get add30MinBonus;
  String get editCategory;
  String get newTimeCategory;
  String get categoryNameLabel;
  String get categoryNameValidator;
  String get dailyLimitMinutesLabel;
  String get validNumberValidator;
  String get selectAppsForCategory;
  String get noInstalledAppsFound;
  String get searchApps;
  String get saveCategoryButton;
  String appUnblockConfirm(String name);
  String get tabAppHistory;
  String get appHistoryTitle;
  String get appHistorySubtitle;
  String get noAppHistory;
  String get availableApps;
  String get availableAppsDesc;
  String get searchAvailableApps;
  String get switchKid;
  String get addKid;

  // ===========================================================================
  // 7. BEDTIME SCHEDULE SCREEN
  // ===========================================================================
  String get bedtimeTitle;
  String get scheduleSaved;
  String get scheduleSaveFailed;
  String get wifiBlockedInstant;
  String get wifiUnblockedInstant;
  String get setBedtime;
  String get setWakeupTime;
  String get apply;
  String get wifiBlockedStatus;
  String get wifiActiveStatus;
  String get wifiBlockedDesc;
  String get wifiActiveDesc;
  String get turnWifiOnNow;
  String get turnWifiOffNow;
  String get autoControlBedtime;
  String get autoControlBedtimeDesc;
  String get scheduleTimes;
  String get bedtimeOff;
  String get wakeupOn;
  String get activeWeekdays;
  String get schoolDaysPreset;
  String get everyDayPreset;
  String get dayMo;
  String get dayDi;
  String get dayMi;
  String get dayDo;
  String get dayFr;
  String get daySa;
  String get daySo;
  String get daysSummaryNoDays;
  String get daysSummaryEveryDay;
  String get daysSummarySchoolDays;
  String get daysSummaryMonToFri;
  String get daysSummaryWeekend;
  String get timeUnit;

  /// Helper to format a summary of active weekdays in the current language
  String formatDaysSummary(List<int> activeDays) {
    if (activeDays.isEmpty) return daysSummaryNoDays;
    if (activeDays.length == 7) return daysSummaryEveryDay;
    final sorted = List<int>.from(activeDays)..sort();
    if (listEquals(sorted, [1, 2, 3, 4, 5])) return schoolDaysPreset;
    if (listEquals(sorted, [1, 2, 3, 4, 7])) {
      return languageCode == 'de' ? 'Schultage (So–Do)' : 'School days (Sun–Thu)';
    }
    if (listEquals(sorted, [6, 7])) {
      return languageCode == 'de' ? 'Wochenende (Sa–So)' : 'Weekend (Sat–Sun)';
    }
    if (listEquals(sorted, [5, 6])) {
      return daysSummaryWeekend;
    }

    final dayNames = {
      1: dayMo,
      2: dayDi,
      3: dayMi,
      4: dayDo,
      5: dayFr,
      6: daySa,
      7: daySo,
    };
    return sorted.map((d) => dayNames[d] ?? '$d').join(', ');
  }

  // ===========================================================================
  // 8. TIME BANK SCREENS
  // ===========================================================================
  String get timeBankTitle;
  String get awardCoinsTitle;
  String get quickSelect;
  String get reasonLabel;
  String get enterReasonValidator;
  String get selectIcon;
  String get awardButton;
  String coinsAwarded(int count);
  String get activated;
  String get deactivated;
  String get visibleForChild;
  String get hiddenForChild;
  String get timeCoins;
  String get awardCoins;
  String get tasksAndRewards;
  String get pendingClaims;
  String costCoins(int cost);
  String get doneButton;
  String rewardFulfilled(String title);
  String get todayActivity;
  String get historyButton;
  String get noTransactionsToday;
  String get timeBankSettingsTitle;
  String get timeBankSettingsInfo;
  String get enableTimeBank;
  String get enableTimeBankDesc;
  String get visibleToChildTitle;
  String get visibleToChildDesc;
  String get activityHistoryTitle;
  String get todayFilter;
  String get weekFilter;
  String get monthFilter;
  String get earned;
  String get spent;
  String get noActivitiesPeriod;
  String get tasksAndRewardsTitle;
  String get createTaskTitle;
  String get taskTitleLabel;
  String get enterTitleValidator;
  String get rewardCoinsLabel;
  String get withTimerMinutes;
  String get durationMinutesLabel;
  String get enterMinutesValidator;
  String get addButton;
  String get createRewardTitle;
  String get rewardTitleLabel;
  String get costCoinsLabel;
  String get tasksTab;
  String get rewardsTab;
  String get noTasksYet;
  String get addTaskButton;
  String timerTaskSubtitle(int dur, int rew);
  String instantTaskSubtitle(int rew);
  String get noRewardsYet;
  String get addRewardButton;

  // ===========================================================================
  // 9. COMMS SCREEN
  // ===========================================================================
  String get walkieTalkieTitle;
  String get missedCallTitle;
  String get channelSimulatedActive;
  String get channelReady;
  String get holdToTalk;
  String get talking;
  String get audioStreaming;
  String get walkieTalkieRules;
  String get autoPlayVoiceTitle;
  String get autoPlayVoiceSubtitle;
  String get childCanInitiateTitle;
  String get childCanInitiateSubtitle;

  // ===========================================================================
  // 10. CALL HISTORY & CHAT MESSAGES
  // ===========================================================================
  String get callHistoryTitle;
  String get chatMessagesTitle;
  String get allCalls;
  String get incomingCalls;
  String get outgoingCalls;
  String get missedCalls;
  String get allApps;
  String get appWhatsApp;
  String get appSms;
  String get appTelegram;
  String get appSignal;
  String get syncNow;
  String get syncing;
  String get syncSuccess;
  String get syncFailed;
  String get noCallsFound;
  String get noChatsFound;
  String get searchCallsPlaceholder;
  String get searchChatsPlaceholder;
  String callDurationFormat(int seconds);
  String get incomingLabel;
  String get outgoingLabel;
  String get missedLabel;
  String get rejectedLabel;
  String get offlineNotice;
  String lastSyncedLabel(String time);
  String get neverSynced;
  String get conversationsTitle;
  String chatDetailTitle(String name);
  String get noMessagesInChat;
  String get today;
  String get yesterday;
}

/// English localization implementation (Default).
class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get languageCode => 'en';

  // 1. General
  @override
  String get appName => 'FamilyLink Buddy Parent';
  @override
  String get appEdition => 'FamilyLink Buddy - Local-First Edition';
  @override
  String appVersion(String version) => 'Version: $version';
  @override
  String get appArchitecture => 'Architecture: 100% LAN Direct REST / Local-First';
  @override
  String get appCloudNotice => 'No cloud requirement, no Google login required.';
  @override
  String get language => 'Language';
  @override
  String get systemDefault => 'System Default';
  @override
  String get english => 'English';
  @override
  String get german => 'German';
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get confirm => 'Confirm';
  @override
  String get save => 'Save';
  @override
  String get close => 'Close';
  @override
  String get refresh => 'Refresh';
  @override
  String get settings => 'Settings';
  @override
  String get lanLocal => 'LAN Local';
  @override
  String get lanDirect => 'LAN Direct';
  @override
  String get cloudSync => 'Cloud Sync';
  @override
  String get connected => 'Connected';
  @override
  String get online => 'Online';
  @override
  String get offline => 'Offline';
  @override
  String get checking => 'Checking';
  @override
  String get errorPrefix => 'Error: ';
  @override
  String get unknown => 'Unknown';

  // 2. Device List Screen
  @override
  String get myChildren => 'My Children';
  @override
  String get refreshTooltip => 'Refresh';
  @override
  String get settingsTooltip => 'Settings';
  @override
  String get unpairDeviceTitle => 'Unpair device?';
  @override
  String unpairDeviceConfirm(String name) => 'Do you really want to unpair the device of $name?';
  @override
  String get unpair => 'Unpair';
  @override
  String deviceUnpaired(String name) => '$name was unpaired.';
  @override
  String get appSettingsTitle => 'App Settings';
  @override
  String get noChildrenPaired => 'No children paired yet';
  @override
  String get noChildrenPairedDesc => 'Pair your child\'s device via local Wi-Fi to manage it directly.';
  @override
  String get pairDevice => 'Pair device';
  @override
  String get localLan => 'Local (LAN)';
  @override
  String get timeBankButton => 'Time Bank ⏳';
  @override
  String get commsButton => 'Comms 🎙️';
  @override
  String get unpairTooltip => 'Unpair';
  @override
  String get addChild => 'Add child';

  // 3. Pairing Screen
  @override
  String get pairDeviceTitle => 'Pair Device (LAN / Local)';
  @override
  String get scanQrCodeTitle => 'Scan QR Code';
  @override
  String get pairChildLocally => 'Pair child device locally';
  @override
  String get pairChildLocallyDesc => 'Pair your child\'s device via Wi-Fi / LAN using an IP address or QR code.';
  @override
  String get invalidQrCode => 'Invalid QR code. Please try again.';
  @override
  String connectionFailed(String ip, int port) => 'Connection to device at $ip:$port failed (timeout after 3s). Please check Wi-Fi.';
  @override
  String connectionFailedHint(String ip, int port) => 'Connection to $ip:$port failed. Please check:\n1. Both devices on same Wi-Fi? (Not Guest Wi-Fi)\n2. Router \'WLAN devices may communicate\' enabled?\n3. Tablet app open?';
  @override
  String deviceNotFoundOnLan(String code) => 'Device \'$code\' was not found on the local Wi-Fi. Please ensure both devices are on the same Wi-Fi network, or pair directly using the tablet\'s IP address or QR code.';
  @override
  String get successfullyPaired => 'Successfully paired!';
  @override
  String get fillAllFields => 'Please fill in all fields.';
  @override
  String pairingFailed(dynamic error) => 'Pairing failed: $error';
  @override
  String get enterCodeOrIp => 'Please enter the code or IP address.';
  @override
  String get deviceNameLabel => 'Device name (e.g. Child Tablet)';
  @override
  String get defaultChildName => 'Child';
  @override
  String get methodA => 'Method A: IP address or PIN';
  @override
  String get codeOrIpHint => 'e.g. 192.168.1.100 or code';
  @override
  String get connect => 'Connect';
  @override
  String get methodB => 'Method B: Scan QR code';
  @override
  String get cameraUnavailableTitle => 'Camera Not Available';
  @override
  String get cameraUnavailableDesc => 'Camera access was denied or is not supported in this browser. Please enter the tablet\'s IP address or 6-digit code manually.';
  @override
  String get enterManually => 'Enter Code / IP Manually';
  @override
  String get webManualPairingHint => 'Web Browser Mode: Enter the IP address or 6-digit pairing code shown on the child tablet.';
  @override
  String get localEmulatorPairing => 'Local emulator pairing (Auto-Pair)';

  // 4. Volume Control Screen
  @override
  String get volumeControlTitle => 'Volume Control';
  @override
  String get statusUpdated => 'Status updated successfully!';
  @override
  String get updateErrorNoResponse => 'Update error: No response from device. Is the child online?';
  @override
  String get audioPlayingSpotify => 'Audio is playing (e.g. Spotify)';
  @override
  String get activeMediaPlayback => 'Active media playback on tablet';
  @override
  String get stopPlayback => 'Stop playback';
  @override
  String get playbackStopped => 'Media playback stopped.';
  @override
  String get errorStoppingPlayback => 'Error stopping playback.';
  @override
  String get quickAccess => 'QUICK ACCESS';
  @override
  String get quickActionAppLimits => 'App Limits & Blocking';
  @override
  String get quickActionBedtime => 'Bedtime & Wi-Fi';
  @override
  String get quickActionScreenshot => 'Screenshot & Camera';
  @override
  String get quickActionUpdate => 'Wi-Fi Update';
  @override
  String get quickActionCalls => 'Call History';
  @override
  String get quickActionChats => 'Chat Messages';
  @override
  String get mediaVolume => 'Media volume';
  @override
  String get ringtoneVolume => 'Ringtone';
  @override
  String get alarmVolume => 'Alarm volume';
  @override
  String get muteAll => 'Mute all';
  @override
  String get maxVolume => 'Maximum';
  @override
  String get lastSeenNever => 'No connection history';
  @override
  String get lastSeenJustNow => 'Active just now';
  @override
  String lastSeenSecondsAgo(int s) => 'Active ${s}s ago';
  @override
  String lastSeenMinutesAgo(int m) => 'Active ${m}m ago';
  @override
  String lastSeenHoursAgo(int h) => 'Active ${h}h ago';
  @override
  String lastSeenDaysAgo(int d) => 'Active ${d}d ago';
  @override
  String get p2pUpdateTitle => 'P2P Wi-Fi Update';
  @override
  String get p2pUpdateDesc => 'Update the child app instantly over the local home network without downloading from the internet on the target device.';
  @override
  String get childIpLabel => 'Child IP address (Port 8085)';
  @override
  String get childIpHint => 'e.g. 192.168.1.100';
  @override
  String get apkFileLabel => 'APK file (Device / Google Drive)';
  @override
  String get apkFileHint => 'Path to APK or use button below';
  @override
  String get selectApkTooltip => 'Select APK from device or Google Drive';
  @override
  String get selectingFile => 'Selecting file...';
  @override
  String get selectApkButton => 'Select APK (Device / Google Drive)';
  @override
  String get unknownSize => 'Unknown size';
  @override
  String apkSelected(String name, String size) => 'APK selected: $name ($size)';
  @override
  String filePickError(dynamic error) => 'Error selecting file: $error';
  @override
  String get enterChildIp => 'Please enter the child device IP address.';
  @override
  String get preparingTransfer => 'Preparing transfer...';
  @override
  String get noValidApk => 'No valid APK found. Please select an APK file via "Select APK".';
  @override
  String sendingApkWifi(String ip) => 'Sending APK via Wi-Fi to $ip:8085...';
  @override
  String wifiTransferProgress(int percent) => 'Wi-Fi transfer: $percent%';
  @override
  String get updateSuccess => 'Update transferred successfully! Installation started.';
  @override
  String get transferring => 'Transferring...';
  @override
  String get transferUpdate => 'Transfer update';
  @override
  String get updatesTitle => 'App Updates';
  @override
  String get checkForUpdates => 'Check for Updates';
  @override
  String updateAvailable(String version) => 'New version available: $version';
  @override
  String get upToDate => 'You are using the latest version';
  @override
  String get downloadAndInstall => 'Download & Install';
  @override
  String downloadingUpdate(int percent) => 'Downloading update: $percent%';
  @override
  String get updateParentApp => 'Update Parent App';
  @override
  String get updateChildApp => 'Update Child Tablet';
  @override
  String get updateError => 'Failed to download update';
  @override
  String get checkingForUpdates => 'Checking for updates...';
  @override
  String get releaseNotes => 'Release Notes';
  @override
  String currentVersionLabel(String version) => 'Current version: $version';
  @override
  String latestVersionLabel(String version) => 'Latest version: $version';
  @override
  String get pushedToChildSuccess => 'Update pushed to Child Tablet! Installing...';
  @override
  String get parentAppUpdated => 'Starting installation...';
  @override
  String get installPermissionRequired => "Install permission required. Please enable 'Allow from this source' in Settings and tap Update again.";
  @override
  String get installFailed => "Failed to start installation.";
  @override
  String get downloadFailed => 'Failed to download update file';
  @override
  String get p2pTransferFailed => 'Failed to send update to tablet over Wi-Fi';
  @override
  String get triggerTabletDownload => 'Download directly on tablet';
  @override
  String get tabletDownloadTriggered => 'Update download started on tablet';
  @override
  String get webManualDownloadNotice => 'Please download the latest release APK from GitHub:';

  // 5. Screenshot Screen
  @override
  String get liveScreenTitle => 'Live Screen';
  @override
  String screenshotNotReceived(String error) => 'Could not receive screenshot: $error';
  @override
  String get screenshotDeleted => 'Screenshot deleted.';
  @override
  String errorDeletingScreenshot(String? error) => error != null && error.isNotEmpty ? 'Error deleting: $error' : 'Screenshot could not be deleted.';
  @override
  String get screenshotNotDeleted => 'Screenshot could not be deleted.';
  @override
  String get invalidImageFormat => 'Invalid image format';
  @override
  String get imageLoadError => 'Image data could not be loaded';
  @override
  String get closeAppTitle => 'Close app?';
  @override
  String closeAppConfirm(String app) => 'Close app \'$app\'? The child device will immediately return to the home screen.';
  @override
  String get closeAppButton => 'Close app';
  @override
  String appClosed(String app) => 'App \'$app\' was closed.';
  @override
  String get appCloseFailed => 'App could not be closed. Is the device reachable?';
  @override
  String get lockTabletTitle => 'Lock tablet screen?';
  @override
  String get lockTabletConfirm => 'Do you want to turn off and lock the tablet screen right now?';
  @override
  String get lockNow => 'Lock now';
  @override
  String get tabletLocked => 'Tablet screen was locked.';
  @override
  String get tabletLockFailed => 'Screen could not be locked. Is the device online?';
  @override
  String get deleteScreenshotTitle => 'Delete screenshot?';
  @override
  String deleteScreenshotConfirm(String dt) => 'Do you really want to delete this capture ($dt)?';
  @override
  String get deleteAllScreenshotsTitle => 'Delete all screenshots?';
  @override
  String deleteAllScreenshotsConfirm(int count) => 'Do you really want to permanently delete all $count captures? This action cannot be undone.';
  @override
  String get deleteAll => 'Delete all';
  @override
  String get allScreenshotsDeleted => 'All screenshots were deleted.';
  @override
  String errorDeletingAllScreenshots(String? error) => error != null && error.isNotEmpty ? 'Error deleting all screenshots: $error' : 'All screenshots could not be deleted.';
  @override
  String get cameraLabel => 'Camera:';
  @override
  String get frontCamera => 'Front camera (Default)';
  @override
  String get backCamera => 'Back camera';
  @override
  String get frontCameraShort => 'Front camera';
  @override
  String get backCameraShort => 'Back camera';
  @override
  String get flashOff => 'Flash: Off';
  @override
  String get screenshotSuccess => 'Screenshot received successfully!';
  @override
  String get cameraSuccess => 'Camera photo captured successfully!';
  @override
  String get running => 'Running...';
  @override
  String get captureScreenshot => 'Screenshot';
  @override
  String get takeCameraPhoto => 'Take Camera Photo';
  @override
  String get locking => 'Locking...';
  @override
  String get lockScreen => 'Lock Screen';
  @override
  String get firestorePermissionDenied => 'Connection / Permission Warning';
  @override
  String get securityRulesUpdateRequired => 'Check Local Network & Accessibility Service';
  @override
  String get firestorePermissionHelp => 'Could not connect to child tablet over LAN. Please ensure:';
  @override
  String get localFirstDiagnosisTitle => 'Connection / Permission Warning';
  @override
  String get localFirstDiagnosisHelp => 'Could not connect to child tablet over LAN. Please verify:';
  @override
  String get localFirstDiagnosisSteps => '1. Both devices are connected to the same Wi-Fi.\n2. Tablet screen is awake and unlocked.\n3. Accessibility Service is granted in Tablet Settings.';
  @override
  String get accessibilityServiceRequired => 'Screenshot failed: Accessibility service must be enabled on the child device.';
  @override
  String get noScreenshotYet => 'No screenshot available yet';
  @override
  String get noScreenshotDesc => 'Tap the button above to retrieve the child\'s current screen in real time.';
  @override
  String get cameraBackLabel => '📷 Back Camera';
  @override
  String get cameraFrontLabel => '📷 Front Camera';
  @override
  String get screenLabel => '📱 Screen';
  @override
  String get zoom => 'Zoom';
  @override
  String activeApp(String app) => 'Active app: $app';
  @override
  String get closingApp => 'Closing...';
  @override
  String get closeAppImmediate => 'Close app immediately';
  @override
  String get lockingTablet => 'Locking...';
  @override
  String get lockTablet => 'Lock tablet';
  @override
  String historyCount(int count) => 'History ($count)';
  @override
  String get deletingAll => 'Deleting...';
  @override
  String get newBadge => 'NEW';

  // 6. App Limits Screen
  @override
  String get appLimitsTitle => 'App Limits & Blocking';
  @override
  String appBlockedInstant(String name) => '„$name“ was blocked immediately.';
  @override
  String appUnblocked(String name) => '„$name“ was unblocked.';
  @override
  String bonusAdded(int min, String category) => '+$min min bonus added for „$category“!';
  @override
  String get bonusSyncFailed => 'Bonus could not be synchronized.';
  @override
  String categorySaved(String name) => 'Category „$name“ saved successfully.';
  @override
  String get categorySaveFailed => 'Category could not be saved.';
  @override
  String get deleteCategoryTitle => 'Delete category?';
  @override
  String deleteCategoryConfirm(String name) => 'Do you really want to remove category „$name“? Assigned apps will no longer have a shared group limit.';
  @override
  String categoryDeleted(String name) => 'Category „$name“ deleted.';
  @override
  String get categoryDeleteFailed => 'Category could not be deleted.';
  @override
  String tabBlacklist(int count) => 'Instant Block ($count)';
  @override
  String tabCategories(int count) => 'Time Categories ($count)';
  @override
  String get blacklistBanner => 'Apps in this list are immediately blocked on the tablet and close automatically when opened.';
  @override
  String blockedApps(int count) => 'Blocked Apps ($count)';
  @override
  String get blockApp => 'Block app';
  @override
  String get noAppsBlocked => 'No apps blocked';
  @override
  String get noAppsBlockedDesc => 'Currently no apps are completely blocked. Block unwanted games or apps here.';
  @override
  String get addAppToBlacklist => 'Add app to block list';
  @override
  String get statusBlocked => 'Blocked';
  @override
  String get unblock => 'Unblock';
  @override
  String timeCategoriesHeader(int count) => 'Time Categories ($count)';
  @override
  String get newCategory => 'New Category';
  @override
  String get noCategoriesYet => 'No time categories yet';
  @override
  String get noCategoriesDesc => 'Create groups like "Games" or "Videos" with a shared daily limit and bonus minutes.';
  @override
  String get createFirstCategory => 'Create first category';
  @override
  String get dailyLimit => 'Daily limit';
  @override
  String get bonusToday => 'Bonus today';
  @override
  String get assignedApps => 'Assigned apps';
  @override
  String get noAppsInGroup => 'No apps in this group yet';
  @override
  String get add15MinBonus => '+15 min';
  @override
  String get add30MinBonus => '+30 min';
  @override
  String get editCategory => 'Edit Category';
  @override
  String get newTimeCategory => 'New Time Category';
  @override
  String get categoryNameLabel => 'Category name (e.g. Games)';
  @override
  String get categoryNameValidator => 'Please enter a name';
  @override
  String get dailyLimitMinutesLabel => 'Daily limit in minutes';
  @override
  String get validNumberValidator => 'Please enter a valid number';
  @override
  String get selectAppsForCategory => 'Select apps for this category:';
  @override
  String get noInstalledAppsFound => 'No apps found (or child tablet offline)';
  @override
  String get searchApps => 'Search apps...';
  @override
  String get saveCategoryButton => 'Save category';
  @override
  String appUnblockConfirm(String name) => 'Do you really want to unblock „$name“?';
  @override
  String get tabAppHistory => 'History';
  @override
  String get appHistoryTitle => 'App Activity History';
  @override
  String get appHistorySubtitle => 'App launches over the last 5 days on this tablet';
  @override
  String get noAppHistory => 'No app activity recorded in the last 5 days.';
  @override
  String get availableApps => 'Available Apps on Tablet';
  @override
  String get availableAppsDesc => 'Tap to block or unblock apps directly without modals.';
  @override
  String get searchAvailableApps => 'Filter available apps...';
  @override
  String get switchKid => 'Switch Kid';
  @override
  String get addKid => 'Add Kid';

  // 7. Bedtime Schedule Screen
  @override
  String get bedtimeTitle => 'Bedtime & Wi-Fi';
  @override
  String get scheduleSaved => 'Wi-Fi schedule saved successfully';
  @override
  String get scheduleSaveFailed => 'Schedule could not be saved';
  @override
  String get wifiBlockedInstant => 'Wi-Fi blocked immediately';
  @override
  String get wifiUnblockedInstant => 'Wi-Fi unblocked';
  @override
  String get setBedtime => 'Set bedtime';
  @override
  String get setWakeupTime => 'Set wake-up time';
  @override
  String get apply => 'Apply';
  @override
  String get wifiBlockedStatus => 'Wi-Fi is blocked';
  @override
  String get wifiActiveStatus => 'Wi-Fi is active';
  @override
  String get wifiBlockedDesc => 'The child device\'s Wi-Fi connection is currently blocked.';
  @override
  String get wifiActiveDesc => 'The child has unrestricted access to the Wi-Fi network.';
  @override
  String get turnWifiOnNow => 'Turn Wi-Fi ON now';
  @override
  String get turnWifiOffNow => 'Turn Wi-Fi OFF now';
  @override
  String get autoControlBedtime => 'Control bedtime automatically';
  @override
  String get autoControlBedtimeDesc => 'Cut off Wi-Fi at scheduled times';
  @override
  String get scheduleTimes => 'Times';
  @override
  String get bedtimeOff => 'Bedtime (Wi-Fi Off)';
  @override
  String get wakeupOn => 'Wake-up time (Wi-Fi On)';
  @override
  String get activeWeekdays => 'Active weekdays';
  @override
  String get schoolDaysPreset => 'School days (Mon–Fri)';
  @override
  String get everyDayPreset => 'Every day';
  @override
  String get dayMo => 'Mo';
  @override
  String get dayDi => 'Tu';
  @override
  String get dayMi => 'We';
  @override
  String get dayDo => 'Th';
  @override
  String get dayFr => 'Fr';
  @override
  String get daySa => 'Sa';
  @override
  String get daySo => 'Su';
  @override
  String get daysSummaryNoDays => 'No days';
  @override
  String get daysSummaryEveryDay => 'Every day';
  @override
  String get daysSummarySchoolDays => 'School days (Mon–Fri)';
  @override
  String get daysSummaryMonToFri => 'Monday – Friday';
  @override
  String get daysSummaryWeekend => 'Weekend (Fri–Sat)';
  @override
  String get timeUnit => '';

  // 8. Time Bank Screens
  @override
  String get timeBankTitle => 'Time Bank';
  @override
  String get awardCoinsTitle => 'Award Coins ⏳';
  @override
  String get quickSelect => 'Quick selection:';
  @override
  String get reasonLabel => 'Reason (e.g. read 30 min)';
  @override
  String get enterReasonValidator => 'Please enter a reason';
  @override
  String get selectIcon => 'Select icon:';
  @override
  String get awardButton => 'Award ✓';
  @override
  String coinsAwarded(int count) => '$count coins awarded successfully!';
  @override
  String get activated => 'Activated';
  @override
  String get deactivated => 'Deactivated';
  @override
  String get visibleForChild => 'Visible to child';
  @override
  String get hiddenForChild => 'Hidden from child';
  @override
  String get timeCoins => 'Time Coins ⏳';
  @override
  String get awardCoins => 'Award coins';
  @override
  String get tasksAndRewards => 'Tasks & Rewards';
  @override
  String get pendingClaims => 'Pending payouts';
  @override
  String costCoins(int cost) => 'Cost: $cost Coins ⏳';
  @override
  String get doneButton => 'Done ✓';
  @override
  String rewardFulfilled(String title) => 'Reward "$title" approved.';
  @override
  String get todayActivity => 'Today\'s activity';
  @override
  String get historyButton => 'History 📊';
  @override
  String get noTransactionsToday => 'No transactions today yet.';
  @override
  String get timeBankSettingsTitle => 'Settings';
  @override
  String get timeBankSettingsInfo => 'Set up the reward system here. The child earns coins for tasks and can exchange them for rewards.';
  @override
  String get enableTimeBank => 'Enable time bank';
  @override
  String get enableTimeBankDesc => 'Enables the coin system and registering transactions/tasks.';
  @override
  String get visibleToChildTitle => 'Visible to child';
  @override
  String get visibleToChildDesc => 'When enabled, the child can view balance, tasks and shop in their app. When disabled, the feature remains completely invisible to the child.';
  @override
  String get activityHistoryTitle => 'Activity History';
  @override
  String get todayFilter => 'Today';
  @override
  String get weekFilter => 'Week';
  @override
  String get monthFilter => 'Month';
  @override
  String get earned => 'Earned';
  @override
  String get spent => 'Spent';
  @override
  String get noActivitiesPeriod => 'No activities in this period.';
  @override
  String get tasksAndRewardsTitle => 'Tasks & Rewards';
  @override
  String get createTaskTitle => 'Create new task';
  @override
  String get taskTitleLabel => 'Title (e.g. Clean room)';
  @override
  String get enterTitleValidator => 'Please enter a title';
  @override
  String get rewardCoinsLabel => 'Reward (Coins)';
  @override
  String get withTimerMinutes => 'With timer (minutes):';
  @override
  String get durationMinutesLabel => 'Duration in minutes';
  @override
  String get enterMinutesValidator => 'Please enter a valid number of minutes';
  @override
  String get addButton => 'Add';
  @override
  String get createRewardTitle => 'Create new reward';
  @override
  String get rewardTitleLabel => 'Title (e.g. 1 hr Minecraft)';
  @override
  String get costCoinsLabel => 'Cost (Coins)';
  @override
  String get tasksTab => 'Tasks 🌟';
  @override
  String get rewardsTab => 'Rewards 🎁';
  @override
  String get noTasksYet => 'No tasks created yet.';
  @override
  String get addTaskButton => 'Add task';
  @override
  String timerTaskSubtitle(int dur, int rew) => 'Timer: $dur min | +$rew Coins';
  @override
  String instantTaskSubtitle(int rew) => 'Instant | +$rew Coins';
  @override
  String get noRewardsYet => 'No rewards created yet.';
  @override
  String get addRewardButton => 'Add reward';

  // 9. Comms Screen
  @override
  String get walkieTalkieTitle => 'Walkie-Talkie Comms';
  @override
  String get missedCallTitle => 'Missed Walkie-Talkie call';
  @override
  String get channelSimulatedActive => 'Simulated Channel Active';
  @override
  String get channelReady => 'Channel Ready';
  @override
  String get holdToTalk => 'HOLD TO TALK';
  @override
  String get talking => 'TALKING...';
  @override
  String get audioStreaming => '🎙️ Streaming audio...';
  @override
  String get walkieTalkieRules => 'WALKIE-TALKIE RULES';
  @override
  String get autoPlayVoiceTitle => 'Play directly on child device';
  @override
  String get autoPlayVoiceSubtitle => 'Audio plays immediately through speaker without ringing.';
  @override
  String get childCanInitiateTitle => 'Child can initiate call';
  @override
  String get childCanInitiateSubtitle => 'Allows child to start walkie-talkie connection from their widget.';

  // 10. Call History & Chat Messages
  @override
  String get callHistoryTitle => 'Call History';
  @override
  String get chatMessagesTitle => 'Chat Messages';
  @override
  String get allCalls => 'All';
  @override
  String get incomingCalls => 'Incoming';
  @override
  String get outgoingCalls => 'Outgoing';
  @override
  String get missedCalls => 'Missed';
  @override
  String get allApps => 'All Apps';
  @override
  String get appWhatsApp => 'WhatsApp';
  @override
  String get appSms => 'SMS / Messages';
  @override
  String get appTelegram => 'Telegram';
  @override
  String get appSignal => 'Signal';
  @override
  String get syncNow => 'Sync Now';
  @override
  String get syncing => 'Syncing...';
  @override
  String get syncSuccess => 'Logs synced successfully';
  @override
  String get syncFailed => 'Failed to sync logs';
  @override
  String get noCallsFound => 'No call records found';
  @override
  String get noChatsFound => 'No chat messages found';
  @override
  String get searchCallsPlaceholder => 'Search by name or number...';
  @override
  String get searchChatsPlaceholder => 'Search messages or contacts...';
  @override
  String callDurationFormat(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    return '${s}s';
  }
  @override
  String get incomingLabel => 'Incoming';
  @override
  String get outgoingLabel => 'Outgoing';
  @override
  String get missedLabel => 'Missed';
  @override
  String get rejectedLabel => 'Rejected';
  @override
  String get offlineNotice => 'Offline • Showing cached records';
  @override
  String lastSyncedLabel(String time) => 'Last synced: $time';
  @override
  String get neverSynced => 'Never synced';
  @override
  String get conversationsTitle => 'Conversations';
  @override
  String chatDetailTitle(String name) => 'Chat with $name';
  @override
  String get noMessagesInChat => 'No messages in this chat';
  @override
  String get today => 'Today';
  @override
  String get yesterday => 'Yesterday';
}

/// German localization implementation.
class AppStringsDe extends AppStrings {
  const AppStringsDe();

  @override
  String get languageCode => 'de';

  // 1. General
  @override
  String get appName => 'FamilyLink Buddy Eltern';
  @override
  String get appEdition => 'FamilyLink Buddy - Local-First Edition';
  @override
  String appVersion(String version) => 'Version: $version';
  @override
  String get appArchitecture => 'Architektur: 100% LAN Direct REST / Local-First';
  @override
  String get appCloudNotice => 'Kein Cloud-Zwang, keine Google-Anmeldung erforderlich.';
  @override
  String get language => 'Sprache';
  @override
  String get systemDefault => 'Systemstandard';
  @override
  String get english => 'Englisch';
  @override
  String get german => 'Deutsch';
  @override
  String get cancel => 'Abbrechen';
  @override
  String get delete => 'Löschen';
  @override
  String get confirm => 'Bestätigen';
  @override
  String get save => 'Speichern';
  @override
  String get close => 'Schließen';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get settings => 'Einstellungen';
  @override
  String get lanLocal => 'LAN Local';
  @override
  String get lanDirect => 'LAN Direct';
  @override
  String get cloudSync => 'Cloud Sync';
  @override
  String get connected => 'Verbunden';
  @override
  String get online => 'Online';
  @override
  String get offline => 'Offline';
  @override
  String get checking => 'Prüfe...';
  @override
  String get errorPrefix => 'Fehler: ';
  @override
  String get unknown => 'Unbekannt';

  // 2. Device List Screen
  @override
  String get myChildren => 'Meine Kinder';
  @override
  String get refreshTooltip => 'Aktualisieren';
  @override
  String get settingsTooltip => 'Einstellungen';
  @override
  String get unpairDeviceTitle => 'Gerät abkoppeln?';
  @override
  String unpairDeviceConfirm(String name) => 'Möchten Sie das Gerät von $name wirklich abkoppeln?';
  @override
  String get unpair => 'Abkoppeln';
  @override
  String deviceUnpaired(String name) => '$name wurde entkoppelt.';
  @override
  String get appSettingsTitle => 'App-Einstellungen';
  @override
  String get noChildrenPaired => 'Noch keine Kinder gekoppelt';
  @override
  String get noChildrenPairedDesc => 'Koppeln Sie das Gerät Ihres Kindes über das lokale WLAN, um es direkt zu steuern.';
  @override
  String get pairDevice => 'Gerät koppeln';
  @override
  String get localLan => 'Lokal (LAN)';
  @override
  String get timeBankButton => 'Zeitkonto ⏳';
  @override
  String get commsButton => 'Comms 🎙️';
  @override
  String get unpairTooltip => 'Abkoppeln';
  @override
  String get addChild => 'Kind hinzufügen';

  // 3. Pairing Screen
  @override
  String get pairDeviceTitle => 'Gerät koppeln (LAN / Local)';
  @override
  String get scanQrCodeTitle => 'QR Code scannen';
  @override
  String get pairChildLocally => 'Kinder-Gerät lokal koppeln';
  @override
  String get pairChildLocallyDesc => 'Koppeln Sie das Gerät Ihres Kindes über WLAN / LAN per IP-Adresse oder QR-Code.';
  @override
  String get invalidQrCode => 'Ungültiger QR-Code. Bitte erneut versuchen.';
  @override
  String connectionFailed(String ip, int port) => 'Verbindung zum Gerät unter $ip:$port fehlgeschlagen (Timeout nach 3s). Bitte WLAN prüfen.';
  @override
  String connectionFailedHint(String ip, int port) => 'Verbindung zu $ip:$port fehlgeschlagen. Bitte prüfen:\n1. Beide Geräte im selben WLAN? (Kein Gast-WLAN)\n2. Im Router \'WLAN-Geräte dürfen untereinander kommunizieren\' aktiviert?\n3. Tablet-App geöffnet?';
  @override
  String deviceNotFoundOnLan(String code) => 'Gerät \'$code\' wurde im lokalen WLAN nicht gefunden. Bitte sicherstellen, dass beide Geräte im selben WLAN sind, oder direkt per IP-Adresse oder QR-Code koppeln.';
  @override
  String get successfullyPaired => 'Erfolgreich gekoppelt!';
  @override
  String get fillAllFields => 'Bitte füllen Sie alle Felder aus.';
  @override
  String pairingFailed(dynamic error) => 'Kopplung fehlgeschlagen: $error';
  @override
  String get enterCodeOrIp => 'Bitte geben Sie den Code oder die IP-Adresse ein.';
  @override
  String get deviceNameLabel => 'Geräte-Name (z.B. Kind Tablet)';
  @override
  String get defaultChildName => 'Kind';
  @override
  String get methodA => 'Methode A: IP-Adresse oder PIN';
  @override
  String get codeOrIpHint => 'z.B. 192.168.1.100 oder Code';
  @override
  String get connect => 'Verbinden';
  @override
  String get methodB => 'Methode B: QR-Code scannen';
  @override
  String get cameraUnavailableTitle => 'Kamera nicht verfügbar';
  @override
  String get cameraUnavailableDesc => 'Kamerazugriff wurde verweigert oder wird in diesem Browser nicht unterstützt. Bitte gib die IP-Adresse oder den 6-stelligen Code des Tablets manuell ein.';
  @override
  String get enterManually => 'Code / IP manuell eingeben';
  @override
  String get webManualPairingHint => 'Webbrowser-Modus: Gib die IP-Adresse oder den 6-stelligen Kopplungscode ein, der auf dem Kind-Tablet angezeigt wird.';
  @override
  String get localEmulatorPairing => 'Lokale Emulator-Kopplung (Auto-Pair)';

  // 4. Volume Control Screen
  @override
  String get volumeControlTitle => 'Lautstärke-Steuerung';
  @override
  String get statusUpdated => 'Status erfolgreich aktualisiert!';
  @override
  String get updateErrorNoResponse => 'Fehler beim Aktualisieren: Keine Antwort vom Gerät. Ist das Kind online?';
  @override
  String get audioPlayingSpotify => 'Audio wird wiedergegeben (z. B. Spotify)';
  @override
  String get activeMediaPlayback => 'Aktive Medienwiedergabe auf dem Tablet';
  @override
  String get stopPlayback => 'Wiedergabe stoppen';
  @override
  String get playbackStopped => 'Medienwiedergabe gestoppt.';
  @override
  String get errorStoppingPlayback => 'Fehler beim Stoppen der Wiedergabe.';
  @override
  String get quickAccess => 'SCHNELLZUGRIFF';
  @override
  String get quickActionAppLimits => 'App-Limits & Sperren';
  @override
  String get quickActionBedtime => 'WLAN-Nachtruhe';
  @override
  String get quickActionScreenshot => 'Live-Screenshot';
  @override
  String get quickActionUpdate => 'WLAN-Update';
  @override
  String get quickActionCalls => 'Anrufverlauf';
  @override
  String get quickActionChats => 'Chat-Nachrichten';
  @override
  String get mediaVolume => 'Medien-Lautstärke';
  @override
  String get ringtoneVolume => 'Klingelton';
  @override
  String get alarmVolume => 'Wecker-Lautstärke';
  @override
  String get muteAll => 'Alles stumm';
  @override
  String get maxVolume => 'Maximal';
  @override
  String get lastSeenNever => 'Keine Verbindungshistorie';
  @override
  String get lastSeenJustNow => 'Gerade eben aktiv';
  @override
  String lastSeenSecondsAgo(int s) => 'Vor $s Sek. aktiv';
  @override
  String lastSeenMinutesAgo(int m) => 'Vor $m Min. aktiv';
  @override
  String lastSeenHoursAgo(int h) => 'Vor $h Std. aktiv';
  @override
  String lastSeenDaysAgo(int d) => 'Vor $d Tagen aktiv';
  @override
  String get p2pUpdateTitle => 'P2P Wi-Fi Update';
  @override
  String get p2pUpdateDesc => 'Aktualisiere die Kinder-App blitzschnell direkt über das lokale Heimnetzwerk ohne Internet-Download auf dem Zielgerät.';
  @override
  String get childIpLabel => 'IP-Adresse des Kindes (Port 8085)';
  @override
  String get childIpHint => 'z.B. 192.168.1.100';
  @override
  String get apkFileLabel => 'APK-Datei (Gerät / Google Drive)';
  @override
  String get apkFileHint => 'Pfad zur APK oder Button unten nutzen';
  @override
  String get selectApkTooltip => 'APK von Gerät oder Google Drive wählen';
  @override
  String get selectingFile => 'Wähle Datei...';
  @override
  String get selectApkButton => 'APK auswählen (Gerät / Google Drive)';
  @override
  String get unknownSize => 'Unbekannte Größe';
  @override
  String apkSelected(String name, String size) => 'APK ausgewählt: $name ($size)';
  @override
  String filePickError(dynamic error) => 'Fehler bei Dateiauswahl: $error';
  @override
  String get enterChildIp => 'Bitte geben Sie die IP-Adresse des Kinder-Geräts ein.';
  @override
  String get preparingTransfer => 'Bereite Übertragung vor...';
  @override
  String get noValidApk => 'Keine gültige APK vorhanden. Bitte wählen Sie eine APK-Datei über "APK auswählen" aus.';
  @override
  String sendingApkWifi(String ip) => 'Sende APK per WLAN an $ip:8085...';
  @override
  String wifiTransferProgress(int percent) => 'WLAN-Übertragung: $percent%';
  @override
  String get updateSuccess => 'Update erfolgreich übertragen! Installation gestartet.';
  @override
  String get transferring => 'Übertrage...';
  @override
  String get transferUpdate => 'Update übertragen';
  @override
  String get updatesTitle => 'App-Aktualisierungen';
  @override
  String get checkForUpdates => 'Nach Updates suchen';
  @override
  String updateAvailable(String version) => 'Neue Version verfügbar: $version';
  @override
  String get upToDate => 'Die App ist auf dem neuesten Stand';
  @override
  String get downloadAndInstall => 'Herunterladen & Installieren';
  @override
  String downloadingUpdate(int percent) => 'Update wird heruntergeladen: $percent%';
  @override
  String get updateParentApp => 'Eltern-App aktualisieren';
  @override
  String get updateChildApp => 'Kinder-Tablet aktualisieren';
  @override
  String get updateError => 'Update konnte nicht heruntergeladen werden';
  @override
  String get checkingForUpdates => 'Suche nach Updates...';
  @override
  String get releaseNotes => 'Versionshinweise';
  @override
  String currentVersionLabel(String version) => 'Aktuelle Version: $version';
  @override
  String latestVersionLabel(String version) => 'Neueste Version: $version';
  @override
  String get pushedToChildSuccess => 'Update an Kinder-Tablet gesendet! Wird installiert...';
  @override
  String get parentAppUpdated => 'Installation wird gestartet...';
  @override
  String get installPermissionRequired => "Installationsberechtigung erforderlich. Bitte aktiviere 'Aus dieser Quelle zulassen' in den Einstellungen und tippe erneut auf Aktualisieren.";
  @override
  String get installFailed => "Installation konnte nicht gestartet werden.";
  @override
  String get downloadFailed => 'Update-Datei konnte nicht heruntergeladen werden';
  @override
  String get p2pTransferFailed => 'Update-Übertragung an das Tablet über WLAN fehlgeschlagen';
  @override
  String get triggerTabletDownload => 'Direkt auf dem Tablet herunterladen';
  @override
  String get tabletDownloadTriggered => 'Update-Download auf dem Tablet gestartet';
  @override
  String get webManualDownloadNotice => 'Bitte lade die neueste Release-APK von GitHub herunter:';

  // 5. Screenshot Screen
  @override
  String get liveScreenTitle => 'Live-Bildschirm';
  @override
  String screenshotNotReceived(String error) => 'Screenshot konnte nicht empfangen werden: $error';
  @override
  String get screenshotDeleted => 'Screenshot gelöscht.';
  @override
  String errorDeletingScreenshot(String? error) => error != null && error.isNotEmpty ? 'Fehler beim Löschen: $error' : 'Screenshot konnte nicht gelöscht werden.';
  @override
  String get screenshotNotDeleted => 'Screenshot konnte nicht gelöscht werden.';
  @override
  String get invalidImageFormat => 'Bildformat ungültig';
  @override
  String get imageLoadError => 'Bilddaten konnten nicht geladen werden';
  @override
  String get closeAppTitle => 'App beenden?';
  @override
  String closeAppConfirm(String app) => 'App \'$app\' beenden? Das Gerät des Kindes kehrt sofort zum Startbildschirm zurück.';
  @override
  String get closeAppButton => 'App beenden';
  @override
  String appClosed(String app) => 'App \'$app\' wurde beendet.';
  @override
  String get appCloseFailed => 'App konnte nicht beendet werden. Ist das Gerät erreichbar?';
  @override
  String get lockTabletTitle => 'Tablet-Bildschirm sperren?';
  @override
  String get lockTabletConfirm => 'Möchtest du den Bildschirm des Tablets jetzt sofort ausschalten und sperren?';
  @override
  String get lockNow => 'Jetzt sperren';
  @override
  String get tabletLocked => 'Tablet-Bildschirm wurde gesperrt.';
  @override
  String get tabletLockFailed => 'Bildschirm konnte nicht gesperrt werden. Ist das Gerät online?';
  @override
  String get deleteScreenshotTitle => 'Screenshot löschen?';
  @override
  String deleteScreenshotConfirm(String dt) => 'Möchtest du diese Aufnahme ($dt) wirklich löschen?';
  @override
  String get deleteAllScreenshotsTitle => 'Alle Screenshots löschen?';
  @override
  String deleteAllScreenshotsConfirm(int count) => 'Möchtest du alle $count Aufnahmen wirklich unwiderruflich löschen? Diese Aktion kann nicht rückgängig gemacht werden.';
  @override
  String get deleteAll => 'Alle löschen';
  @override
  String get allScreenshotsDeleted => 'Alle Screenshots wurden gelöscht.';
  @override
  String errorDeletingAllScreenshots(String? error) => error != null && error.isNotEmpty ? 'Fehler beim Löschen aller Screenshots: $error' : 'Screenshots konnten nicht gelöscht werden.';
  @override
  String get cameraLabel => 'Kamera:';
  @override
  String get frontCamera => 'Frontkamera (Standard)';
  @override
  String get backCamera => 'Rückkamera';
  @override
  String get frontCameraShort => 'Frontkamera';
  @override
  String get backCameraShort => 'Rückkamera';
  @override
  String get flashOff => 'Blitz: Aus';
  @override
  String get screenshotSuccess => 'Screenshot erfolgreich empfangen!';
  @override
  String get cameraSuccess => 'Kamera-Foto erfolgreich aufgenommen!';
  @override
  String get running => 'Läuft...';
  @override
  String get captureScreenshot => 'Screenshot';
  @override
  String get takeCameraPhoto => 'Kamera-Foto aufnehmen';
  @override
  String get locking => 'Wird gesperrt...';
  @override
  String get lockScreen => 'Bildschirm sperren';
  @override
  String get firestorePermissionDenied => 'Verbindungs- / Berechtigungs-Hinweis';
  @override
  String get securityRulesUpdateRequired => 'Lokales Netzwerk & Bedienungshilfen prüfen';
  @override
  String get firestorePermissionHelp => 'Keine Verbindung zum Kinder-Tablet über LAN. Bitte prüfe:';
  @override
  String get localFirstDiagnosisTitle => 'Verbindungs- / Berechtigungs-Hinweis';
  @override
  String get localFirstDiagnosisHelp => 'Keine Verbindung zum Kinder-Tablet über LAN. Bitte prüfe:';
  @override
  String get localFirstDiagnosisSteps => '1. Beide Geräte sind im selben WLAN verbunden.\n2. Tablet-Bildschirm ist an und entsperrt.\n3. Bedienungshilfen-Dienst ist in den Tablet-Einstellungen aktiviert.';
  @override
  String get accessibilityServiceRequired => 'Screenshot fehlgeschlagen: Auf dem Kinder-Gerät muss der Bedienungshilfen-Dienst (Accessibility) aktiviert sein.';
  @override
  String get noScreenshotYet => 'Noch kein Screenshot vorhanden';
  @override
  String get noScreenshotDesc => 'Tippe auf den Button oben, um den aktuellen Bildschirm des Kindes in Echtzeit abzurufen.';
  @override
  String get cameraBackLabel => '📷 Rück-Kamera';
  @override
  String get cameraFrontLabel => '📷 Front-Kamera';
  @override
  String get screenLabel => '📱 Bildschirm';
  @override
  String get zoom => 'Vergrößern';
  @override
  String activeApp(String app) => 'Aktive App: $app';
  @override
  String get closingApp => 'Wird beendet...';
  @override
  String get closeAppImmediate => 'App sofort beenden';
  @override
  String get lockingTablet => 'Wird gesperrt...';
  @override
  String get lockTablet => 'Tablet sperren';
  @override
  String historyCount(int count) => 'Verlauf ($count)';
  @override
  String get deletingAll => 'Wird gelöscht...';
  @override
  String get newBadge => 'NEU';

  // 6. App Limits Screen
  @override
  String get appLimitsTitle => 'App-Limits & Sperren';
  @override
  String appBlockedInstant(String name) => '„$name“ wurde sofort gesperrt.';
  @override
  String appUnblocked(String name) => '„$name“ wurde entsperrt.';
  @override
  String bonusAdded(int min, String category) => '+$min Min. Bonus für „$category“ hinzugefügt!';
  @override
  String get bonusSyncFailed => 'Bonus konnte nicht synchronisiert werden.';
  @override
  String categorySaved(String name) => 'Kategorie „$name“ erfolgreich gespeichert.';
  @override
  String get categorySaveFailed => 'Kategorie konnte nicht gespeichert werden.';
  @override
  String get deleteCategoryTitle => 'Kategorie löschen?';
  @override
  String deleteCategoryConfirm(String name) => 'Möchtest du die Kategorie „$name“ wirklich entfernen? Die zugewiesenen Apps haben dann kein gemeinsames Gruppen-Limit mehr.';
  @override
  String categoryDeleted(String name) => 'Kategorie „$name“ gelöscht.';
  @override
  String get categoryDeleteFailed => 'Kategorie konnte nicht gelöscht werden.';
  @override
  String tabBlacklist(int count) => 'Sofort-Sperre ($count)';
  @override
  String tabCategories(int count) => 'Zeit-Kategorien ($count)';
  @override
  String get blacklistBanner => 'Apps in dieser Liste werden auf dem Tablet sofort blockiert und schließen sich automatisch beim Öffnen.';
  @override
  String blockedApps(int count) => 'Blockierte Apps ($count)';
  @override
  String get blockApp => 'App sperren';
  @override
  String get noAppsBlocked => 'Keine Apps gesperrt';
  @override
  String get noAppsBlockedDesc => 'Derzeit sind keine Apps komplett gesperrt. Sperre hier gezielt unerwünschte Spiele oder Apps.';
  @override
  String get addAppToBlacklist => 'App zur Sperrliste hinzufügen';
  @override
  String get statusBlocked => 'Gesperrt';
  @override
  String get unblock => 'Entsperren';
  @override
  String timeCategoriesHeader(int count) => 'Zeit-Kategorien ($count)';
  @override
  String get newCategory => 'Neue Kategorie';
  @override
  String get noCategoriesYet => 'Noch keine Zeit-Kategorien';
  @override
  String get noCategoriesDesc => 'Erstelle Gruppen wie „Spiele“ oder „Videos“ mit gemeinsamem Tageslimit und Bonusminuten.';
  @override
  String get createFirstCategory => 'Erste Kategorie anlegen';
  @override
  String get dailyLimit => 'Tageslimit';
  @override
  String get bonusToday => 'Bonus heute';
  @override
  String get assignedApps => 'Zugewiesene Apps';
  @override
  String get noAppsInGroup => 'Noch keine Apps in dieser Gruppe';
  @override
  String get add15MinBonus => '+15 Min.';
  @override
  String get add30MinBonus => '+30 Min.';
  @override
  String get editCategory => 'Kategorie bearbeiten';
  @override
  String get newTimeCategory => 'Neue Zeit-Kategorie';
  @override
  String get categoryNameLabel => 'Kategorie-Name (z.B. Spiele)';
  @override
  String get categoryNameValidator => 'Bitte einen Namen eingeben';
  @override
  String get dailyLimitMinutesLabel => 'Tageslimit in Minuten';
  @override
  String get validNumberValidator => 'Bitte eine gültige Zahl eingeben';
  @override
  String get selectAppsForCategory => 'Apps für diese Kategorie auswählen:';
  @override
  String get noInstalledAppsFound => 'Keine Apps gefunden (oder Kinder-Tablet offline)';
  @override
  String get searchApps => 'Apps durchsuchen...';
  @override
  String get saveCategoryButton => 'Kategorie speichern';
  @override
  String appUnblockConfirm(String name) => 'Möchtest du „$name“ wirklich entsperren?';
  @override
  String get tabAppHistory => 'Historie';
  @override
  String get appHistoryTitle => 'App-Öffnungsverlauf';
  @override
  String get appHistorySubtitle => 'App-Starts der letzten 5 Tage auf diesem Tablet';
  @override
  String get noAppHistory => 'Keine App-Aktivitäten in den letzten 5 Tagen aufgezeichnet.';
  @override
  String get availableApps => 'Verfügbare Apps auf dem Tablet';
  @override
  String get availableAppsDesc => 'Tippe auf Sperren, um eine App direkt zu blockieren.';
  @override
  String get searchAvailableApps => 'Verfügbare Apps filtern...';
  @override
  String get switchKid => 'Kind wechseln';
  @override
  String get addKid => 'Kind hinzufügen';

  // 7. Bedtime Schedule Screen
  @override
  String get bedtimeTitle => 'WLAN-Nachtruhe';
  @override
  String get scheduleSaved => 'WLAN-Zeitplan erfolgreich gespeichert';
  @override
  String get scheduleSaveFailed => 'Zeitplan konnte nicht gespeichert werden';
  @override
  String get wifiBlockedInstant => 'WLAN wurde sofort gesperrt';
  @override
  String get wifiUnblockedInstant => 'WLAN wurde wieder freigegeben';
  @override
  String get setBedtime => 'Schlafenszeit festlegen';
  @override
  String get setWakeupTime => 'Aufstehzeit festlegen';
  @override
  String get apply => 'Übernehmen';
  @override
  String get wifiBlockedStatus => 'WLAN ist gesperrt';
  @override
  String get wifiActiveStatus => 'WLAN ist aktiv';
  @override
  String get wifiBlockedDesc => 'Die WLAN-Verbindung des Kindergeräts ist derzeit blockiert.';
  @override
  String get wifiActiveDesc => 'Das Kind hat uneingeschränkten Zugriff auf das WLAN-Netzwerk.';
  @override
  String get turnWifiOnNow => 'WLAN jetzt einschalten';
  @override
  String get turnWifiOffNow => 'WLAN jetzt ausschalten';
  @override
  String get autoControlBedtime => 'WLAN-Nachtruhe automatisch steuern';
  @override
  String get autoControlBedtimeDesc => 'WLAN zu festgelegten Uhrzeiten kappen';
  @override
  String get scheduleTimes => 'Uhrzeiten';
  @override
  String get bedtimeOff => 'Schlafenszeit (WLAN Aus)';
  @override
  String get wakeupOn => 'Aufstehzeit (WLAN An)';
  @override
  String get activeWeekdays => 'Aktive Wochentage';
  @override
  String get schoolDaysPreset => 'Schultage (Mo–Fr)';
  @override
  String get everyDayPreset => 'Jeden Tag';
  @override
  String get dayMo => 'Mo';
  @override
  String get dayDi => 'Di';
  @override
  String get dayMi => 'Mi';
  @override
  String get dayDo => 'Do';
  @override
  String get dayFr => 'Fr';
  @override
  String get daySa => 'Sa';
  @override
  String get daySo => 'So';
  @override
  String get daysSummaryNoDays => 'Keine Tage';
  @override
  String get daysSummaryEveryDay => 'Jeden Tag';
  @override
  String get daysSummarySchoolDays => 'Schultage (Mo–Fr)';
  @override
  String get daysSummaryMonToFri => 'Montag – Freitag';
  @override
  String get daysSummaryWeekend => 'Wochenende (Fr–Sa)';
  @override
  String get timeUnit => ' Uhr';

  // 8. Time Bank Screens
  @override
  String get timeBankTitle => 'Zeitkonto';
  @override
  String get awardCoinsTitle => 'Coins vergeben ⏳';
  @override
  String get quickSelect => 'Schnellauswahl:';
  @override
  String get reasonLabel => 'Grund (z.B. 30 Min gelesen)';
  @override
  String get enterReasonValidator => 'Bitte einen Grund eingeben';
  @override
  String get selectIcon => 'Symbol wählen:';
  @override
  String get awardButton => 'Vergeben ✓';
  @override
  String coinsAwarded(int count) => '$count Coins erfolgreich vergeben!';
  @override
  String get activated => 'Aktiviert';
  @override
  String get deactivated => 'Deaktiviert';
  @override
  String get visibleForChild => 'Sichtbar für Kind';
  @override
  String get hiddenForChild => 'Versteckt für Kind';
  @override
  String get timeCoins => 'Time Coins ⏳';
  @override
  String get awardCoins => 'Coins vergeben';
  @override
  String get tasksAndRewards => 'Aufgaben & Bel.';
  @override
  String get pendingClaims => 'Offene Auszahlungen';
  @override
  String costCoins(int cost) => 'Kosten: $cost Coins ⏳';
  @override
  String get doneButton => 'Erledigt ✓';
  @override
  String rewardFulfilled(String title) => 'Belohnung "$title" freigegeben.';
  @override
  String get todayActivity => 'Aktivitäten von heute';
  @override
  String get historyButton => 'Verlauf 📊';
  @override
  String get noTransactionsToday => 'Heute noch keine Buchungen.';
  @override
  String get timeBankSettingsTitle => 'Einstellungen';
  @override
  String get timeBankSettingsInfo => 'Richten Sie hier das Belohnungssystem ein. Das Kind verdient Coins für Aufgaben und kann diese gegen Belohnungen eintauschen.';
  @override
  String get enableTimeBank => 'Zeitkonto aktivieren';
  @override
  String get enableTimeBankDesc => 'Schaltet das Münzsystem und das Eintragen von Transaktionen/Aufgaben frei.';
  @override
  String get visibleToChildTitle => 'Für Kind sichtbar';
  @override
  String get visibleToChildDesc => 'Wenn diese Option aktiviert ist, kann das Kind sein Guthaben, Aufgaben und den Shop in der eigenen App einsehen. Wenn sie deaktiviert ist, bleibt das Feature für das Kind komplett unsichtbar.';
  @override
  String get activityHistoryTitle => 'Aktivitätsverlauf';
  @override
  String get todayFilter => 'Heute';
  @override
  String get weekFilter => 'Woche';
  @override
  String get monthFilter => 'Monat';
  @override
  String get earned => 'Verdient';
  @override
  String get spent => 'Ausgegeben';
  @override
  String get noActivitiesPeriod => 'Keine Aktivitäten in diesem Zeitraum.';
  @override
  String get tasksAndRewardsTitle => 'Aufgaben & Belohnungen';
  @override
  String get createTaskTitle => 'Neue Aufgabe erstellen';
  @override
  String get taskTitleLabel => 'Titel (z.B. Zimmer aufräumen)';
  @override
  String get enterTitleValidator => 'Bitte einen Titel eingeben';
  @override
  String get rewardCoinsLabel => 'Belohnung (Coins)';
  @override
  String get withTimerMinutes => 'Mit Timer (Minuten):';
  @override
  String get durationMinutesLabel => 'Dauer in Minuten';
  @override
  String get enterMinutesValidator => 'Bitte eine gültige Minutenzahl eingeben';
  @override
  String get addButton => 'Hinzufügen';
  @override
  String get createRewardTitle => 'Neue Belohnung erstellen';
  @override
  String get rewardTitleLabel => 'Titel (z.B. 1 Std. Minecraft)';
  @override
  String get costCoinsLabel => 'Kosten (Coins)';
  @override
  String get tasksTab => 'Aufgaben 🌟';
  @override
  String get rewardsTab => 'Belohnungen 🎁';
  @override
  String get noTasksYet => 'Noch keine Aufgaben erstellt.';
  @override
  String get addTaskButton => 'Aufgabe hinzufügen';
  @override
  String timerTaskSubtitle(int dur, int rew) => 'Timer: $dur Min | +$rew Coins';
  @override
  String instantTaskSubtitle(int rew) => 'Direkt | +$rew Coins';
  @override
  String get noRewardsYet => 'Noch keine Belohnungen erstellt.';
  @override
  String get addRewardButton => 'Belohnung hinzufügen';

  // 9. Comms Screen
  @override
  String get walkieTalkieTitle => 'Walkie-Talkie Comms';
  @override
  String get missedCallTitle => 'Verpasster Walkie-Talkie Anruf';
  @override
  String get channelSimulatedActive => 'Simulierter Kanal Aktiv';
  @override
  String get channelReady => 'Kanal Bereit';
  @override
  String get holdToTalk => 'DRÜCKEN & HALTEN';
  @override
  String get talking => 'SPRECHEN...';
  @override
  String get audioStreaming => '🎙️ Audio wird übertragen...';
  @override
  String get walkieTalkieRules => 'WALKIE-TALKIE REGELN';
  @override
  String get autoPlayVoiceTitle => 'Direkt beim Kind abspielen';
  @override
  String get autoPlayVoiceSubtitle => 'Audio wird sofort über Lautsprecher abgespielt ohne anzuklopfen.';
  @override
  String get childCanInitiateTitle => 'Kind darf Anruf starten';
  @override
  String get childCanInitiateSubtitle => 'Erlaubt dem Kind, die Walkie-Talkie Verbindung über sein Widget zu initiieren.';

  // 10. Call History & Chat Messages
  @override
  String get callHistoryTitle => 'Anrufprotokoll';
  @override
  String get chatMessagesTitle => 'Chat-Nachrichten';
  @override
  String get allCalls => 'Alle';
  @override
  String get incomingCalls => 'Eingehend';
  @override
  String get outgoingCalls => 'Ausgehend';
  @override
  String get missedCalls => 'Verpasst';
  @override
  String get allApps => 'Alle Apps';
  @override
  String get appWhatsApp => 'WhatsApp';
  @override
  String get appSms => 'SMS / Nachrichten';
  @override
  String get appTelegram => 'Telegram';
  @override
  String get appSignal => 'Signal';
  @override
  String get syncNow => 'Jetzt synchronisieren';
  @override
  String get syncing => 'Synchronisiere...';
  @override
  String get syncSuccess => 'Protokolle erfolgreich synchronisiert';
  @override
  String get syncFailed => 'Synchronisierung fehlgeschlagen';
  @override
  String get noCallsFound => 'Keine Anrufe gefunden';
  @override
  String get noChatsFound => 'Keine Chat-Nachrichten gefunden';
  @override
  String get searchCallsPlaceholder => 'Nach Name oder Nummer suchen...';
  @override
  String get searchChatsPlaceholder => 'Nachrichten oder Kontakte suchen...';
  @override
  String callDurationFormat(int seconds) {
    if (seconds <= 0) return '0 Sek.';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return s > 0 ? '$m Min. $s Sek.' : '$m Min.';
    }
    return '$s Sek.';
  }
  @override
  String get incomingLabel => 'Eingehend';
  @override
  String get outgoingLabel => 'Ausgehend';
  @override
  String get missedLabel => 'Verpasst';
  @override
  String get rejectedLabel => 'Abgelehnt';
  @override
  String get offlineNotice => 'Offline • Gespeicherte Daten';
  @override
  String lastSyncedLabel(String time) => 'Zuletzt synchronisiert: $time';
  @override
  String get neverSynced => 'Noch nicht synchronisiert';
  @override
  String get conversationsTitle => 'Unterhaltungen';
  @override
  String chatDetailTitle(String name) => 'Chat mit $name';
  @override
  String get noMessagesInChat => 'Keine Nachrichten in diesem Chat';
  @override
  String get today => 'Heute';
  @override
  String get yesterday => 'Gestern';
}
