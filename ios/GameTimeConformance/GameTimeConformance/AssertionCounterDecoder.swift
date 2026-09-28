import GameTimeCore

// The harness decodes assertion counters with GameTimeCore's bounded production
// decoder, `AssertionCounterDecoder`, used by its plain name. A local alias
// can't name it: in `GameTimeCore.AssertionCounterDecoder`, the module's
// `GameTimeCore` enum hides the module.
