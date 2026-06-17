import XCTest
@testable import DetectionCore

final class DetectionEngineTests: XCTestCase {
    private let engine = DetectionEngine()

    override func setUp() {
        super.setUp()
        CustomDictionaryRuleCache.resetForTesting()
    }

    func testDetectsEmailPhoneMoneyURLAndContract() async {
        let text = "Contact ivan@acme.com at +1 415 555 1212 for CN-4812 worth $80,000. See https://example.com and portal.acme.internal"
        let result = await engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.email))
        XCTAssertTrue(types.contains(.phone))
        XCTAssertTrue(types.contains(.money))
        XCTAssertTrue(types.contains(.contractId))
        XCTAssertTrue(types.contains(.url))
        XCTAssertTrue(types.contains(.internalDomain))
    }

    func testDetectsSecretPatterns() async {
        let text = "OPENAI sk-abcdefghijklmnopqrstuvwxyzABCDEF123456 and jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature"
        let result = await engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.openAIAPIKey))
        XCTAssertTrue(types.contains(.jwt))
    }

    func testDetectsProviderServiceKeysAsCriticalSecrets() async {
        // (label, token) — all map to `.apiKeyGeneric` (a critical secret) via their provider prefix.
        let cases: [(String, String)] = [
            ("groq", "gsk_012345678901234567890123456789"),
            ("xai", "xai-012345678901234567890123456789"),
            ("google", "AIza01234567890123456789012345678901234"),
            ("supabasePAT", "sbp_0123456789abcdef0123456789abcdef01234567"),
            ("supabaseSecret", "sb_secret_0123456789abcdefABCDEF01"),
            ("resend", "re_AbCdEf12_0123456789abcdef"),
            ("linear", "lin_api_012345678901234567890123456789"),
            ("vercelBlob", "vercel_blob_rw_012345678901234567_012345678901234567"),
            ("gitlab", "glpat-012345678901234567890123"),
            ("huggingface", "hf_012345678901234567890123456789abcd"),
            ("sendgrid", "SG.0123456789012345678901.0123456789012345678901234567890123456789012"),
            ("npm", "npm_012345678901234567890123456789abcdef"),
            ("doppler", "dp.pt.0123456789012345678901234567890123456789"),
        ]
        for (label, token) in cases {
            let result = await engine.scan(DetectionRequest(text: "key = \(token)"))
            XCTAssertTrue(
                result.entities.contains { $0.type == .apiKeyGeneric && $0.value == token },
                "\(label): expected apiKeyGeneric for \(token), got: \(result.entities.map { ($0.type, $0.value) })"
            )
        }
    }

    func testDetectsAnthropicKeyAsCriticalSecret() async {
        let token = "sk-ant-api03-012345678901234567890123456789"
        let result = await engine.scan(DetectionRequest(text: "ANTHROPIC_API_KEY=\(token)"))
        XCTAssertTrue(
            result.entities.contains { $0.type.countsAsCriticalSecret },
            "Anthropic key must flag as a critical secret, got: \(result.entities.map(\.type))"
        )
    }

    func testSwiftClosureDollarDigitsNotDetectedAsMoney() async {
        let text =
            #"let cursedColor = (([0xDEADBEEF].enumerated().reduce(CGFloat(0)) { $0 + CGFloat(($1.element >> ($1.offset * 8)) & 0xFF) / 255.0 })"#
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(
            result.entities.contains { $0.type == .money },
            "Expected no money from Swift `$0` / `$1`, got: \(result.entities.map(\.type))"
        )
    }

    func testDetectsMultiDigitDollarAmounts() async {
        let text = "Pay $50 today and $1,200 tomorrow"
        let result = await engine.scan(DetectionRequest(text: text))
        let money = result.entities.filter { $0.type == .money }.map(\.value).sorted()
        XCTAssertEqual(money, ["$1,200", "$50"])
    }

    func testCachesCustomDictionaryRulesAcrossScans() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .client, value: "Acme Corp"),
            CustomDictionaryItem(kind: .company, value: "Globex"),
        ])

        _ = await engine.scan(DetectionRequest(text: "Acme Corp and Globex", options: options))
        XCTAssertEqual(CustomDictionaryRuleCache.entryCount, 2)

        _ = await engine.scan(DetectionRequest(text: "Another Acme Corp mention", options: options))
        XCTAssertEqual(CustomDictionaryRuleCache.entryCount, 2)
    }

    func testCustomDictionaryMatchesClientName() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .client, value: "Acme Corp")
        ])

        let result = await engine.scan(DetectionRequest(text: "Send Acme Corp proposal", options: options))

        XCTAssertEqual(result.entities.first?.type, .customClient)
        XCTAssertEqual(result.entities.first?.value, "Acme Corp")
    }

    func testFlagsTruncationButStillScansFullTextWhenOverLimit() async {
        let result = await engine.scan(DetectionRequest(text: String(repeating: "a", count: 20), options: DetectionOptions(maximumLength: 10)))

        // `wasTruncated` now only signals the input exceeded the limit (AI sees a prefix); deterministic
        // detectors still cover the whole input, so the full character count is reported.
        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.scannedCharacterCount, 20)
    }

    func testSecretBeyondLegacyTruncationLimitIsStillDetected() async {
        // A secret placed far past `maximumLength` would have been silently dropped by the old hard cut.
        let token = "AKIA1234567890ABCDEF"
        let text = String(repeating: "padding ", count: 50) + token
        let result = await engine.scan(DetectionRequest(text: text, options: DetectionOptions(maximumLength: 32)))

        XCTAssertTrue(result.wasTruncated)
        XCTAssertTrue(
            result.entities.contains { $0.type == .awsAccessKeyId && $0.value == token },
            "Windowed scanning must find a secret past the limit: \(result.entities.map { ($0.type, $0.value) })"
        )
    }

    func testSpacedCardNumberNotDetectedAsPhone() async {
        let text = "4242 4242 4242 4242"
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertTrue(result.entities.contains { $0.type == .creditCardLike }, "Expected card-like entity, got: \(result.entities.map(\.type))")
        XCTAssertFalse(result.entities.contains { $0.type == .phone }, "PAN-shaped value must not be a phone: \(result.entities.map(\.type))")
        XCTAssertEqual(result.entities.first { $0.type == .creditCardLike }?.value, text)
    }

    func testIPv4ListNotDetectedAsPhones() async {
        let text = """
        160.79.104.10
        34.36.57.103
        104.16.174.226
        104.16.175.22
        """
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(result.entities.contains { $0.type == .phone }, "IPv4 quads must not be phones: \(result.entities.map(\.type))")
        let ips = result.entities.filter { $0.type == .ipAddress }.map(\.value).sorted()
        XCTAssertEqual(ips, ["104.16.174.226", "104.16.175.22", "160.79.104.10", "34.36.57.103"])
    }

    func testPhotoFilenameDateAndTimeNotDetectedAsPhone() async {
        let dashed = "photo_2026-04-23 16.50.15.jpeg"
        let dotted = "photo_2026.04.23 16.50.15.jpeg"
        let maskedPlaceholder = "photo_{{PHONE_1}} 16.50.15.jpeg"

        for text in [dashed, dotted, maskedPlaceholder] {
            let result = await engine.scan(DetectionRequest(text: text))
            XCTAssertFalse(
                result.entities.contains { $0.type == .phone },
                "Expected no phone in: \(text), got: \(result.entities.map(\.type))"
            )
        }
    }

    func testCustomDictionaryWinsOverlap() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "portal.acme.internal")
        ])

        let result = await engine.scan(DetectionRequest(text: "https://portal.acme.internal/login", options: options))

        XCTAssertTrue(result.entities.contains { $0.type == .customInternalDomain })
    }

    func testCustomRegexDictionaryMatchesPattern() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .regex, value: #"ACME-\d{4,}"#)
        ])

        let result = await engine.scan(DetectionRequest(text: "ticket ACME-12345 filed", options: options))

        let matches = result.entities.filter { $0.type == .customSensitiveTerm }
        XCTAssertEqual(matches.map(\.value), ["ACME-12345"])
    }

    func testCustomRegexDictionaryIgnoresInvalidPattern() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .regex, value: "ACME-[")
        ])

        let result = await engine.scan(DetectionRequest(text: "ACME-[ literal", options: options))

        XCTAssertFalse(result.entities.contains { $0.type == .customSensitiveTerm })
    }

    func testSparkleEdSignaturesDetectedAsHighEntropySecrets() async {
        let sig1 = "pNFd7KbcQSu+Mq7UYrbQXTPq82luht2ACXm/r2utp1u/Uv/5hWqctdT2jwQgMejW7DRoeV/hVr6J4VdZYdwWDw=="
        let sig2 = "Ody3D/ybSMH4T+P/oNj3LN4F0SA8RJGLEr1TI4UemrBAiJ9aEcDnYV3u58P75AbcFjI13jPYmHDUHXMSTFQbDw=="
        let text = """
        <enclosure sparkle:edSignature="\(sig1)" />
        <enclosure sparkle:edSignature="\(sig2)" />
        """
        let result = await engine.scan(DetectionRequest(text: text))
        let secrets = result.entities.filter { $0.type == .highEntropyString }.map(\.value)

        XCTAssertEqual(secrets, [sig1, sig2])
    }

    func testLongSwiftIdentifierNotDetectedAsHighEntropySecret() async {
        let text = "subheadline: OffsendStrings.settingsLicensePricingFallbackSubheadline,"
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(
            result.entities.contains { $0.type == .highEntropyString },
            "A letters-only identifier must not be a secret: \(result.entities.map { ($0.type, $0.value) })"
        )
    }

    func testLetterOnlyURLPathSegmentsNotDetectedAsHighEntropySecret() async {
        // No scheme, so the URL detector cannot absorb it; the path is still letters + slashes only.
        let text = "route = api/internal/customers/accounts/settings/profile"
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(
            result.entities.contains { $0.type == .highEntropyString },
            "A letters-only path must not be a secret: \(result.entities.map(\.value))"
        )
    }

    func testHighEntropyTokenWithDigitsStillDetected() async {
        let token = "0bCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEf"
        let result = await engine.scan(DetectionRequest(text: "value = \(token)"))
        XCTAssertTrue(
            result.entities.contains { $0.type == .highEntropyString && $0.value == token },
            "A long mixed token with digits must still flag: \(result.entities.map(\.value))"
        )
    }

    func testModelIdentifierNotDetectedAsHighEntropySecret() async {
        let text = "Isotonic/mdeberta-v3-base_finetuned_ai4privacy_v2"
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertFalse(
            result.entities.contains { $0.type == .highEntropyString },
            "A model identifier must not be a secret: \(result.entities.map(\.value))"
        )
    }

    func testFigmaFileURLDoesNotFalsePositiveAsSecretOrPhone() async {
        // Synthetic Figma-shaped URL (no real file key or client project name).
        let text =
            "https://www.figma.com/design/AbCdEfGhIjKlMnOqRsTuVwXyZ/Example-Design-File?node-id=12-345&t=ZzYyXxWwVvUuTtSs-1"
        let result = await engine.scan(DetectionRequest(text: text))
        let types = Set(result.entities.map(\.type))

        XCTAssertTrue(types.contains(.url), "Expected URL entity, got: \(types)")
        XCTAssertFalse(types.contains(.highEntropyString), "Path must not match fuzzy high-entropy rule: \(types)")
        XCTAssertFalse(types.contains(.phone), "`node-id=12-345` must not be a phone: \(types)")
    }

    // MARK: - OverlapResolver coverage (no leaks)

    func testOverlapMergePreservesFullCoverageWhenHigherPriorityIsShorter() async {
        let text = "0123456789"
        func range(_ lower: Int, _ upper: Int) -> Range<String.Index> {
            let lo = text.index(text.startIndex, offsetBy: lower)
            let hi = text.index(text.startIndex, offsetBy: upper)
            return lo..<hi
        }
        // Long fuzzy match fully containing a short, higher-priority secret.
        let high = SensitiveEntity(
            type: .highEntropyString, range: range(0, 10), value: String(text[range(0, 10)]),
            confidence: 0.65, source: .secret
        )
        let aws = SensitiveEntity(
            type: .awsAccessKeyId, range: range(2, 6), value: String(text[range(2, 6)]),
            confidence: 0.99, source: .secret
        )

        let merged = OverlapResolver.resolve([high, aws], in: text)

        XCTAssertEqual(merged.count, 1, "Overlapping spans must collapse to one entity")
        XCTAssertEqual(merged.first?.type, .awsAccessKeyId, "Higher-priority metadata wins")
        XCTAssertEqual(
            merged.first.map { String(text[$0.range]) }, text,
            "Merged range must cover the union so no flagged character is left unmasked"
        )
    }

    // MARK: - Truncation

    func testFullTextIsRetainedWhenOverLimit() async {
        let result = await engine.scan(
            DetectionRequest(text: "alpha bravo charlie", options: DetectionOptions(maximumLength: 15))
        )

        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.scannedText, "alpha bravo charlie", "Full text is retained, not cut")
        XCTAssertEqual(result.scannedCharacterCount, 19)
    }

    // MARK: - Phone boundary

    func testPhoneEmbeddedInAlphanumericTokenNotDetected() async {
        let result = await engine.scan(DetectionRequest(text: "build abc1234567890 done"))
        XCTAssertFalse(
            result.entities.contains { $0.type == .phone },
            "Digits embedded in an alphanumeric token must not start a phone match: \(result.entities.map(\.type))"
        )
    }

    func testPhoneSeparatorDoesNotBridgeAcrossNewline() async {
        let text = "555 1212\n333 4444"
        let result = await engine.scan(DetectionRequest(text: text))
        for entity in result.entities where entity.type == .phone {
            XCTAssertFalse(entity.value.contains("\n"), "A phone match must not span a newline: \(entity.value)")
        }
    }

    func testMoneySeparatorDoesNotBridgeAcrossNewline() async {
        let text = "$80,000\n160 reasons"
        let result = await engine.scan(DetectionRequest(text: text))
        let money = result.entities.filter { $0.type == .money }.map(\.value)
        XCTAssertEqual(money, ["$80,000"], "Money must stop at the line break, not absorb the next line")
    }

    // MARK: - Custom internal domain boundaries

    func testCustomInternalDomainDoesNotMatchSubstringOfLargerHost() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "acme.internal")
        ])

        let result = await engine.scan(DetectionRequest(text: "host notacme.internalx pinged", options: options))

        XCTAssertFalse(result.entities.contains { $0.type == .customInternalDomain })
    }

    func testCustomInternalDomainMatchesStandaloneHost() async {
        let options = DetectionOptions(customDictionaries: [
            CustomDictionaryItem(kind: .internalDomain, value: "acme.internal")
        ])

        let result = await engine.scan(DetectionRequest(text: "open https://acme.internal/x", options: options))

        XCTAssertTrue(result.entities.contains { $0.type == .customInternalDomain })
    }

    func testRecordsAIDetectionErrorWithoutDiscardingRegexResults() async {
        let engine = DetectionEngine(aiDetector: FailingAIDetector())
        let result = await engine.scan(
            DetectionRequest(
                text: "Contact ivan@acme.com",
                options: DetectionOptions(aiDetectionEnabled: true)
            )
        )

        XCTAssertTrue(result.entities.contains { $0.type == .email })
        XCTAssertEqual(result.aiDetectionError, "mock failure")
    }

    func testRecordsMissingAIDetectorError() async {
        let engine = DetectionEngine(aiDetector: nil)
        let result = await engine.scan(
            DetectionRequest(
                text: "Contact ivan@acme.com",
                options: DetectionOptions(aiDetectionEnabled: true)
            )
        )

        XCTAssertTrue(result.entities.contains { $0.type == .email })
        XCTAssertEqual(result.aiDetectionError, "AI model is not loaded.")
    }
}

