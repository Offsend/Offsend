import XCTest
@testable import DetectionCore

final class FileSensitivityClassifierTests: XCTestCase {
    func testSecretsConfigPaths() {
        let paths = [
            ".env",
            "config/.env.production",
            "src/config.ts",
            "app/configuration.json",
            "infra/secrets.yaml",
            "ops/credentials.json",
            "infra/prod.tfvars",
            "deploy/server.pem",
            "keys/service.key",
            "/Users/me/.ssh/known_hosts",
            "/Users/me/.aws/config",
        ]
        for path in paths {
            XCTAssertEqual(FileSensitivityClassifier.tier(forPath: path), .secretsConfig, path)
        }
    }

    func testDocsOrTestsPaths() {
        let paths = [
            "README.md",
            "CHANGELOG",
            "docs/guide.mdx",
            "src/__tests__/user.ts",
            "api/user_test.go",
            "tests/test_login.py",
            "components/Button.test.tsx",
            "service/auth.spec.ts",
            "fixtures/data.json",
        ]
        for path in paths {
            XCTAssertEqual(FileSensitivityClassifier.tier(forPath: path), .docsOrTests, path)
        }
    }

    func testNeutralPaths() {
        let paths = [
            "src/index.ts",
            "lib/main.py",
            // Placeholder files ship sample values, so an env-shaped name is not treated as a secret store.
            ".env.example",
            "config.sample.json",
            // Framework configs use a compound base name, so they don't trip the bare `config` rule.
            "tailwind.config.ts",
            "next.config.js",
        ]
        for path in paths {
            XCTAssertEqual(FileSensitivityClassifier.tier(forPath: path), .neutral, path)
        }
    }

    func testSecretsConfigWinsOverTestDirectoryForRealEnvFile() {
        // A real `.env` inside a tests/ folder is still a secret store, not sample data.
        XCTAssertEqual(FileSensitivityClassifier.tier(forPath: "tests/fixtures/.env"), .secretsConfig)
    }
}
