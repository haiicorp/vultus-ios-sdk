import Foundation

/// 측정 meta 의 `appendix` 에 실을 설치 식별자. `XXXX-XXXX` 형태의 9자다.
///
/// **기기 식별자가 아니다.** 앱이 처음 실행될 때 만든 40비트 난수를 `UserDefaults` 에
/// 저장해 재사용하며, 앱을 지우면 함께 사라진다. `identifierForVendor` 처럼 시스템이
/// 주는 값을 쓰지 않는 이유가 여기 있다 — 같은 사람이 여러 번 잰 측정을 묶고 원격
/// 지원에서 서로를 가리키는 데는 이걸로 충분하고, 그 이상을 식별할 필요가 없다.
///
/// **화면에 뜨는 값과 `appendix` 로 나가는 값이 같다.** 표시만 줄이면 사용자가 읽어
/// 준 번호로 서버 기록을 찾지 못하는 일이 생긴다.
///
/// > `appendix` 에 담는 값은 **앱의 개인정보 신고 대상**이다. SDK 의
/// > `PrivacyInfo.xcprivacy` 는 SDK 가 보내는 것만 신고한다.
enum InstallationId {
    /// 저장 키.
    private static let key = "installation_id_v2"

    /// Crockford Base32. `I` `L` `O` `U` 가 빠져 있어 1/0 과 헷갈리지 않고 우연히
    /// 단어가 만들어지지도 않는다. 전화로 불러 주기 좋다.
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static let current: String = {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: key) {
            return saved
        }
        let generated = generate()
        defaults.set(generated, forKey: key)
        return generated
    }()

    /// 40비트 난수 → Base32 8자 → `XXXX-XXXX`.
    ///
    /// 40비트면 약 1.1조 가지다. 원격 지원에서 서로를 가리기에 충분하다.
    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 5)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<5).map { _ in UInt8.random(in: .min ... .max) }
        }

        var bits: UInt64 = 0
        for byte in bytes { bits = (bits << 8) | UInt64(byte) }

        var chars = [Character](repeating: "0", count: 8)
        for i in stride(from: 7, through: 0, by: -1) {
            chars[i] = alphabet[Int(bits & 0x1F)]
            bits >>= 5
        }
        return String(chars[0..<4]) + "-" + String(chars[4..<8])
    }
}
