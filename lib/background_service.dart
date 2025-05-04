<<<<<<< HEAD
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer';

void onStart(ServiceInstance service) async {
  FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initSettings =
      InitializationSettings(android: androidInitSettings);

  notifications.initialize(initSettings);

  DatabaseReference database = FirebaseDatabase.instance.ref("schedule");

  Timer.periodic(Duration(minutes: 1), (timer) async {
    DateTime now = DateTime.now();
    String today = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ][now.weekday % 7];
    String currentTime = "${now.hour}:${now.minute}";

    DataSnapshot snapshot = await database.child(today).get();

    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      if (data['scheduled'] == true && data['time'] == currentTime) {
        triggerCleaning();
        showNotification(notifications, "Vacuum Cleaner Started",
            "Cleaning started at $currentTime");
      }
    }
  });
}

void triggerCleaning() {
  log("Vacuum Cleaner Started Cleaning");
}

void showNotification(FlutterLocalNotificationsPlugin notifications,
    String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'cleaning_schedule',
    'Cleaning Schedule',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await notifications.show(0, title, body, details);
}
=======
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:developer';

void onStart(ServiceInstance service) async {
  FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initSettings =
      InitializationSettings(android: androidInitSettings);

  notifications.initialize(initSettings);

  DatabaseReference database = FirebaseDatabase.instance.ref("schedule");

  Timer.periodic(Duration(minutes: 1), (timer) async {
    DateTime now = DateTime.now();
    String today = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ][now.weekday % 7];
    String currentTime = "${now.hour}:${now.minute}";

    DataSnapshot snapshot = await database.child(today).get();

    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      if (data['scheduled'] == true && data['time'] == currentTime) {
        triggerCleaning();
        showNotification(notifications, "Vacuum Cleaner Started",
            "Cleaning started at $currentTime");
      }
    }
  });
}

void triggerCleaning() {
  log("Vacuum Cleaner Started Cleaning");
}

void showNotification(FlutterLocalNotificationsPlugin notifications,
    String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'cleaning_schedule',
    'Cleaning Schedule',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await notifications.show(0, title, body, details);
}
>>>>>>> 0636a1a300621acb322bf2346864d4e26f5bbfca
