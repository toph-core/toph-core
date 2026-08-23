import 'dart:async';
import 'dart:typed_data';

import 'package:alice_dio/alice_dio_adapter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/auth/models/auth_token_pair/auth_token_pair.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/auth/storage/token_storage_impl.dart';
import 'package:mary_ai_pos/core/services/auth/offline_auth_cache.dart';
import 'package:mary_ai_pos/core/services/connectivity/connectivity_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/data/data_sources/auth_datasource.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connectivity_platform.dart';
import 'support/in_memory_secure_storage.dart';

/// A PIN this terminal has already verified is answered locally, with no
/// request — even when the terminal is online.
///
/// The inverted case is what this pins. `verifyPincodeRole` used to be
/// online-first: it awaited `POST /login/pincode` whenever connectivity was
/// up and reached for the cache only after that request had failed. Offline
/// that was fine, because the connectivity check short-circuited it. The cost
/// landed on the *online* path — an authorization prompt in the middle of an
/// order waited on a round trip for an answer the terminal already had, and a
/// server that was reachable but slow delayed every one of them.
///
/// So a test that merely pulls the cable cannot tell the two versions apart:
/// both answer from the cache. This one keeps the terminal online and makes
/// the transport **hang** instead of fail. Local-first returns immediately;
/// online-first waits forever. That is the whole difference, and it is
/// otherwise invisible.
class HangingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    // Never completes. A caller that awaits this never returns.
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HangingAdapter adapter;
  late AuthDatasourceImpl datasource;
  late OfflineAuthCache cache;
  late AppTokenStorage storage;

  const brandId = 'brand-1';
  const pincode = '1234';

  setUp(() async {
    InMemorySecureStoragePlatform.install();
    FakeConnectivityPlatform.install(initial: [ConnectivityResult.wifi]);

    SharedPreferences.setMockInitialValues({});
    const secure = FlutterSecureStorage();
    storage = AppTokenStorage(await SharedPreferences.getInstance(), secure);
    cache = const OfflineAuthCache(secure);

    final connectivity = ConnectivityCubit(Connectivity());
    // The cubit's own reachability probe would otherwise decide this terminal
    // is offline the moment the hanging adapter times it out, which would let
    // an online-first implementation pass by taking its offline branch.
    connectivity.emit(true);

    final client = DioClient(storage, connectivity);
    // The Alice inspector interceptor throws `LateInitializationError` outside
    // a running app (its core is initialised by the app shell), which would
    // kill every request before the adapter saw it — and a request that never
    // leaves would make the hanging transport meaningless.
    client.dio.interceptors.removeWhere((i) => i is AliceDioAdapter);
    adapter = HangingAdapter();
    client.dio.httpClientAdapter = adapter;

    datasource = AuthDatasourceImpl(client, storage, cache);

    await storage.writeBrandIdToken(
      const BrandIdTokenPair(brandId: brandId, password: 'brand-password'),
    );
    // A session token has to exist or the auth interceptor rejects the
    // request before it ever reaches [adapter] — which would make the
    // hanging transport a no-op and the first test below a false pass.
    await storage.writeAuthToken(
      const AuthTokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );
  });

  test('a cached PIN is verified locally, while online, with the network hung',
      () async {
    await cache.saveForPin(
      brandId: brandId,
      pincode: pincode,
      user: const UserModel(id: 'u1', fullName: 'Aziza', username: 'aziza'),
      accessToken: 'access',
      refreshToken: 'refresh',
    );

    final result = await datasource
        .verifyPincodeRole(pincode)
        // Generous enough that a slow machine does not fail this, short
        // enough that a regression to online-first fails it rather than
        // hanging the suite.
        .timeout(const Duration(seconds: 5));

    expect(
      result.isRight(),
      isTrue,
      reason: 'the cached PIN was not accepted from local state',
    );
    result.fold((_) {}, (user) => expect(user.id, 'u1'));
  });

  test('the control: an uncached PIN does reach the hung transport', () async {
    // This is what makes the test above mean anything. If a request could not
    // leave — rejected by an interceptor, say — then "returned quickly" would
    // prove nothing, because *every* version of this code would return
    // quickly. So: a PIN with no local answer must genuinely go out, reach
    // [adapter], and hang there.
    //
    // It is also the other half of the contract. Cache-first is not
    // "never ask": a PIN never seen on this terminal is the first use of it,
    // which is exactly what the initial setup pull exists for.
    var completed = false;
    unawaited(datasource.verifyPincodeRole('9999').then((_) {
      completed = true;
    }));

    // Long enough for the request to be built, dispatched and handed to the
    // adapter; the adapter never answers, so nothing can complete after it.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      adapter.requests.map((r) => r.uri.path),
      isNotEmpty,
      reason: 'an uncached PIN was answered without consulting the server',
    );
    expect(
      completed,
      isFalse,
      reason: 'the transport did not actually hang, so the cached-PIN test '
          'above proves nothing',
    );
  });
}
