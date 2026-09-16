import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_services.dart';
import '../../core/billing/billing_service.dart';

const _navy = Color(0xFF10141F);
const _raised = Color(0xFF1A2232);
const _ivory = Color(0xFFF5EDE0);
const _apricot = Color(0xFFEFB38C);
const _lavender = Color(0xFFB9A9D3);

Future<bool?> showPaywallSheet(
  BuildContext context, {
  required AppController app,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.68),
  builder: (_) => _PaywallSheet(app: app),
);

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({required this.app});

  final AppController app;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  String? _message;
  bool _preparing = true;

  BillingService get _billing => widget.app.billing;

  @override
  void initState() {
    super.initState();
    // Billing notifies the app as soon as refresh begins. Wait until the sheet
    // is mounted before rebuilding listeners above this route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prepare();
    });
  }

  Future<void> _prepare() async {
    final result = _billing.isConfigured
        ? await _billing.refresh()
        : await _billing.configure();
    if (!mounted) return;
    setState(() {
      _preparing = false;
      if (!result.succeeded && result.status != BillingStatus.cancelled) {
        _message = result.message ?? 'Plans are unavailable right now.';
      }
    });
  }

  Future<void> _purchase(Package package) async {
    setState(() => _message = null);
    final result = await _billing.purchase(package);
    if (!mounted) return;
    if (_billing.isPlus) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _message = switch (result.status) {
        BillingStatus.cancelled => result.message ?? 'Purchase cancelled.',
        BillingStatus.success =>
          'The purchase finished, but Plus is not active yet. Try Restore purchases.',
        BillingStatus.failure || BillingStatus.unavailable =>
          result.message ?? 'The store could not complete this request.',
      };
    });
  }

  Future<void> _restore() async {
    setState(() => _message = null);
    BillingResult result;
    if (!_billing.isConfigured) {
      result = await _billing.configure();
      if (result.succeeded && !_billing.isPlus) {
        result = await _billing.restore();
      }
    } else {
      result = await _billing.restore();
    }
    if (!mounted) return;
    if (_billing.isPlus) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _message = result.status == BillingStatus.cancelled
          ? (result.message ?? 'Restore cancelled.')
          : result.succeeded
          ? 'No active Plus purchase was found for this store account.'
          : (result.message ?? 'Could not restore purchases right now.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight:
                (media.size.height - media.viewInsets.bottom).clamp(
                  0,
                  double.infinity,
                ) *
                0.94,
          ),
          child: Material(
            color: _navy,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AnimatedBuilder(
              animation: _billing,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: _billing.isBusy
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: _ivory),
                      ),
                    ),
                    const Icon(
                      Icons.nightlight_round,
                      color: _apricot,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _billing.isPlus
                          ? 'Your movie nights are unlimited.'
                          : 'More movie nights.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: _ivory,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _billing.isPlus
                          ? 'MeowWatch Plus is active on this store account.'
                          : 'Host as many Together Sessions as you like. Your guests always join free.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _ivory.withValues(alpha: 0.82),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Benefit(
                      icon: Icons.all_inclusive,
                      title: 'Unlimited hosting',
                      detail: 'Start another shared watch whenever you want.',
                    ),
                    const SizedBox(height: 12),
                    const _Benefit(
                      icon: Icons.group_outlined,
                      title: 'Guests always join free',
                      detail: 'Friends never need Plus to join your room.',
                    ),
                    const SizedBox(height: 12),
                    const _Benefit(
                      icon: Icons.wb_sunny_outlined,
                      title: 'A real free session every day',
                      detail:
                          'Without Plus, you can still host one new Together Session per local day.',
                    ),
                    if (usesTestStore) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _lavender.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _lavender.withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.science_outlined, color: _lavender),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'RevenueCat Test Store · sandbox purchase, no real charge.',
                                style: TextStyle(color: _ivory, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _apricot, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_preparing || _billing.isBusy)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: CircularProgressIndicator(color: _apricot),
                        ),
                      )
                    else if (_billing.isPlus)
                      _PrimaryButton(
                        label: 'Done',
                        onPressed: () => Navigator.of(context).pop(true),
                      )
                    else if (_billing.packages.isEmpty)
                      const Text(
                        'No purchase option is available right now. You can try again or restore an existing purchase.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _ivory),
                      )
                    else
                      ..._billing.packages.map(
                        (package) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PrimaryButton(
                            key: ValueKey('purchase-${package.identifier}'),
                            label:
                                'Continue · ${package.storeProduct.priceString}',
                            onPressed: () => _purchase(package),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _lavender,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _billing.isBusy ? null : _restore,
                      child: const Text('Restore purchases'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _ivory.withValues(alpha: 0.72),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _billing.isBusy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Maybe tomorrow'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _raised,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _apricot),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _ivory,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  color: _ivory.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: _apricot,
      foregroundColor: _navy,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
