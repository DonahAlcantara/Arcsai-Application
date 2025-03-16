// ignore_for_file: avoid_print, use_key_in_widget_constructors, library_private_types_in_public_api, unused_element

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' as intl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'loginpage.dart';
import 'scheduling.dart';
import 'package:battery_plus/battery_plus.dart';
import 'notification.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:developer';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void onStart(ServiceInstance service) {
  log('Background service started');
}

bool onIosBackground(ServiceInstance service) {
  log('iOS background fetch');
  return true;
}

void callbackDispatcher() {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  flutterLocalNotificationsPlugin.initialize(initializationSettings);

  Workmanager().executeTask((task, inputData) async {
    if (task == "start_vacuum") {
      // Trigger vacuum process here
      // Notify the user
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails('vacuum_channel', 'Vacuum Notifications',
              importance: Importance.max,
              priority: Priority.high,
              showWhen: false);
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      await flutterLocalNotificationsPlugin.show(0, 'Vacuum Started',
          'The vacuum process has started', platformChannelSpecifics);
    }
    return Future.value(true);
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _configureLocalTimeZone() {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Manila'));
}

void initializeNotifications() {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  flutterLocalNotificationsPlugin.initialize(initSettings);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureLocalTimeZone();
  initializeNotifications();
  await Firebase.initializeApp();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  runApp(MyApp());

  FirebaseMessaging messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    log(" Notification permission granted.");
  } else {
    log(" Notification permission denied.");
  }

  String? token = await messaging.getToken();
  print(" FCM Token: $token");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: '',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginPage(),
        '/notifications': (context) => NotificationPage(),
      },
    );
  }
}

class VacuumControlScreen extends StatefulWidget {
  @override
  _VacuumControlScreenState createState() => _VacuumControlScreenState();
}

class _VacuumControlScreenState extends State<VacuumControlScreen> {
  String? nextSchedule;
  bool isLoading = true;
  int notificationCount = 0; // Tracks unread notifications
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference database = FirebaseDatabase.instance.ref();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Battery _battery = Battery();
  int _batteryLevel = 100; // Default value

  bool isMoving = false;
  bool isCleaning = false;
  bool vacuum = true;
  bool wiper = false;
  String lastCleanTime = "Not started yet";
  String nextScheduledClean = "Fetching...";
  DateTime? startTime;
  String firstLetter = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _listenToFeatureChanges();

    _battery.onBatteryStateChanged.listen((BatteryState state) {
      _getBatteryLevel();
    });

    FirebaseMessaging.instance.subscribeToTopic("vacuumStatus");
    setupLocalNotifications();
    listenToVacuumStatus();
    fetchSchedule();
    loadNextSchedule();

    database.child("robot_commands").get().then((event) {
      final data = event.value;
      if (data is! Map) return;
      if (data["move_forward"] == true) {
        triggerVacuum(true);
      }
    });

