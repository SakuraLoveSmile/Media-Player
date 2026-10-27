/// Error taxonomy shared by the data layer and the UI (contract §6).
///
/// UI must map each code to user-facing text; raw exceptions never reach the
/// screen and tokens never reach the logs.
enum AppErrorCode {
  networkUnreachable,
  tlsUntrusted,
  unauthorized,
  forbidden,
  notFound,
  serverError,

  /// A second address resolved to a different server than the stored profile.
  /// Added in contract v1.1 §6 during B3.
  serverMismatch,
  directPlayDenied,
  playbackUnsupported,
  transcodeFailed,
  subtitleFailed;

  /// Whether retrying the same operation can plausibly succeed.
  bool get retryable => switch (this) {
        AppErrorCode.networkUnreachable ||
        AppErrorCode.serverError ||
        AppErrorCode.transcodeFailed =>
          true,
        _ => false,
      };
}
