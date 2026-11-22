import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/models/albums/album_search.model.dart';
import 'package:immich_mobile/presentation/widgets/album/album_tile.dart';
import 'package:immich_mobile/presentation/widgets/album/new_album_name_modal.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/providers/album/album_sort_by_options.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/album_filter.utils.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:sliver_tools/sliver_tools.dart';

typedef AlbumSelectorCallback = void Function(RemoteAlbum album);


const bool _serverless = true;

class AlbumSelector extends ConsumerStatefulWidget {
  final AlbumSelectorCallback onAlbumSelected;
  final Function? onKeyboardExpanded;

  const AlbumSelector({super.key, required this.onAlbumSelected, this.onKeyboardExpanded});

  @override
  ConsumerState<AlbumSelector> createState() => _AlbumSelectorState();
}

class _AlbumSelectorState extends ConsumerState<AlbumSelector> {
  bool isGrid = false;
  final searchController = TextEditingController();
  final menuController = MenuController();
  final searchFocusNode = FocusNode();
  List<RemoteAlbum> sortedAlbums = [];
  List<RemoteAlbum> shownAlbums = [];

  AlbumFilter filter = const AlbumFilter(query: "", mode: QuickFilterMode.all);
  AlbumSort sort = const AlbumSort(mode: AlbumSortMode.lastModified, isReverse: true);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final albumConfig = ref.read(appConfigProvider).album;

      setState(() {
        sort = AlbumSort(mode: albumConfig.sortMode, isReverse: albumConfig.isReverse);
        isGrid = albumConfig.isGrid;
      });

      unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
    });

    searchController.addListener(() {
      onSearch(searchController.text, filter.mode);
    });

    searchFocusNode.addListener(() {
      if (searchFocusNode.hasFocus) {
        widget.onKeyboardExpanded?.call();
      }
    });
  }

  void onSearch(String searchTerm, QuickFilterMode filterMode) {
    final userId = ref.read(currentUserProvider)?.id;
    filter = filter.copyWith(query: searchTerm, userId: userId, mode: filterMode);

    unawaited(filterAlbums());
  }

  void toggleViewMode() {
    setState(() {
      isGrid = !isGrid;
    });
    unawaited(ref.read(settingsProvider).write(.albumIsGrid, isGrid));
  }

  void changeFilter(QuickFilterMode mode) {
    setState(() {
      filter = filter.copyWith(mode: mode);
    });

    unawaited(filterAlbums());
  }

  Future<void> changeSort(AlbumSort sort) async {
    setState(() {
      this.sort = sort;
    });

    final metadata = ref.read(settingsProvider);
    await metadata.write(.albumSortMode, sort.mode);
    await metadata.write(.albumIsReverse, sort.isReverse);

    await sortAlbums();
  }

  void clearSearch() {
    setState(() {
      filter = filter.copyWith(mode: QuickFilterMode.all, query: null);
      searchController.clear();
    });

    unawaited(filterAlbums());
  }

  Future<void> sortAlbums() async {
    final sorted = await ref
        .read(remoteAlbumProvider.notifier)
        .sortAlbums(ref.read(remoteAlbumProvider).albums, sort.mode, isReverse: sort.isReverse);

    if (!mounted) {
      return;
    }

    setState(() {
      sortedAlbums = sorted;
    });

    // we need to re-filter the albums after sorting
    // so shownAlbums gets updated
    unawaited(filterAlbums());
  }

  Future<void> filterAlbums() async {
    if (filter.query == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        shownAlbums = sortedAlbums;
      });

      return;
    }

    final filteredAlbums = ref
        .read(remoteAlbumProvider.notifier)
        .searchAlbums(sortedAlbums, filter.query!, filter.userId, filter.mode);

    if (!mounted) {
      return;
    }

    setState(() {
      shownAlbums = filteredAlbums;
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserProvider.select((user) => user?.id));

    // refilter and sort when albums change
    ref.listen(remoteAlbumProvider.select((state) => state.albums), (_, _) async {
      await sortAlbums();
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        menuController.close();
      },
      child: MultiSliver(
        children: [
          _SearchBar(
            searchController: searchController,
            searchFocusNode: searchFocusNode,
            onSearch: onSearch,
            filterMode: filter.mode,
            onClearSearch: clearSearch,
          ),
          _QuickFilterButtonRow(
            filterMode: filter.mode,
            onChangeFilter: changeFilter,
            onSearch: onSearch,
            searchController: searchController,
          ),
          _QuickSortAndViewMode(
            isGrid: isGrid,
            onToggleViewMode: toggleViewMode,
            onSortChanged: changeSort,
            controller: menuController,
            currentSortMode: sort.mode,
            currentIsReverse: sort.isReverse,
          ),
          isGrid
              ? _AlbumGrid(
                  albums: shownAlbums,
                  hasAnyAlbums: sortedAlbums.isNotEmpty,
                  searchQuery: searchController.text,
                  onClearSearch: clearSearch,
                  userId: userId,
                  onAlbumSelected: widget.onAlbumSelected,
                )
              : _AlbumList(
                  albums: shownAlbums,
                  hasAnyAlbums: sortedAlbums.isNotEmpty,
                  searchQuery: searchController.text,
                  onClearSearch: clearSearch,
                  userId: userId,
                  onAlbumSelected: widget.onAlbumSelected,
                ),
        ],
      ),
    );
  }
}

