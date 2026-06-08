// lib/screens/download/download_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'download_controller.dart';

class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DownloadController(),
      child: const _DownloadView(),
    );
  }
}

class _DownloadView extends StatefulWidget {
  const _DownloadView();
  @override
  State<_DownloadView> createState() => _DownloadViewState();
}

class _DownloadViewState extends State<_DownloadView> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final ctl = context.watch<DownloadController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────
        Text('Téléchargements',
            style: TextStyle(
              color: cs.onSurface, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),

        // ── URL input ────────────────────────────────────────────────
        TextField(
          controller:  _ctrl,
          maxLines:    4,
          decoration:  const InputDecoration(
            hintText: 'Coller des URLs (une par ligne)…',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 12),

        // ── Actions ──────────────────────────────────────────────────
        Row(children: [
          ElevatedButton.icon(
            onPressed: () {
              context.read<DownloadController>().addUrls(_ctrl.text);
              _ctrl.clear();
            },
            icon:  const Icon(Icons.add_rounded),
            label: const Text('Ajouter'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: ctl.state == DownloadStatus.running
                ? null
                : () => context.read<DownloadController>().startQueue(),
            icon:  const Icon(Icons.play_arrow_rounded),
            label: const Text('Démarrer'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.read<DownloadController>().clearAll(),
            icon:  Icon(Icons.clear_all_rounded, color: cs.error),
            label: Text('Vider', style: TextStyle(color: cs.error)),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Queue list ───────────────────────────────────────────────
        Expanded(
          child: ctl.items.isEmpty
              ? Center(
                  child: Text('Aucune URL dans la file.',
                      style: TextStyle(color: cs.outline)),
                )
              : ListView.builder(
                  itemCount: ctl.items.length,
                  itemBuilder: (ctx, i) => _DownloadTile(
                    item:     ctl.items[i],
                    onRemove: () => context.read<DownloadController>().removeItem(i),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onRemove;
  const _DownloadTile({required this.item, required this.onRemove});

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
              Expanded(
                child: Text(item.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                onPressed: onRemove,
              ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value:            item.progress,
              backgroundColor:  cs.outline.withOpacity(0.2),
              color:            cs.primary,
              borderRadius:     BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(item.status,
                style: TextStyle(color: cs.outline, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}