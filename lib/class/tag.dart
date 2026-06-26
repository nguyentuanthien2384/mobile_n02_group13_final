class Tag {
  final int id;
  String name;
  final DateTime createdAt;
  String? remoteId;
  final Set<int> noteIds;

  Tag({
    required this.id,
    required this.name,
    required this.createdAt,
    this.remoteId,
    Set<int>? noteIds,
  }) : noteIds = noteIds != null ? Set<int>.from(noteIds) : <int>{};

  Tag copyWith({
    String? name,
    DateTime? createdAt,
    String? remoteId,
    Set<int>? noteIds,
  }) {
    return Tag(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      remoteId: remoteId ?? this.remoteId,
      noteIds: noteIds ?? this.noteIds,
    );
  }
}
