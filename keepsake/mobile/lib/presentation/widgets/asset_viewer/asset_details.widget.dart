import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/appears_in_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/asset_owner_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/date_time_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/description.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/drag_handle.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/location_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/people_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/rating_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/tag_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/technical_details.widget.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/asset.provider.dart';
import 'package:immich_ui/immich_ui.dart';

class AssetDetails extends ConsumerWidget {
  final BaseAsset asset;
  final double minHeight;

  const AssetDetails({super.key, required this.asset, required this.minHeight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exifInfo = ref.watch(assetExifProvider(asset)).valueOrNull;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ImmichRadius.xl)),
        border: Border(top: BorderSide(color: context.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            DateTimeDetails(asset: asset, exifInfo: exifInfo),
            _VaultStatusPill(storage: asset.storage),
            AssetOwnerDetails(asset: asset),
            SheetAssetDescription(asset: asset, exifInfo: exifInfo),
            PeopleDetails(asset: asset),
            LocationDetails(asset: asset, exifInfo: exifInfo),
            TechnicalDetails(asset: asset, exifInfo: exifInfo),
            RatingDetails(exifInfo: exifInfo),
            AppearsInDetails(asset: asset),
            TagDetails(asset: asset),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _VaultStatusPill extends StatelessWidget {
  final AssetState storage;

  const _VaultStatusPill({required this.storage});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final colors = context.immichColors;

    final (icon, label, bg, fg) = switch (storage) {
      AssetState.merged => (
        Icons.verified_user_outlined,
        'Backed up in Telegram vault & on device',
        colors.successContainer,
        colors.onSuccessContainer,
      ),
      AssetState.remote => (
        Icons.cloud_done_outlined,
        'Stored in Telegram vault',
        colors.infoContainer,
        colors.onInfoContainer,
      ),
      AssetState.local => (
        Icons.smartphone_outlined,
        'On device only',
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: context.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
