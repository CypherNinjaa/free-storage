import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_ui/immich_ui.dart';

class TimelineHeader extends ConsumerWidget {
  final Bucket bucket;
  final HeaderType header;
  final double height;
  final int assetOffset;

  const TimelineHeader({
    super.key,
    required this.bucket,
    required this.header,
    required this.height,
    required this.assetOffset,
  });

  String _formatMonth(DateTime date) {
    final formatter = date.year == DateTime.now().year
        ? DateFormat.MMMM(resolvedDateTimeLocale())
        : DateFormat.yMMMM(resolvedDateTimeLocale());
    return formatter.format(date);
  }

  String _formatDay(DateTime date) {
    final formatter = DateFormat.yMMMEd(resolvedDateTimeLocale());
    return formatter.format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bucket is! TimeBucket || header == HeaderType.none) {
      return const SizedBox.shrink();
    }

    final date = (bucket as TimeBucket).date;
    final isMonthHeader = header == HeaderType.month || header == HeaderType.monthAndDay;
    final isDayHeader = header == HeaderType.day || header == HeaderType.monthAndDay;
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    void onToggleBucket() {
      if (isReadonlyModeEnabled) {
        return;
      }
      unawaited(ref.read(multiSelectProvider.notifier).toggleBucketSelection(assetOffset, bucket.assetCount));
      ref.read(hapticFeedbackProvider.notifier).heavyImpact();
    }

    return SizedBox(
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isReadonlyModeEnabled ? null : onToggleBucket,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isMonthHeader && isDayHeader ? MainAxisAlignment.end : MainAxisAlignment.center,
            children: [
              if (isMonthHeader)
                Padding(
                  padding: EdgeInsets.only(bottom: isDayHeader ? 4.0 : 0.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          toBeginningOfSentenceCase(_formatMonth(date)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.headlineSmall?.copyWith(color: context.colorScheme.onSurface),
                        ),
                      ),
                      if (header != HeaderType.monthAndDay)
                        _BulkSelectIconButton(bucket: bucket, assetOffset: assetOffset),
                    ],
                  ),
                ),
              if (isDayHeader)
                Padding(
                  padding: EdgeInsets.only(bottom: isMonthHeader ? 6.0 : 0.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          toBeginningOfSentenceCase(_formatDay(date)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleSmall?.copyWith(color: context.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      _BulkSelectIconButton(bucket: bucket, assetOffset: assetOffset),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkSelectIconButton extends ConsumerWidget {
  final Bucket bucket;
  final int assetOffset;

  const _BulkSelectIconButton({required this.bucket, required this.assetOffset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final isMultiSelectEnabled = ref.watch(multiSelectProvider.select((s) => s.isEnabled));
    if (isReadonlyModeEnabled) {
      return const SizedBox.shrink();
    }

    List<BaseAsset> bucketAssets;
    if (isMultiSelectEnabled) {
      try {
        bucketAssets = ref.watch(timelineServiceProvider).getAssets(assetOffset, bucket.assetCount);
      } catch (e) {
        bucketAssets = <BaseAsset>[];
      }
    } else {
      bucketAssets = const <BaseAsset>[];
    }

    final isAllSelected =
        isMultiSelectEnabled &&
        ref.watch(
          multiSelectProvider.select(
            (state) => bucketAssets.isNotEmpty && bucketAssets.every(state.selectedAssets.contains),
          ),
        );

    final duration = AmbryMotion.durationOf(context, AmbryMotion.dStandard);

    return IgnorePointer(
      ignoring: !isMultiSelectEnabled,
      child: AnimatedOpacity(
        duration: duration,
        curve: AmbryMotion.easeEffects,
        opacity: isMultiSelectEnabled ? 1.0 : 0.0,
        child: AnimatedScale(
          duration: duration,
          curve: AmbryMotion.easeSpatial,
          scale: isMultiSelectEnabled ? 1.0 : 0.75,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              unawaited(ref.read(multiSelectProvider.notifier).toggleBucketSelection(assetOffset, bucket.assetCount));
              ref.read(hapticFeedbackProvider.notifier).heavyImpact();
            },
            icon: isAllSelected
                ? Icon(Icons.check_circle_rounded, size: 24, color: context.colorScheme.primary)
                : Icon(Icons.radio_button_unchecked_rounded, size: 24, color: context.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
