import Testing

@testable import Decoy

@Test("package builds and exposes a version")
func version() {
    #expect(!Decoy.version.isEmpty)
}
