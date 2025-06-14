// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCe4--ek3rESG87GX2BcqpRJNrEqoG1iV0',
    appId: '1:584764414026:web:20e42ad7eb6271b00e6eb3',
    messagingSenderId: '584764414026',
    projectId: 'testing-a04d9',
    authDomain: 'testing-a04d9.firebaseapp.com',
    databaseURL: 'https://testing-a04d9-default-rtdb.firebaseio.com',
    storageBucket: 'testing-a04d9.firebasestorage.app',
    measurementId: 'G-VRCWZ2NLY6',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA-fKv0M_ltotyPp4wKnZDjbUNrzzITwOQ',
    appId: '1:584764414026:android:45293d659e15e2920e6eb3',
    messagingSenderId: '584764414026',
    projectId: 'testing-a04d9',
    databaseURL: 'https://testing-a04d9-default-rtdb.firebaseio.com',
    storageBucket: 'testing-a04d9.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBG-yeCy7mlhdvtAP50UjMqHNSEpcNcfwg',
    appId: '1:584764414026:ios:d79b975479c898400e6eb3',
    messagingSenderId: '584764414026',
    projectId: 'testing-a04d9',
    databaseURL: 'https://testing-a04d9-default-rtdb.firebaseio.com',
    storageBucket: 'testing-a04d9.firebasestorage.app',
    androidClientId: '584764414026-p7492kd0a23vllfdtcgo676pf8kfrnqo.apps.googleusercontent.com',
    iosClientId: '584764414026-cclo7ucmkc8ngmpk7jtvrlaufst5m79q.apps.googleusercontent.com',
    iosBundleId: 'com.example.testing',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBG-yeCy7mlhdvtAP50UjMqHNSEpcNcfwg',
    appId: '1:584764414026:ios:d79b975479c898400e6eb3',
    messagingSenderId: '584764414026',
    projectId: 'testing-a04d9',
    databaseURL: 'https://testing-a04d9-default-rtdb.firebaseio.com',
    storageBucket: 'testing-a04d9.firebasestorage.app',
    androidClientId: '584764414026-p7492kd0a23vllfdtcgo676pf8kfrnqo.apps.googleusercontent.com',
    iosClientId: '584764414026-cclo7ucmkc8ngmpk7jtvrlaufst5m79q.apps.googleusercontent.com',
    iosBundleId: 'com.example.testing',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCe4--ek3rESG87GX2BcqpRJNrEqoG1iV0',
    appId: '1:584764414026:web:1b1d2f55bfcf7dd70e6eb3',
    messagingSenderId: '584764414026',
    projectId: 'testing-a04d9',
    authDomain: 'testing-a04d9.firebaseapp.com',
    databaseURL: 'https://testing-a04d9-default-rtdb.firebaseio.com',
    storageBucket: 'testing-a04d9.firebasestorage.app',
    measurementId: 'G-GBJ9X4C12E',
  );

}