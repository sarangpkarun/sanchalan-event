import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/organizer.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/bottom_action_bar.dart';
import '../../shared/widgets/primary_button.dart';

/// One-time profile step after the first login: just the name. Who is organizing is asked per event.
class ProfileSetupView extends StatefulWidget {
  const ProfileSetupView({
    super.key,
    required this.onSubmit,
    this.initial,
    this.onBack,
  });

  final Future<String?> Function(UpdateOrganizerProfileBody body) onSubmit;

  /// Set when editing an existing profile instead of the first-time setup.
  final Organizer? initial;
  final VoidCallback? onBack;

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late final _name = TextEditingController(
    text: widget.initial?.displayName ?? '',
  );
  bool _showErrors = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _showErrors = true;
      _error = null;
    });
    if (_name.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    final error = await widget.onSubmit(
      UpdateOrganizerProfileBody(displayName: _name.text.trim()),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = widget.initial != null;
    return Scaffold(
      appBar: editing
          ? AppBar(
              title: const Text('Edit profile'),
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed:
                    widget.onBack ?? () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  editing ? AppSpace.s : AppSpace.xxl,
                  AppSpace.xl,
                  AppSpace.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!editing) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          'Tell us about you',
                          style: text.headlineLarge?.copyWith(
                            color: AppColors.maroon,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s),
                      Text(
                        'What should we call you? You choose who is organizing each event when you create it.',
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: AppSpace.xl),
                    ],
                    AppTextField(
                      label: 'Your name',
                      controller: _name,
                      hint: 'e.g. Priya Sharma',
                      errorText: _showErrors && _name.text.trim().isEmpty
                          ? 'Please enter your name.'
                          : null,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpace.m),
                      Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.errorText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            BottomActionBar(
              children: [
                PrimaryButton(
                  label: editing ? 'Save' : 'Continue',
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
