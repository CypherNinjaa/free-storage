import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/images/local_album_thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/user.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';
import 'package:immich_mobile/widgets/map/map_thumbnail.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

@RoutePage()
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CustomScrollView(
        slivers: [
          ImmichSliverAppBar(snap: false, floating: false, pinned: true, showUploadButton: false),
          _ActionButtonGrid(),
          _CollectionCards(),
          SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class _ActionButtonGrid extends ConsumerWidget {
  const _ActionButtonGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTrashEnable = ref.watch(serverInfoProvider.select((state) => state.serverFeatures.trash));

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            _ActionButton(
              icon: Icons.favorite_outline_rounded,
              onTap: () => context.pushRoute(const FavoriteRoute()),
              label: context.t.favorites,
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.archive_outlined,
              onTap: () => context.pushRoute(const ArchiveRoute()),
              label: context.t.archived,
            ),
            if (isTrashEnable) ...[
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => context.pushRoute(const TrashRoute()),
                label: context.t.trash,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Expanded(
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelLarge?.copyWith(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionCards extends StatelessWidget {
  const _CollectionCards();

  @override
  Widget build(BuildContext context) {
    return const SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlacesHeroCard(),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _LocalAlbumsCollectionCard()),
                SizedBox(width: 12),
                Expanded(child: _MemoriesCollectionCard()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlacesHeroCard extends StatelessWidget {
  const _PlacesHeroCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushRoute(MapRoute()),
        child: SizedBox(
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: MapThumbnail(
                  zoom: 8,
                  centre: const LatLng(21.44950, -157.91959),
                  showAttribution: false,
                  themeMode: context.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(gradient: ImmichColors.scrimEditorial)),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: const BoxDecoration(
                        color: Color(0x94000000),
                        borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            context.t.places,
                            style: context.textTheme.labelLarge?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
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

class _LocalAlbumsCollectionCard extends ConsumerWidget {
  const _LocalAlbumsCollectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(localAlbumProvider);
    final scheme = context.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        onTap: () => context.pushRoute(const LocalAlbumsRoute()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                clipBehavior: Clip.antiAlias,
                child: albums.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return Center(
                        child: Icon(Icons.smartphone_outlined, size: 32, color: scheme.onSurfaceVariant),
                      );
                    }
                    return GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.all(10),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: data.take(4).map((album) {
                        return ClipRRect(
                          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
                          child: LocalAlbumThumbnail(albumId: album.id),
                        );
                      }).toList(),
                    );
                  },
                  error: (error, _) => Center(
                    child: Icon(Icons.error_outline_rounded, size: 28, color: scheme.error),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                context.t.on_this_device,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoriesCollectionCard extends ConsumerWidget {
  const _MemoriesCollectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(allMemoriesProvider(false));
    final scheme = context.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        onTap: () => context.pushRoute(const MemoryListRoute()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                clipBehavior: Clip.antiAlias,
                child: memories.widgetWhen(
                  onLoading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  onData: (memories) {
                    final covers = memories.where((m) => m.assets.isNotEmpty).take(4).toList();
                    if (covers.isEmpty) {
                      return Center(
                        child: Icon(Icons.auto_awesome_outlined, size: 32, color: scheme.onSurfaceVariant),
                      );
                    }
                    return GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.all(10),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: covers.map((memory) {
                        return ClipRRect(
                          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
                          child: Thumbnail.remote(
                            remoteId: memory.assets.first.id,
                            thumbhash: memory.assets.first.thumbHash ?? "",
                            fit: BoxFit.cover,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                context.t.memories,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
final sharedWithPartnerProvider = StreamProvider.autoDispose<Iterable<Partner>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) {
    return const .empty();
  }

  return ref.watch(partnerServiceProvider).search(currentUser.id, .sharedWith);
});
