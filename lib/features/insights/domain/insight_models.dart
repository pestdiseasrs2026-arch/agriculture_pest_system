class ActivityRecord {
  final String id, actor, action, entity, category;
  final DateTime timestamp;
  const ActivityRecord({required this.id, required this.actor, required this.action, required this.entity, required this.category, required this.timestamp});
  factory ActivityRecord.fromMap(String id, Map<String,dynamic> d) => ActivityRecord(id:id, actor:d['actor']?.toString()??'System', action:d['action']?.toString()??d['title']?.toString()??'Activity', entity:d['entity']?.toString()??d['description']?.toString()??'', category:d['category']?.toString()??'information', timestamp:DateTime.tryParse(d['timestamp']?.toString()??d['createdAt']?.toString()??'')??DateTime.fromMillisecondsSinceEpoch(0));
}

class AnalyticsPoint { final DateTime date; final int detections; final double confidence; const AnalyticsPoint(this.date,this.detections,this.confidence); }
class AnalyticsSummary {
  final int detections, activeIssues, pestSignals, cropCount;
  final double averageConfidence;
  final List<AnalyticsPoint> points;
  final List<ActivityRecord> activities;
  const AnalyticsSummary({required this.detections,required this.activeIssues,required this.pestSignals,required this.cropCount,required this.averageConfidence,required this.points,required this.activities});
}

class NotificationFilter {
  final String category, priority; final bool unreadOnly;
  const NotificationFilter({this.category='All',this.priority='All',this.unreadOnly=false});
  NotificationFilter copyWith({String? category,String? priority,bool? unreadOnly})=>NotificationFilter(category:category??this.category,priority:priority??this.priority,unreadOnly:unreadOnly??this.unreadOnly);
}

class ReportFilter {
  final DateTime start,end; final String farm,crop,type;
  const ReportFilter({required this.start,required this.end,this.farm='All',this.crop='All',this.type='AI Detection Report'});
}
