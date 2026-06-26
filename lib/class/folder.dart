class Folder {
  final int id;
  final String name;
  final int color;
  final String icon;
  final DateTime createdAt;
  final String? remoteId;

  Folder({
    required this.id,
    required this.name,
    this.color = 0xFF2196F3, // Default Material Blue
    this.icon = 'folder',
    required this.createdAt,
    this.remoteId,
  });

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'color': color,
      'icon': icon,
      'createdAt': createdAt.toIso8601String(),
      'remoteId': remoteId,
    };
  }

  Folder copyWith({
    int? id,
    String? name,
    int? color,
    String? icon,
    DateTime? createdAt,
    String? remoteId,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int,
      name: map['name'] as String,
      color: map['color'] as int? ?? 0xFF2196F3,
      icon: map['icon'] as String? ?? 'folder',
      createdAt: DateTime.parse(map['createdAt'] as String),
      remoteId: map['remoteId'] as String?,
    );
  }
}
