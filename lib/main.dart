// ignore_for_file: avoid_print, use_key_in_widget_constructors, library_private_types_in_public_api, unused_element, deprecated_member_use

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
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:developer';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'settings.dart';

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
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );

  FirebaseMessaging messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    log("Notification permission granted.");
  } else {
    log("Notification permission denied.");
  }

  String? token = await messaging.getToken();
  print("FCM Token: $token");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: themeProvider.themeData,
          home: LoginPage(),
          routes: {
            '/vacuum': (context) => VacuumControlScreen(),
            '/notifications': (context) => NotificationPage(),
            '/scheduling': (context) => SchedulingScreen(),
            '/settings': (context) => SettingsPage(),
          },
        );
      },
    );
  }
}

class VacuumControlScreen extends StatefulWidget {
  @override
  _VacuumControlScreenState createState() => _VacuumControlScreenState();
}

class _VacuumControlScreenState extends State<VacuumControlScreen> {
  static _VacuumControlScreenState? _instance; // Hold the instance

  String? nextSchedule;
  String? nextScheduledClean;
  bool isLoading = true;
  int notificationCount = 0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference database = FirebaseDatabase.instance.ref();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Battery _battery = Battery();
  Timer? _scheduleTimer;
  Timer? _stopVacuumTimer;
  int _batteryLevel = 100;
  bool isMoving = false;
  bool isCleaning = false;
  bool vacuum = true;
  bool wiper = false;
  String lastCleanTime = "Not started yet";
  DateTime? startTime;
  String firstLetter = '';
  final Set<String> processedScheduleIds = {};
  bool _hasNotifiedLowBattery = false;

  @override
  void initState() {
    super.initState();
    _instance = this; // Store the instance
    _loadUserProfile();
    _listenToFeatureChanges();
    _getBatteryLevel();
    _listenToRobotCommands();
    _listenToNotifications();

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
      if (data["Clean"] == true) {
        triggerVacuum(true, fromSchedule: false);
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
    _scheduleTimer = Timer.periodic(Duration(seconds: 5), (Timer timer) {
      if (mounted) {
        fetchSchedule();
      }
    });
  }

  void _listenToNotifications() {
    database.child('notifications').onValue.listen((event) {
      if (mounted) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        setState(() {
          notificationCount = data != null ? data.length : 0;
        });
      }
    });
  }

  void _clearNotifications() async {
    await database.child('notifications').remove();
    setState(() {
      notificationCount = 0;
    });
  }

  @override
  void dispose() {
    _instance = null; // Clear the instance
    print("VacuumControlScreen: dispose()");
    _scheduleTimer?.cancel();
    _stopVacuumTimer?.cancel();
    super.dispose();
  }

