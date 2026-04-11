import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/usecase/usecase.dart';
import 'package:mary_ai_pos/core/utils/helper/helper_widget.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';
import 'package:mary_ai_pos/features/view/auth/domain/usecases/user/get_user_usecase.dart';
import 'package:mary_ai_pos/features/view/main/domain/usecase/sync_printer_settings_usecase.dart';
part 'user_event.dart';
part 'user_state.dart';
part 'user_bloc.freezed.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  late final GetUserUsecase _getUserUsecase;
  late final SyncPrinterSettingsUsecase _syncPrinterSettingsUsecase;

  UserBloc({
    required GetUserUsecase getUserUsecase,
    required SyncPrinterSettingsUsecase syncPrinterSettingsUsecase,
  }) : _getUserUsecase = getUserUsecase,
       _syncPrinterSettingsUsecase = syncPrinterSettingsUsecase,
       super(const UserState()) {
    on<_Started>(_started);
    on<_GetUser>(_getUser);
  }

  void _getUser(_GetUser event, emit) async {
    emit(state.copyWith(status: Status.LOADING));
    final response = await _getUserUsecase.call(NoParams());
    response.fold(
      (l) {
        // Token invalid or expired — force back to login
        Navigator.pushNamedAndRemoveUntil(
          navigatorKey.currentContext!,
          AppRoutes.loginScreen,
          (route) => false,
        );
        emit(state.copyWith(status: Status.ERROR, failure: l));
      },
      (r) {
        // Navigation already happened in splash screen — just emit user data
        emit(state.copyWith(status: Status.SUCCESS, userMOdel: r));
        unawaited(
          _syncPrinterSettingsUsecase.call(NoParams()).then((sync) {
            sync.fold(
              (f) {
                if (kDebugMode) {
                  debugPrint('[UserBloc] Printer settings sync: $f');
                }
              },
              (_) {},
            );
          }),
        );
      },
    );
  }

  void _started(_Started event, emit) => emit(const UserState());
}