extension DetectionEngineTests {
    // MARK: - Checksum / structural validators

    func testInvalidLuhnNumberNotDetectedAsCard() async {
        let result = await engine.scan(DetectionRequest(text: "1234 5678 9012 3456"))
        XCTAssertFalse(
            result.entities.contains { $0.type == .creditCardLike },
            "A 16-digit number failing Luhn must not be a card: \(result.entities.map(\.type))"
        )
    }

    func testValidLuhnNumberDetectedAsCard() async {
        let result = await engine.scan(DetectionRequest(text: "4111 1111 1111 1111"))
        XCTAssertTrue(result.entities.contains { $0.type == .creditCardLike })
    }

    func testInvalidIBANChecksumRejected() async {
        let result = await engine.scan(DetectionRequest(text: "GB00WEST12345698765432"))
        XCTAssertFalse(result.entities.contains { $0.type == .iban }, "Bad mod-97 IBAN must be rejected")
    }

    func testValidIBANChecksumDetected() async {
        let result = await engine.scan(DetectionRequest(text: "GB82WEST12345698765432"))
        XCTAssertTrue(result.entities.contains { $0.type == .iban })
    }

    func testNonDecodableJWTRejected() async {
        // Three base64url-ish segments, but the header is not valid JSON with an `alg`.
        let result = await engine.scan(DetectionRequest(text: "eyJrandomdata.payloadsegment.signaturepart"))
        XCTAssertFalse(result.entities.contains { $0.type == .jwt }, "Header without decodable alg must be rejected")
    }