  void _listenToRobotCommands() {
    database.child("robot_commands/Clean").onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          isMoving = event.snapshot.value as bool;
        });
      }
    });
  }

  void _getBatteryLevel() async {
    final batteryLevel = await _battery.batteryLevel;
    setState(() {
      _batteryLevel = batteryLevel;
    });
    checkBatteryStatus(batteryLevel);
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
      await database.child("features/vacuum").set(newValue).then((_) {
        if (mounted) {
          setState(() => vacuum = newValue);
        }
        log("Vacuum feature toggled: $newValue");
      });
    } catch (e) {
      log("Failed to toggle vacuum: $e");
    }
  }

  void toggleFeature2() async {
    final newValue = !wiper;
    try {
      await database.child("features/wiper").set(newValue).then((_) {
        if (mounted) {
          setState(() => wiper = newValue);
        }
        log("Wiper feature toggled: $newValue");
      });
    } catch (e) {
      log("Failed to toggle wiper: $e");
    }
  }

  void _loadUserProfile() {
    User? user = _auth.currentUser;
    setState(() {
      if (user != null && user.email != null && user.email!.isNotEmpty) {
        firstLetter = user.email![0];
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

  void _showLocalNotification(String? title, String? body, int id) {
    flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vacuum_channel',
          'Vac | Vacuum Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  void listenToVacuumStatus() {
    database.child("vacuum_status").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          isCleaning = data["status"] == "cleaning";
        });
        updateVacuumStatus(data["status"]);
      }
    });
  }

  void checkBatteryStatus(int batteryLevel) {
    if (batteryLevel < 25 && !_hasNotifiedLowBattery) {
      _showLocalNotification(
        "Battery Low",
        "Vacuum battery is at $batteryLevel%. Please charge.",
        3,
      );
      database.child('notifications').push().set({
        'title': 'Battery Low',
        'description': 'Vacuum battery is at $batteryLevel%. Please charge.',
        'type': 'Battery',
        'batteryLevel': batteryLevel,
        'timestamp': ServerValue.timestamp,
      });
      setState(() {
        _hasNotifiedLowBattery = true;
      });
    } else if (batteryLevel >= 25 && _hasNotifiedLowBattery) {
      setState(() {
        _hasNotifiedLowBattery = false;
      });
    }
  }

  void updateVacuumStatus(String status) {
    if (status == "cleaning") {
      _showLocalNotification(
          "Vacuum Alert", "Your vacuum is Cleaning! Check it.", 4);
      database.child('notifications').push().set({
        'title': 'Vacuum Alert',
        'description': 'Your vacuum is Cleaning! Check it.',
        'type': 'Vacuum Process',
        'timestamp': ServerValue.timestamp,
      });
    } else if (status == "charging") {
      _showLocalNotification("Charging", "Vacuum is charging.", 5);
      database.child('notifications').push().set({
        'title': 'Charging',
        'description': 'Vacuum is charging.',
        'type': 'Vacuum Process',
        'timestamp': ServerValue.timestamp,
      });
    }
  }

  void loadNextSchedule() async {
    DatabaseEvent event = await database.child("schedules").once();
    if (event.snapshot.exists && event.snapshot.value != null) {
      try {
        Map<dynamic, dynamic> schedulesMap =
            event.snapshot.value as Map<dynamic, dynamic>;
        List<MapEntry<dynamic, dynamic>> schedulesList =
            schedulesMap.entries.toList();

        schedulesList.sort((a, b) {
          if (a.value is Map &&
              a.value.containsKey("dateTime") &&
              a.value["dateTime"] is String &&
              b.value is Map &&
              b.value.containsKey("dateTime") &&
              b.value["dateTime"] is String) {
            DateTime dateTimeA = DateTime.parse(a.value["dateTime"]);
            DateTime dateTimeB = DateTime.parse(b.value["dateTime"]);
            return dateTimeA.compareTo(dateTimeB);
          } else {
            return 0;
          }
        });

        DateTime now = DateTime.now().toLocal();
        bool foundFutureSchedule = false;

        for (var entry in schedulesList) {
          if (entry.value is Map &&
              entry.value.containsKey("dateTime") &&
              entry.value["dateTime"] is String) {
            DateTime scheduledDateTime =
                DateTime.parse(entry.value["dateTime"]).toLocal();
            if (scheduledDateTime.isAfter(now)) {
              if (mounted) {
                setState(() {
                  nextScheduledClean = intl.DateFormat('yyyy-MM-dd – kk:mm')
                      .format(scheduledDateTime);
                });
              }
              foundFutureSchedule = true;
              break;
            }
          }
        }
        if (mounted && !foundFutureSchedule) {
          setState(() {
            nextScheduledClean = "No upcoming schedule";
          });
        }
      } catch (e) {
        print("Error in loadNextSchedule: $e");
        if (mounted) {
          setState(() {
            nextScheduledClean = "Error loading schedule";
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          nextSchedule = "No schedule set";
          nextScheduledClean = "No schedule available";
        });
      }
    }
  }

  void startVacuumProcess() {
    log("Vacuum process started");
  }

  void toggleMovementAsync() async {
    setState(() {
      isMoving = !isMoving;
    });
    triggerVacuum(isMoving, fromSchedule: false);

    if (!isMoving) {
      _stopVacuumTimer?.cancel();
      DateTime scheduledDateTime = DateTime.now();
      String formattedTime = intl.DateFormat('yyyy-MM-dd – kk:mm')
          .format(scheduledDateTime.toLocal());

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

  static void triggerVacuumStatic(bool start, {required bool fromSchedule}) {
    if (_instance != null && _instance!.mounted) {
      _instance!.triggerVacuum(start, fromSchedule: fromSchedule);
    }
  }

  void triggerVacuum(bool start, {required bool fromSchedule}) async {
    print(
        "triggerVacuum called with start: $start, fromSchedule: $fromSchedule");
    setState(() {
      isMoving = start;
    });
    log(start ? "Vacuum should start now!" : "Vacuum should stop.");

    DatabaseReference robotCommandsRef = database.child("robot_commands");
    await robotCommandsRef.update({"Clean": start}).then((_) {
      log("Vacuum status updated successfully in Firebase.");
      if (mounted) {
        setState(() {
          isMoving = start;
        });
      }
    }).catchError((error) {
      log("Failed to update vacuum status: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update vacuum status.")),
      );
    });

    if (fromSchedule) {
      await database.child('notifications').push().set({
        'title': 'Vacuum Status',
        'description': start ? 'Cleaning started' : 'Cleaning stopped',
        'type': 'Vacuum Process',
        'timestamp': ServerValue.timestamp,
      });
      _showLocalNotification("Vacuum Status",
          start ? "Cleaning started" : "Cleaning stopped", start ? 1 : 2);
    }

    if (!start) {
      DateTime now = DateTime.now();
      String formattedTime =
          intl.DateFormat('yyyy-MM-dd – kk:mm').format(now.toLocal());
      await database
          .child("vacuum_status")
          .update({"lastCleanTime": formattedTime});
      setState(() {
        lastCleanTime = formattedTime;
      });
    }
  }

  void fetchSchedule() {
    print("VacuumControlScreen: fetchSchedule() called");
    database.child("schedules").onValue.listen((event) {
      if (!mounted) return;

      print("VacuumControlScreen: fetchSchedule: Listener triggered");
      final data = event.snapshot.value;
      print("VacuumControlScreen: fetchSchedule: Data received: $data");

      if (data == null) {
        if (mounted) {
          setState(() {
            nextScheduledClean = "No schedule available";
          });
        }
        return;
      }

      try {
        Map<dynamic, dynamic> schedulesMap = data as Map<dynamic, dynamic>;
        List<MapEntry> entries = schedulesMap.entries.toList();

        entries.sort((a, b) {
          if (a.value is Map &&
              a.value.containsKey("dateTime") &&
              a.value["dateTime"] is String &&
              b.value is Map &&
              b.value.containsKey("dateTime") &&
              b.value["dateTime"] is String) {
            DateTime dateTimeA = DateTime.parse(a.value["dateTime"]);
            DateTime dateTimeB = DateTime.parse(b.value["dateTime"]);
            return dateTimeA.compareTo(dateTimeB);
          } else {
            print(
                "VacuumControlScreen: fetchSchedule: Invalid dateTime format for ${a.key} or ${b.key}");
            return 0;
          }
        });

        DateTime now = DateTime.now().toLocal();
        String? nextScheduleTime;

        print("VacuumControlScreen: fetchSchedule: Current time (Local): $now");

        for (var entry in entries) {
          if (entry.value is Map &&
              entry.value.containsKey("dateTime") &&
              entry.value["dateTime"] is String) {
            DateTime scheduledDateTime =
                DateTime.parse(entry.value["dateTime"]).toLocal();
            String scheduleId = entry.key.toString();

            print(
                "fetchSchedule: Checking schedule: $scheduleId, dateTime (Local): $scheduledDateTime, enabled: ${entry.value['enabled']}");

            bool shouldTrigger = false;

            if (entry.value["enabled"] == true &&
                !processedScheduleIds.contains(scheduleId)) {
              Duration difference = now.difference(scheduledDateTime);
              if (difference.inSeconds >= 0 && difference.inSeconds <= 5) {
                switch (entry.value["repeat"]) {
                  case "Once":
                    shouldTrigger = true;
                    break;
                  case "Daily":
                    if (now.day == scheduledDateTime.day &&
                        now.month == scheduledDateTime.month &&
                        now.year == scheduledDateTime.year) {
                      shouldTrigger = true;
                    }
                    break;
                  case "Weekly":
                    if (now.weekday == scheduledDateTime.weekday) {
                      shouldTrigger = true;
                    }
                    break;
                  case "Monthly":
                    if (now.day == scheduledDateTime.day) {
                      shouldTrigger = true;
                    }
                    break;
                  default:
                    shouldTrigger = true;
                    break;
                }
              }
            }

            if (shouldTrigger && !isMoving) {
              processedScheduleIds.add(scheduleId);
              triggerVacuum(true, fromSchedule: true);
              log("Vacuum start command sent due to schedule: $scheduleId");

              if (entry.value["repeat"] == "Once") {
                database
                    .child("schedules/$scheduleId")
                    .update({"enabled": false});
              }

              _stopVacuumTimer?.cancel();
              _stopVacuumTimer = Timer(Duration(minutes: 5), () {
                if (mounted && isMoving) {
                  triggerVacuum(false, fromSchedule: true);
                  log("Vacuum stopped after 5 minutes for schedule: $scheduleId");
                }
              });
            }

            if (scheduledDateTime.isAfter(now) && nextScheduleTime == null) {
              nextScheduleTime = intl.DateFormat('yyyy-MM-dd – kk:mm')
                  .format(scheduledDateTime);
            }
          } else {
            print("fetchSchedule: Skipping invalid entry: ${entry.key}");
          }
        }

        if (mounted) {
          setState(() {
            nextScheduledClean = nextScheduleTime ?? "No upcoming schedule";
          });
        }
      } catch (e) {
        print("VacuumControlScreen: fetchSchedule: Error: $e");
        if (mounted) {
          setState(() {
            nextScheduledClean = "Error loading schedule";
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
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
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        isMoving ? 'Cleaning in progress' : 'Ready to clean',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.notifications,
                              color: Theme.of(context)
                                  .appBarTheme
                                  .iconTheme
                                  ?.color,
                            ),
                            onPressed: () {
                              _clearNotifications();
                              Navigator.pushNamed(context, '/notifications');
                            },
                          ),
                          if (notificationCount > 0)
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
                        backgroundColor: Theme.of(context).cardColor,
                        child: Text(
                          firstLetter,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.secondary,
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
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(100),
                    topRight: Radius.circular(100),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: ElevatedButton(
                        onPressed: toggleMovementAsync,
                        style: ElevatedButton.styleFrom(
                          shape: CircleBorder(),
                          backgroundColor: isMoving ? Colors.red : Colors.green,
                          padding: EdgeInsets.all(20),
                        ),
                        child: Text(
                          isMoving ? 'Stop' : 'Start',
                          style: TextStyle(
                            fontSize: 25,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 50),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text(
                              "Vacuum",
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
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
                            Text(
                              "Wiper",
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
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
                        Navigator.pushNamed(context, '/scheduling');
                      },
                      child: Card(
                        margin:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        elevation: 8,
                        shadowColor: Colors.black.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: Theme.of(context).cardColor,
                        child: ListTile(
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondary
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.calendar_today,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            'Next Scheduled Clean',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          subtitle: Text(
                            nextScheduledClean ?? "Loading...",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            color: Theme.of(context).colorScheme.secondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 5),
                    Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _batteryLevel > 20
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _batteryLevel > 20
                                          ? Icons.battery_full
                                          : Icons.battery_alert,
                                      color: _batteryLevel > 20
                                          ? Colors.green
                                          : Colors.red,
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Battery',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                    ),
                                  ),
                                  Text(
                                    '$_batteryLevel%',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 50,
                              width: 1,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withOpacity(0.2),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary
                                          .withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.timelapse,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Last Clean',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                    ),
                                  ),
                                  Text(
                                    lastCleanTime,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
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
