/// SHA-512, implemented here rather than imported.
///
/// Every one of the 51 pinned artifacts carries an SRI `sha512-` integrity hash, and
/// verifying them is the thing that stands between the corpus and a silently substituted
/// upstream — it is what caught `www2.census.gov` answering HTTP 200 with a 247-byte
/// rejection page where a 12 MB zip should have been.
///
/// Swift offers CryptoKit on Apple platforms only. Linux and Windows would need
/// swift-crypto, which would be this package's **first external dependency**, against a
/// manifest that declares none and a README that leads with it. Two hundred lines of a
/// fully specified, fixed-shape algorithm is a smaller cost than that, and unlike a
/// dependency it can be proved correct: `SHA512Tests` checks it against the NIST vectors,
/// including the multi-block and length-edge cases where a hand-rolled implementation
/// actually goes wrong.
///
/// FIPS 180-4, section 6.4.
public struct SHA512 {

    /// Section 4.2.3 — the first 64 bits of the fractional parts of the cube roots of the
    /// first eighty primes.
    private static let k: [UInt64] = [
        0x428A_2F98_D728_AE22, 0x7137_4491_23EF_65CD, 0xB5C0_FBCF_EC4D_3B2F,
        0xE9B5_DBA5_8189_DBBC, 0x3956_C25B_F348_B538, 0x59F1_11F1_B605_D019,
        0x923F_82A4_AF19_4F9B, 0xAB1C_5ED5_DA6D_8118, 0xD807_AA98_A303_0242,
        0x1283_5B01_4570_6FBE, 0x2431_85BE_4EE4_B28C, 0x550C_7DC3_D5FF_B4E2,
        0x72BE_5D74_F27B_896F, 0x80DE_B1FE_3B16_96B1, 0x9BDC_06A7_25C7_1235,
        0xC19B_F174_CF69_2694, 0xE49B_69C1_9EF1_4AD2, 0xEFBE_4786_384F_25E3,
        0x0FC1_9DC6_8B8C_D5B5, 0x240C_A1CC_77AC_9C65, 0x2DE9_2C6F_592B_0275,
        0x4A74_84AA_6EA6_E483, 0x5CB0_A9DC_BD41_FBD4, 0x76F9_88DA_8311_53B5,
        0x983E_5152_EE66_DFAB, 0xA831_C66D_2DB4_3210, 0xB003_27C8_98FB_213F,
        0xBF59_7FC7_BEEF_0EE4, 0xC6E0_0BF3_3DA8_8FC2, 0xD5A7_9147_930A_A725,
        0x06CA_6351_E003_826F, 0x1429_2967_0A0E_6E70, 0x27B7_0A85_46D2_2FFC,
        0x2E1B_2138_5C26_C926, 0x4D2C_6DFC_5AC4_2AED, 0x5338_0D13_9D95_B3DF,
        0x650A_7354_8BAF_63DE, 0x766A_0ABB_3C77_B2A8, 0x81C2_C92E_47ED_AEE6,
        0x9272_2C85_1482_353B, 0xA2BF_E8A1_4CF1_0364, 0xA81A_664B_BC42_3001,
        0xC24B_8B70_D0F8_9791, 0xC76C_51A3_0654_BE30, 0xD192_E819_D6EF_5218,
        0xD699_0624_5565_A910, 0xF40E_3585_5771_202A, 0x106A_A070_32BB_D1B8,
        0x19A4_C116_B8D2_D0C8, 0x1E37_6C08_5141_AB53, 0x2748_774C_DF8E_EB99,
        0x34B0_BCB5_E19B_48A8, 0x391C_0CB3_C5C9_5A63, 0x4ED8_AA4A_E341_8ACB,
        0x5B9C_CA4F_7763_E373, 0x682E_6FF3_D6B2_B8A3, 0x748F_82EE_5DEF_B2FC,
        0x78A5_636F_4317_2F60, 0x84C8_7814_A1F0_AB72, 0x8CC7_0208_1A64_39EC,
        0x90BE_FFFA_2363_1E28, 0xA450_6CEB_DE82_BDE9, 0xBEF9_A3F7_B2C6_7915,
        0xC671_78F2_E372_532B, 0xCA27_3ECE_EA26_619C, 0xD186_B8C7_21C0_C207,
        0xEADA_7DD6_CDE0_EB1E, 0xF57D_4F7F_EE6E_D178, 0x06F0_67AA_7217_6FBA,
        0x0A63_7DC5_A2C8_98A6, 0x113F_9804_BEF9_0DAE, 0x1B71_0B35_131C_471B,
        0x28DB_77F5_2304_7D84, 0x32CA_AB7B_40C7_2493, 0x3C9E_BE0A_15C9_BEBC,
        0x431D_67C4_9C10_0D4C, 0x4CC5_D4BE_CB3E_42B6, 0x597F_299C_FC65_7E2A,
        0x5FCB_6FAB_3AD6_FAEC, 0x6C44_198C_4A47_5817,
    ]

    /// Section 5.3.5 — the fractional parts of the square roots of the first eight primes.
    private static let initial: [UInt64] = [
        0x6A09_E667_F3BC_C908, 0xBB67_AE85_84CA_A73B, 0x3C6E_F372_FE94_F82B,
        0xA54F_F53A_5F1D_36F1, 0x510E_527F_ADE6_82D1, 0x9B05_688C_2B3E_6C1F,
        0x1F83_D9AB_FB41_BD6B, 0x5BE0_CD19_137E_2179,
    ]

    /// The digest of `bytes`, as 64 bytes.
    public static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var state = initial

        // Section 5.1.2: append 0x80, then zeroes until the length ends 128 bytes, then the
        // message length in bits as a 128-bit big-endian integer. The high 64 bits are
        // always zero here: reaching them needs an artifact of two exabytes.
        var message = bytes
        message.append(0x80)
        while message.count % 128 != 112 { message.append(0) }
        let bitCount = UInt64(bytes.count) &* 8
        message.append(contentsOf: [UInt8](repeating: 0, count: 8))
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
        }

        for start in stride(from: 0, to: message.count, by: 128) {
            var w = [UInt64](repeating: 0, count: 80)
            for i in 0..<16 {
                var word: UInt64 = 0
                for byte in 0..<8 {
                    word = (word << 8) | UInt64(message[start + i * 8 + byte])
                }
                w[i] = word
            }
            for i in 16..<80 {
                let s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7)
                let s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var (a, b, c, d) = (state[0], state[1], state[2], state[3])
            var (e, f, g, h) = (state[4], state[5], state[6], state[7])

            for i in 0..<80 {
                let s1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                h = g; g = f; f = e
                e = d &+ temp1
                d = c; c = b; b = a
                a = temp1 &+ temp2
            }

            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
        }

        var digest = [UInt8]()
        digest.reserveCapacity(64)
        for word in state {
            for shift in stride(from: 56, through: 0, by: -8) {
                digest.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
        return digest
    }

    private static func rotr(_ value: UInt64, _ by: UInt64) -> UInt64 {
        (value >> by) | (value << (64 - by))
    }
}
