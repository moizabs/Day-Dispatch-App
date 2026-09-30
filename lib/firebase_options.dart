import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('Firebase has not been configured for Linux.');
      default:
        throw UnsupportedError('Firebase is not supported on this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALcIXTfR3Fwgzh9H0Rd0vtJP5eD_enz5E',
    appId: '1:625358424286:web:d1051ff0960cf16c27da4f',
    messagingSenderId: '625358424286',
    projectId: 'daydispatch-4e285',
    authDomain: 'daydispatch-4e285.firebaseapp.com',
    storageBucket: 'daydispatch-4e285.firebasestorage.app',
    measurementId: 'G-W6CL3G7NL1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAqpU1hSxsSsXT0ib8_k6uEFgOSC2lTMMQ',
    appId: '1:625358424286:android:0a875845d1476b8a27da4f',
    messagingSenderId: '625358424286',
    projectId: 'daydispatch-4e285',
    storageBucket: 'daydispatch-4e285.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDgW2cAFZkL_MSjORkHejgZYykgvFFGc80',
    appId: '1:625358424286:ios:89641dae561fd0c127da4f',
    messagingSenderId: '625358424286',
    projectId: 'daydispatch-4e285',
    storageBucket: 'daydispatch-4e285.firebasestorage.app',
    iosBundleId: 'com.daydispatch.app',
  );

  static const FirebaseOptions macos = ios;

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyALcIXTfR3Fwgzh9H0Rd0vtJP5eD_enz5E',
    appId: '1:625358424286:web:e5a2c46bc76e44aa27da4f',
    messagingSenderId: '625358424286',
    projectId: 'daydispatch-4e285',
    authDomain: 'daydispatch-4e285.firebaseapp.com',
    storageBucket: 'daydispatch-4e285.firebasestorage.app',
    measurementId: 'G-9E0BQ4P8CK',
  );
}
