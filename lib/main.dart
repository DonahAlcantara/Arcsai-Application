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

// Background service initialization callback
void onStart(ServiceInstance service) {
  log('Background service started');
}

// iOS-specific background fetch handler
bool onIosBackground(ServiceInstance service) {
  log('iOS background fetch');
  return true;
}

// Workmanager callback for periodic tasks and notifications
void callbackDispatcher() {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize Android notification settings
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  // Initialize local notifications for background tasks
  flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Execute background task
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}

// Global navigator key for navigation from non-widget contexts
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Configure timezone to Asia/Manila for scheduling
void _configureLocalTimeZone() {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Manila'));
}

// Initialize local notifications for the app
void initializeNotifications() {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  // Initialize notifications with Android settings
  flutterLocalNotificationsPlugin.initialize(initSettings);
}

// App entry point
void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  // Set up timezone and notifications
  _configureLocalTimeZone();
  initializeNotifications();
  // Initialize Firebase
  await Firebase.initializeApp();
  // Initialize Workmanager for background tasks
  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  // Run the app with ThemeProvider for dynamic theming
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );

  // Configure Firebase Cloud Messaging (FCM)
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request notification permissions
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    sound: true,
  );

  // Log permission status
  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    log("Notification permission granted.");
  } else {
    log("Notification permission denied.");
  }

  // Retrieve and log FCM token
  String? token = await messaging.getToken();
  print("FCM Token: $token");
}

