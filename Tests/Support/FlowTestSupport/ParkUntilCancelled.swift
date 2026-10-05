/// Suspends until the surrounding task is cancelled.
///
/// A sleep this long never elapses; cancellation is what ends it. Use it as the
/// body of a producer that must stay open until the test cancels it.
package func parkUntilCancelled() async {
    try? await Task.sleep(for: .seconds(1 << 40))
}
