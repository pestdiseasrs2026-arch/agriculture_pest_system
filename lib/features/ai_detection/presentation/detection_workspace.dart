import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:agriculture_pest_system/core/models/app_models.dart';
import 'package:agriculture_pest_system/core/providers/repository_providers.dart';
import 'package:agriculture_pest_system/features/ai_detection/domain/detection_job.dart';
import 'package:agriculture_pest_system/features/ai_detection/providers/ai_detection_providers.dart';

class DetectionWorkspace extends ConsumerStatefulWidget {
  final UserProfile user;
  const DetectionWorkspace({super.key, required this.user});
  @override ConsumerState<DetectionWorkspace> createState() => _DetectionWorkspaceState();
}

class _DetectionWorkspaceState extends ConsumerState<DetectionWorkspace> {
  final crop = TextEditingController();
  final picker = ImagePicker();
  DropzoneViewController? dropzone;
  double comparison = .5;
  @override void dispose() { crop.dispose(); super.dispose(); }

  Future<void> _pick(bool camera) async {
    if (camera) { final file = await picker.pickImage(source: ImageSource.camera); if (file != null) _add(file.name, await file.readAsBytes()); }
    else { for (final file in await picker.pickMultiImage()) { _add(file.name, await file.readAsBytes()); } }
  }
  void _add(String name, Uint8List bytes) {
    if (bytes.lengthInBytes > 15 * 1024 * 1024) { _message('$name exceeds the 15 MB limit.'); return; }
    ref.read(detectionJobsProvider.notifier).add(name, bytes);
  }
  Future<void> _processAll() async {
    if (crop.text.trim().isEmpty) { _message('Enter the crop type before processing.'); return; }
    final jobs = ref.read(detectionJobsProvider);
    for (final job in jobs.where((j) => j.status == DetectionJobStatus.queued || j.status == DetectionJobStatus.failed)) {
      await ref.read(detectionJobsProvider.notifier).process(job.id, crop.text.trim(), widget.user.uid);
    }
  }
  Future<void> _review(DetectionJob job) async {
    await ref.read(operationsRepositoryProvider).add('expert_reviews', {'jobId': job.id, 'farmerId': widget.user.uid, 'imageUrl': job.imageUrl, 'crop': crop.text.trim(), 'prediction': job.prediction?.disease, 'confidence': job.prediction?.confidence, 'status': 'pending'});
    ref.read(detectionJobsProvider.notifier).markReviewRequested(job.id); _message('Expert review requested.');
  }
  Future<Uint8List> _report(DetectionJob job) async {
    final p = job.prediction; final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (_) => [pw.Header(level: 0, child: pw.Text('AgriAI Detection Report')), pw.Text('Crop: ${p?.crop ?? crop.text}'), pw.Text('Disease: ${p?.disease ?? 'Pending'}'), pw.Text('Pest: ${p?.pest ?? 'None identified'}'), pw.Text('Confidence: ${((p?.confidence ?? 0) * 100).toStringAsFixed(1)}%'), pw.Text('Severity: ${p?.severity ?? 'Pending'}'), pw.SizedBox(height: 12), pw.Text('Treatment: ${p?.treatment ?? ''}'), pw.Text('Prevention: ${p?.prevention ?? ''}'), pw.Text('Model: ${p?.modelVersion ?? ''}'), pw.SizedBox(height: 20), pw.Text('AI guidance must be reviewed before chemical treatment.') ]));
    return doc.save();
  }
  Future<void> _share(DetectionJob job) async { final bytes = await _report(job); await SharePlus.instance.share(ShareParams(text: 'AgriAI crop-health detection report', files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'agri_ai_detection.pdf')])); }
  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  @override Widget build(BuildContext context) {
    final jobs = ref.watch(detectionJobsProvider); final configured = ref.watch(aiDetectionServiceProvider).isConfigured;
    return Scaffold(appBar: AppBar(title: const Text('AI Detection Workspace')), body: ListView(padding: const EdgeInsets.all(20), children: [
      if (!configured) const Card(child: ListTile(leading: Icon(Icons.settings_applications), title: Text('AI API configuration required'), subtitle: Text('Start with --dart-define=AI_API_URL=https://your-api/predict and optionally AI_API_TOKEN. Simulated predictions are disabled.'))),
      TextField(controller: crop, decoration: const InputDecoration(labelText: 'Crop type', prefixIcon: Icon(Icons.eco_outlined))), const SizedBox(height: 12),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera'))), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.collections_outlined), label: const Text('Select multiple')))]), const SizedBox(height: 12),
      if (kIsWeb) SizedBox(height: 130, child: Stack(children: [DropzoneView(onCreated: (c) => dropzone = c, mime: const ['image/jpeg','image/png','image/webp'], onDropFiles: (files) async { for (final file in files ?? const []) { _add(await dropzone!.getFilename(file), await dropzone!.getFileData(file)); } }), IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(16)), child: const Center(child: Text('Drag and drop crop images here'))))])),
      const SizedBox(height: 16), FilledButton.icon(onPressed: jobs.isEmpty || !configured ? null : _processAll, icon: const Icon(Icons.auto_awesome), label: Text('Process ${jobs.length} image${jobs.length == 1 ? '' : 's'}')), const SizedBox(height: 16),
      if (jobs.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Add one or more clear crop images to begin.'))),
      ...jobs.map((job) => _JobCard(job: job, comparison: comparison, onComparison: (v) => setState(() => comparison = v), onCancel: () => ref.read(detectionJobsProvider.notifier).cancel(job.id), onRetry: () => ref.read(detectionJobsProvider.notifier).retry(job.id, crop.text.trim(), widget.user.uid), onRemove: () => ref.read(detectionJobsProvider.notifier).remove(job.id), onReview: () => _review(job), onShare: () => _share(job))),
    ]));
  }
}

