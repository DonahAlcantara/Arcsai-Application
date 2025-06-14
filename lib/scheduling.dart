import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'notification.dart'; // Import NotificationPage for notification methods

// Widget for managing vacuum cleaning schedules
class SchedulingScreen extends StatefulWidget {
  @override
  _SchedulingScreenState createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen> {
  // Firebase Realtime Database reference
  final DatabaseReference database = FirebaseDatabase.instance.ref();
  // Local notifications plugin
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  // Firestore instance for notifications
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // List to store schedules
  List<Map<String, dynamic>> schedules = [];
  // Current time display
  String formattedTime = "";
  // Timer for vacuum stop
  Timer? _vacuumTimer;

  // Default repeat option for new schedules
  String repeatOption = "Once";
  // Flag to delete schedule after completion
  bool deleteAfterCleaning = false;
  // Controller for schedule label input
  TextEditingController labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize timezone for notifications
    tz.initializeTimeZones();
    // Load existing schedules
    _loadSchedules();
    // Update current time display
    _updateCurrentTime();
    // Initialize local notifications
    _initializeNotifications();
    // Start periodic schedule checks
    _startScheduleChecker();
  }

  // Initialize local notifications
  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // Update current time every second
  void _updateCurrentTime() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          formattedTime = DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
        });
      }
    });
  }

  // Start periodic schedule checks every second
  void _startScheduleChecker() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        _checkSchedules();
      }
    });
  }

  // Check schedules and trigger vacuum if within 1 second of scheduled time
  void _checkSchedules() {
    final now = DateTime.now();
    for (var schedule in schedules) {
      if (!schedule['enabled']) continue;

      DateTime scheduledDateTime = schedule['dateTime'];
      bool isWithinOneSecond =
          now.difference(scheduledDateTime).inSeconds.abs() <= 1;

      if (isWithinOneSecond) {
        // Show start notification
        _showStartNotification(scheduledDateTime);

        // Start vacuum by setting Firebase node
        database.child("move_forward").set(true);
        print(
            "Vacuum started at ${DateFormat('HH:mm dd/MM/yyyy').format(now)}");

        // Schedule vacuum to stop after 5 minutes
        _vacuumTimer?.cancel();
        _vacuumTimer = Timer(Duration(minutes: 5), () {
          database.child("move_forward").set(false);
          print(
              "Vacuum stopped after 5 minutes at ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}");

          // Delete schedule if flagged
          if (schedule['delete']) {
            database.child("schedules/${schedule['id']}").remove();
            print("Schedule deleted after completion: ${schedule['id']}");
          }

          // Handle repeat options (Daily, Weekly, Monthly)
          _handleRepeatOption(schedule);
        });

        // Log notifications using NotificationPage
        print(
            "Schedule triggered at ${DateFormat('HH:mm dd/MM/yyyy').format(now)} for ${schedule['id']}");
        // Log start cleaning notification
        NotificationPage()
            .startCleaning(scheduledDateTime, schedule['label'] ?? "room");

        // Schedule stop cleaning notification
        _vacuumTimer?.cancel();
        _vacuumTimer = Timer(Duration(minutes: 5), () {
          _showStopNotification(DateTime.now());
          NotificationPage().stopCleaning(DateTime.now());
        });
      }
    }
  }

  // Show local notification when vacuum starts
  void _showStartNotification(DateTime scheduledDate) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      scheduledDate.millisecondsSinceEpoch ~/ 1000,
      'Vacuum Started',
      'Your vacuum has started cleaning at ${DateFormat('HH:mm dd/MM/yyyy').format(scheduledDate)}',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'vacuum_start_channel',
          'Vacuum Start Notifications',
          channelDescription: 'Notifications when the vacuum starts cleaning',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          playSound: true,
          enableVibration: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Show local notification when vacuum stops
  void _showStopNotification(DateTime stopDate) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        stopDate.millisecondsSinceEpoch ~/ 1000,
        'Cleaning Complete',
        'Your vacuum has finished cleaning at ${DateFormat('HH:mm dd/MM/yyyy').format(stopDate)}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'vacuum_stop_channel',
            'Vacuum Stop Notifications',
            channelDescription: 'Notifications when the vacuum stops cleaning',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
      print(
          "Stop notification shown successfully for ${DateFormat('HH:mm dd/MM/yyyy').format(stopDate)}");
    } catch (e) {
      print("Error showing stop notification: $e");
    }
  }

  // Handle repeat options for schedules
  void _handleRepeatOption(Map<String, dynamic> schedule) {
    String repeat = schedule['repeat'];
    DateTime scheduledDateTime = schedule['dateTime'];
    DateTime? nextDateTime;

    // Calculate next schedule based on repeat option
    switch (repeat) {
      case "Daily":
        nextDateTime = scheduledDateTime.add(Duration(days: 1));
        break;
      case "Weekly":
        nextDateTime = scheduledDateTime.add(Duration(days: 7));
        break;
      case "Monthly":
        nextDateTime = DateTime(
          scheduledDateTime.year,
          scheduledDateTime.month + 1,
          scheduledDateTime.day,
          scheduledDateTime.hour,
          scheduledDateTime.minute,
        );
        break;
      case "Once":
      default:
        return;
    }

    // Add new schedule for repeating events
    if (nextDateTime != null) {
      String newKey = DateFormat('yyyyMMdd_HHmm').format(nextDateTime);
      database.child("schedules").child(newKey).set({
        "dateTime": nextDateTime.toIso8601String(),
        "enabled": true,
        "repeat": repeat,
        "delete": schedule['delete'],
        "label": schedule['label'],
      });
      print(
          "New schedule added for repeat: $repeat at ${DateFormat('HH:mm dd/MM/yyyy').format(nextDateTime)}");
    }
  }

  // Load schedules from Firebase
  void _loadSchedules() {
    database.child("schedules").onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        Map<String, dynamic> data =
            Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          schedules = data.entries
              .map((e) {
                DateTime? parsedDateTime;
                try {
                  parsedDateTime = DateTime.parse(e.value["dateTime"]);
                } catch (e) {
                  print("Error parsing date: ${e.toString()}");
                  return null;
                }
                return {
                  "id": e.key,
                  "dateTime": parsedDateTime,
                  "enabled": e.value["enabled"] ?? false,
                  "repeat": e.value["repeat"] ?? "Once",
                  "delete": e.value["delete"] ?? false,
                  "label": e.value["label"] ?? "",
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      } else {
        if (mounted) {
          setState(() {
            schedules = [];
          });
        }
      }
    });
  }

  // Add a new schedule
  void _addSchedule() async {
    // Show date picker
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return;

    // Show time picker
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return;

    // Create scheduled datetime
    DateTime scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    String formattedDateTime =
        DateFormat('HH:mm dd/MM/yyyy').format(scheduledDateTime);
    String customKey = DateFormat('yyyyMMdd_HHmm').format(scheduledDateTime);

    // Show dialog for schedule options
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).dialogBackgroundColor,
              title: Text(
                "Schedule Options",
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Repeat option dropdown
                    ListTile(
                      title: Text(
                        "Repeat",
                        style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color),
                      ),
                      trailing: DropdownButton<String>(
                        value: repeatOption,
                        items: <String>["Once", "Daily", "Weekly", "Monthly"]
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            repeatOption = newValue!;
                          });
                        },
                      ),
                    ),
                    // Delete after completion switch
                    SwitchListTile(
                      title: Text(
                        "Delete after alarm goes off",
                        style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color),
                      ),
                      value: deleteAfterCleaning,
                      onChanged: (bool value) {
                        setState(() {
                          deleteAfterCleaning = value;
                        });
                      },
                      activeColor: Theme.of(context).colorScheme.secondary,
                    ),
                    // Label input field
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: "Label",
                        labelStyle: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                // Cancel button
                TextButton(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                // Save button
                TextButton(
                  child: Text(
                    'Save',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Save schedule to Firebase
                    database.child("schedules").child(customKey).set({
                      "dateTime": scheduledDateTime.toIso8601String(),
                      "enabled": true,
                      "repeat": repeatOption,
                      "delete": deleteAfterCleaning,
                      "label": labelController.text,
                    });

                    // Schedule local notification
                    _scheduleNotification(scheduledDateTime);

                    // Log schedule creation using NotificationPage
                    NotificationPage().setSchedule(scheduledDateTime);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Schedule a local notification for the vacuum start
  void _scheduleNotification(DateTime scheduledDate) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      scheduledDate.millisecondsSinceEpoch ~/ 1000,
      'The ARCSAI Vacuum is Cleaning',
      'The vacuum process has started',
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'your_channel_id',
          'your_channel_name',
          channelDescription: 'your_channel_description',
          importance: Importance.low,
          priority: Priority.low,
          showWhen: true,
          playSound: false,
          enableVibration: false,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Delete a schedule with confirmation dialog
  void _deleteSchedule(String scheduleId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).dialogBackgroundColor,
          title: Text(
            "Delete Schedule",
            style:
                TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
          ),
          content: Text(
            "Are you sure you want to delete this schedule?",
            style:
                TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
          ),
          actions: <Widget>[
            // Cancel button
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            // Delete button
            TextButton(
              child: Text(
                "Delete",
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                // Remove schedule from Firebase
                database.child("schedules/$scheduleId").remove().then((_) {
                  print("Schedule deleted successfully");
                }).catchError((error) {
                  print("Error deleting schedule: $error");
                });
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // Cancel vacuum timer to prevent memory leaks
    _vacuumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // App bar with title and current time
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        title: Text(
          "Alarm Clock",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
        ),
        centerTitle: true,
        iconTheme: Theme.of(context).appBarTheme.iconTheme,
        actions: [
          Padding(
            padding: EdgeInsets.all(10),
            child: Center(
              child: Text(
                formattedTime,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Theme.of(context).appBarTheme.titleTextStyle?.color,
                ),
              ),
            ),
          ),
        ],
      ),
      // Display schedules or empty message
      body: schedules.isEmpty
          ? Center(
              child: Text(
                "No schedules yet.",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            )
          : ListView.builder(
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  // Long press to delete schedule
                  onLongPress: () {
                    _deleteSchedule(schedules[index]['id']);
                  },
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                    color: Theme.of(context).cardColor,
                    child: ListTile(
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      // Schedule datetime
                      title: Text(
                        DateFormat('HH:mm dd/MM/yyyy')
                            .format(schedules[index]['dateTime']),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Repeat option
                          Text(
                            "Repeat: ${schedules[index]['repeat']}",
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                          // Schedule label
                          Text(
                            "Label: ${schedules[index]['label']}",
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
                      // Enable/disable schedule switch
                      trailing: Switch(
                        value: schedules[index]['enabled'],
                        onChanged: (bool newValue) {
                          database
                              .child("schedules/${schedules[index]['id']}")
                              .update({'enabled': newValue});
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
      // Button to add new schedule
      floatingActionButton: FloatingActionButton(
        onPressed: _addSchedule,
        backgroundColor: Theme.of(context).colorScheme.secondary,
        child: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.onSecondary,
        ),
      ),
    );
  }
}
