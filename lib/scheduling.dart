import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class SchedulingScreen extends StatefulWidget {
  @override
  _SchedulingScreenState createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen> {
  final DatabaseReference database = FirebaseDatabase.instance.ref();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> schedules = [];
  String formattedTime = "";
  Timer? _vacuumTimer; // Timer to handle the 5-minute duration

  // New variables to store repeat options, delete, and label
  String repeatOption = "Once"; // Default value
  bool deleteAfterCleaning = false;
  TextEditingController labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _loadSchedules();
    _updateCurrentTime();
    _initializeNotifications();
    _startScheduleChecker(); // Start checking for schedules
  }

  // Initialize the notification plugin
  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _updateCurrentTime() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          formattedTime = DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
        });
      }
    });
  }

  void _startScheduleChecker() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        _checkSchedules();
      }
    });
  }

  void _checkSchedules() {
    final now = DateTime.now();
    for (var schedule in schedules) {
      if (!schedule['enabled']) continue; // Skip disabled schedules

      DateTime scheduledDateTime = schedule['dateTime'];
      bool isWithinOneSecond =
          now.difference(scheduledDateTime).inSeconds.abs() <= 1;

      if (isWithinOneSecond) {
        // Start the vacuum
        database.child("move_forward").set(true);
        print(
            "Vacuum started at ${DateFormat('HH:mm dd/MM/yyyy').format(now)}");

        // Schedule the vacuum to stop after 5 minutes
        _vacuumTimer?.cancel(); // Cancel any existing timer
        _vacuumTimer = Timer(Duration(minutes: 5), () {
          database.child("move_forward").set(false);
          print(
              "Vacuum stopped after 5 minutes at ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}");

          // Handle "delete after cleaning" option
          if (schedule['delete']) {
            database.child("schedules/${schedule['id']}").remove();
            print("Schedule deleted after completion: ${schedule['id']}");
          }

          // Handle repeat options
          _handleRepeatOption(schedule);
        });
      }
    }
  }

  void _handleRepeatOption(Map<String, dynamic> schedule) {
    String repeat = schedule['repeat'];
    DateTime scheduledDateTime = schedule['dateTime'];
    DateTime? nextDateTime;

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
        return; // No repeat, do nothing
    }

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
                  "repeat": e.value["repeat"] ?? "Once", // Load repeat option
                  "delete": e.value["delete"] ?? false, // Load delete option
                  "label": e.value["label"] ?? "", // Load label
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

  void _addSchedule() async {
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

    // Show options for repeat, delete, and label before saving
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
                    // Repeat Options
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
                    // Delete After Cleaning
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
                    // Label
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
                      "repeat": repeatOption, // Save repeat option
                      "delete": deleteAfterCleaning, // Save delete option
                      "label": labelController.text, // Save label
                    });

                    _scheduleNotification(scheduledDateTime);

                    firestore.collection('notifications').add({
                      "title": "New Schedule Added",
                      "description": "Scheduled for $formattedDateTime",
                      "timestamp": Timestamp.now(),
                      "type": "Schedule",
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

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
            TextButton(
              child: Text(
                "Delete",
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color),
              ),
              onPressed: () {
                Navigator.of(context).pop();
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
    _vacuumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                          Text(
                            "Repeat: ${schedules[index]['repeat']}",
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                          Text(
                            "Label: ${schedules[index]['label']}",
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
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
