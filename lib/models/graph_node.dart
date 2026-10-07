/// Represents a vertex in the road network graph (an intersection or junction).
class GraphNode {
  final int id;
  final double lat;
  final double lon;
  final bool hasSignal;
  final String? signalId;
  final String? signalSource;

  const GraphNode({
    required this.id,
    required this.lat,
    required this.lon,
    this.hasSignal = false,
    this.signalId,
    this.signalSource,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as int,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      hasSignal: json['signal'] as bool? ?? false,
      signalId: json['signal_id'] as String?,
      signalSource: json['signal_source'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': lat,
    'lon': lon,
    'signal': hasSignal,
    if (signalId != null) 'signal_id': signalId,
    if (signalSource != null) 'signal_source': signalSource,
  };

  @override
  String toString() => 'GraphNode(id: $id, lat: $lat, lon: $lon, signal: $signalId)';
}

