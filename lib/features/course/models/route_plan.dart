class RoutePlan {
  const RoutePlan({
    required this.title,
    required this.distance,
    required this.slope,
    required this.flow,
    required this.environment,
    required this.safety,
    required this.mission,
    required this.scores,
  });

  final String title;
  final String distance;
  final String slope;
  final String flow;
  final String environment;
  final String safety;
  final String mission;
  final Map<String, int> scores;
}
