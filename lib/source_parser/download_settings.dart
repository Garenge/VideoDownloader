class DownloadSettings {
  const DownloadSettings({
    required this.enableYtDlpFallback,
    required this.ytDlpConcurrency,
    required this.ytDlpRetries,
    required this.ytDlpFragmentRetries,
  });

  const DownloadSettings.defaults()
    : enableYtDlpFallback = true,
      ytDlpConcurrency = 8,
      ytDlpRetries = 10,
      ytDlpFragmentRetries = 50;

  final bool enableYtDlpFallback;
  final int ytDlpConcurrency;
  final int ytDlpRetries;
  final int ytDlpFragmentRetries;

  DownloadSettings copyWith({
    bool? enableYtDlpFallback,
    int? ytDlpConcurrency,
    int? ytDlpRetries,
    int? ytDlpFragmentRetries,
  }) {
    return DownloadSettings(
      enableYtDlpFallback: enableYtDlpFallback ?? this.enableYtDlpFallback,
      ytDlpConcurrency: ytDlpConcurrency ?? this.ytDlpConcurrency,
      ytDlpRetries: ytDlpRetries ?? this.ytDlpRetries,
      ytDlpFragmentRetries: ytDlpFragmentRetries ?? this.ytDlpFragmentRetries,
    );
  }

  static DownloadSettings fromJson(Map<String, Object?> json) {
    final defaults = const DownloadSettings.defaults();
    return DownloadSettings(
      enableYtDlpFallback:
          json['enableYtDlpFallback'] is bool
              ? json['enableYtDlpFallback'] as bool
              : defaults.enableYtDlpFallback,
      ytDlpConcurrency: _readInt(json['ytDlpConcurrency']) ??
          defaults.ytDlpConcurrency,
      ytDlpRetries: _readInt(json['ytDlpRetries']) ?? defaults.ytDlpRetries,
      ytDlpFragmentRetries: _readInt(json['ytDlpFragmentRetries']) ??
          defaults.ytDlpFragmentRetries,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enableYtDlpFallback': enableYtDlpFallback,
      'ytDlpConcurrency': ytDlpConcurrency,
      'ytDlpRetries': ytDlpRetries,
      'ytDlpFragmentRetries': ytDlpFragmentRetries,
    };
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class DownloadToolStatus {
  const DownloadToolStatus({
    required this.ytDlpAvailable,
    required this.ffmpegAvailable,
    this.externalCommandBlocked = false,
    this.externalCommandBlockReason,
    this.ytDlpVersion,
    this.ffmpegVersion,
    this.checkedAt,
  });

  const DownloadToolStatus.unknown()
    : ytDlpAvailable = false,
      ffmpegAvailable = false,
      externalCommandBlocked = false,
      externalCommandBlockReason = null,
      ytDlpVersion = null,
      ffmpegVersion = null,
      checkedAt = null;

  final bool ytDlpAvailable;
  final bool ffmpegAvailable;
  final bool externalCommandBlocked;
  final String? externalCommandBlockReason;
  final String? ytDlpVersion;
  final String? ffmpegVersion;
  final DateTime? checkedAt;

  DownloadToolStatus copyWith({
    bool? ytDlpAvailable,
    bool? ffmpegAvailable,
    bool? externalCommandBlocked,
    String? externalCommandBlockReason,
    String? ytDlpVersion,
    String? ffmpegVersion,
    DateTime? checkedAt,
  }) {
    return DownloadToolStatus(
      ytDlpAvailable: ytDlpAvailable ?? this.ytDlpAvailable,
      ffmpegAvailable: ffmpegAvailable ?? this.ffmpegAvailable,
      externalCommandBlocked:
          externalCommandBlocked ?? this.externalCommandBlocked,
      externalCommandBlockReason:
          externalCommandBlockReason ?? this.externalCommandBlockReason,
      ytDlpVersion: ytDlpVersion ?? this.ytDlpVersion,
      ffmpegVersion: ffmpegVersion ?? this.ffmpegVersion,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }
}

