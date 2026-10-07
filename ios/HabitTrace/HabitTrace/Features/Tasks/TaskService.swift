import Foundation
import Combine

@MainActor
final class TaskService: ObservableObject {
    @Published private(set) var tasks: [HabitTraceTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func loadTasks(accessToken: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            tasks = try await apiClient.fetchTasks(
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