// Main app widget with theme and navigation setup
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use Consumer to access ThemeProvider for dynamic theme updates
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: themeProvider.themeData, // Apply dynamic theme
          home: LoginPage(), // Start with login page
          routes: {
            // Define app routes
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

// Main screen for controlling the vacuum cleaner
class VacuumControlScreen extends StatefulWidget {
  @override
  _VacuumControlScreenState createState() => _VacuumControlScreenState();
}

class _VacuumControlScreenState extends State<VacuumControlScreen> {
  // Singleton instance for static access
  static _VacuumControlScreenState? _instance;

  // State variables
  String? nextSchedule; // Next scheduled cleaning time
  String? nextScheduledClean; // Formatted next schedule display
  bool isLoading = true; // Loading state for initialization
  int notificationCount = 0; // Count of unread notifications
  final FirebaseAuth _auth = FirebaseAuth.instance; // Firebase authentication
  final DatabaseReference database =
      FirebaseDatabase.instance.ref(); // Firebase database reference
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin(); // Local notifications
  final Battery _battery = Battery(); // Battery monitoring
  Timer? _scheduleTimer; // Periodic timer for schedule checks
  Timer? _stopVacuumTimer; // Timer to stop vacuum after a duration
  int _batteryLevel = 100; // Current battery level
  bool isMoving = false; // Vacuum movement status
  bool isCleaning = false; // Vacuum cleaning status
  bool vacuum = false; // Vacuum feature toggle
  bool wiper = false; // Wiper feature toggle
  String lastCleanTime = "Not started yet"; // Last cleaning timestamp
  DateTime? startTime; // Start time of cleaning
  String firstLetter = ''; // First letter of user's email
  final Set<String> processedScheduleIds = {}; // Track processed schedules
  bool _hasNotifiedLowBattery = false; // Flag for low battery notification
  bool isConnected = false; // Device connection status

  @override
  void initState() {
    super.initState();
    _instance = this; // Store singleton instance
    // Initialize state and listeners
    _loadUserProfile(); // Load user profile data
    _listenToFeatureChanges(); // Monitor feature toggles
    _getBatteryLevel(); // Get initial battery level
    _listenToRobotCommands(); // Monitor vacuum commands
    _listenToNotifications(); // Monitor notification updates
    _initializeDeviceStatus(); // Initialize device status in Firebase
    _listenToDeviceConnection(); // Monitor device connection status

    // Listen for battery state changes
    _battery.onBatteryStateChanged.listen((BatteryState state) {
      _getBatteryLevel();
    });

    // Subscribe to FCM topic for vacuum status updates
    FirebaseMessaging.instance.subscribeToTopic("vacuumStatus");
    // Set up local notifications
    setupLocalNotifications();
    // Listen for vacuum status changes
    listenToVacuumStatus();
    // Fetch schedules
    fetchSchedule();
    // Load next schedule
    loadNextSchedule();

    // Ensure vacuum is stopped unless already running
    database.child("robot_commands").get().then((event) {
      final data = event.value;
      if (data is Map && data["Clean"] == true) {
        log("Vacuum is already running on initialization, preserving state.");
      } else {
        triggerVacuum(false, fromSchedule: false);
        log("Vacuum stopped by default after login.");
      }
    });

    // Monitor vacuum feature changes
    database.child("features/vacuum").onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          vacuum = event.snapshot.value as bool;
        });
      }
    });

    // Monitor wiper feature changes
    database.child("features/wiper").onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          wiper = event.snapshot.value as bool;
        });
      }
    });

    // Periodically check schedules every 5 seconds
    _scheduleTimer = Timer.periodic(Duration(seconds: 5), (Timer timer) {
      if (mounted) {
        fetchSchedule();
      }
    });
  }

  // Initialize device_status/connected node in Firebase
  void _initializeDeviceStatus() async {
    DatabaseEvent event =
        await database.child("device_status/connected").once();
    if (!event.snapshot.exists) {
      try {
        await database.child("device_status").set({"connected": false});
        log("Initialized device_status/connected to false");
      } catch (e) {
        log("Failed to initialize device_status: $e");
      }
    }
  }

  // Monitor device connection status
  void _listenToDeviceConnection() {
    database.child("device_status/connected").onValue.listen((event) {
      if (mounted) {
        final value = event.snapshot.value;
        bool newConnectionStatus = value is bool ? value : false;
        setState(() {
          isConnected = newConnectionStatus;
        });
        log("Device connection status updated: $isConnected");
        // Stop vacuum if device disconnects while running
        if (!isConnected && isMoving) {
          triggerVacuum(false, fromSchedule: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Vacuum stopped: Device disconnected."),
            ),
          );
          log("Vacuum stopped due to device disconnection.");
        }
      }
    }, onError: (error) {
      log("Failed to listen to device connection: $error");
      if (mounted) {
        setState(() {
          isConnected = false;
        });
        // Stop vacuum on connection error
        if (isMoving) {
          triggerVacuum(false, fromSchedule: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Vacuum stopped: Connection error."),
            ),
          );
          log("Vacuum stopped due to connection error.");
        }
      }
    });
  }

  // Toggle device connection status for testing
  void _toggleDeviceConnection() async {
    final newStatus = !isConnected;
    try {
      await database.child("device_status").set({"connected": newStatus});
      log("Device connection status set to: $newStatus");
    } catch (e) {
      log("Failed to update device connection status: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update device connection status.")),
      );
    }
  }

  // Monitor notifications and update count
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

  // Clear all notifications
  void _clearNotifications() async {
    await database.child('notifications').remove();
    setState(() {
      notificationCount = 0;
    });
  }

  @override
  void dispose() {
    _instance = null; // Clear singleton instance
    print("VacuumControlScreen: dispose()");
    _scheduleTimer?.cancel(); // Cancel schedule timer
    _stopVacuumTimer?.cancel(); // Cancel stop vacuum timer
    super.dispose();
  }

  // Monitor vacuum command changes
  void _listenToRobotCommands() {
    database.child("robot_commands/Clean").onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          isMoving = event.snapshot.value as bool;
        });
      }
    });
  }

  // Get current battery level
  void _getBatteryLevel() async {
    final batteryLevel = await _battery.batteryLevel;
    setState(() {
      _batteryLevel = batteryLevel;
    });
    checkBatteryStatus(batteryLevel);
  }

  // Monitor feature toggle changes
  void _listenToFeatureChanges() {
    database.child("features/vacuum").onValue.listen((event) {
      setState(() {
        vacuum = event.snapshot.value as bool? ?? false;
      });
    });

    database.child("features/wiper").onValue.listen((event) {
      setState(() {
        wiper = event.snapshot.value as bool? ?? false;
      });
    });
  }

  // Toggle vacuum feature
  void toggleFeature1() async {
    final newValue = !vacuum;
    // Ensure at least one feature is on
    if (!newValue && !wiper) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "At least one feature (Vacuum or Wiper) must be on during cleaning."),
        ),
      );
      return;
    }
    try {
      await database.child("features/vacuum").set(newValue).then((_) {
        if (mounted) {
          setState(() => vacuum = newValue);
        }
        log("Vacuum feature toggled: $newValue");
      });
    } catch (e) {
      log("Failed to toggle vacuum: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to toggle vacuum feature.")),
      );
    }
  }

  // Toggle wiper feature
  void toggleFeature2() async {
    final newValue = !wiper;
    // Ensure at least one feature is on
    if (!newValue && !vacuum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "At least one feature (Vacuum or Wiper) must be on during cleaning."),
        ),
      );
      return;
    }
    try {
      await database.child("features/wiper").set(newValue).then((_) {
        if (mounted) {
          setState(() => wiper = newValue);
        }
        log("Wiper feature toggled: $newValue");
      });
    } catch (e) {
      log("Failed to toggle wiper: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to toggle wiper feature.")),
      );
    }
  }

  // Load user profile data (first letter of email)
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

  // Set up local notifications
  void setupLocalNotifications() {
    var initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    // Initialize notifications with tap handler
    flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _handleNotificationTap(response.payload!);
        }
      },
    );
  }

  // Handle notification tap to navigate to notifications page
  void _handleNotificationTap(String payload) {
    navigatorKey.currentState?.pushNamed('/notifications');
  }

  // Show local notification
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

  // Monitor vacuum status changes
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

  // Check battery status and send notifications if low
  void checkBatteryStatus(int batteryLevel) {
    if (batteryLevel < 25 && !_hasNotifiedLowBattery) {
      _showLocalNotification(
        "Battery Low",
        "Vacuum battery is at $batteryLevel%. Please charge.",
        3,
      );
      // Log low battery notification in Firebase
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

    // Log low battery using NotificationPage
    if (batteryLevel < 25 && !_hasNotifiedLowBattery) {
      NotificationPage().lowBattery(batteryLevel);
    }
  }

  // Update vacuum status and send notifications
  void updateVacuumStatus(String status) {
    if (status == "cleaning") {
      NotificationPage().startCleaning(DateTime.now(), "room");
    } else if (status == "charging") {
      NotificationPage().addNotification(
        title: "Charging",
        description: "Vacuum is charging.",
        type: "Vacuum Process",
      );
      _showLocalNotification("Charging", "Vacuum is charging.", 5);
    }
  }

  // Load the next scheduled cleaning time
  void loadNextSchedule() async {
    DatabaseEvent event = await database.child("schedules").once();
    if (event.snapshot.exists && event.snapshot.value != null) {
      try {
        Map<dynamic, dynamic> schedulesMap =
            event.snapshot.value as Map<dynamic, dynamic>;
        List<MapEntry<dynamic, dynamic>> schedulesList =
            schedulesMap.entries.toList();

        // Sort schedules by date
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

        // Find the next future schedule
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

  // Placeholder for starting vacuum process
  void startVacuumProcess() {
    log("Vacuum process started");
  }

  // Toggle vacuum movement
  void toggleMovementAsync() async {
    // Prevent action if device is disconnected
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Cannot start vacuum: Device is disconnected."),
        ),
      );
      return;
    }

    setState(() {
      isMoving = !isMoving;
    });
    triggerVacuum(isMoving, fromSchedule: false);

    // Update last clean time when stopping
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

  // Toggle cleaning status
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

  // Static method to trigger vacuum from external calls
  static void triggerVacuumStatic(bool start, {required bool fromSchedule}) {
    if (_instance != null && _instance!.mounted) {
      _instance!.triggerVacuum(start, fromSchedule: fromSchedule);
    }
  }

  // Trigger vacuum start/stop
  void triggerVacuum(bool start, {required bool fromSchedule}) async {
    print(
        "triggerVacuum called with start: $start, fromSchedule: $fromSchedule");
    setState(() {
      isMoving = start;
      // Update feature toggles based on start/stop
      if (start) {
        vacuum = true;
        wiper = false;
      } else {
        vacuum = false;
        wiper = false;
      }
    });

    // Update Firebase with vacuum status and features
    DatabaseReference robotCommandsRef = database.child("robot_commands");
    DatabaseReference featuresRef = database.child("features");
    await Future.wait([
      robotCommandsRef.update({"Clean": start}),
      featuresRef.update({
        "vacuum": start ? true : false,
        "wiper": start ? false : false,
      }),
    ]).then((_) {
      log("Vacuum status and features updated successfully in Firebase.");
      if (mounted) {
        setState(() {
          isMoving = start;
        });
      }
    }).catchError((error) {
      log("Failed to update vacuum status or features: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update vacuum status.")),
      );
    });

    // Send notification for scheduled actions
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

    // Update last clean time when stopping
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

    // Log cleaning start/stop notifications
    if (start) {
      NotificationPage().startCleaning(DateTime.now(), "room");
    } else {
      NotificationPage().stopCleaning(DateTime.now());
    }
  }

  // Fetch and process schedules
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

        // Sort schedules by date
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

        // Process each schedule
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

            // Check if schedule should trigger
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

            // Trigger vacuum for valid schedule
            if (shouldTrigger && !isMoving) {
              if (!isConnected) {
                log("Cannot start vacuum for schedule $scheduleId: Device is disconnected.");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "Scheduled cleaning at ${intl.DateFormat('yyyy-MM-dd – kk:mm').format(scheduledDateTime)} cannot start: Device is disconnected."),
                  ),
                );
                continue;
              }

              processedScheduleIds.add(scheduleId);
              triggerVacuum(true, fromSchedule: true);
              log("Vacuum start command sent due to schedule: $scheduleId");

              // Disable one-time schedules
              if (entry.value["repeat"] == "Once") {
                database
                    .child("schedules/$scheduleId")
                    .update({"enabled": false});
              }

              // Set timer to stop vacuum after 5 minutes
              _stopVacuumTimer?.cancel();
              _stopVacuumTimer = Timer(Duration(minutes: 5), () {
                if (mounted && isMoving) {
                  triggerVacuum(false, fromSchedule: true);
                  log("Vacuum stopped after 5 minutes for schedule: $scheduleId");
                }
              });
            }

            // Update next schedule display
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
    // Build UI with Scaffold
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Header with app name, status, and notifications
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // App title
                      Text(
                        'ARCSAI Vacuum',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      // Vacuum status
                      Text(
                        isMoving ? 'Cleaning in progress' : 'Ready to clean',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Notification icon with badge
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
                      // User avatar with first letter
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
            // Main content area
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
                    // Start/Stop vacuum button
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
                    // Feature toggles (shown only when vacuum is moving)
                    if (isMoving)
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
                    // Schedule card
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

                    SizedBox(height: 10),
                    // Status card (device, battery, last clean)
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
                            // Device connection status
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isConnected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .secondary
                                              .withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: CircleAvatar(
                                      backgroundImage:
                                          AssetImage('assets/icon/logo.png'),
                                      backgroundColor: isConnected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .secondary
                                              .withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      radius: 14,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Device',
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
                                    isConnected ? 'Connected' : 'Disconnected',
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
                            // Battery status
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
                            // Last clean time
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
