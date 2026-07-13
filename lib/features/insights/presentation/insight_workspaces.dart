// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';
import 'package:agriculture_pest_system/features/insights/providers/insight_providers.dart';

class AnalyticsWorkspace extends ConsumerWidget {
  final UserProfile user; const AnalyticsWorkspace({super.key,required this.user});
  @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Analytics Dashboard')),body:ref.watch(analyticsSummaryProvider(user.uid)).when(
    loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Text('Unable to load analytics: $e')),
    data:(s)=>ListView(padding:const EdgeInsets.all(20),children:[GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:MediaQuery.sizeOf(context).width>700?4:2,childAspectRatio:1.7,children:[_Kpi('Detections','${s.detections}'),_Kpi('Active issues','${s.activeIssues}'),_Kpi('Pest signals','${s.pestSignals}'),_Kpi('Avg confidence','${(s.averageConfidence*100).toStringAsFixed(1)}%')]),const SizedBox(height:20),Text('Detection trend',style:Theme.of(context).textTheme.titleMedium),SizedBox(height:220,child:Card(child:Padding(padding:const EdgeInsets.all(16),child:s.points.isEmpty?const Center(child:Text('No chart data for this period.')):LineChart(LineChartData(minY:0,lineBarsData:[LineChartBarData(isCurved:true,color:Theme.of(context).colorScheme.primary,spots:[for(var i=0;i<s.points.length;i++)FlSpot(i.toDouble(),s.points[i].detections.toDouble())])],titlesData:const FlTitlesData(show:false),borderData:FlBorderData(show:false)))))),const SizedBox(height:20),Text('Recent activity',style:Theme.of(context).textTheme.titleMedium),Card(child:Column(children:s.activities.isEmpty?[const ListTile(title:Text('No activity yet'))]:s.activities.take(20).map((a)=>ListTile(leading:const Icon(Icons.timeline),title:Text(a.action),subtitle:Text('${a.actor} • ${a.entity}'),trailing:Text('${a.timestamp.month}/${a.timestamp.day}'))).toList()))])));
}
class _Kpi extends StatelessWidget{final String label,value;const _Kpi(this.label,this.value);@override Widget build(BuildContext c)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:Theme.of(c).textTheme.headlineSmall),Text(label)])));}

class LiveNotificationsWorkspace extends ConsumerStatefulWidget {
  final UserProfile user;
  const LiveNotificationsWorkspace({super.key, required this.user});
  @override
  ConsumerState<LiveNotificationsWorkspace> createState() => _NotificationsState();
}