    func testStructurallyValidJWTDetected() async {
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature"
        let result = await engine.scan(DetectionRequest(text: token))
        XCTAssertTrue(result.entities.contains { $0.type == .jwt })
    }

    // MARK: - Placeholder denylist

    func testPlaceholderSecretValueRejected() async {
        let result = await engine.scan(DetectionRequest(text: "OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))
        XCTAssertFalse(
            result.entities.contains { $0.type.isSecret },
            "An `xxxx…` placeholder key must not flag: \(result.entities.map { ($0.type, $0.value) })"
        )
    }

    func testRealSecretWithTestKeywordStillDetected() async {
        // `test` appears in real Stripe test-mode keys, so it must not be treated as a placeholder.
        let token = "sk_test_0123456789abcdefABCDEF12"
        let result = await engine.scan(DetectionRequest(text: "STRIPE=\(token)"))
        XCTAssertTrue(result.entities.contains { $0.type == .stripeKey && $0.value == token })
    }

    // MARK: - Inline ignore

    private var ignoreEnabled: DetectionOptions { DetectionOptions(honorInlineIgnore: true) }

    func testInlineIgnoreSuppressesSameLine() async {
        let token = "AKIA1234567890ABCDEF"
        let withComment = await engine.scan(DetectionRequest(text: "aws = \(token) // offsend:ignore", options: ignoreEnabled))
        XCTAssertFalse(withComment.entities.contains { $0.type == .awsAccessKeyId }, "Same-line ignore must suppress")

        let withoutComment = await engine.scan(DetectionRequest(text: "aws = \(token)", options: ignoreEnabled))
        XCTAssertTrue(withoutComment.entities.contains { $0.type == .awsAccessKeyId }, "Sanity: detected without comment")
    }

    func testInlineIgnoreNextLineSuppressesFollowingLine() async {
        let text = "# offsend:ignore-next-line\nAKIA1234567890ABCDEF"
        let result = await engine.scan(DetectionRequest(text: text, options: ignoreEnabled))
        XCTAssertFalse(result.entities.contains { $0.type == .awsAccessKeyId })
    }

    func testInlineIgnoreOnlyAffectsTargetedLine() async {
        let text = "AKIA1111111111111111 // offsend:ignore\nAKIA2222222222222222"
        let result = await engine.scan(DetectionRequest(text: text, options: ignoreEnabled))
        let aws = result.entities.filter { $0.type == .awsAccessKeyId }.map(\.value)
        XCTAssertEqual(aws, ["AKIA2222222222222222"], "Only the commented line is suppressed")
    }

    func testInlineIgnoreNotHonoredByDefault() async {
        // Clipboard path uses default options: a copied `offsend:ignore` must NOT disable masking.
        let text = "aws = AKIA1234567890ABCDEF // offsend:ignore"
        let result = await engine.scan(DetectionRequest(text: text))
        XCTAssertTrue(
            result.entities.contains { $0.type == .awsAccessKeyId },
            "Inline ignore must be off by default so untrusted content can't suppress findings"
        )
    }
}

private struct FailingAIDetector: AIModelDetecting {
    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        throw StubAIModelError.inferenceFailed
    }
}

private enum StubAIModelError: LocalizedError {
    case inferenceFailed

    var errorDescription: String? {
        "mock failure"
    }
}
