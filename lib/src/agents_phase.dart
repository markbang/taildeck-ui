import 'herdr.dart';

/// What the Agents page draws. The tailnet node comes up before herdr is
/// dialed, so the page never shows a dial error for a dial it could not make.
enum AgentsPhase {
  /// The tailnet node is not Running with its peer table read yet.
  tailnet,

  /// A dial (with its retries) is in flight.
  connecting,

  /// herdr answered; the list is live.
  ready,

  /// The last dial failed: a human sentence and Retry.
  failed,

  /// Signed in with a saved target, herdr not connected.
  idle,

  /// No target saved yet: first setup.
  setup,
}

AgentsPhase agentsPhaseOf({
  required bool herdrReady,
  required bool waking,
  required HerdrLink link,
  required bool tailnetReady,
  required bool hasTarget,
  required bool staleFailure,
}) {
  if (herdrReady) return AgentsPhase.ready;
  if (waking || link == HerdrLink.connecting) return AgentsPhase.connecting;
  if (!tailnetReady) return AgentsPhase.tailnet;
  return switch (link) {
    // A failure no dial of this visit made belongs to an earlier attempt: the
    // page wakes the target and shows progress, never another attempt's error.
    HerdrLink.failed || HerdrLink.notInstalled || HerdrLink.notRunning =>
      staleFailure
          ? (hasTarget ? AgentsPhase.connecting : AgentsPhase.setup)
          : AgentsPhase.failed,
    HerdrLink.unavailable => AgentsPhase.tailnet,
    _ => hasTarget ? AgentsPhase.idle : AgentsPhase.setup,
  };
}
