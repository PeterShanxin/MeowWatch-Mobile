import 'package:flutter/material.dart';

import '../shared/invitation_scanner.dart';

Future<String?> scanNearbyInvitation(BuildContext context) =>
    showInvitationScanner(context, InvitationScanPurpose.nearby);