class _NotificationsState extends ConsumerState<LiveNotificationsWorkspace> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final repo = ref.read(insightsRepositoryProvider);
      await repo.initializeFcm(widget.user.uid);
      repo.foregroundMessages.listen((message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.notification?.title ?? 'New notification')),
          );
        }
      });
    });
  }

  Future<void> preferences() async {
    await ref.read(insightsRepositoryProvider).savePreferences(
      widget.user.uid,
      {'disease': true, 'sensor': true, 'stock': true},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(notificationFilterProvider);
    final state = ref.watch(notificationsProvider(widget.user.uid));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Alerts'),
        actions: [IconButton(onPressed: preferences, icon: const Icon(Icons.tune))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                DropdownButton<String>(
                  value: filter.category,
                  items: const ['All', 'Disease', 'Sensor', 'Inventory', 'System']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => ref.read(notificationFilterProvider.notifier)
                      .set(filter.copyWith(category: v)),
                ),
                DropdownButton<String>(
                  value: filter.priority,
                  items: const ['All', 'High', 'Medium', 'Low']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => ref.read(notificationFilterProvider.notifier)
                      .set(filter.copyWith(priority: v)),
                ),
                FilterChip(
                  label: const Text('Unread only'),
                  selected: filter.unreadOnly,
                  onSelected: (v) => ref.read(notificationFilterProvider.notifier)
                      .set(filter.copyWith(unreadOnly: v)),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (snapshot) {
                final docs = snapshot.docs.where((doc) {
                  final data = doc.data();
                  final category = data['category']?.toString().toLowerCase();
                  final priority = data['priority']?.toString().toLowerCase();
                  return (filter.category == 'All' ||
                          category == filter.category.toLowerCase()) &&
                      (filter.priority == 'All' ||
                          priority == filter.priority.toLowerCase()) &&
                      (!filter.unreadOnly || data['read'] != true);
                }).toList();
                if (docs.isEmpty) {
                  return const Center(child: Text('No matching notifications.'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    return Dismissible(
                      key: ValueKey(doc.id),
                      onDismissed: (_) => ref
                          .read(insightsRepositoryProvider)
                          .deleteNotification(doc.id),
                      child: ListTile(
                        leading: Icon(data['read'] == true
                            ? Icons.notifications_none
                            : Icons.notifications_active),
                        title: Text(data['title']?.toString() ?? 'Alert'),
                        subtitle: Text(data['message']?.toString() ?? ''),
                        onTap: () => ref
                            .read(insightsRepositoryProvider)
                            .updateNotification(doc.id, {'read': true}),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref
                              .read(insightsRepositoryProvider)
                              .deleteNotification(doc.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ReportsWorkspace extends ConsumerStatefulWidget{final UserProfile user;const ReportsWorkspace({super.key,required this.user});@override ConsumerState<ReportsWorkspace> createState()=>_ReportsState();}
class _ReportsState extends ConsumerState<ReportsWorkspace>{DateTime start=DateTime.now().subtract(const Duration(days:30)),end=DateTime.now();String type='AI Detection Report',farm='All',crop='All';bool busy=false;Uint8List? last;String lastExtension='pdf';
  Future<List<DetectionRecord>> records()async{final all=await ref.read(insightsRepositoryProvider).detections(widget.user.uid).first;return all.where((d){final date=DateTime.tryParse(d.date);return date!=null&&!date.isBefore(start)&&!date.isAfter(end.add(const Duration(days:1)))&&(crop=='All'||d.cropType==crop);}).toList();}
  Future<void> generate(bool csv)async{setState(()=>busy=true);try{final rows=await records();final id=DateTime.now().millisecondsSinceEpoch.toString();late Uint8List bytes;late String extension,mime;if(csv){final text='crop,disease,confidence,severity,date\n${rows.map((d)=>[d.cropType,d.diseaseName,d.confidenceScore,d.severity,d.date].map((v)=>'"${v.replaceAll('"','""')}"').join(',')).join('\n')}';bytes=Uint8List.fromList(utf8.encode(text));extension='csv';mime='text/csv';}else{final doc=pw.Document();doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(_)=>[pw.Header(level:0,child:pw.Text(type)),pw.Text('Farm: $farm • Crop: $crop'),pw.Text('Period: ${start.toIso8601String().substring(0,10)} to ${end.toIso8601String().substring(0,10)}'),...rows.map((d)=>pw.Text('${d.cropType} • ${d.diseaseName} • ${d.severity} • ${d.confidenceScore}'))]));bytes=await doc.save();extension='pdf';mime='application/pdf';}final url=await ref.read(insightsRepositoryProvider).uploadReport(widget.user.uid,id,extension,bytes,mime);await ref.read(insightsRepositoryProvider).saveReportMetadata({'farmerId':widget.user.uid,'type':type,'format':extension,'farm':farm,'crop':crop,'start':start.toIso8601String(),'end':end.toIso8601String(),'recordCount':rows.length,'storageUrl':url,'status':'ready'});if(mounted)setState((){last=bytes;lastExtension=extension;});}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> share()async{if(last==null)return;await SharePlus.instance.share(ShareParams(text:type,files:[XFile.fromData(last!,mimeType:lastExtension=='pdf'?'application/pdf':'text/csv',name:'agri-report.$lastExtension')]));}
  Future<void> pickDate(bool first)async{final d=await showDatePicker(context:context,initialDate:first?start:end,firstDate:DateTime(2020),lastDate:DateTime.now());if(d!=null)setState(()=>first?start=d:end=d);}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Reports & Exports')),body:ListView(padding:const EdgeInsets.all(20),children:[DropdownButtonFormField(value:type,items:const ['AI Detection Report','Farm Health Report','Disease Surveillance Report','Soil Analysis Report','IoT Sensor Report'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>type=v??type),decoration:const InputDecoration(labelText:'Report type')),const SizedBox(height:12),TextFormField(initialValue:farm,onChanged:(v)=>farm=v.trim().isEmpty?'All':v.trim(),decoration:const InputDecoration(labelText:'Farm filter')),const SizedBox(height:12),TextFormField(initialValue:crop,onChanged:(v)=>crop=v.trim().isEmpty?'All':v.trim(),decoration:const InputDecoration(labelText:'Crop filter')),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>pickDate(true),child:Text('From ${start.toIso8601String().substring(0,10)}'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>pickDate(false),child:Text('To ${end.toIso8601String().substring(0,10)}')))]),const SizedBox(height:16),FilledButton.icon(onPressed:busy?null:()=>generate(false),icon:const Icon(Icons.picture_as_pdf),label:const Text('Generate PDF')),const SizedBox(height:8),OutlinedButton.icon(onPressed:busy?null:()=>generate(true),icon:const Icon(Icons.table_view),label:const Text('Export CSV')),const SizedBox(height:8),OutlinedButton.icon(onPressed:last==null?null:share,icon:const Icon(Icons.share),label:const Text('Share last export')),const SizedBox(height:20),StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:ref.read(insightsRepositoryProvider).reports(widget.user.uid),builder:(_,s)=>Card(child:Column(children:[const ListTile(title:Text('Export history')),...?s.data?.docs.map((d)=>ListTile(title:Text(d['type']?.toString()??'Report'),subtitle:Text('${d['format']} • ${d['recordCount']} records'),trailing:const Icon(Icons.cloud_done)))]))) ]));}
