import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth/delete_account.dart';
import '../../application/auth/get_user_profile.dart';
import '../../application/transactions/get_activity_summary.dart';
import '../../domain/transactions/activity_summary.dart';
import '../../domain/user_data/user_data_repository.dart';
import '../../infrastructure/user_data/firestore_user_data_repository.dart';
import '../auth/auth_providers.dart';
import '../common/ai_providers.dart';
import '../transactions/transaction_providers.dart';

final userDataRepositoryProvider = Provider<UserDataRepository>((ref) {
  return FirestoreUserDataRepository();
});

final getUserProfileProvider = Provider<GetUserProfile>(
  (ref) => GetUserProfile(ref.watch(authRepositoryProvider)),
);

final getActivitySummaryProvider = Provider<GetActivitySummary>(
  (ref) => GetActivitySummary(ref.watch(transactionRepositoryProvider)),
);

final activitySummaryProvider = FutureProvider.autoDispose.family<ActivitySummary, String>(
  (ref, userId) => ref.watch(getActivitySummaryProvider)(userId: userId),
);

final deleteAccountProvider = Provider<DeleteAccount>(
  (ref) => DeleteAccount(
    ref.watch(authRepositoryProvider),
    ref.watch(userDataRepositoryProvider),
    ref.watch(transactionsChangeNotifierProvider),
  ),
);
