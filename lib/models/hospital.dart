/// Represents a destination hospital in the network.
class Hospital {
  final String id;
  final String name;
  final int nodeId;

  const Hospital({
    required this.id,
    required this.name,
    required this.nodeId,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      id: json['id'] as String,
      name: json['name'] as String,
      nodeId: json['node'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'node': nodeId,
  };

  @override
  String toString() => 'Hospital($id: $name at node $nodeId)';
}

