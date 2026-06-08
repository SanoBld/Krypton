// lib/screens/convert/convert_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'convert_controller.dart';

class ConvertScreen extends StatelessWidget {
  const ConvertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConvertController(),
      child: const _ConvertView(),
    );
  }
}

class _ConvertView extends StatelessWidget {
  const _ConvertView();

  Future<void> _pickFiles(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type:          FileType.media,
    );
    if (result == null) return;
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (context.mounted) {
      context.read<ConvertController>().addFiles(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final ctl = context.watch<ConvertController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────
        Text(
          'Batch conversion',
          style: TextStyle(
            color: cs.onSurface, fontSize: 22, fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),

        // ── Format selector + actions ────────────────────────────────
        Row(children: [
          // Format dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:        cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: cs.outline.withValues(alpha: 0.4)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value:         ctl.selectedFormat,
                dropdownColor: cs.surfaceContainerHighest,
                style:         TextStyle(color: cs.onSurface),
                items: ConvertController.supportedFormats
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())))
                    .toList(),
                onChanged: (v) {
                  if (v != null) context.read<ConvertController>().setFormat(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _pickFiles(context),
            icon:  const Icon(Icons.folder_open_rounded),
            label: const Text('Add files'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: ctl.state == ConvertStatus.running
                ? null
                : () => context.read<ConvertController>().startAll(),
            icon:  const Icon(Icons.play_arrow_rounded),
            label: const Text('Convert'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.read<ConvertController>().clearAll(),
            icon:  Icon(Icons.clear_all_rounded, color: cs.error),
            label: Text('Clear', style: TextStyle(color: cs.error)),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Jobs list ────────────────────────────────────────────────
        Expanded(
          child: ctl.jobs.isEmpty
              ? Center(
                  child: Text(
                    'No files added.',
                    style: TextStyle(color: cs.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: ctl.jobs.length,
                  itemBuilder: (ctx, i) => _ConvertTile(
                    job:      ctl.jobs[i],
                    onRemove: () => context.read<ConvertController>().removeJob(i),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ConvertTile extends StatelessWidget {
  final ConvertJob   job;
  final VoidCallback onRemove;
  const _ConvertTile({required this.job, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.audio_file_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.inputPath.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '→ ${job.outputFormat.toUpperCase()}',
                  style: TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                onPressed: onRemove,
              ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value:           job.progress,
              backgroundColor: cs.outline.withValues(alpha: 0.2),
              color:           cs.primary,
              borderRadius:    BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(job.status, style: TextStyle(color: cs.outline, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}