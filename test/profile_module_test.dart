import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/api/app_config.dart';
import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/api/mappers/mappers.dart';
import 'package:dine_circle/models/user_profile.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/users_provider.dart';
import 'package:dine_circle/repositories/location_repository.dart';
import 'package:dine_circle/screens/location/location_settings_screen.dart';
import 'package:dine_circle/screens/profile/profile_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/widgets/avatar_picker_sheet.dart';
import 'package:dine_circle/widgets/avatar_widget.dart';

import 'fake_repositories.dart';

const String _tokenKey = 'dinecircle.auth.token';

const _me = UserDto(
  id: 'u1',
  name: 'Ana Khan',
  handle: 'ana.k',
  instagram: 'ana.eats',
  role: 'user',
  email: 'ana@example.com',
  city: 'Karachi',
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('avatarImageProvider', () {
    test('resolves uploaded, absolute, asset and empty references', () {
      final uploaded = avatarImageProvider('/public/avatars/u1?v=7');
      expect(uploaded, isA<NetworkImage>());
      expect(
        (uploaded! as NetworkImage).url,
        '${AppConfig.apiUrl}/public/avatars/u1?v=7',
      );

      final absolute = avatarImageProvider('https://cdn.example.com/a.png');
      expect((absolute! as NetworkImage).url, 'https://cdn.example.com/a.png');

      final asset = avatarImageProvider('assets/images/portrait_1.png');
      expect(asset, isA<AssetImage>());

      expect(avatarImageProvider(null), isNull);
      expect(avatarImageProvider('  '), isNull);
    });
  });

  group('profile mapping', () {
    test('handle and instagram flow from the DTO into the profile', () {
      final dto = UserDto.fromJson({
        'id': 'u1',
        'name': 'Ana Khan',
        'handle': 'ana.k',
        'instagram': '@ana.eats',
      });
      expect(dto.instagram, 'ana.eats', reason: 'legacy @ is stripped');

      final profile = Mappers.userFromDto(dto);
      expect(profile.handle, 'ana.k');
      expect(profile.instagram, 'ana.eats');
    });

    test('an empty instagram yields no social link; initials are safe', () {
      final profile = Mappers.userFromDto(const UserDto(id: 'u', name: ' '));
      expect(profile.instagram, isEmpty);
      expect(profile.socialLinks, isEmpty);
      expect(profile.initials, '?');
      expect(const UserProfile(id: 'u', name: 'ana  khan').initials, 'AK');
    });

    test('copyWith(clearAvatar) drops the photo', () {
      const p = UserProfile(id: 'u', name: 'A', avatarPath: '/public/x');
      expect(p.copyWith(clearAvatar: true).avatarPath, isNull);
      expect(p.copyWith(name: 'B').avatarPath, '/public/x');
    });
  });

  /// Restores a session of [user], then pushes [home] — the way these screens
  /// are reached in the app, so `initState` sees the signed-in profile.
  Future<(ProviderContainer, FakeSessionRepository, FakeUsersRepository)>
  pumpSignedIn(
    WidgetTester tester, {
    required Widget home,
    UserDto user = _me,
    UserProfile? meResult,
    AvatarImagePicker? picker,
    List<ServiceCity>? cities,
  }) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final storage = InMemorySecureStorage();
    await storage.write(key: _tokenKey, value: 'tok');
    final sessionRepo = FakeSessionRepository(user: user);
    final usersRepo = FakeUsersRepository(
      meResult: meResult ?? Mappers.userFromDto(user),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sessionRepositoryProvider.overrideWithValue(sessionRepo),
          usersRepositoryProvider.overrideWithValue(usersRepo),
          socialRepositoryProvider.overrideWithValue(FakeSocialRepository()),
          eventsRepositoryProvider.overrideWithValue(FakeEventsRepository()),
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(cities: cities),
          ),
          if (picker != null)
            avatarImagePickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              // Watching the session runs the bootstrap before the push.
              body: ref.watch(currentUserProvider) == null
                  ? const SizedBox.shrink()
                  : TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => home),
                      ),
                      child: const Text('open'),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // bootstrap restores the stored token
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(home.runtimeType)),
    );
    return (container, sessionRepo, usersRepo);
  }

  group('ProfileScreen header', () {
    testWidgets('shows the real username and instagram, not a derived one', (
      tester,
    ) async {
      await pumpSignedIn(tester, home: const ProfileScreen());

      expect(find.text('Ana Khan'), findsOneWidget);
      expect(find.text('@ana.k'), findsOneWidget);
      expect(find.text('@anakhan'), findsNothing);
      expect(find.text('instagram.com/ana.eats'), findsOneWidget);
    });

    testWidgets('omits the username row when the account has none', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        user: const UserDto(id: 'u1', name: 'No Handle', role: 'user'),
      );
      expect(find.byKey(const Key('profileHandle')), findsNothing);
      expect(find.byKey(const Key('profileInstagram')), findsNothing);
    });

    testWidgets('pull-to-refresh re-reads the session', (tester) async {
      final (_, sessionRepo, _) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
      );
      final before = sessionRepo.meCalls;

      await tester.fling(find.text('Ana Khan'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(sessionRepo.meCalls, before + 1);
    });

    testWidgets('hosts see the Host Studio entry point', (tester) async {
      await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        user: const UserDto(id: 'u1', name: 'Host', role: 'host'),
      );
      expect(find.text('Host Studio'), findsOneWidget);
    });
  });

  group('Avatar picker', () {
    final png = Uint8List.fromList(List<int>.filled(64, 7));

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('profileAvatarEdit')));
      await tester.pumpAndSettle();
      expect(find.text('Profile Photo'), findsOneWidget);
    }

    testWidgets('gallery pick uploads and republishes the session', (
      tester,
    ) async {
      AvatarSource? asked;
      final (container, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        picker: (source) async {
          asked = source;
          return png;
        },
      );
      await openPicker(tester);
      // No photo yet, so there is nothing to remove.
      expect(find.byKey(const Key('avatarRemove')), findsNothing);

      await tester.tap(find.byKey(const Key('avatarChooseGallery')));
      await tester.pumpAndSettle();

      expect(asked, AvatarSource.gallery);
      expect(usersRepo.uploadAvatarCalls, 1);
      expect(usersRepo.lastAvatarBytes, png);
      expect(find.text('Profile photo updated'), findsOneWidget);
      expect(find.text('Profile Photo'), findsNothing);
      expect(
        container.read(currentUserProvider)?.avatarPath,
        '/public/avatars/u1?v=1',
      );
      // Email survives the avatar round-trip.
      expect(container.read(currentUserProvider)?.email, 'ana@example.com');
    });

    testWidgets('cancel does nothing; oversize photos never upload', (
      tester,
    ) async {
      Uint8List? next;
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        picker: (_) async => next,
      );
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('avatarTakePhoto')));
      await tester.pumpAndSettle();
      expect(usersRepo.uploadAvatarCalls, 0);
      expect(find.text('Profile Photo'), findsOneWidget);

      next = Uint8List(kMaxAvatarBytes + 1);
      await tester.tap(find.byKey(const Key('avatarChooseGallery')));
      await tester.pumpAndSettle();
      expect(usersRepo.uploadAvatarCalls, 0);
      expect(find.textContaining('too large'), findsOneWidget);
    });

    testWidgets('server errors stay inline in the sheet', (tester) async {
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        picker: (_) async => png,
      );
      usersRepo.avatarError = const ApiException(
        ApiErrorKind.validation,
        message: 'Upload a JPEG, PNG or WebP image.',
        statusCode: 415,
      );
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('avatarChooseGallery')));
      await tester.pumpAndSettle();

      expect(usersRepo.uploadAvatarCalls, 1);
      expect(find.text('Upload a JPEG, PNG or WebP image.'), findsOneWidget);
      expect(find.text('Profile Photo'), findsOneWidget);
    });

    testWidgets('remove clears an existing photo', (tester) async {
      const withPhoto = UserDto(
        id: 'u1',
        name: 'Ana Khan',
        role: 'user',
        email: 'ana@example.com',
        avatarUrl: 'assets/images/portrait_1.png',
      );
      final (container, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
        user: withPhoto,
        picker: (_) async => null,
      );
      await openPicker(tester);

      await tester.tap(find.byKey(const Key('avatarRemove')));
      await tester.pumpAndSettle();

      expect(usersRepo.removeAvatarCalls, 1);
      expect(find.text('Profile photo removed'), findsOneWidget);
      expect(container.read(currentUserProvider)?.avatarPath, isNull);
    });
  });

  group('Edit profile sheet', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
    }

    testWidgets('sends only the changed, normalised fields', (tester) async {
      final (container, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
      );
      await openEditor(tester);

      await tester.enterText(
        find.byKey(const Key('editProfileHandle')),
        '@Ana.Eats_Out',
      );
      await tester.enterText(
        find.byKey(const Key('editProfileInstagram')),
        'https://www.instagram.com/ana.dines/',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(usersRepo.lastSettingsPatch, {
        'handle': 'ana.eats_out',
        'instagram': 'ana.dines',
      });
      expect(container.read(currentUserProvider)?.handle, 'ana.eats_out');
      expect(find.text('@ana.eats_out'), findsOneWidget);
    });

    testWidgets('invalid usernames are refused before any request', (
      tester,
    ) async {
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
      );
      await openEditor(tester);

      for (final bad in ['ab.', 'a..b', 'deleted_me']) {
        await tester.enterText(find.byKey(const Key('editProfileHandle')), bad);
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(usersRepo.patchSettingsCalls, 0, reason: bad);
      }
      expect(find.text('That username is reserved.'), findsOneWidget);
    });

    testWidgets('saving with no changes closes without a request', (
      tester,
    ) async {
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
      );
      await openEditor(tester);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(usersRepo.patchSettingsCalls, 0);
      expect(find.byKey(const Key('editProfileHandle')), findsNothing);
    });

    testWidgets('a taken username shows the server message inline', (
      tester,
    ) async {
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const ProfileScreen(),
      );
      usersRepo.settingsError = const ApiException(
        ApiErrorKind.conflict,
        message: 'That username is taken',
        statusCode: 409,
      );
      await openEditor(tester);

      await tester.enterText(
        find.byKey(const Key('editProfileHandle')),
        'taken_name',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('That username is taken'), findsOneWidget);
      expect(find.byKey(const Key('editProfileHandle')), findsOneWidget);
    });
  });

  testWidgets('Profile delete account runs the password-confirmed flow', (
    tester,
  ) async {
    final (_, sessionRepo, _) = await pumpSignedIn(
      tester,
      home: const ProfileScreen(),
    );

    await tester.tap(find.byKey(const Key('profileDeleteAccount')));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsOneWidget);

    // Disabled until a password is typed.
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(sessionRepo.deleteAccountCalls, 0);

    await tester.enterText(
      find.byKey(const Key('deleteAccountPassword')),
      'secret123',
    );
    await tester.pump();
    await tester.tap(find.text('Delete forever'));
    // The cleared session swaps the screen for a spinner; don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(sessionRepo.deleteAccountCalls, 1);
    expect(sessionRepo.lastDeletePassword, 'secret123');
  });

  group('LocationSettingsScreen', () {
    const cities = [
      ServiceCity(name: 'Karachi', areas: ['DHA', 'Clifton']),
      ServiceCity(name: 'Lahore', areas: ['Gulberg']),
    ];

    testWidgets('offers supported cities and their areas', (tester) async {
      final (_, _, usersRepo) = await pumpSignedIn(
        tester,
        home: const LocationSettingsScreen(),
        cities: cities,
      );

      expect(find.byKey(const Key('cityChip_Karachi')), findsOneWidget);
      expect(find.byKey(const Key('cityChip_Lahore')), findsOneWidget);
      expect(find.byKey(const Key('areaChip_Clifton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cityChip_Lahore')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('areaChip_Clifton')), findsNothing);
      await tester.tap(find.byKey(const Key('areaChip_Gulberg')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save location'));
      await tester.pumpAndSettle();
      expect(usersRepo.lastSettingsPatch, {
        'city': 'Lahore',
        'homeArea': 'Gulberg',
      });
    });

    testWidgets('keeps a legacy city outside the supported list', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        home: const LocationSettingsScreen(),
        user: const UserDto(id: 'u1', name: 'A', role: 'user', city: 'Quetta'),
        cities: cities,
      );
      expect(find.byKey(const Key('cityChip_Quetta')), findsOneWidget);
    });
  });
}