    database.child("features/vacuum").onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          vacuum = event.snapshot.value as bool;
        });
      }
    });

    database.child("features/wiper").onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          wiper = event.snapshot.value as bool;
        });
      }
    });
  }

  void _listenToFeatureChanges() {
    database.child("features/vacuum").onValue.listen((event) {
      setState(() {
        vacuum = event.snapshot.value as bool? ?? true;
      });
    });

    database.child("features/wiper").onValue.listen((event) {
      setState(() {
        wiper = event.snapshot.value as bool? ?? false;
      });
    });
  }

  void toggleFeature1() async {
    final newValue = !vacuum;
    try {
      await database.child("features/vacuum").set(newValue);
      setState(() => vacuum = newValue);
      log("Vacuum feature toggled: $newValue");
    } catch (e) {
      log("Failed to toggle vacuum: $e");
    }
  }

  void toggleFeature2() async {
    final newValue = !wiper;
    try {
      await database.child("features/wiper").set(newValue);
      setState(() => wiper = newValue);
      log("Wiper feature toggled: $newValue");
    } catch (e) {
      log("Failed to toggle wiper: $e");
    }
  }

  void _getBatteryLevel() async {
    final batteryLevel = await _battery.batteryLevel;
    setState(() {
      _batteryLevel = batteryLevel;
    });
    await FirebaseFirestore.instance.collection('battery').doc('device1').set({
      'level': _batteryLevel,
      'timestamp': DateTime.now(),
    });
  }

  void toggleMovement() {
    setState(() {
      isMoving = !isMoving;
    });
  }

  void toggleCleaning() {
    setState(() {
      isCleaning = !isCleaning;
    });
  }

  void _loadUserProfile() {
    User? user = _auth.currentUser;
    setState(() {
      if (user != null &&
          user.displayName != null &&
          user.displayName!.isNotEmpty) {
        firstLetter = user.displayName![0].toUpperCase();
      } else {
        firstLetter = '?';
      }
    });
  }

  void setupLocalNotifications() {
    var initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _handleNotificationTap(response.payload!);
        }
      },
    );
  }

  void _handleNotificationTap(String payload) {
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  void _showLocalNotification(String? title, String? body) {
    flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vacuum_channel',
          'Vacuum Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  void initializeNotifications() {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  void listenToVacuumStatus() {
    database.child("vacuum_status").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          isCleaning = data["status"] == "cleaning";
        });
      }
    });
  }

  void checkBatteryStatus(int batteryLevel) {
    if (batteryLevel < 25) {
      _showLocalNotification(
          "Battery Low", "Vacuum battery is at $batteryLevel%. Please charge.");
    }
  }

  void updateVacuumStatus(String status) {
    if (status == "Cleaning started") {
      _showLocalNotification(
          "Vacuum Alert", "Your vacuum is Cleaning! Check it.");
    } else if (status == "charging") {
      _showLocalNotification("Charging", "Vacuum is charging.");
    }
  }

  void loadNextSchedule() async {
    DatabaseEvent event = await database.child("schedule/nextSchedule").once();
    if (event.snapshot.value != null) {
      setState(() {
        nextSchedule = intl.DateFormat('dd HH:mm')
            .format(DateTime.parse(event.snapshot.value as String));
      });
    } else {
      setState(() {
        nextSchedule = "No schedule set";
      });
    }
  }

  void startVacuumProcess() {
    // Add your vacuum process logic here
    log("Vacuum process started");
  }

  void toggleMovementAsync() async {
    setState(() {
      isMoving = !isMoving;
    });
    triggerVacuum(isMoving);

    if (!isMoving) {
      // Store last clean time when stopping
      String formattedTime =
          intl.DateFormat('MM-dd HH:mm a').format(DateTime.now());
      await database
          .child("vacuum_status")
          .update({"lastCleanTime": formattedTime});
      setState(() {
        lastCleanTime = formattedTime;
      });
    }
  }

  void toggleCleaningStatus() async {
    bool newStatus = !isCleaning;
    log(newStatus ? "Vacuum started cleaning" : "Vacuum stopped");
    await database
        .child("vacuum_status")
        .update({"status": newStatus ? "cleaning" : "idle"});
    setState(() {
      isCleaning = newStatus;
    });
  }

  void triggerVacuum(bool start) async {
    log(start ? "Vacuum should start now!" : "Vacuum should stop.");

    DatabaseReference robotCommandsRef = database.child("robot_commands");
    robotCommandsRef.update({"move_forward": start}).then((_) {
      log("Vacuum status updated successfully in Firebase.");
    }).catchError((error) {
      log("Failed to update vacuum status: $error");
    });

    // Show a local notification
    flutterLocalNotificationsPlugin.show(
      0,
      "Vacuum Status",
      start ? "Cleaning started" : "Cleaning stopped",
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vacuum_channel',
          'Vacuum Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  void _configureLocalTimeZone() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
  }

  void fetchSchedule() {
    database.child("schedule").onValue.listen((event) {
      final data = event.snapshot.value;
      if (data == null) {
        setState(() {
          nextScheduledClean = "No schedule available";
        });
        return;
      }

      final schedule = data as Map;
      DateTime now = DateTime.now();
      String today = intl.DateFormat('yyyy-MM-dd a').format(now);

      for (var entry in schedule.entries) {
        var details = entry.value;
        if (details["date"] == today) {
          setState(() {
            nextScheduledClean = "${details["date"]} at ${details["time"]}";
          });

          DateTime scheduledTime = intl.DateFormat('yyyy-MM-dd HH:mm')
              .parse("${details["date"]} ${details["time"]}");

          if (DateTime.now().isAfter(scheduledTime)) {
            log("Starting vacuum process...");
            triggerVacuum(true);
          } else {
            log("Scheduled time not yet reached.");
          }
          return;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[900],
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ARCSAI Vacuum',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isMoving ? 'Cleaning in progress' : 'Ready to clean',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications,
                                color: Colors.white70),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => NotificationPage()),
                              );
                            },
                          ),
                          if (notificationCount >
                              0) // Show badge only if count > 0
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$notificationCount',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(width: 10),
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white,
                        child: Text(
                          firstLetter,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(100),
                    topRight: Radius.circular(100),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200, // Make it circular
                      height: 200,
                      child: ElevatedButton(
                        onPressed: toggleMovementAsync,
                        style: ElevatedButton.styleFrom(
                          shape: CircleBorder(), // Circular shape
                          backgroundColor: isMoving
                              ? Colors.green
                              : Colors.red, // Color change
                          padding: EdgeInsets.all(20), // Button padding
                        ),
                        child: Text(
                          isMoving ? 'Move' : 'Stop', // Change label
                          style: TextStyle(fontSize: 25, color: Colors.white),
                        ),
                      ),
                    ),
                    SizedBox(height: 50),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text("Vacuum"),
                            Switch(
                              value: vacuum,
                              onChanged: (value) {
                                toggleFeature1();
                              },
                            ),
                          ],
                        ),
                        SizedBox(width: 20),
                        Column(
                          children: [
                            Text("Wiper"),
                            Switch(
                              value: wiper,
                              onChanged: (value) {
                                toggleFeature2();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => SchedulingScreen()),
                        );
                      },
                      child: Card(
                        margin: EdgeInsets.symmetric(horizontal: 20),
                        child: ListTile(
                          leading:
                              Icon(Icons.calendar_today, color: Colors.blue),
                          title: Text(
                            'Next Scheduled Clean',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          subtitle: Text(nextScheduledClean),
                          trailing: Icon(Icons.arrow_circle_right),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Icon(
                                  _batteryLevel > 20
                                      ? Icons.battery_full
                                      : Icons.battery_alert,
                                  color: _batteryLevel > 20
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                Text(
                                  'Battery',
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                                Text(
                                  '$_batteryLevel%',
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Icon(Icons.timelapse, color: Colors.blue),
                                Text(
                                  'Last Clean',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  lastCleanTime,
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Icon(Icons.cleaning_services,
                                    color: Colors.green),
                                Text(
                                  'Status',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  isCleaning ? 'Cleaning in progress' : 'Idle',
                                  style: TextStyle(
                                      color:
                                          const Color.fromARGB(179, 10, 0, 0),
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