class _SortButton extends ConsumerStatefulWidget {
  const _SortButton(
    this.onSortChanged, {
    required this.initialSortMode,
    required this.initialIsReverse,
    this.controller,
  });

  final Future<void> Function(AlbumSort) onSortChanged;
  final MenuController? controller;
  final AlbumSortMode initialSortMode;
  final bool initialIsReverse;

  @override
  ConsumerState<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends ConsumerState<_SortButton> {
  late AlbumSortMode albumSortOption;
  late bool albumSortIsReverse;
  bool isSorting = false;

  @override
  void initState() {
    super.initState();
    albumSortOption = widget.initialSortMode;
    albumSortIsReverse = widget.initialIsReverse;
  }

  @override
  void didUpdateWidget(_SortButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSortMode != widget.initialSortMode || oldWidget.initialIsReverse != widget.initialIsReverse) {
      setState(() {
        albumSortOption = widget.initialSortMode;
        albumSortIsReverse = widget.initialIsReverse;
      });
    }
  }

  Future<void> onMenuTapped(AlbumSortMode sortMode) async {
    final selected = albumSortOption == sortMode;
    // Switch direction
    if (selected) {
      setState(() {
        albumSortIsReverse = !albumSortIsReverse;
        isSorting = true;
      });
    } else {
      setState(() {
        albumSortOption = sortMode;
        isSorting = true;
        // reset sort order to default state when switching option
        albumSortIsReverse = false;
      });
    }

    await widget.onSortChanged.call(AlbumSort(mode: albumSortOption, isReverse: albumSortIsReverse));

    setState(() {
      isSorting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveOrder = albumSortOption.effectiveOrder(albumSortIsReverse);
    return MenuAnchor(
      controller: widget.controller,
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(1),
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      ),
      consumeOutsideTap: true,
      menuChildren: AlbumSortMode.values
          .map(
            (sortMode) {
              final isSelected = albumSortOption == sortMode;
              return MenuItemButton(
                leadingIcon: isSelected
                    ? Icon(
                        effectiveOrder == SortOrder.desc
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: context.colorScheme.onPrimaryContainer,
                      )
                    : const SizedBox(width: 24),
                onPressed: () => onMenuTapped(sortMode),
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.fromLTRB(12, 12, 24, 12)),
                  backgroundColor: WidgetStateProperty.all(
                    isSelected ? context.colorScheme.primaryContainer : Colors.transparent,
                  ),
                  shape: WidgetStateProperty.all(
                    const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.md))),
                  ),
                ),
                child: Text(
                  sortMode.label(context.t),
                  style: context.textTheme.labelLarge?.copyWith(
                    color: isSelected ? context.colorScheme.onPrimaryContainer : context.colorScheme.onSurface,
                  ),
                ),
              );
            },
          )
          .toList(),
      builder: (context, controller, child) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.pill)),
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    effectiveOrder == SortOrder.desc
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    albumSortOption.label(context.t),
                    style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurface),
                  ),
                  if (isSorting) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearch,
    required this.filterMode,
    required this.onClearSearch,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final void Function(String, QuickFilterMode) onSearch;
  final QuickFilterMode filterMode;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      sliver: SliverToBoxAdapter(
        child: AmbrySearchBar(
          controller: searchController,
          focusNode: searchFocusNode,
          hintText: context.t.search_albums,
          onChanged: (value) => onSearch(value, filterMode),
          onClear: onClearSearch,
        ),
      ),
    );
  }
}

class _QuickFilterButtonRow extends StatelessWidget {
  const _QuickFilterButtonRow({
    required this.filterMode,
    required this.onChangeFilter,
    required this.onSearch,
    required this.searchController,
  });

