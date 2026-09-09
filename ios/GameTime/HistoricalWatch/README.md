# Historical Watch prototype — inert

The September 9 Beta contract removes the dedicated GameTime watchOS app and
WatchConnectivity from every active product configuration. These unchanged
coordinator, handshake-test and scheme files are retained as history, outside
all active Xcode target/scheme directories. The original Watch app and shared
handshake source remain in the adjacent `GameTimeWatch` and `GameTimeWatchShared`
directories, also outside target membership. Do not restore them to build, test,
launch or embed a Beta companion.

The iPhone keeps HealthKit. Apple Watch records activity into Apple Health;
accepted Watch-origin reading and minimum normalized upload remain separately
versioned source work. See [the current contract](../../../docs/BETA_REMAINING_WORK_CONTRACT.md).
