class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.action,
    required this.description,
    required this.createdAt,
    this.surveyId,
    this.projectId,
  });

  final int id;
  final String action;
  final String description;
  final DateTime createdAt;
  final int? surveyId;
  final int? projectId;

  factory ActivityLog.fromJson(Map<String, Object?> row) => ActivityLog(
    id: row['id'] as int,
    action: row['action'] as String,
    description: row['description'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    surveyId: row['survey_id'] as int?,
    projectId: row['project_id'] as int?,
  );
}

class SurveyProject {
  const SurveyProject({required this.id, required this.name});
  final int id;
  final String name;
}
