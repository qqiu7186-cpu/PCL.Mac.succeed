import Foundation

enum AppError: LocalizedError, Equatable {
    case network(String)
    case fileSystem(String)
    case configuration(String)
    case authentication(String)
    case runtime(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let message), .fileSystem(let message), .configuration(let message), .authentication(let message), .runtime(let message), .unknown(let message):
            return message
        }
    }

    var localizedDescription: String {
        errorDescription ?? "未知错误"
    }

    static func wrap(_ error: Error, category: Category, action: String) -> AppError {
        let message = "\(action)：\(error.localizedDescription)"
        switch category {
        case .network: return .network(message)
        case .fileSystem: return .fileSystem(message)
        case .configuration: return .configuration(message)
        case .authentication: return .authentication(message)
        case .runtime: return .runtime(message)
        case .unknown: return .unknown(message)
        }
    }

    enum Category {
        case network
        case fileSystem
        case configuration
        case authentication
        case runtime
        case unknown
    }
}
