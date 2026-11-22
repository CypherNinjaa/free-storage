import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/presentation/pages/memory.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_title.widget.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_ui/immich_ui.dart';

class MemoryLane extends ConsumerWidget {
  const MemoryLane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryLane = ref.watch(memoryLaneProvider);
    final memories = memoryLane.value ?? const [];
    if (memories.isEmpty) {
      return const SizedBox.shrink();
    }

    void handleTap(int index) {
      ref.read(hapticFeedbackProvider.notifier).heavyImpact();
      if (memories[index].assets.isNotEmpty) {
        MemoryPage.setMemory(ref, memories[index]);
      }
      unawaited(context.pushRoute(MemoryRoute(memories: memories, memoryIndex: index)));
    }

    return SizedBox(
      height: 204,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: memories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => SizedBox(
          key: Key(memories[index].id),
          width: 152,
          child: Material(
            color: Colors.black,
            elevation: 0,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.lg))),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MemoryCard(memory: memories[index]),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.12)),
                    onTap: () => handleTap(index),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final cover = memory.assets.isNotEmpty ? memory.assets.first : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          Thumbnail.remote(
            remoteId: cover.id,
            thumbhash: cover.thumbHash ?? "",
            fit: BoxFit.cover,
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: ImmichColors.scrimEditorial),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: MemoryTitle(
            memory: memory,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