class _JobCard extends StatelessWidget {
  final DetectionJob job; final double comparison; final ValueChanged<double> onComparison; final VoidCallback onCancel, onRetry, onRemove, onReview, onShare;
  const _JobCard({required this.job, required this.comparison, required this.onComparison, required this.onCancel, required this.onRetry, required this.onRemove, required this.onReview, required this.onShare});
  @override Widget build(BuildContext context) { final p = job.prediction; final busy = {DetectionJobStatus.compressing, DetectionJobStatus.predicting, DetectionJobStatus.uploading}.contains(job.status); return Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(job.name, style: const TextStyle(fontWeight: FontWeight.w700))), Chip(label: Text(job.status.name)), IconButton(onPressed: busy ? null : onRemove, icon: const Icon(Icons.close))]),
    if (busy) ...[LinearProgressIndicator(value: job.progress), const SizedBox(height: 6), Text('${(job.progress * 100).round()}% • ${job.status.name}'), TextButton.icon(onPressed: onCancel, icon: const Icon(Icons.stop), label: const Text('Cancel'))],
    if (job.status == DetectionJobStatus.failed) ...[Text(job.error ?? 'Processing failed', style: TextStyle(color: Theme.of(context).colorScheme.error)), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry this image'))],
    if (p != null) ...[const SizedBox(height: 12), _Comparison(job: job, fraction: comparison), Slider(value: comparison, onChanged: onComparison), Text('${p.crop}: ${p.disease}${p.pest.isEmpty ? '' : ' • ${p.pest}'}', style: Theme.of(context).textTheme.titleMedium), LinearProgressIndicator(value: p.confidence), Text('Confidence ${(p.confidence * 100).toStringAsFixed(1)}% • ${p.severity} • model ${p.modelVersion}'), ExpansionTile(title: const Text('Treatment and prevention'), children: [ListTile(title: const Text('Treatment'), subtitle: Text(p.treatment)), ListTile(title: const Text('Prevention'), subtitle: Text(p.prevention))]), if (p.confidence < .7) const ListTile(leading: Icon(Icons.warning_amber), title: Text('Low-confidence result'), subtitle: Text('Request expert review before treatment.')), Wrap(spacing: 8, children: [OutlinedButton.icon(onPressed: job.reviewRequested ? null : onReview, icon: const Icon(Icons.verified_user_outlined), label: Text(job.reviewRequested ? 'Review pending' : 'Request expert review')), OutlinedButton.icon(onPressed: onShare, icon: const Icon(Icons.share_outlined), label: const Text('Share PDF report'))])]
  ]))); }
}

class _Comparison extends StatelessWidget { final DetectionJob job; final double fraction; const _Comparison({required this.job, required this.fraction}); @override Widget build(BuildContext context) { final after = job.prediction?.processedImage ?? job.compressedBytes ?? job.originalBytes; return LayoutBuilder(builder: (_, box) => SizedBox(height: 220, child: Stack(fit: StackFit.expand, children: [Image.memory(job.originalBytes, fit: BoxFit.cover), ClipRect(clipper: _FractionClipper(fraction), child: Image.memory(after, fit: BoxFit.cover)), Positioned(left: box.maxWidth * fraction - 1, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white))]))); } }
class _FractionClipper extends CustomClipper<Rect> { final double value; const _FractionClipper(this.value); @override Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * value, size.height); @override bool shouldReclip(_FractionClipper old) => old.value != value; }
