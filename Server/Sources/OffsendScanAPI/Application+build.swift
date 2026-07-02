import Foundation
import Hummingbird
import Jobs
import JobsValkey
import Logging
import ServiceLifecycle
import Valkey

struct AppDependencies: Sendable {
    let config: AppConfiguration
    let jobStore: JobStore
    let reportStorage: ReportStorageBox
    let htmlTemplates: HTMLTemplateRenderer
    let pushScanJob: @Sendable (ScanRepositoryJobParameters) async throws -> Void
}

struct AppRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
    }
}

enum ApplicationBuilder {
    static func build(config: AppConfiguration, logger: Logger) async throws -> Application<Router<AppRequestContext>.Responder> {
        try FileManager.default.createDirectory(at: config.scanWorkDirectory, withIntermediateDirectories: true)

        let jobStore = JobStore(ttl: config.reportTTL)
        let reportStorage = ReportStorageBox(try await ReportStorageFactory.make(config: config, logger: logger))
        let htmlTemplates = try HTMLTemplateRenderer.load()
        let scanServices = ScanServices(
            jobStore: jobStore,
            cloner: RepositoryCloner(gitPath: config.gitPath, timeout: config.cloneTimeout),
            scanner: RepositoryScanner(),
            reportStorage: reportStorage,
            htmlTemplates: htmlTemplates,
            workDirectory: config.scanWorkDirectory,
            toolVersion: config.toolVersion,
            logger: logger,
            reportTTL: config.reportTTL
        )

        let (pushScanJob, processorService) = try await makeJobQueue(
            config: config,
            logger: logger,
            scanServices: scanServices
        )

        let dependencies = AppDependencies(
            config: config,
            jobStore: jobStore,
            reportStorage: reportStorage,
            htmlTemplates: htmlTemplates,
            pushScanJob: pushScanJob
        )

        let router = Routes.buildRouter(dependencies: dependencies)
        let address = BindAddress.hostname(config.host, port: config.port)

        return Application(
            router: router,
            configuration: .init(address: address, serverName: "OffsendScanAPI"),
            services: [processorService],
            logger: logger
        )
    }

    private static func makeJobQueue(
        config: AppConfiguration,
        logger: Logger,
        scanServices: ScanServices
    ) async throws -> (@Sendable (ScanRepositoryJobParameters) async throws -> Void, any Service) {
        if let valkeyHost = config.valkeyHost {
            logger.info("Job queue: Valkey", metadata: ["host": .string(valkeyHost)])
            let valkey = ValkeyClient(.hostname(valkeyHost, port: config.valkeyPort), logger: logger)
            let driver = try await ValkeyJobQueue.valkey(
                valkey,
                configuration: .init(queueName: config.valkeyQueueName),
                logger: logger
            )
            let queue = JobQueue(driver, logger: logger)
            return registerScanJob(on: queue, config: config, scanServices: scanServices)
        }

        logger.info("Job queue: in-memory")
        let queue = JobQueue(.memory, logger: logger)
        return registerScanJob(on: queue, config: config, scanServices: scanServices)
    }

    private static func registerScanJob<D: JobQueueDriver>(
        on queue: JobQueue<D>,
        config: AppConfiguration,
        scanServices: ScanServices
    ) -> (@Sendable (ScanRepositoryJobParameters) async throws -> Void, any Service) {
        let services = scanServices
        queue.registerJob(parameters: ScanRepositoryJobParameters.self) { parameters, context in
            context.logger.info("Processing scan job", metadata: ["jobID": .string(parameters.jobID)])
            await ScanJobRunner.run(parameters: parameters, services: services)
        }

        let push: @Sendable (ScanRepositoryJobParameters) async throws -> Void = { parameters in
            _ = try await queue.push(parameters)
        }
        let processor = queue.processor(options: .init(numWorkers: config.jobWorkers))
        return (push, processor)
    }
}
