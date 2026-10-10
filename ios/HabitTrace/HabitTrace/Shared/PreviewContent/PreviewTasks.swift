#if DEBUG
import Foundation

/// Sample tasks for SwiftUI previews only. Never used by services.
extension HabitTraceTask {
    static var previewTasks: [HabitTraceTask] {
        let today = TaskTimeFormatting.isoDate(from: .now)
        let yesterday = TaskTimeFormatting.isoDate(
            from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        )

        return [
            HabitTraceTask(
                id: "preview-1",
                title: "Write project proposal",
                notes: "Outline the three main sections before drafting.",
                taskCategory: "Work",
                plannedDate: today,
                plannedStartTime: "2:00 PM",
                plannedDurationMin: 45,
                importance: 4,
                energyLevel: 3,
                focusLevel: 4,
                taskStatus: "pending",
                createdAt: nil
            ),
            HabitTraceTask(
                id: "preview-2",
                title: "Review lecture notes",
                notes: nil,
                taskCategory: "Study",
                plannedDate: today,
                plannedStartTime: "4:30 PM",
                plannedDurationMin: 60,
                importance: 5,
                energyLevel: 3,
                focusLevel: 5,
                taskStatus: "pending",
                createdAt: nil
            ),
            HabitTraceTask(
                id: "preview-3",
                title: "Morning run",
                notes: nil,
                taskCategory: "Fitness/Health",
                plannedDate: today,
                plannedStartTime: "7:30 AM",
                plannedDurationMin: 30,
                importance: 3,
                energyLevel: 4,
                focusLevel: 2,
                taskStatus: "success",
                createdAt: nil
            ),
            HabitTraceTask(
                id: "preview-4",
                title: "Call the dentist",
                notes: nil,
                taskCategory: "Errands/Admin",
                plannedDate: yesterday,
                plannedStartTime: "11:00 AM",
                plannedDurationMin: 15,
                importance: 2,
                energyLevel: 2,
                focusLevel: 2,
                taskStatus: "pending",
                createdAt: nil
            ),
        ]
    }
}
#endif