  final QuickFilterMode filterMode;
  final void Function(QuickFilterMode) onChangeFilter;
  final void Function(String, QuickFilterMode) onSearch;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    // Serverless albums are never shared, so "All", "Shared with me" and "My albums" would list the same albums.
    if (_serverless) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _QuickFilterButton(
              label: context.t.all,
              isSelected: filterMode == QuickFilterMode.all,
              onTap: () {
                onChangeFilter(QuickFilterMode.all);
                onSearch(searchController.text, QuickFilterMode.all);
              },
            ),
            _QuickFilterButton(
              label: context.t.shared_with_me,
              isSelected: filterMode == QuickFilterMode.sharedWithMe,
              onTap: () {
                onChangeFilter(QuickFilterMode.sharedWithMe);
                onSearch(searchController.text, QuickFilterMode.sharedWithMe);
              },
            ),
            _QuickFilterButton(
              label: context.t.my_albums,
              isSelected: filterMode == QuickFilterMode.myAlbums,
              onTap: () {
                onChangeFilter(QuickFilterMode.myAlbums);
                onSearch(searchController.text, QuickFilterMode.myAlbums);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickFilterButton extends StatelessWidget {
  const _QuickFilterButton({required this.isSelected, required this.onTap, required this.label});

  final bool isSelected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(isSelected ? context.colorScheme.primary : Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: context.colorScheme.onSurface.withAlpha(25), width: 1),
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? context.colorScheme.onPrimary : context.colorScheme.onSurface,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _QuickSortAndViewMode extends StatelessWidget {
  const _QuickSortAndViewMode({
    required this.isGrid,
    required this.onToggleViewMode,
    required this.onSortChanged,
    required this.currentSortMode,
    required this.currentIsReverse,
    this.controller,
  });

  final bool isGrid;
  final VoidCallback onToggleViewMode;
  final MenuController? controller;
  final Future<void> Function(AlbumSort) onSortChanged;
  final AlbumSortMode currentSortMode;
  final bool currentIsReverse;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SortButton(
              onSortChanged,
              controller: controller,
              initialSortMode: currentSortMode,
              initialIsReverse: currentIsReverse,
            ),
            IconButton(
              tooltip: isGrid ? 'List view' : 'Grid view',
              icon: Icon(
                isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined,
                size: 22,
                color: context.colorScheme.onSurfaceVariant,
              ),
              onPressed: onToggleViewMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumEmptyState extends StatelessWidget {
  final bool hasAnyAlbums;
  final String searchQuery;
  final VoidCallback onClearSearch;

  const _AlbumEmptyState({
    required this.hasAnyAlbums,
    required this.searchQuery,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasAnyAlbums && searchQuery.trim().isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AmbryEmptyState(
          icon: Icons.photo_album_outlined,
          title: 'No albums yet',
          subtitle: 'Organize your photos and videos into private albums stored in your vault.',
          actionLabel: context.t.common_create_new_album,
          onAction: () => context.pushRoute(const CreateAlbumRoute()),
        ),
      );
    }

    return SliverFillRemaining(
      hasScrollBody: false,
      child: AmbryEmptyState(
        icon: Icons.search_off_rounded,
        title: context.t.album_search_not_found,
        subtitle: searchQuery.trim().isNotEmpty ? 'No albums match "${searchQuery.trim()}"' : null,
        actionLabel: 'Clear search',
        onAction: onClearSearch,
      ),
    );
  }
}

class _AlbumList extends ConsumerWidget {
  const _AlbumList({
    required this.albums,
    required this.hasAnyAlbums,
    required this.searchQuery,
    required this.onClearSearch,
    required this.userId,
    required this.onAlbumSelected,
  });

  final List<RemoteAlbum> albums;
  final bool hasAnyAlbums;
  final String searchQuery;
  final VoidCallback onClearSearch;
  final String? userId;
  final AlbumSelectorCallback onAlbumSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (albums.isEmpty) {
      return _AlbumEmptyState(
        hasAnyAlbums: hasAnyAlbums,
        searchQuery: searchQuery,
        onClearSearch: onClearSearch,
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 80.0),
      sliver: SliverList.builder(
        itemBuilder: (_, index) {
          final album = albums[index];
          final isOwner = album.ownerId == userId;

          if (isOwner) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
                child: Dismissible(
                  key: ValueKey(album.id),
                  background: Container(
                    color: context.colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete_outline_rounded, color: context.colorScheme.onError),
                  ),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) {
                    return showDialog<bool>(
                      context: context,
                      builder: (context) => ConfirmDialog(
                        onOk: () => true,
                        title: context.t.delete_album,
                        content: context.t.album_delete_confirmation(album: album.name),
                        ok: context.t.delete,
                      ),
                    );
                  },
                  onDismissed: (direction) async {
                    await ref.read(remoteAlbumProvider.notifier).deleteAlbum(album.id);
                  },
                  child: AlbumTile(album: album, isOwner: isOwner, onAlbumSelected: onAlbumSelected),
                ),
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: AlbumTile(album: album, isOwner: isOwner, onAlbumSelected: onAlbumSelected),
            );
          }
        },
        itemCount: albums.length,
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.hasAnyAlbums,
    required this.searchQuery,
    required this.onClearSearch,
    required this.userId,
    required this.onAlbumSelected,
  });

  final List<RemoteAlbum> albums;
  final bool hasAnyAlbums;
  final String searchQuery;
  final VoidCallback onClearSearch;
  final String? userId;
  final AlbumSelectorCallback onAlbumSelected;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return _AlbumEmptyState(
        hasAnyAlbums: hasAnyAlbums,
        searchQuery: searchQuery,
        onClearSearch: onClearSearch,
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 80.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.76,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final album = albums[index];
          return _GridAlbumCard(album: album, userId: userId, onAlbumSelected: onAlbumSelected);
        }, childCount: albums.length),
      ),
    );
  }
}

