import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show ProductCategory, RecurrenceMode;

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
  String? _selectedPackageId;

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
              builder: (context, _) {
                final packages = _billing.packages;
                final selected = packages.isEmpty
                    ? null
                    : packages.firstWhere(
                        (package) => package.identifier == _selectedPackageId,
                        orElse: () => packages.first,
                      );
                final plan = selected == null ? null : _PlanDetails(selected);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 12, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(Icons.nightlight_round, color: _apricot),
                          IconButton(
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
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          4,
                          24,
                          24 + media.padding.bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: _ivory.withValues(alpha: 0.82),
                                    height: 1.4,
                                  ),
                            ),
                            if (!_billing.isPlus) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Free includes one hosted session per local day.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _ivory.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                            if (usesTestStore) ...[
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(12),
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
                                    Icon(
                                      Icons.science_outlined,
                                      color: _lavender,
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'RevenueCat Test Store · no real charge.',
                                        style: TextStyle(
                                          color: _ivory,
                                          height: 1.35,
                                        ),
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
                                  style: const TextStyle(
                                    color: _apricot,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (_preparing || _billing.isBusy)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: CircularProgressIndicator(
                                    color: _apricot,
                                  ),
                                ),
                              )
                            else if (_billing.isPlus)
                              _PrimaryButton(
                                label: 'Done',
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                              )
                            else if (_billing.packages.isEmpty)
                              const Text(
                                'No purchase option is available right now. You can try again or restore an existing purchase.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _ivory),
                              )
                            else if (selected != null && plan != null) ...[
                              if (packages.length > 1) ...[
                                const Text(
                                  'Choose your plan',
                                  style: TextStyle(
                                    color: _ivory,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                RadioGroup<String>(
                                  groupValue: selected.identifier,
                                  onChanged: (value) => setState(
                                    () => _selectedPackageId = value,
                                  ),
                                  child: Column(
                                    children: packages.map((package) {
                                      final option = _PlanDetails(package);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Material(
                                          color: _raised,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: RadioListTile<String>(
                                            key: ValueKey(
                                              'plan-${package.identifier}',
                                            ),
                                            value: package.identifier,
                                            activeColor: _apricot,
                                            fillColor:
                                                WidgetStateProperty.resolveWith(
                                                  (states) =>
                                                      states.contains(
                                                        WidgetState.selected,
                                                      )
                                                      ? _apricot
                                                      : _lavender,
                                                ),
                                            title: Text(
                                              option.name,
                                              style: const TextStyle(
                                                color: _ivory,
                                              ),
                                            ),
                                            subtitle: Text(
                                              option.price,
                                              style: const TextStyle(
                                                color: _ivory,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 4,
                                                ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ] else
                                Text(
                                  plan.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _ivory,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                plan.renewal,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _ivory.withValues(alpha: 0.82),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _PrimaryButton(
                                key: ValueKey(
                                  'purchase-${selected.identifier}',
                                ),
                                label: 'Continue · ${plan.price}',
                                onPressed: () => _purchase(selected),
                              ),
                            ],
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanDetails {
  const _PlanDetails(this.package);
  final Package package;
  StoreProduct get product => package.storeProduct;
  bool get oneTime =>
      product.productCategory == ProductCategory.nonSubscription ||
      (package.packageType == PackageType.lifetime &&
          product.subscriptionPeriod == null);
  bool get prepaid =>
      product.defaultOption?.isPrepaid == true ||
      product.defaultOption?.fullPricePhase?.recurrenceMode ==
          RecurrenceMode.nonRecurring;

  (int, String)? get period {
    if (oneTime) return null;
    // Product metadata outranks the merchandising package name. Custom plans
    // can have a valid store period; missing periods use known SDK types only.
    final iso =
        product.subscriptionPeriod ??
        product.defaultOption?.billingPeriod?.iso8601 ??
        switch (package.packageType) {
          PackageType.annual => 'P1Y',
          PackageType.sixMonth => 'P6M',
          PackageType.threeMonth => 'P3M',
          PackageType.twoMonth => 'P2M',
          PackageType.monthly => 'P1M',
          PackageType.weekly => 'P1W',
          _ => null,
        };
    final match = iso == null
        ? null
        : RegExp(r'^P([1-9][0-9]*)([DWMY])$').firstMatch(iso);
    if (match == null) return null;
    final count = int.tryParse(match[1]!);
    if (count == null) return null;
    final unit = switch (match[2]) {
      'D' => 'day',
      'W' => 'week',
      'M' => 'month',
      _ => 'year',
    };
    return (count, unit);
  }

  String get duration {
    final (count, unit) = period!;
    return '$count $unit${count == 1 ? '' : 's'}';
  }

  String get name {
    if (oneTime) {
      return package.packageType == PackageType.lifetime
          ? 'Lifetime'
          : 'One-time purchase';
    }
    final value = period;
    if (value == null) {
      return product.title.isEmpty ? 'Store plan' : product.title;
    }
    final (count, unit) = value;
    if (prepaid) return '$duration prepaid';
    if (count != 1) return 'Every $duration';
    return switch (unit) {
      'day' => 'Daily',
      'week' => 'Weekly',
      'month' => 'Monthly',
      _ => 'Yearly',
    };
  }

  String get price {
    if (oneTime) return '${product.priceString} once';
    final value = period;
    if (value == null) return product.priceString;
    if (prepaid) return '${product.priceString} for $duration';
    final (count, unit) = value;
    return '${product.priceString} / ${count == 1 ? unit : duration}';
  }

  String get renewal {
    if (oneTime) return 'One-time purchase. No recurring subscription.';
    if (period == null) {
      return 'Review the billing period and renewal terms in the store before confirming.';
    }
    if (prepaid) return 'Access for $duration. Does not renew automatically.';
    if (usesTestStore) {
      return 'Test subscription. Renewals run on an accelerated schedule, then access expires automatically.';
    }
    if (product.defaultOption?.fullPricePhase?.recurrenceMode ==
            RecurrenceMode.infiniteRecurring &&
        product.defaultOption?.installmentsInfo == null) {
      return 'Renews every $duration until cancelled in your store account.';
    }
    return 'Billed every $duration. Review renewal and cancellation terms in the store before confirming.';
  }
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
    child: Text(label, textAlign: TextAlign.center),
  );
}
