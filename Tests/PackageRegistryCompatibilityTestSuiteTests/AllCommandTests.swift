//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

import PackageRegistryClient
@testable import PackageRegistryCompatibilityTestSuite
import TSCBasic

final class AllCommandTests: XCTestCase {
    private var sourceArchives: [SourceArchiveMetadata]!
    private var registryClient: PackageRegistryClient!

    override func setUp() {
        do {
            let archivesJSON = self.fixtureURL(subdirectory: "SourceArchives", filename: "source_archives.json")
            self.sourceArchives = try JSONDecoder().decode([SourceArchiveMetadata].self, from: Data(contentsOf: archivesJSON))
        } catch {
            XCTFail("Failed to load source_archives.json")
        }

        let clientConfiguration = PackageRegistryClient.Configuration(url: self.registryURL, defaultRequestTimeout: .seconds(1))
        self.registryClient = PackageRegistryClient(httpClientProvider: .createNew, configuration: clientConfiguration)
    }

    override func tearDown() {
        try! self.registryClient.syncShutdown()
    }

    func test_help() throws {
        let result = try executeCommand(command: "package-registry-compatibility all --help")
        print(result.stderr)
        XCTAssert(result.stdout.contains("USAGE: package-registry-compatibility all <url> <config-path>"))
    }

    func test_run() throws {
        // Create package releases
        let scope = "apple-\(UUID().uuidString.prefix(6))"
        let name = "swift-nio"
        let versions = ["1.14.2", "2.29.0", "2.30.0"]
        self.createPackageReleases(scope: scope, name: name, versions: versions, client: self.registryClient, sourceArchives: self.sourceArchives)

        // Make version 2.29.0 unavailable by deleting it
        let deleteResponse = try self.registryClient.httpClient.delete(url: "\(self.registryURL)/\(scope)/\(name)/2.29.0").wait()
        XCTAssertEqual(.noContent, deleteResponse.status)

        let unknownScope = "test-\(UUID().uuidString.prefix(6))"

        let config = PackageRegistryCompatibilityTestSuite.Configuration(
            createPackageRelease: CreatePackageReleaseTests.Configuration(
                packageReleases: [
                    .init(
                        package: nil,
                        version: "1.0.0",
                        sourceArchivePath: self.fixturePath(subdirectory: "SourceArchives", filename: "swift-nio@1.14.2.zip"),
                        metadataPath: self.fixturePath(subdirectory: "CompatibilityTestSuite/Metadata", filename: "swift-nio@1.14.2.json")
                    ),
                    .init(
                        package: nil,
                        version: "2.0.0",
                        sourceArchivePath: self.fixturePath(subdirectory: "SourceArchives", filename: "SwiftyUserDefaults@5.3.0.zip"),
                        metadataPath: self.fixturePath(subdirectory: "CompatibilityTestSuite/Metadata", filename: "SwiftyUserDefaults@5.3.0.json")
                    ),
                ],
                maxProcessingTimeInSeconds: 10
            ),
            listPackageReleases: ListPackageReleasesTests.Configuration(
                packages: [
                    .init(
                        package: PackageIdentity(scope: scope, name: name),
                        numberOfReleases: versions.count,
                        versions: Set(versions),
                        unavailableVersions: ["2.29.0"],
                        linkRelations: ["latest-version", "canonical"]
                    ),
                ],
                unknownPackages: [PackageIdentity(scope: unknownScope, name: "unknown")],
                packageURLProvided: true,
                problemProvided: true,
                paginationSupported: false
            ),
            fetchPackageReleaseInfo: FetchPackageReleaseInfoTests.Configuration(
                packageReleases: [
                    .init(
                        packageRelease: PackageRelease(package: PackageIdentity(scope: scope, name: name), version: "2.30.0"),
                        resources: [.sourceArchive(checksum: "e9a5540d37bf4fa0b5d5a071b366eeca899b37ece4ce93b26cc14286d57fbcef")],
                        keyValues: [
                            "repositoryURL": "https://github.com/\(scope)/swift-nio",
                            "commitHash": "d79e333",
                        ],
                        linkRelations: ["latest-version", "predecessor-version"]
                    ),
                ],
                unknownPackageReleases: [PackageRelease(package: PackageIdentity(scope: unknownScope, name: "unknown"), version: "1.0.0")]
            )
        )
        let configData = try JSONEncoder().encode(config)

        try withTemporaryDirectory(removeTreeOnDeinit: true) { directoryPath in
            let configPath = directoryPath.appending(component: "config.json")
            try localFileSystem.writeFileContents(configPath, bytes: ByteString(Array(configData)))

            let stdout = try self.executeCommand(subcommand: "all", configPath: configPath.pathString, generateData: false).stdout
            XCTAssert(stdout.contains("Create Package Release - All tests passed."))
            XCTAssert(stdout.contains("List Package Releases - All tests passed."))
            XCTAssert(stdout.contains("Fetch Package Release Information - All tests passed."))
        }
    }

    func test_run_generateConfig() throws {
        let configPath = self.fixturePath(filename: "gendata.json")
        let stdout = try self.executeCommand(subcommand: "all", configPath: configPath, generateData: true).stdout
        XCTAssert(stdout.contains("Create Package Release - All tests passed."))
        XCTAssert(stdout.contains("List Package Releases - All tests passed."))
        XCTAssert(stdout.contains("Fetch Package Release Information - All tests passed."))
    }
}