class _GridAlbumCard extends ConsumerWidget {
  const _GridAlbumCard({required this.album, required this.userId, required this.onAlbumSelected});

  final RemoteAlbum album;
  final String? userId;
  final AlbumSelectorCallback onAlbumSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumThumbnailAsset = ref.watch(assetServiceProvider).getRemoteAsset(album.thumbnailAssetId ?? "");

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
        onTap: () => onAlbumSelected(album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.lg)),
                child: FutureBuilder(
                  future: albumThumbnailAsset,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Thumbnail.remote(
                        remoteId: album.thumbnailAssetId!,
                        thumbhash: snapshot.data!.thumbHash ?? "",
                      );
                    }

                    return ColoredBox(
                      color: context.colorScheme.surfaceContainer,
                      child: Center(
                        child: Icon(
                          Icons.photo_album_outlined,
                          size: 36,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall?.copyWith(color: context.colorScheme.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                context.t.items_count(count: album.assetCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddToAlbumHeader extends ConsumerWidget {
  const AddToAlbumHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> onCreateAlbum() async {
      final albumName = await showDialog<String?>(context: context, builder: (context) => const NewAlbumNameModal());
      if (albumName == null || !context.mounted) {
        return;
      }

      final selectedAssets = ref.read(multiSelectProvider).selectedAssets;
      final newAlbum = await ref
          .read(remoteAlbumProvider.notifier)
          .createAlbumWithAssets(title: albumName, assets: selectedAssets);

      if (!context.mounted) {
        return;
      }

      if (newAlbum == null) {
        ImmichToast.show(context: context, toastType: ToastType.error, msg: context.t.errors.failed_to_create_album);
        return;
      }

      ref.read(multiSelectProvider.notifier).reset();
      unawaited(context.pushRoute(RemoteAlbumRoute(album: newAlbum)));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.t.add_to_album, style: context.textTheme.titleSmall),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // remove internal padding
                minimumSize: Size.zero, // allow shrinking
                tapTargetSize: MaterialTapTargetSize.shrinkWrap, // remove extra height
              ),
              onPressed: onCreateAlbum,
              icon: Icon(Icons.add, color: context.primaryColor),
              label: Text(
                context.t.common_create_new_album,
                style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateAlbumButton extends ConsumerWidget {
  const CreateAlbumButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> onCreateAlbum() async {
      final albumName = await showDialog<String?>(context: context, builder: (context) => const NewAlbumNameModal());
      if (albumName == null || !context.mounted) {
        return;
      }

      final asset = ref.read(assetViewerProvider).currentAsset;

      if (asset == null) {
        ImmichToast.show(context: context, msg: "Cannot load asset information.", toastType: ToastType.error);
        return;
      }

      final album = await ref
          .read(remoteAlbumProvider.notifier)
          .createAlbum(title: albumName, assetIds: [asset.remoteId!]);

      if (!context.mounted) {
        return;
      }

      if (album == null) {
        ImmichToast.show(context: context, toastType: ToastType.error, msg: context.t.errors.failed_to_create_album);
        return;
      }

      ImmichToast.show(
        context: context,
        msg: context.t.add_to_album_bottom_sheet_added(album: album.name),
      );

      // Invalidate using the asset's remote ID to refresh the "Appears in" list
      ref.invalidate(albumsContainingAssetProvider(asset.remoteId!));

      ContextHelper(context).pop();
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.t.add_to_album, style: context.textTheme.titleSmall),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onCreateAlbum,
              icon: Icon(Icons.add, color: context.primaryColor),
              label: Text(
                context.t.common_create_new_album,
                style: TextStyle(color: context.primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
