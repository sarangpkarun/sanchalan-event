import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/ui_feedback.dart';
import '../../models/enums.dart';
import '../../models/event.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/organizer.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/primary_button.dart';
import 'widgets/vendor_card.dart';

/// Profile tab: who is signed in, with an option to edit and to sign out.
class OrganizerProfileView extends StatelessWidget {
  const OrganizerProfileView({
    super.key,
    required this.organizer,
    this.events = const [],
    this.today,
    this.onEdit,
    this.onSignOut,
  });

  final Organizer organizer;

  /// The organizer's events, for the numbers at the top.
  final List<EventGroup> events;
  final DateTime? today;
  final VoidCallback? onEdit;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = organizer.displayName ?? 'Organizer';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Profile'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.s, AppSpace.gutter, AppSpace.xxl),
        children: [
          AppCard(
            child: Column(
              children: [
                VendorAvatar(name: name, size: 72),
                const SizedBox(height: AppSpace.m),
                Text(name, style: text.headlineSmall, textAlign: TextAlign.center),
                if (organizer.organizerType != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${organizerTypeLabel(organizer.organizerType!)} organizer',
                      style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
                const SizedBox(height: AppSpace.l),
                const Divider(),
                const SizedBox(height: AppSpace.m),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, color: AppColors.maroon),
                    const SizedBox(width: AppSpace.m),
                    Expanded(child: Text(organizer.phoneNumber, style: text.titleMedium)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.m),
          _StatsRow(events: events, today: today),
          const SizedBox(height: AppSpace.m),
          SecondaryButton(label: 'Edit profile', icon: Icons.edit_outlined, onPressed: onEdit),
          const SizedBox(height: AppSpace.l),
          const _SectionLabel('My plans'),
          _TileGroup(tiles: [
            _Tile(Icons.favorite_border, 'Saved vendors', 'Vendors you bookmarked'),
            _Tile(Icons.receipt_long_outlined, 'Bookings and payments', 'Quotes, bookings and receipts'),
          ]),
          const SizedBox(height: AppSpace.l),
          const _SectionLabel('Settings'),
          _TileGroup(tiles: [
            _Tile(Icons.notifications_none, 'Notifications', 'Reminders for tasks and payments'),
            _Tile(Icons.language, 'Language', 'English'),
          ]),
          const SizedBox(height: AppSpace.l),
          const _SectionLabel('Support'),
          _TileGroup(tiles: [
            _Tile(Icons.help_outline, 'Help and support', supportEmail, soon: false),
            _Tile(Icons.info_outline, 'About SetzO', 'Version 1.0'),
            _Tile(Icons.privacy_tip_outlined, 'Privacy and terms', 'How we use your data'),
            _Tile(Icons.delete_outline, 'Delete account', 'Remove your data from SetzO', danger: true),
          ]),
          const SizedBox(height: AppSpace.xxl),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
          ),
        ],
      ),
    );
  }
}


class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.events, this.today});

  final List<EventGroup> events;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final now = dateOnly(today ?? DateTime.now());
    final done = events.where((e) => e.status == EventGroupStatus.completed).length;
    final upcoming = events
        .where((e) =>
            e.status != EventGroupStatus.completed &&
            e.status != EventGroupStatus.archived &&
            !dateOnly(e.primaryDate).isBefore(now))
        .length;
    return Row(
      children: [
        Expanded(child: _Stat(value: events.length, label: 'Events')),
        const SizedBox(width: AppSpace.s),
        Expanded(child: _Stat(value: upcoming, label: 'Upcoming')),
        const SizedBox(width: AppSpace.s),
        Expanded(child: _Stat(value: done, label: 'Completed')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        children: [
          Text('$value', style: text.headlineSmall?.copyWith(color: AppColors.maroon)),
          Text(label, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s, left: AppSpace.xs),
        child: Semantics(header: true, child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
      );
}

class _Tile {
  const _Tile(this.icon, this.title, this.subtitle, {this.soon = true, this.danger = false});

  final IconData icon;
  final String title;
  final String subtitle;

  /// True for placeholders that have no feature behind them yet.
  final bool soon;
  final bool danger;
}

class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(tiles[i].icon, color: tiles[i].danger ? AppColors.errorText : AppColors.maroon),
              title: Text(
                tiles[i].title,
                style: tiles[i].danger ? TextStyle(color: AppColors.errorText) : null,
              ),
              subtitle: Text(tiles[i].subtitle),
              trailing: tiles[i].soon ? const Text('Soon') : const Icon(Icons.chevron_right),
              onTap: () => showToast(
                context,
                tiles[i].soon ? '${tiles[i].title} is coming soon' : 'Write to ${tiles[i].subtitle}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
