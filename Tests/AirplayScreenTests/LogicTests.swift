import Testing
@testable import AirplayScreen

@Suite struct LogicTests {
    @Test func mirroringBit() {
        #expect(supportsMirroring(features: "0x7F8AD0,0xBCF46"))        // a TV
        #expect(supportsMirroring(features: "0x4A7FCFD5,0x38174FDE"))   // a Mac
        #expect(!supportsMirroring(features: "0x4A7FCA00,0x3C356BD0"))  // a speaker
        #expect(!supportsMirroring(features: nil))
        #expect(!supportsMirroring(features: "garbage"))
    }

    @Test func displayName() {
        #expect(airPlayDisplayName("Living Room (AirPlay)") == "Living Room")
        #expect(airPlayDisplayName("Built-in Retina Display") == nil)
    }

    @Test func resolveChoiceByNumberOrName() {
        let names = ["marBook", "Telek"]
        #expect(resolveChoice("2", from: names) == "Telek")
        #expect(resolveChoice(" telek ", from: names) == "Telek")
        #expect(resolveChoice("3", from: names) == nil)
        #expect(resolveChoice("0", from: names) == nil)
        #expect(resolveChoice("nope", from: names) == nil)
    }
}
