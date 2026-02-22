import 'package:flutter/material.dart';
import 'update_service.dart';

class UpdateServiceWrapper {
  Future<void> checkForUpdatesSilently(BuildContext context) async {
    return UpdateService.checkForUpdatesSilently(context);
  }
}
