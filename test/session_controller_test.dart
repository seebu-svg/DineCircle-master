import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/models/user_profile.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';

import 'fake_repositories.dart';

const String _tokenKey = 'dinecircle.auth.token';

void main() {
  group('SessionController', () {
    test('starts signed out when there is no stored token', () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
          sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
        ],
      );
      addTearDown(container.dispose);

      final session = await container.read(sessionControllerProvider.future);

      expect(session.signedIn, isFalse);
    });

    test('signing up persists the token and publishes the profile', () async {
      final storage = InMemorySecureStorage();
      final repo = FakeSessionRepository();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sessionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.future); // bootstrap
      await container
          .read(sessionControllerProvider.notifier)
          .signUp(
            name: 'Alex Rivera',
            email: 'alex@example.com',
            password: 'password123',
          );

      final session = container.read(sessionControllerProvider).requireValue;
      expect(session.signedIn, isTrue);
      expect(session.userId, 'u1');
      expect(repo.signUpCalls, 1);

      // The bearer token was written to (fake) secure storage.
      final stored = await storage.read(key: _tokenKey);
      expect(stored, 'fake-token');
    });

    test(
      'restores a signed-in session from a stored token via /auth/me',
      () async {
        final storage = InMemorySecureStorage();
        await storage.write(key: _tokenKey, value: 'tok');
        final repo = FakeSessionRepository();
        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            sessionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final session = await container.read(sessionControllerProvider.future);

        expect(session.signedIn, isTrue);
        expect(repo.meCalls, 1);
      },
    );

    test(
      'a rejected stored token drops back to signed-out and is cleared',
      () async {
        final storage = InMemorySecureStorage();
        await storage.write(key: _tokenKey, value: 'stale');
        final repo = FakeSessionRepository(error: StateError('token rejected'));
        final container = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            sessionRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final session = await container.read(sessionControllerProvider.future);

        expect(session.signedIn, isFalse);
        final stored = await storage.read(key: _tokenKey);
        expect(stored, isNull);
      },
    );

    test('signing out clears the stored token and state', () async {
      final storage = InMemorySecureStorage();
      await storage.write(key: _tokenKey, value: 'tok');
      final repo = FakeSessionRepository();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sessionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.future); // signed in
      await container.read(sessionControllerProvider.notifier).signOut();

      expect(
        container.read(sessionControllerProvider).requireValue.signedIn,
        isFalse,
      );
      expect(repo.signOutCalls, 1);
      final stored = await storage.read(key: _tokenKey);
      expect(stored, isNull);
    });
  });

  group('Account lifecycle (P1)', () {
    const signedInDto = UserDto(
      id: 'u1',
      name: 'Test Diner',
      role: 'user',
      email: 'diner@example.com',
      city: 'Karachi',
    );

    /// Boots a container with a stored token so bootstrap lands signed in as
    /// [signedInDto]; the users repository fake backs settings writes.
    Future<
      (
        ProviderContainer,
        InMemorySecureStorage,
        FakeSessionRepository,
        FakeUsersRepository,
      )
    >
    pumpSignedIn({
      Object? changePasswordError,
      Object? emailChangeError,
      Object? deleteAccountError,
    }) async {
      final storage = InMemorySecureStorage();
      await storage.write(key: _tokenKey, value: 'tok');
      final sessionRepo = FakeSessionRepository(
        user: signedInDto,
        changePasswordError: changePasswordError,
        emailChangeError: emailChangeError,
        deleteAccountError: deleteAccountError,
      );
      final usersRepo = FakeUsersRepository(
        meResult: const UserProfile(id: 'u1', name: 'Test Diner'),
      );
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sessionRepositoryProvider.overrideWithValue(sessionRepo),
          usersRepositoryProvider.overrideWithValue(usersRepo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionControllerProvider.future); // bootstrap
      return (container, storage, sessionRepo, usersRepo);
    }

    test(
      'updateSettings republishes the session and carries the email over',
      () async {
        final (container, _, _, users) = await pumpSignedIn();

        await container.read(sessionControllerProvider.notifier).updateSettings(
          {'showFollowList': false, 'homeArea': 'Gulberg'},
        );

        expect(users.patchSettingsCalls, 1);
        expect(users.lastSettingsPatch, {
          'showFollowList': false,
          'homeArea': 'Gulberg',
        });
        final user = container
            .read(sessionControllerProvider)
            .requireValue
            .user!;
        expect(user.showFollowList, isFalse);
        expect(user.homeArea, 'Gulberg');
        // /users/me payloads omit the email — the session must keep it.
        expect(user.email, 'diner@example.com');
      },
    );

    test('changePassword succeeds and keeps this device signed in', () async {
      final (container, _, repo, _) = await pumpSignedIn();

      await container
          .read(sessionControllerProvider.notifier)
          .changePassword(currentPassword: 'old12345', newPassword: 'new12345');

      expect(repo.changePasswordCalls, 1);
      expect(repo.lastCurrentPassword, 'old12345');
      expect(repo.lastNewPassword, 'new12345');
      final session = container.read(sessionControllerProvider).requireValue;
      expect(session.signedIn, isTrue);
      expect(session.user!.email, 'diner@example.com');
    });

    test(
      'a wrong current password throws and leaves the session intact',
      () async {
        final (container, _, _, _) = await pumpSignedIn(
          changePasswordError: const ApiException(
            ApiErrorKind.unauthorized,
            message: 'Your password is incorrect.',
            statusCode: 401,
          ),
        );

        await expectLater(
          container
              .read(sessionControllerProvider.notifier)
              .changePassword(
                currentPassword: 'nope',
                newPassword: 'whatever123',
              ),
          throwsA(isA<ApiException>()),
        );
        expect(
          container.read(sessionControllerProvider).requireValue.signedIn,
          isTrue,
        );
      },
    );

    test('email change only applies after the code confirms', () async {
      final (container, _, repo, _) = await pumpSignedIn();
      final controller = container.read(sessionControllerProvider.notifier);

      final challenge = await controller.requestEmailChange(
        email: 'moved@example.com',
        password: 'dinerpass',
      );
      expect(challenge.sent, isTrue);
      expect(challenge.pendingEmail, 'moved@example.com');
      expect(challenge.devCode, '654321');
      expect(repo.lastRequestedEmail, 'moved@example.com');
      // Staging the change must not touch the live session.
      expect(
        container.read(sessionControllerProvider).requireValue.user!.email,
        'diner@example.com',
      );

      await controller.confirmEmailChange(code: challenge.devCode!);
      expect(repo.confirmEmailChangeCalls, 1);
      expect(repo.lastConfirmedCode, '654321');
      expect(
        container.read(sessionControllerProvider).requireValue.user!.email,
        'moved@example.com',
      );
    });

    test(
      'logoutAllDevices clears the token even when the call fails',
      () async {
        final (container, storage, repo, _) = await pumpSignedIn();
        repo.error = ApiException(ApiErrorKind.network, message: 'offline');

        await container
            .read(sessionControllerProvider.notifier)
            .logoutAllDevices();

        expect(repo.logoutAllCalls, 1);
        expect(
          container.read(sessionControllerProvider).requireValue.signedIn,
          isFalse,
        );
        expect(await storage.read(key: _tokenKey), isNull);
      },
    );

    test('deleteAccount clears the session after a confirmed call', () async {
      final (container, storage, repo, _) = await pumpSignedIn();

      await container
          .read(sessionControllerProvider.notifier)
          .deleteAccount(password: 'dinerpass');

      expect(repo.deleteAccountCalls, 1);
      expect(repo.lastDeletePassword, 'dinerpass');
      expect(
        container.read(sessionControllerProvider).requireValue.signedIn,
        isFalse,
      );
      expect(await storage.read(key: _tokenKey), isNull);
    });

    test('a failed delete keeps the session and the stored token', () async {
      final (container, storage, _, _) = await pumpSignedIn(
        deleteAccountError: const ApiException(
          ApiErrorKind.unauthorized,
          message: 'Your password is incorrect.',
          statusCode: 401,
        ),
      );

      await expectLater(
        container
            .read(sessionControllerProvider.notifier)
            .deleteAccount(password: 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(
        container.read(sessionControllerProvider).requireValue.signedIn,
        isTrue,
      );
      expect(await storage.read(key: _tokenKey), 'tok');
    });
  });
}
