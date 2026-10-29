import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/paths.dart';
import '../../../core/ui_feedback.dart';
import '../events_view.dart';
import '../organizer_repository.dart';
import '../sheets/join_dialog.dart';
import '../home_view.dart' show HomeStatus;
import '../organizer_providers.dart';

/// Events tab.
class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(organizerDataProvider);
    final data = async.value;
    return EventsView(
      status: data is OrganizerReady
          ? HomeStatus.ready
          : async.hasError
              ? HomeStatus.error
              : HomeStatus.loading,
      events: data is OrganizerReady ? data.eventGroups : const [],
      onRetry: () => ref.read(organizerDataProvider.notifier).refetch(),
      onRefresh: () => ref.read(organizerDataProvider.notifier).reloadEvents(),
      onOpenEvent: (id) => context.push(AppPaths.eventHome(id)),
      onNewEvent: () => context.push(AppPaths.eventSetup),
      onJoin: () async {
        final code = await showJoinDialog(context);
        if (code == null || !context.mounted) return;
        try {
          final r = await ref.read(organizerRepositoryProvider).joinEvent(code);
          await ref.read(organizerDataProvider.notifier).reloadEvents();
          if (!context.mounted) return;
          showToast(
            context,
            r.pending
                ? 'Request sent. ${r.eventName} will appear once the organizer approves.'
                : 'You joined ${r.eventName}.',
          );
        } catch (e) {
          if (context.mounted) showToast(context, friendlyError(e, 'Could not join with that code.'));
        }
      },
    );
  }
}
